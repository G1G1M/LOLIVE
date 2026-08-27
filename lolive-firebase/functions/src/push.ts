import * as admin from "firebase-admin";
import { Match } from "./types";

// index.ts의 admin.initializeApp()이 실행되기 전에 이 모듈이 import되면서
// admin.firestore()가 곧바로 호출되면 "default app이 없다" 에러가 나서, 실제
// 사용 시점(함수 호출 시점)에 지연 평가되도록 getter로 감싼다.
function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

interface DeviceTokenDoc {
  token: string;
  favoriteTeamCodes: string[];
  platform: "ios";
  updatedAt: FirebaseFirestore.FieldValue;
}

export async function registerDeviceToken(
  token: string,
  favoriteTeamCodes: string[]
): Promise<void> {
  const doc: DeviceTokenDoc = {
    token,
    favoriteTeamCodes: favoriteTeamCodes.map((c) => c.toUpperCase()),
    platform: "ios",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await db().collection("deviceTokens").doc(token).set(doc);
}

// 실제 라이브 경기 없이도 "앱이 완전히 종료된 상태에서 원격 푸시가 도착하는지"를
// 바로 검증하기 위한 관리자용 테스트 — 가장 최근에 등록된 기기 토큰 하나로 발송한다.
export async function sendTestPushToLatestDevice(): Promise<{ sent: boolean; reason?: string }> {
  const snap = await db().collection("deviceTokens").orderBy("updatedAt", "desc").limit(1).get();
  if (snap.empty) return { sent: false, reason: "등록된 기기 토큰이 없음" };

  const token = (snap.docs[0].data() as DeviceTokenDoc).token;
  await admin.messaging().send({
    token,
    notification: {
      title: "LOLIVE 테스트 푸시",
      body: "앱이 꺼져 있어도 이 알림이 보이면 백그라운드 푸시가 정상 작동하는 거예요.",
    },
    apns: { payload: { aps: { sound: "default" } } },
  });
  return { sent: true };
}

// 팀 코드 1~2개(교전 중인 두 팀)를 즐겨찾기한 기기를 찾아 각자의 응원팀 관점으로
// 메시지를 만들어 보낸다. 만료된 토큰(재설치/삭제 등)은 응답에서 걸러내 정리한다.
export async function notifyFavoritedDevices(
  teamCodes: string[],
  build: (myCode: string) => { title: string; body: string }
): Promise<void> {
  const codes = teamCodes.map((c) => c.toUpperCase()).filter(Boolean);
  if (codes.length === 0) return;

  const snap = await db()
    .collection("deviceTokens")
    .where("favoriteTeamCodes", "array-contains-any", codes)
    .get();
  if (snap.empty) return;

  const messages: admin.messaging.TokenMessage[] = [];
  for (const doc of snap.docs) {
    const data = doc.data() as DeviceTokenDoc;
    const myCode = codes.find((c) => data.favoriteTeamCodes.includes(c));
    if (!myCode) continue;
    const { title, body } = build(myCode);
    messages.push({
      token: data.token,
      notification: { title, body },
      apns: { payload: { aps: { sound: "default" } } },
    });
  }
  if (messages.length === 0) return;

  const res = await admin.messaging().sendEach(messages);
  const staleTokens: string[] = [];
  res.responses.forEach((r, i) => {
    if (!r.success && r.error?.code === "messaging/registration-token-not-registered") {
      staleTokens.push(messages[i].token);
    }
  });
  if (staleTokens.length > 0) {
    const batch = db().batch();
    staleTokens.forEach((t) => batch.delete(db().collection("deviceTokens").doc(t)));
    await batch.commit();
  }
}

function perspective(match: Match, myCode: string) {
  const isTeamA = match.teamA.code.toUpperCase() === myCode;
  const myTeam = isTeamA ? match.teamA : match.teamB;
  const opponent = isTeamA ? match.teamB : match.teamA;
  const myScore = isTeamA ? match.scoreA : match.scoreB;
  const oppScore = isTeamA ? match.scoreB : match.scoreA;
  return { myTeam, opponent, myScore, oppScore };
}

export async function notifyMatchStart(match: Match): Promise<void> {
  await notifyFavoritedDevices([match.teamA.code, match.teamB.code], (myCode) => {
    const { myTeam, opponent } = perspective(match, myCode);
    return {
      title: `${myTeam.name} 경기 시작`,
      body: `vs ${opponent.name} · ${match.league.name}`,
    };
  });
}

// 서버는 1분 주기로만 확인하기 때문에 세트 종료·시작을 항상 같은 시점에 함께 발견한다
// (클라이언트의 실시간 폴링과 달리 둘을 따로 감지할 수 없음) — 그래서 알림 두 번이 아니라
// 하나로 합쳐서 보낸다.
export async function notifySetChange(match: Match, endedSet: number, newSet: number): Promise<void> {
  await notifyFavoritedDevices([match.teamA.code, match.teamB.code], (myCode) => {
    const { opponent, myScore, oppScore } = perspective(match, myCode);
    return {
      title: `Game ${endedSet} 종료 · Game ${newSet} 시작`,
      body: `${myCode} ${myScore} - ${oppScore} ${opponent.code}`,
    };
  });
}

export async function notifyMatchEnd(match: Match): Promise<void> {
  await notifyFavoritedDevices([match.teamA.code, match.teamB.code], (myCode) => {
    const { myTeam, opponent, myScore, oppScore } = perspective(match, myCode);
    return {
      title: myScore > oppScore ? `${myTeam.name} 승리` : `${myTeam.name} 패배`,
      body: `${myScore} - ${oppScore}  vs ${opponent.name}`,
    };
  });
}
