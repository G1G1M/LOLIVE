import * as admin from "firebase-admin";
import { Match, League } from "./types";
import { fetchTournamentPages, fetchMatchesForOverviewPage } from "./historical";

// index.ts의 admin.initializeApp()보다 이 파일의 최상단 코드가 먼저 평가될 수 있어서(import 순서),
// 모듈 로드 시점이 아니라 실제 호출 시점에 admin.firestore()를 얻도록 지연 평가한다
// (historicalDaily.ts에서 이미 겪은 "default app 없음" 에러와 동일한 함정).
function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

// Riot League(name/slug) → Leaguepedia League_Short. 클라이언트 LeaguepediaService.leaguepediaName(for:)와
// 동일한 매핑(historicalDaily.ts에도 별도 사본이 있음 — 용도가 달라 각자 유지, 12개 리그/대회만 다룸).
function leaguepediaName(league: League): string | null {
  const lower = league.name.toLowerCase().trim();
  const slug = league.slug.toLowerCase().trim();

  if (lower === "worlds" || slug === "worlds" || lower.includes("world championship")) return "Worlds";
  if (lower === "msi" || slug === "msi" || lower.includes("mid-season")) return "MSI";
  if (lower === "lck" || slug === "lck") return "LCK";
  if (lower === "lpl" || slug === "lpl") return "LPL";
  if (lower === "lec" || slug === "lec" || lower.includes("emea championship")) return "LEC";
  if (lower === "lcs" || slug === "lcs") return "LCS";
  if (lower === "pcs" || slug === "pcs") return "PCS";
  if (lower === "vcs" || slug === "vcs") return "VCS";
  if (lower === "cblol" || slug === "cblol") return "CBLOL";
  if (lower === "ljl" || slug === "ljl") return "LJL";
  if (lower === "lla" || slug === "lla") return "LLA";
  if (lower === "kespa cup" || slug === "kespa_cup" || lower.includes("kespa")) return "KeSPA Cup";
  return null;
}

const UNSTARTED_CUTOFF_MS = 3 * 60 * 60 * 1000;
const INPROGRESS_CUTOFF_MS = 90 * 60 * 1000;
const SAME_MATCH_WINDOW_MS = 6 * 60 * 60 * 1000;

/** 클라이언트 RiotEsportsService.reconcileUnreportedResults와 동일한 감지 조건. */
function needsReconciliation(m: Match): boolean {
  const now = Date.now();
  const start = m.startTime.getTime();
  const isStaleUnstarted = m.state === "unstarted" && start < now - UNSTARTED_CUTOFF_MS;
  const isZeroScoreCompleted = m.state === "completed" && m.scoreA === 0 && m.scoreB === 0;
  const isStuckInProgress = m.state === "inProgress" && start < now - INPROGRESS_CUTOFF_MS;
  return isStaleUnstarted || isZeroScoreCompleted || isStuckInProgress;
}

function normalizedName(name: string): string {
  return name.toUpperCase().trim();
}

/** 클라이언트 LeaguepediaService+History.teamsMatch와 동일 — 이름 포함 관계 또는 팀 코드 겹침. */
function teamsMatchOne(a: { name: string; code: string }, b: { name: string; code: string }): boolean {
  const nameA = normalizedName(a.name);
  const nameB = normalizedName(b.name);
  if (nameA === nameB || nameA.includes(nameB) || nameB.includes(nameA)) return true;
  const codeA = a.code.toUpperCase().trim();
  const codeB = b.code.toUpperCase().trim();
  if (codeA && (codeA === nameB || nameB.includes(codeA))) return true;
  if (codeB && (codeB === nameA || nameA.includes(codeB))) return true;
  return false;
}

function sameTeams(a: Match, b: Match): boolean {
  return (teamsMatchOne(a.teamA, b.teamA) && teamsMatchOne(a.teamB, b.teamB)) ||
         (teamsMatchOne(a.teamA, b.teamB) && teamsMatchOne(a.teamB, b.teamA));
}

