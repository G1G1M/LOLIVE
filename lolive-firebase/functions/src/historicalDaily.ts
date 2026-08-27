import * as admin from "firebase-admin";
import { League, Match } from "./types";

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

// Riot League(name/slug) → Leaguepedia League_Short. LOLIVE 클라이언트의
// LeaguepediaService.leaguepediaName(for:)과 동일한 매핑을 서버에도 둔다 — 이 함수는
// /matches(Riot 기준)에서 온 완료 경기를 /historicalMatches(Leaguepedia 리그명 기준
// 인덱스)에 적립할 때만 쓰이므로, 실제로 백필된 12개 리그/대회만 다루면 충분하다.
export function leaguepediaName(league: League): string | null {
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

function historicalMatchToDoc(match: Match, leagueName: string, year: number): Record<string, unknown> {
  return {
    id: match.id,
    leagueName,
    year,
    overviewPage: "live-sync",
    league: match.league,
    teamA: match.teamA,
    teamB: match.teamB,
    scoreA: match.scoreA,
    scoreB: match.scoreB,
    startTime: match.startTime,
    state: match.state,
    blockName: match.blockName ?? null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

// /matches(syncSchedule/syncLive가 5분/1분마다 채워주는 실시간 캐시)에서 최근 완료된
// 경기를 골라 /historicalMatches(과거 시즌 "기록" 탭이 읽는 컬렉션)에도 복사해 넣는다.
// 예전엔 이 컬렉션이 로컬 스크립트(backfill_datalisk.py)로 1회 백필한 스냅샷이라 그
// 이후 끝난 경기가 "기록" 탭에 영영 안 나타났음 — 이 함수가 매일 그 간극을 메운다.
// 밴/게임별 상세 스탯(games 필드)은 여기서 채우지 않는다: 이 경로로 들어오는 매치 id는
// 과거 백필 데이터(oe_/lp_ 접두사)와 달리 Riot 원본 id 그대로라, 상세 화면 진입 시
// MatchDetailViewModel이 알아서 Riot API로 정상 조회한다.
export async function syncHistoricalMatches(): Promise<{ scanned: number; written: number }> {
  // merge write라 겹쳐도 안전 — 누락 방지 차원에서 매번 최근 3일치를 다시 훑는다.
  const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 3 * 24 * 60 * 60 * 1000);
  const snap = await db().collection("matches")
    .where("state", "==", "completed")
    .where("updatedAt", ">=", cutoff)
    .get();

  const yearsByLeague = new Map<string, Set<number>>();
  let batch = db().batch();
  let opsInBatch = 0;
  let written = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const league = data.league as League;
    const name = leaguepediaName(league);
    if (!name) continue;

    const startTime = (data.startTime as admin.firestore.Timestamp).toDate();
    const year = startTime.getFullYear();
    const match: Match = { ...data, id: doc.id, startTime } as Match;

    batch.set(db().collection("historicalMatches").doc(doc.id), historicalMatchToDoc(match, name, year), { merge: true });
    written++;
    opsInBatch++;

    if (!yearsByLeague.has(name)) yearsByLeague.set(name, new Set());
    yearsByLeague.get(name)!.add(year);

    if (opsInBatch >= 400) {
      await batch.commit();
      batch = db().batch();
      opsInBatch = 0;
    }
  }
  if (opsInBatch > 0) await batch.commit();

  // 연도 선택 칩이 읽는 인덱스(historicalTournaments.years)에 새 연도만 추가 — 기존
  // pages(Leaguepedia 크롤 결과)는 이 경로와 무관하니 건드리지 않는다.
  for (const [leagueName, years] of yearsByLeague) {
    await db().collection("historicalTournaments").doc(leagueName).set({
      years: admin.firestore.FieldValue.arrayUnion(...Array.from(years)),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  return { scanned: snap.size, written };
}
