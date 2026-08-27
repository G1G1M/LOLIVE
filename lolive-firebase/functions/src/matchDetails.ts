import * as admin from "firebase-admin";
import { fetchEventDetails, isGenuinelyComplete } from "./riot";

// index.ts의 admin.initializeApp()보다 이 모듈의 import가 먼저 실행되므로(push.ts와
// 동일한 이유) db() 지연 평가로 감싼다.
function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

const PENDING_MAX_AGE_MS = 24 * 60 * 60 * 1000;

// 방금 종료된 경기 하나를 시도 — 성공하면 matchDetails에 영구 저장, 아직 Riot 쪽 상세가
// 안 채워졌거나 호출 자체가 실패하면 pendingMatchDetails에 등록해서 다음 폴링에 재시도.
export async function backfillMatchDetail(matchId: string): Promise<void> {
  try {
    const detail = await fetchEventDetails(matchId);
    if (isGenuinelyComplete(detail)) {
      await db().collection("matchDetails").doc(matchId).set({
        ...detail,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await db().collection("pendingMatchDetails").doc(matchId).delete();
    } else {
      await markPending(matchId);
    }
  } catch (error) {
    console.error(`[matchDetails] ${matchId} 조회 실패:`, error);
    await markPending(matchId);
  }
}

async function markPending(matchId: string): Promise<void> {
  const ref = db().collection("pendingMatchDetails").doc(matchId);
  const existing = await ref.get();
  if (!existing.exists) {
    await ref.set({ createdAt: admin.firestore.FieldValue.serverTimestamp() });
  }
}

// syncLive가 매 폴링(1분)마다 호출 — 아직 못 채운 경기 상세를 재시도하고, 24시간 지나도
// 안 채워지면 포기하고 지운다(Riot이 끝내 안 채워주는 극소수 경기에 대한 무한 재시도 방지).
export async function retryPendingMatchDetails(): Promise<void> {
  const snap = await db().collection("pendingMatchDetails").get();
  if (snap.empty) return;

  const now = Date.now();
  for (const doc of snap.docs) {
    const createdAtMs = (doc.data().createdAt as FirebaseFirestore.Timestamp | undefined)?.toMillis() ?? now;
    if (now - createdAtMs > PENDING_MAX_AGE_MS) {
      await doc.ref.delete();
      continue;
    }
    await backfillMatchDetail(doc.id);
  }
}
