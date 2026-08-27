import * as admin from "firebase-admin";
import { fetchTournamentPages, fetchMatchesForOverviewPage, TournamentPage } from "./historical";
import { Match } from "./types";

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function historicalMatchToDoc(
  match: Match,
  leagueName: string,
  year: number,
  overviewPage: string
): Record<string, unknown> {
  return {
    id: match.id,
    leagueName,
    year,
    overviewPage,
    league: match.league,
    teamA: match.teamA,
    teamB: match.teamB,
    scoreA: match.scoreA,
    scoreB: match.scoreB,
    startTime: admin.firestore.Timestamp.fromDate(match.startTime),
    state: match.state,
    blockName: match.blockName,
    games: match.games,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function writeYearData(
  leagueName: string,
  year: number,
  allPages: TournamentPage[],
  matchesByPage: Array<{ page: string; matches: Match[] }>
): Promise<{ pagesProcessed: number; matchesWritten: number }> {
  let matchesWritten = 0;
  for (const { page, matches } of matchesByPage) {
    for (let i = 0; i < matches.length; i += 400) {
      const batch = db().batch();
      for (const m of matches.slice(i, i + 400)) {
        batch.set(
          db().collection("historicalMatches").doc(m.id),
          historicalMatchToDoc(m, leagueName, year, page),
          { merge: true }
        );
      }
      await batch.commit();
    }
    matchesWritten += matches.length;
  }

  // 대회 페이지/연도 인덱스는 매번 전체를 다시 씀 — allPages 자체가 이미 리그 전체 목록이라
  // 특정 연도만 백필해도 인덱스는 항상 최신 상태로 유지됨.
  const years = Array.from(new Set(allPages.map((p) => p.year))).sort((a, b) => b - a);
  await db().collection("historicalTournaments").doc(leagueName).set(
    { pages: allPages, years, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  return { pagesProcessed: matchesByPage.length, matchesWritten };
}

// 리그(Leaguepedia 이름) + 연도 하나를 통째로 백필한다 — 관리자가 리그·연도 조합별로
// 직접 호출. 한 번에 다 하면 레이트리밋 + 함수 실행시간 제한에 걸리기 쉬워서 연도 단위로 쪼갬.
export async function backfillLeagueYear(
  leagueName: string,
  year: number
): Promise<{ pagesProcessed: number; matchesWritten: number }> {
  const allPages = await fetchTournamentPages(leagueName);
  const yearPages = allPages.filter((p) => p.year === year);

  const matchesByPage: Array<{ page: string; matches: Match[] }> = [];
  for (const entry of yearPages) {
    const matches = await fetchMatchesForOverviewPage(entry.page, leagueName);
    matchesByPage.push({ page: entry.page, matches });
  }

  return writeYearData(leagueName, year, allPages, matchesByPage);
}

// backfillLeagueYear와 동일한 결과를 만들지만, Leaguepedia를 직접 호출하지 않고 이미
// 가져와진 데이터(로컬 IP 등 레이트리밋에 안 걸리는 곳에서 미리 fetch)를 받아서 Firestore에만
// 쓴다 — Google Cloud Functions의 아시아 리전 공유 IP가 Leaguepedia에 장기 차단당해서,
// 조회는 로컬에서 하고 저장만 서버(이미 정상 동작하는 Admin SDK 자격증명)에 맡기는 우회 경로.
export async function importLeagueYear(
  leagueName: string,
  year: number,
  allPages: TournamentPage[],
  matchesByPage: Array<{ page: string; matches: Match[] }>
): Promise<{ pagesProcessed: number; matchesWritten: number }> {
  const parsedMatches = matchesByPage.map(({ page, matches }) => ({
    page,
    matches: matches.map((m) => ({ ...m, startTime: new Date(m.startTime) })),
  }));
  return writeYearData(leagueName, year, allPages, parsedMatches);
}