// 클라이언트는 15분 디스크 캐시(lpresults_ 키)가 있어서 같은 리그를 15분에 한 번만 조회하지만,
// 서버(syncSchedule)는 5분마다 돌아서 캐시 없이 그대로 두면 결과가 미보고 상태인 리그(케스파컵 등)를
// 매번 다시 조회하려다 Leaguepedia 레이트리밋(분당 1회 추정)에 계속 걸린다 — 실측 확인함(같은 리그가
// 5분마다 재시도 2회씩 실패, 실행 시간만 2분 넘게 낭비). 리그별 마지막 시도 시각을 Firestore에 남겨
// 15분 이내 재시도는 건너뛴다.
const COOLDOWN_MS = 15 * 60 * 1000;

async function isOnCooldown(lpName: string): Promise<boolean> {
  const doc = await db().collection("reconcileCooldowns").doc(lpName).get();
  const lastAttemptAt = doc.data()?.lastAttemptAt as admin.firestore.Timestamp | undefined;
  if (!lastAttemptAt) return false;
  return Date.now() - lastAttemptAt.toDate().getTime() < COOLDOWN_MS;
}

async function recordAttempt(lpName: string): Promise<void> {
  await db().collection("reconcileCooldowns").doc(lpName).set(
    { lastAttemptAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
}

/**
 * Riot이 결과를 안 채워주는 경기(케스파컵 등 — 오래 unstarted로 멈춤 / 0:0 completed /
 * 90분 넘게 안 바뀌는 inProgress)를 Leaguepedia의 현재 대회 페이지 결과로 보정한다.
 * 클라이언트 RiotEsportsService.reconcileUnreportedResults + LeaguepediaService.reconcileResults와
 * 동일한 로직 — 서버가 채우는 /matches 컬렉션도 같은 보정을 거쳐야, syncHistoricalDaily가 매일
 * 그대로 historicalMatches에 영구 저장할 때도 정확한 값이 들어간다(안 그러면 오답이 영구 박제됨).
 *
 * 매치가 하나라도 보정이 필요해야만(needsReconciliation) Leaguepedia를 호출한다 — 정상적으로
 * 결과가 갱신되는 리그(대부분)는 추가 API 호출 0회. 팀 로고 등 나머지 메타데이터는 Riot 원본을
 * 유지한다.
 */
export async function reconcileUnreportedResults(matches: Match[], league: League): Promise<Match[]> {
  if (!matches.some(needsReconciliation)) return matches;

  const lpName = leaguepediaName(league);
  if (!lpName) return matches;

  if (await isOnCooldown(lpName)) {
    console.log(`[reconcile] ${lpName} — 최근 ${COOLDOWN_MS / 60000}분 내 시도 기록 있어 건너뜀(쿨다운)`);
    return matches;
  }
  await recordAttempt(lpName);

  const pages = await fetchTournamentPages(lpName);
  if (pages.length === 0) return matches;
  const now = new Date();
  const currentPage = pages.find((p) => new Date(`${p.dateStart}T00:00:00Z`) <= now) ?? pages[0];

  const lpMatches = await fetchMatchesForOverviewPage(currentPage.page, lpName);
  if (lpMatches.length === 0) return matches;

  return matches.map((riot) => {
    if (!needsReconciliation(riot)) return riot;
    const lp = lpMatches.find((cand) =>
      cand.state === "completed" &&
      sameTeams(riot, cand) &&
      Math.abs(cand.startTime.getTime() - riot.startTime.getTime()) < SAME_MATCH_WINDOW_MS
    );
    if (!lp) return riot;

    const sameOrder = teamsMatchOne(riot.teamA, lp.teamA);
    const scoreA = sameOrder ? lp.scoreA : lp.scoreB;
    const scoreB = sameOrder ? lp.scoreB : lp.scoreA;
    console.log(`[reconcile] ${riot.teamA.code} vs ${riot.teamB.code} — 보정 ${riot.scoreA}-${riot.scoreB} → ${scoreA}-${scoreB}`);
    return { ...riot, scoreA, scoreB, state: "completed" as const };
  });
}
