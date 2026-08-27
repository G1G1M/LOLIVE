export interface League {
  id: string;
  slug: string;
  name: string;
  region: string;
  imageURL: string | null;
}

export interface Team {
  id: string;
  name: string;
  code: string;
  imageURL: string | null;
}

export interface Match {
  id: string;
  league: League;
  teamA: Team;
  teamB: Team;
  scoreA: number;
  scoreB: number;
  startTime: Date;
  state: "unstarted" | "inProgress" | "completed";
  blockName: string | null;
  games?: BackfilledGameDetail[];
}

// ── 과거 시즌 백필(oe.datalisk.io) 게임별 상세 — 밴 데이터는 원본에 없어 포함 안 함 ──────

export interface BackfilledPlayerStats {
  participantId: number;
  summonerName: string;
  championId: string;
  role: string;
  kills: number;
  deaths: number;
  assists: number;
  totalGold: number;
  creepScore: number;
  level: number;
}

export interface BackfilledTeamGameStats {
  totalGold: number;
  towers: number;
  barons: number;
  totalKills: number;
  dragons: number;
  inhibitors: number;
}

export interface BackfilledGameDetail {
  number: number;
  gameId: string;
  patch: number | null;
  vod: string | null;
  blueTeamId: string;
  redTeamId: string;
  winnerTeamId: string | null;
  blueTeamStats: BackfilledTeamGameStats;
  redTeamStats: BackfilledTeamGameStats;
  bluePlayers: BackfilledPlayerStats[];
  redPlayers: BackfilledPlayerStats[];
}

export interface LiveMatch {
  match: Match;
  currentSet: number;
}

// ── Riot API raw types ──────────────────────────────────────────

export interface RiotLeaguesResponse {
  data: { leagues: RiotLeagueDTO[] };
}

export interface RiotLeagueDTO {
  id: string;
  slug: string;
  name: string;
  region: string;
  image: string;
}

export interface RiotScheduleResponse {
  data: {
    schedule: {
      events: RiotEventDTO[];
      pages?: { older?: string; newer?: string };
    };
  };
}

export interface RiotEventDTO {
  startTime: string;
  state: string;
  type: string;
  blockName?: string;
  league: { id?: string; slug: string; name: string; image?: string };
  match?: RiotMatchDTO;
}

export interface RiotMatchDTO {
  id: string;
  teams: Array<{
    id?: string;
    name: string;
    code: string;
    image?: string;
    result?: { gameWins: number };
  }>;
  games?: Array<{ state: string }>;
  strategy?: { count: number };
}

// ── getEventDetails 응답 (완료 경기 상세: 밴픽, 게임별 승자) ──────────

export interface RiotEventDetailsResponse {
  data: { event: { id: string; match: RiotMatchDetailDTO } };
}

export interface RiotMatchDetailDTO {
  strategy: { count: number };
  teams: Array<{ id: string }>;
  games: RiotGameDetailDTO[];
}

export interface RiotGameDetailDTO {
  number: number;
  id: string;
  state: string;
  teams: Array<{
    id: string;
    side: string;
    bans?: Array<{ championId: string }>;
    outcome?: string;
    result?: { outcome?: string };
  }>;
}

export interface GameInfo {
  number: number;
  gameId: string;
  state: string;
  blueTeamId: string;
  redTeamId: string;
  blueBans: string[];
  redBans: string[];
  winnerTeamId: string | null;
}

export interface EventDetailInfo {
  strategyCount: number;
  games: GameInfo[];
  teamAEsportsId: string;
  teamBEsportsId: string;
}
