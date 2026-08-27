import axios from "axios";
import { Match, League } from "./types";

const BASE_URL = "https://lol.fandom.com/api.php";

// ── 레이트리밋. 0.5초/2초 간격으로도 계속 ratelimited가 나서 조사해보니, 익명 요청
// 기준으로 Leaguepedia(Fandom) 쪽 실제 제한이 "분당 1회" 근처인 것으로 보임(공식 문서
// 없음, MediaWiki API 메일링 리스트의 경험담 + 우리가 직접 겪은 것 기준 추정).
// 백필은 사용자가 보는 화면이 아니라 한 번 도는 관리용 작업이라 속도보다 안정성을
// 우선해 이 추정치 근처(65~70초)로 훨씬 여유 있게 잡았다. 그래도 겹치면 재시도하되,
// 함수 실행시간 제한(540초) 안에 끝나야 해서 재시도 횟수는 크게 늘리지 않는다.
let nextSlotTime = 0;
const SLOT_INTERVAL_MS = 68_000;
const RETRY_WAIT_MS = 70_000;
const MAX_RETRIES = 2;

async function claimSlot(): Promise<void> {
  const now = Date.now();
  const mySlot = Math.max(now, nextSlotTime);
  nextSlotTime = mySlot + SLOT_INTERVAL_MS;
  const wait = mySlot - now;
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
}

function isRateLimited(data: unknown): boolean {
  const err = (data as { error?: { code?: string } } | undefined)?.error;
  return err?.code === "ratelimited";
}

