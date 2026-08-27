import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { fetchLeagues, fetchSchedule, fetchLive } from "./riot";
import { League, Match } from "./types";
import {
  registerDeviceToken as registerDeviceTokenImpl,
  notifyMatchStart,
  notifySetChange,
  notifyMatchEnd,
  sendTestPushToLatestDevice,
} from "./push";
import { backfillMatchDetail, retryPendingMatchDetails } from "./matchDetails";
import { backfillLeagueYear, importLeagueYear } from "./historicalBackfill";
import type { TournamentPage } from "./historical";
import { syncHistoricalMatches } from "./historicalDaily";
import { reconcileUnreportedResults } from "./reconcile";

admin.initializeApp();
const db = admin.firestore();
db.settings({ ignoreUndefinedProperties: true });

// ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
// 공�? ????
// ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�

function matchToDoc(match: Match): Record<string, unknown> {
  return {
    id: match.id,
    league: {
      id: match.league.id,
      slug: match.league.slug,
      name: match.league.name,
      region: match.league.region,
      imageURL: match.league.imageURL,
    },
    teamA: {
      id: match.teamA.id,
      name: match.teamA.name,
      code: match.teamA.code,
      imageURL: match.teamA.imageURL,
    },
    teamB: {
      id: match.teamB.id,
      name: match.teamB.name,
      code: match.teamB.code,
      imageURL: match.teamB.imageURL,
    },
    scoreA: match.scoreA,
    scoreB: match.scoreB,
    startTime: admin.firestore.Timestamp.fromDate(match.startTime),
    state: match.state,
    blockName: match.blockName,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

// ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
// [1] 리그 + ?��? ?��?� ?�기화 ?�� 5분마??
// ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
export const syncSchedule = functions
  .region("asia-northeast3")
  // 기본 타임아웃(60초)로는 Leaguepedia 보정이 필요한 리그가 하나라도 있으면 부족함
  // (레이트리밋 재시도까지 포함하면 리그당 최대 ~140초) — 넉넉히 잡음.
  .runWith({ timeoutSeconds: 300, memory: "256MB" })
  .pubsub.schedule("every 5 minutes")
  .onRun(async () => {
    // 1-a. 리그 목록 가져오기
    const leagues = await fetchLeagues();
    if (!leagues.length) { console.log("[syncSchedule] 리그 없음"); return; }

    // 1-b. 1시간에 한 번만 하는 "정비" 작업 여부 — 리그 메타데이터, 그리고 아래에서 한참
    // 남은 예정 경기를 여기에 같이 태운다. 둘 다 거의 안 바뀌는데 5분마다 매번 다시 쓰면
    // Firestore 쓰기 할당량을 낭비하니, 새로 생기거나 바뀐 걸 잡아내는 용도로 1시간에
    // 한 번씩만 훑는다.
    const hourlySyncedAtRef = db.collection("_meta").doc("hourlySyncedAt");
    const hourlySyncedAtSnap = await hourlySyncedAtRef.get();
    const hourlyLastSyncedMs = (hourlySyncedAtSnap.data()?.at as admin.firestore.Timestamp | undefined)
      ?.toMillis() ?? 0;
    const isHourlyPass = Date.now() - hourlyLastSyncedMs > 60 * 60 * 1000;

    // 1-b-2. Firestore /leagues 업데이트 — 이름/로고가 거의 안 바뀌는데 5분마다 45개 문서를
    // 매번 다시 썼더니 Firestore 쓰기 할당량을 크게 낭비함(실측). 1시간에 한 번만 갱신.
    if (isHourlyPass) {
      const leagueBatch = db.batch();
      for (const l of leagues) {
        leagueBatch.set(db.collection("leagues").doc(l.id), {
          ...l, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      leagueBatch.set(hourlySyncedAtRef, { at: admin.firestore.FieldValue.serverTimestamp() });
      await leagueBatch.commit();
    }

    // 1-c. 리그별 일정 병렬 fetch
    const leagueMap = new Map<string, League>(leagues.map((l) => [l.id, l]));
    const results = await Promise.allSettled(
      leagues.map((l) => fetchSchedule(l.id, leagueMap))
    );

    // 1-c-2. Riot이 결과를 안 채워주는 경기(케스파컵 등)를 Leaguepedia로 보정 — 클라이언트가
    // 화면 표시 시점에 하던 걸 서버에도 반영해서, syncHistoricalDaily가 매일 그대로 영구
    // 저장할 때도 정확한 값이 들어가게 한다. 보정이 필요한 매치가 없는 리그는 Leaguepedia를
    // 호출하지 않는다(reconcileUnreportedResults 내부에서 판단).
    const reconciledResults = await Promise.all(
      leagues.map(async (l, idx) => {
        const r = results[idx];
        if (r.status !== "fulfilled") return [] as Match[];
        return reconcileUnreportedResults(r.value, l);
      })
    );

    const allMatches: Match[] = reconciledResults.flat();

    // 1-d. 중복 제거 후 /matches 저장 (400개씩 batch 처리)
    const seen = new Set<string>();
    const unique = allMatches.filter((m) => seen.has(m.id) ? false : (seen.add(m.id), true));

    // 실시간성이 필요한 경기만 5분마다 다시 쓰고, 나머지는 건너뛰거나 1시간에 한 번만 쓴다
    // (실측: 30일간 613만 건 → 완료 경기 생략만으로 30% 수준까지 줄었지만, 여전히 대부분이
    // "몇 주 뒤 예정된, 어차피 거의 안 바뀌는" 경기였음).
    //  - 완료된 지 오래된 경기: 절대 안 바뀌니 생략. 완료 직후 보정(reconcileUnreportedResults)이
    //    뒤늦게 들어올 여유만 COMPLETED_REWRITE_GRACE_MS만큼 준다. syncHistoricalDaily가 읽는
    //    "최근 3일 내 updatedAt" 조건은 이 유예 시간 동안 최소 한 번은 갱신되므로 영향 없음.
    //  - 곧 시작하는(NEAR_TERM_MS 이내) 예정 경기: 막판 일정 변경 가능성이 있어 계속 최신화.
    //  - 한참 남은 예정 경기: 새로 추가되거나 드물게 일정이 바뀌는 것만 잡으면 되니
    //    isHourlyPass일 때만(1시간에 한 번) 기록.
    //  - 진행 중 경기: 항상 최신화(실시간 스코어는 주로 syncLive가 담당하지만 안전하게 유지).
    const COMPLETED_REWRITE_GRACE_MS = 6 * 60 * 60 * 1000;
    const NEAR_TERM_MS = 48 * 60 * 60 * 1000;
    const toWrite = unique.filter((m) => {
      if (m.state === "completed") {
        return Date.now() - m.startTime.getTime() < COMPLETED_REWRITE_GRACE_MS;
      }
      if (m.state === "unstarted") {
        const startsSoon = m.startTime.getTime() - Date.now() < NEAR_TERM_MS;
        return startsSoon || isHourlyPass;
      }
      return true;
    });

    for (let i = 0; i < toWrite.length; i += 400) {
      const batch = db.batch();
      for (const match of toWrite.slice(i, i + 400)) {
        batch.set(db.collection("matches").doc(match.id), matchToDoc(match), { merge: true });
      }
      await batch.commit();
      console.log(`[syncSchedule] batch commit — 이번 배치 쓰기 ${Math.min(400, toWrite.length - i)}건`);
    }
    // 디버깅용 — reads: hourlySyncedAtRef 조회 1건뿐(매치/리그 쓰기 전 별도 조회 없음, 시간
    // 기반 필터라서). writes: 정비 실행 시 리그 45개+메타 1건, 그리고 이번에 기록한 경기 수.
    const readCount = 1;
    const leagueWriteCount = isHourlyPass ? leagues.length + 1 : 0;
    const writeCount = leagueWriteCount + toWrite.length;
    console.log(
      `[syncSchedule] reads=${readCount} writes=${writeCount} ` +
      `(리그쓰기=${leagueWriteCount}, 경기쓰기=${toWrite.length}) ` +
      `리그 ${leagues.length}개(${isHourlyPass ? "정비 실행" : "정비 생략"}), ` +
      `경기 ${unique.length}개 중 ${toWrite.length}개 기록`
    );
  });

// ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
// [2] ?�이�? 경기 ?�기화 ?�� 1분마??
// ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
// syncLive이 1분마다 leagues 컬렉션(45개 문서)을 매번 통째로 다시 읽어서 Firestore 읽기의
// 대부분을 차지했음(실측: 시간당 약 2,700건, 전체 읽기의 70%). 리그 이름표는 거의 안 바뀌니
// 함수 인스턴스가 재사용되는(warm) 동안은 메모리에 캐싱해두고 1시간 동안은 Firestore를 아예
// 안 읽는다 — 콜드 스타트 직후나 1시간 지난 뒤에만 다시 읽는다.
let cachedLeagueMap: Map<string, League> | null = null;
let leagueMapCachedAt = 0;
const LEAGUE_MAP_CACHE_MS = 60 * 60 * 1000;

// 디버깅용 — 이번 호출이 캐시를 썼는지(Firestore 읽기 0건) 아니면 다시 읽었는지(읽기
// N건) 호출부가 로그에 바로 찍을 수 있도록 읽기 건수까지 같이 반환한다.
async function getLeagueMap(): Promise<{ map: Map<string, League>; reads: number }> {
  if (cachedLeagueMap && Date.now() - leagueMapCachedAt < LEAGUE_MAP_CACHE_MS) {
    return { map: cachedLeagueMap, reads: 0 };
  }
  const snap = await db.collection("leagues").get();
  cachedLeagueMap = new Map(snap.docs.map((d) => [d.id, d.data() as League]));
  leagueMapCachedAt = Date.now();
  return { map: cachedLeagueMap, reads: snap.size };
}

export const syncLive = functions
  .region("asia-northeast3")
  .pubsub.schedule("every 1 minutes")
  .onRun(async () => {
    const { map: leagueMap, reads: leagueMapReads } = await getLeagueMap();
    console.log(`[syncLive] leagueMap ${leagueMapReads === 0 ? "cache hit(읽기 0건)" : `refetch(읽기 ${leagueMapReads}건)`}`);

    const liveMatches = await fetchLive(leagueMap);

    // 기존 라이브 경기 상태 (id → 직전에 저장해둔 match/currentSet) — 경기 시작·세트 변경·
    // 경기 종료를 감지하는 기준선으로 쓴다. match.startTime은 Firestore Timestamp로 저장돼
    // 있어 Match.startTime(Date) 타입과 완전히 일치하진 않지만, 푸시 로직에서 startTime을
    // 쓰지 않아 문제없다.
    const prevSnap = await db.collection("liveMatches").get();
    const prevById = new Map(
      prevSnap.docs.map((d) => [d.id, d.data() as { match: Match; currentSet: number }])
    );
    const prevIds = new Set(prevById.keys());
    const newIds  = new Set(liveMatches.map((lm) => lm.match.id));

    const batch = db.batch();
    const pushes: Promise<void>[] = [];
    const detailBackfills: Promise<void>[] = [];
    // 디버깅용 쓰기 건수 카운터 — 배치 안에 실제로 몇 개의 문서 쓰기(set/update/delete)가
    // 담기는지 실행마다 로그로 남겨서, 나중에 Cloud Logging에서 시간대별 쓰기 추이를
    // grep만으로 바로 뽑아볼 수 있게 한다.
    let writeCount = 0;
    let skippedUnchangedCount = 0;

    // 종료된 경기 제거 + /matches 상태 completed로 업데이트 + 결과 푸시 + 상세(밴픽) 영구 캐싱
    for (const id of prevIds) {
      if (!newIds.has(id)) {
        batch.delete(db.collection("liveMatches").doc(id));
        batch.update(db.collection("matches").doc(id), {
          state: "completed",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writeCount += 2;
        const prevMatch = prevById.get(id)?.match;
        if (prevMatch) pushes.push(notifyMatchEnd(prevMatch));
        detailBackfills.push(backfillMatchDetail(id));
      }
    }

    // 신규/진행 중 라이브 경기 반영 + 경기 시작·세트 변경 푸시
    for (const lm of liveMatches) {
      const doc: Record<string, unknown> = {
        match: matchToDoc(lm.match),
        currentSet: lm.currentSet,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      batch.set(db.collection("liveMatches").doc(lm.match.id), doc, { merge: true });
      writeCount++;

      const prev = prevById.get(lm.match.id);
      // /matches는 inProgress로 업데이트 — 방금 읽어온 prevById와 비교해서 스코어/세트/상태가
      // 실제로 안 바뀌었으면 쓰기를 생략한다(추가 읽기 없이 이미 메모리에 있는 값으로 비교).
      // 매분 라이브 경기 전체를 무조건 다시 쓰던 게 쓰기 낭비의 한 축이었음.
      const changed = !prev ||
        prev.match.scoreA !== lm.match.scoreA ||
        prev.match.scoreB !== lm.match.scoreB ||
        prev.match.state !== lm.match.state ||
        prev.currentSet !== lm.currentSet;
      if (changed) {
        batch.set(db.collection("matches").doc(lm.match.id), matchToDoc(lm.match), { merge: true });
        writeCount++;
      } else {
        skippedUnchangedCount++;
      }

      if (!prev) {
        pushes.push(notifyMatchStart(lm.match));
      } else if (lm.currentSet > prev.currentSet) {
        pushes.push(notifySetChange(lm.match, prev.currentSet, lm.currentSet));
      }
    }

    await batch.commit();
    await Promise.allSettled(pushes);
    await Promise.allSettled(detailBackfills);
    await retryPendingMatchDetails();
    const totalReads = leagueMapReads + prevSnap.size;
    console.log(
      `[syncLive] reads=${totalReads} writes=${writeCount} ` +
      `(leagues읽기=${leagueMapReads}, liveMatches읽기=${prevSnap.size}, ` +
      `스코어 변동없어 쓰기 생략=${skippedUnchangedCount}건) ` +
      `라이브 ${liveMatches.length}개 동기화, 푸시 ${pushes.length}건 발송, 상세 백필 ${detailBackfills.length}건`
    );
  });

// ────────────────────────────────────────────────────────────────
// [3] 과거 시즌 기록 매일 자동 갱신 — 새벽 3시(KST)
// ────────────────────────────────────────────────────────────────
// syncSchedule/syncLive가 채워주는 /matches는 실시간용 캐시일 뿐, "기록" 탭이 읽는
// /historicalMatches(예전에 로컬 스크립트로 1회 백필한 스냅샷)와는 별개였다. 매일
// 완료된 경기를 여기로도 복사해서 "기록" 탭이 현재 시즌도 계속 최신으로 보여주게 한다.
export const syncHistoricalDaily = functions
  .region("asia-northeast3")
  .pubsub.schedule("every day 03:00")
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    const { scanned, written } = await syncHistoricalMatches();
    console.log(`[syncHistoricalDaily] 완료 경기 ${scanned}건 스캔, ${written}건 기록 반영`);
  });

// ────────────────────────────────────────────────────────────────
// [5] 기기 푸시 토큰 등록 — Callable
// ────────────────────────────────────────────────────────────────
export const registerDeviceToken = functions
  .region("asia-northeast3")
  .https.onCall(async (data) => {
    const token = data?.token as string | undefined;
    const favoriteTeamCodes = (data?.favoriteTeamCodes as string[] | undefined) ?? [];
    if (!token) throw new functions.https.HttpsError("invalid-argument", "token 필요");
    await registerDeviceTokenImpl(token, favoriteTeamCodes);
    return { ok: true };
  });

// ────────────────────────────────────────────────────────────────
// [5-1] 테스트 푸시 발송 — 관리자용. 가장 최근 등록된 기기로 즉시 발송.
// ────────────────────────────────────────────────────────────────
export const sendTestPush = functions
  .region("asia-northeast3")
  .https.onCall(async () => {
    return await sendTestPushToLatestDevice();
  });

// ────────────────────────────────────────────────────────────────
// [6] 완료 경기 상세(밴픽 등) 조회 — Callable. 없으면 null 반환(앱이 Riot 직접 호출로 폴백)
// ────────────────────────────────────────────────────────────────
export const getMatchDetail = functions
  .region("asia-northeast3")
  .https.onCall(async (data) => {
    const matchId = data?.matchId as string | undefined;
    if (!matchId) throw new functions.https.HttpsError("invalid-argument", "matchId 필요");

    const doc = await db.collection("matchDetails").doc(matchId).get();
    if (!doc.exists) return { detail: null };
    return { detail: doc.data() };
  });

// ────────────────────────────────────────────────────────────────
// [7] 과거 시즌(2013~) 백필 — 관리자용 Callable. 앱에서 호출 안 함.
// 리그(Leaguepedia 이름) + 연도 하나씩 수동으로 실행. Leaguepedia 레이트리밋 때문에
// 실행시간이 길어질 수 있어 타임아웃을 넉넉히 잡음.
// ────────────────────────────────────────────────────────────────
export const backfillHistoricalMatches = functions
  .region("asia-northeast3")
  .runWith({ timeoutSeconds: 540, memory: "256MB" })
  .https.onCall(async (data) => {
    const leagueName = data?.leagueName as string | undefined;
    const year = data?.year as number | undefined;
    if (!leagueName || !year) {
      throw new functions.https.HttpsError("invalid-argument", "leagueName, year 필요");
    }
    return await backfillLeagueYear(leagueName, year);
  });

// ────────────────────────────────────────────────────────────────
// [7-1] 과거 시즌 백필 — 데이터 주입용 Callable. 관리자용, 앱에서 호출 안 함.
// Google Cloud Functions의 아시아 리전 공유 IP가 Leaguepedia에 장기 차단당해서, 로컬(차단
// 안 된 IP)에서 미리 fetch한 데이터를 받아 Firestore 저장만 여기서 처리한다.
// ────────────────────────────────────────────────────────────────
export const importHistoricalMatches = functions
  .region("asia-northeast3")
  .runWith({ timeoutSeconds: 300, memory: "256MB" })
  .https.onCall(async (data) => {
    const leagueName = data?.leagueName as string | undefined;
    const year = data?.year as number | undefined;
    const pages = data?.pages as TournamentPage[] | undefined;
    const matchesByPage = data?.matchesByPage as
      Array<{ page: string; matches: Match[] }> | undefined;
    if (!leagueName || !year || !pages || !matchesByPage) {
      throw new functions.https.HttpsError(
        "invalid-argument", "leagueName, year, pages, matchesByPage 필요"
      );
    }
    return await importLeagueYear(leagueName, year, pages, matchesByPage);
  });

// ────────────────────────────────────────────────────────────────
// [8] 과거 시즌 연도 목록 조회 — Callable
// ────────────────────────────────────────────────────────────────
export const getHistoricalYears = functions
  .region("asia-northeast3")
  .https.onCall(async (data) => {
    const leagueName = data?.leagueName as string | undefined;
    if (!leagueName) throw new functions.https.HttpsError("invalid-argument", "leagueName 필요");

    const doc = await db.collection("historicalTournaments").doc(leagueName).get();
    if (!doc.exists) return { years: [] };
    return { years: (doc.data()?.years as number[] | undefined) ?? [] };
  });

// ────────────────────────────────────────────────────────────────
// [9] 과거 시즌 경기 목록 조회 — Callable
// ────────────────────────────────────────────────────────────────
export const getHistoricalMatches = functions
  .region("asia-northeast3")
  .https.onCall(async (data) => {
    const leagueName = data?.leagueName as string | undefined;
    const year = data?.year as number | undefined;
    if (!leagueName || !year) {
      throw new functions.https.HttpsError("invalid-argument", "leagueName, year 필요");
    }

    const snap = await db.collection("historicalMatches")
      .where("leagueName", "==", leagueName)
      .where("year", "==", year)
      .get();
    // startTime은 Firestore Timestamp라 Callable 응답으로 그대로 보내면 클라이언트에서
    // 디코딩 형식이 애매해진다 — ISO8601 문자열로 명시적으로 변환해서 보낸다.
    const matches = snap.docs.map((d) => {
      const data = d.data();
      const startTime = (data.startTime as admin.firestore.Timestamp).toDate().toISOString();
      return { ...data, startTime };
    });
    return { matches };
  });

// getPlayerImageURL / getPlayerStats(선수 이미지·시즌 스탯 Callable)는 여기 있었으나
// 앱이 실제로는 클라이언트에서 Leaguepedia를 직접 호출하도록 별도 구현돼 있어(LeaguepediaService.swift)
// 30일간 호출 0건으로 확인돼 삭제함(2026-08-10). playerImages/playerStats 컬렉션도 더 이상 안 씀.
