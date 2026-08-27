import axios from "axios";
import {
  League, Match, LiveMatch,
  RiotLeaguesResponse, RiotScheduleResponse, RiotEventDTO, RiotMatchDTO,
  RiotEventDetailsResponse, EventDetailInfo, GameInfo,
} from "./types";

const API_KEY = "0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z";
const BASE   = "https://esports-api.lolesports.com/persisted/gw";

const headers = { "x-api-key": API_KEY };
const hl = { hl: "ko-KR" };

function https(url?: string): string | null {
  return url ? url.replace("http://", "https://") : null;
}

function parseMatch(event: RiotEventDTO, fallbackLeague?: League): Match | null {
  const m: RiotMatchDTO | undefined = event.match;
  if (!m || m.teams.length < 2) return null;

  const league: League = {
    id: fallbackLeague?.id ?? event.league.id ?? event.league.slug,
    slug: event.league.slug,
    name: event.league.name,
    region: fallbackLeague?.region ?? "",
    imageURL: fallbackLeague?.imageURL ?? https(event.league.image),
  };

  return {
    id: m.id,
    league,
    teamA: {
      id: m.teams[0].id ?? m.teams[0].code,
      name: m.teams[0].name,
      code: m.teams[0].code,
      imageURL: https(m.teams[0].image),
    },
    teamB: {
      id: m.teams[1].id ?? m.teams[1].code,
      name: m.teams[1].name,
      code: m.teams[1].code,
      imageURL: https(m.teams[1].image),
    },
    scoreA: m.teams[0].result?.gameWins ?? 0,
    scoreB: m.teams[1].result?.gameWins ?? 0,
    startTime: new Date(event.startTime),
    state: event.state as Match["state"],
    blockName: event.blockName ?? null,
  };
}

export async function fetchLeagues(): Promise<League[]> {
  const res = await axios.get<RiotLeaguesResponse>(`${BASE}/getLeagues`, { headers, params: hl });
  return (res.data?.data?.leagues ?? []).map((l) => ({
    id: l.id, slug: l.slug, name: l.name, region: l.region,
    imageURL: https(l.image),
  }));
}

export async function fetchSchedule(leagueId: string, leagueMap: Map<string, League>): Promise<Match[]> {
  const res = await axios.get<RiotScheduleResponse>(`${BASE}/getSchedule`, {
    headers, params: { ...hl, leagueId },
  });
  const events = res.data?.data?.schedule?.events ?? [];
  const league = leagueMap.get(leagueId);
  return events.map((e) => parseMatch(e, league)).filter((m): m is Match => m !== null);
}

export async function fetchLive(leagueMap: Map<string, League>): Promise<LiveMatch[]> {
  const res = await axios.get<RiotScheduleResponse>(`${BASE}/getLive`, { headers, params: hl });
  const events = res.data?.data?.schedule?.events ?? [];
  return events.flatMap((event): LiveMatch[] => {
    const match = parseMatch(event, leagueMap.get(event.league.id ?? ""));
    if (!match) return [];
    const completedGames = event.match?.games?.filter((g) => g.state === "completed").length ?? 0;
    return [{ match, currentSet: completedGames + 1 }];
  });
}

// 밴픽 + 게임별 승자 — 완료 경기 상세를 한 번만 가져와 영구 캐싱하는 데 씀 (앱의
// fetchEventDetails와 동일 로직). 경기 종료 직후엔 이 데이터가 아직 안 채워진 경우가
// 있어서, 호출부(syncLive)에서 isGenuinelyComplete로 신뢰 가능 여부를 따로 검사한다.
export async function fetchEventDetails(matchId: string): Promise<EventDetailInfo> {
  const res = await axios.get<RiotEventDetailsResponse>(`${BASE}/getEventDetails`, {
    headers, params: { ...hl, id: matchId },
  });
  const matchDTO = res.data.data.event.match;

  const games: GameInfo[] = matchDTO.games.map((game) => {
    const blueTeamDTO = game.teams.find((t) => t.side === "blue");
    const redTeamDTO  = game.teams.find((t) => t.side === "red");
    const winnerTeamId = game.teams.find(
      (t) => t.outcome === "win" || t.result?.outcome === "win"
    )?.id ?? null;
    return {
      number: game.number,
      gameId: game.id,
      state: game.state,
      blueTeamId: blueTeamDTO?.id ?? "",
      redTeamId: redTeamDTO?.id ?? "",
      blueBans: blueTeamDTO?.bans?.map((b) => b.championId) ?? [],
      redBans: redTeamDTO?.bans?.map((b) => b.championId) ?? [],
      winnerTeamId,
    };
  });

  return {
    strategyCount: matchDTO.strategy.count,
    games,
    teamAEsportsId: matchDTO.teams[0]?.id ?? "",
    teamBEsportsId: matchDTO.teams[1]?.id ?? "",
  };
}

// 클라이언트 MatchDetailViewModel.isGenuinelyComplete와 동일한 기준 — 게임 하나라도
// 완료+승자 확정이어야 "믿고 캐싱해도 되는" 상세로 취급한다.
export function isGenuinelyComplete(detail: EventDetailInfo): boolean {
  return detail.games.some((g) => g.state === "completed" && g.winnerTeamId !== null);
}