function escapeSql(value: string): string {
  return value.replace(/'/g, "\\'");
}

interface CargoRow {
  title: Record<string, string>;
}

async function cargoQuery(params: Record<string, string>): Promise<CargoRow[]> {
  await claimSlot();
  let retries = 0;
  for (;;) {
    let res;
    try {
      res = await axios.get(BASE_URL, {
        params: { ...params, format: "json" },
        headers: { "User-Agent": "LOLIVE/1.0 (Firebase backfill)" },
      });
    } catch (error) {
      console.error("[historical] cargoQuery 요청 실패:", params, error);
      return [];
    }
    if (res.data?.error) {
      console.error("[historical] cargoQuery 에러 응답:", params.where, res.data.error);
    }
    if (!isRateLimited(res.data)) {
      const rows = (res.data?.cargoquery as CargoRow[] | undefined) ?? [];
      console.log(`[historical] cargoQuery ${params.tables} where=${params.where} → ${rows.length}행`);
      return rows;
    }
    if (retries >= MAX_RETRIES) {
      console.error(`[historical] cargoQuery 재시도 ${MAX_RETRIES}회 초과, 포기:`, params.where);
      return [];
    }
    console.log(`[historical] ratelimited, ${RETRY_WAIT_MS / 1000}초 대기 후 재시도 (${retries + 1}/${MAX_RETRIES})`);
    await new Promise((r) => setTimeout(r, RETRY_WAIT_MS));
    await claimSlot();
    retries++;
  }
}

function parseLPDate(dateStr: string): Date | null {
  const spaceFormat = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/;
  const d = spaceFormat.test(dateStr) ? new Date(`${dateStr.replace(" ", "T")}Z`) : new Date(dateStr);
  return isNaN(d.getTime()) ? null : d;
}

// ── 대회 페이지 목록 (앱의 allOverviewPagesForLeague와 동일) ────────────────

export interface TournamentPage {
  page: string;
  year: number;
  dateStart: string; // yyyy-MM-dd
}

// 백필은 "최근 탭 몇 개"가 아니라 전체 역사를 다 가져와야 해서, 앱의 원래 조회(최근 것만
// limit 20~50)와 달리 끝까지 페이지네이션한다 — 시즌이 계속 쌓이는 리그(LCK 등)가 잘리는 걸 방지.
export async function fetchTournamentPages(leagueName: string): Promise<TournamentPage[]> {
  const isInternational = leagueName === "Worlds" || leagueName === "MSI" || leagueName === "KeSPA Cup";
  const whereClause = isInternational
    ? `Tournaments.OverviewPage LIKE '${
      leagueName === "Worlds" ? "%Season World Championship%" :
        leagueName === "MSI" ? "%Mid-Season Invitational%" : "%KeSPA Cup%"
    }'`
    : `Leagues.League_Short='${escapeSql(leagueName)}'`;

  let allRows: CargoRow[] = [];
  let offset = 0;
  const batchSize = 500;
  for (;;) {
    const rows = isInternational
      ? await cargoQuery({
        action: "cargoquery",
        tables: "Tournaments",
        fields: "Tournaments.OverviewPage,Tournaments.DateStart",
        where: whereClause,
        order_by: "Tournaments.DateStart DESC",
        offset: String(offset),
        limit: String(batchSize),
      })
      : await cargoQuery({
        action: "cargoquery",
        tables: "Tournaments,Leagues",
        join_on: "Tournaments.League=Leagues.League",
        fields: "Tournaments.OverviewPage,Tournaments.DateStart",
        where: whereClause,
        order_by: "Tournaments.DateStart DESC",
        offset: String(offset),
        limit: String(batchSize),
      });
    allRows = allRows.concat(rows);
    if (rows.length < batchSize) break;
    offset += batchSize;
  }

  const pages: TournamentPage[] = [];
  for (const row of allRows) {
    const page = row.title["OverviewPage"];
    const dateStr = row.title["DateStart"];
    if (!page || !dateStr) continue;
    const date = parseLPDate(`${dateStr} 00:00:00`);
    if (!date) continue;
    pages.push({ page, year: date.getUTCFullYear(), dateStart: dateStr });
  }
  return pages;
}

// ── 팀 로고 배치 조회 (앱의 fetchTeamImageURLs와 동일) ──────────────────────

async function fetchTeamImageURLs(names: Set<string>): Promise<Map<string, string>> {
  if (names.size === 0) return new Map();
  const inClause = Array.from(names).map((n) => `'${escapeSql(n)}'`).join(",");
  const rows = await cargoQuery({
    action: "cargoquery",
    tables: "Teams",
    fields: "Teams.Short=Short,Teams.Image=Image",
    where: `Teams.Short IN (${inClause})`,
    limit: "50",
  });
  const result = new Map<string, string>();
  for (const row of rows) {
    const short = row.title["Short"];
    const image = row.title["Image"];
    if (!short || !image) continue;
    result.set(short, `https://lol.fandom.com/wiki/Special:FilePath/${encodeURIComponent(image.replace(/ /g, "_"))}`);
  }
  return result;
}

function fallbackLogoURL(name: string): string {
  return `https://lol.fandom.com/wiki/Special:FilePath/${encodeURIComponent(`${name}logo std.png`)}`;
}

// ── 페이지 하나의 경기 전체 (앱의 matchesForOverviewPage와 동일) ────────────

export async function fetchMatchesForOverviewPage(overviewPage: string, leagueName: string): Promise<Match[]> {
  let allRows: Record<string, string>[] = [];
  let offset = 0;
  const batchSize = 500;

  for (;;) {
    const rows = await cargoQuery({
      action: "cargoquery",
      tables: "MatchSchedule",
      fields: "MatchId,DateTime_UTC,Team1,Team2,Team1Score,Team2Score,Winner,Tab",
      where: `OverviewPage='${escapeSql(overviewPage)}' AND Team1 IS NOT NULL AND Team2 IS NOT NULL AND DateTime_UTC IS NOT NULL`,
      order_by: "DateTime_UTC ASC",
      offset: String(offset),
      limit: String(batchSize),
    });
    const batch = rows.map((r) => r.title);
    allRows = allRows.concat(batch);
    if (batch.length < batchSize) break;
    offset += batchSize;
  }

  const uniqueTeamNames = new Set<string>();
  for (const row of allRows) {
    if (row["Team1"]) uniqueTeamNames.add(row["Team1"]);
    if (row["Team2"]) uniqueTeamNames.add(row["Team2"]);
  }
  const teamImages = await fetchTeamImageURLs(uniqueTeamNames);

  const league: League = {
    id: `lp_${leagueName}`, slug: leagueName, name: leagueName, region: "", imageURL: null,
  };

  const matches: Match[] = [];
  for (const row of allRows) {
    const dateStr = row["DateTime UTC"];
    const team1 = row["Team1"];
    const team2 = row["Team2"];
    if (!dateStr || !team1 || !team2) continue;
    const startTime = parseLPDate(dateStr);
    if (!startTime) continue;

    const rawId = (row["MatchId"] ?? "").trim();
    const matchId = rawId ? `lp_${rawId}` : `lp_${overviewPage}_${team1}_${team2}_${dateStr}`;

    const scoreA = parseInt(row["Team1Score"] ?? "", 10) || 0;
    const scoreB = parseInt(row["Team2Score"] ?? "", 10) || 0;
    const winner = row["Winner"] ?? "";
    const state: Match["state"] = winner ? "completed" : (scoreA > 0 || scoreB > 0 ? "inProgress" : "unstarted");
    const blockName = (row["Tab"] ?? "").trim() || null;

    matches.push({
      id: matchId,
      league,
      teamA: { id: `lp_${team1}`, name: team1, code: team1, imageURL: teamImages.get(team1) ?? fallbackLogoURL(team1) },
      teamB: { id: `lp_${team2}`, name: team2, code: team2, imageURL: teamImages.get(team2) ?? fallbackLogoURL(team2) },
      scoreA, scoreB, startTime, state, blockName,
    });
  }
  return matches;
}
