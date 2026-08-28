# LOLIVE

[![CI](https://github.com/G1G1M/LOLIVE/actions/workflows/ci.yml/badge.svg)](https://github.com/G1G1M/LOLIVE/actions/workflows/ci.yml)

리그 오브 레전드 e스포츠 경기 정보 iOS 앱

---

## 소개

전 세계 LoL 프로 경기 일정, 실시간 스코어, 팀·선수 정보 및 시즌 스탯을 한눈에 확인할 수 있는 iOS 앱입니다.

## 기술 스택

| 항목 | 내용 |
|------|------|
| 플랫폼 | iOS 17+ |
| 언어 | Swift 6.0 |
| UI | SwiftUI (라이트/다크 모드 앱 설정에서 시스템 기본/라이트/다크 직접 선택 가능), iOS 26 Liquid Glass 적용(배포 타깃 17.6은 유지, `#available` 분기) |
| 아키텍처 | MVVM + `@Observable` |
| 네트워크 | URLSession + async/await |
| 로컬 저장 | SwiftData |
| 알림 | UNUserNotificationCenter (로컬) + Firebase Cloud Messaging (서버 푸시) |
| 위젯 | ActivityKit + WidgetKit |
| 백엔드 | Firebase (Cloud Functions + Firestore) — `lolive-firebase/` |
| 데이터 공유 | App Groups (main app ↔ widget) |

## 사용 API

| API | 용도 |
|-----|------|
| Riot Esports API (비공식) | 경기 일정, 라이브 스코어, 팀·선수 정보 |
| Leaguepedia MediaWiki Cargo API | Oracle's Elixir로도 못 찾은 경기의 최종 폴백(시즌 스탯/챔피언픽/밴/결과 보정 전부) |
| oe.datalisk.io (Oracle's Elixir 비공식 API) | 과거 시즌 백필(2013년~) 원본 데이터, 선수 프로필 사진, 리그 공식 출전 선수 명단, 팀/선수 시즌 스탯, 게임별 챔피언픽(챔피언풀), 밴 데이터, 케스파컵처럼 Riot이 결과를 안 채워주는 경기의 스코어·상태 보정 |

## 주요 기능

### 대회 상세 (Worlds / MSI)
- 연도별 탭으로 과거~현재 전체 대회 기록 조회 (Riot API 최신 데이터 + 서버(Firestore) 백필 데이터 병합)
- 라운드(플레이-인 / 그룹 / 8강 / 4강 / 결승 등) 칩 선택 → 날짜별 경기 목록, 언어(한/영)가 달라도 같은 라운드는 자동으로 하나로 묶임
- 리그 상세 "기록" 탭과 동일한 서버 경로라 레이트리밋 없이 연도 전체를 한 번에 빠르게 조회

### Today
- FotMob 스타일 날짜 선택 스트립 + 선택 날짜 기준 리그별 경기 목록
- LIVE 경기 자동 감지 및 실시간 폴링
- 전체 / 즐겨찾기 / LIVE 필터 (라디오 버튼처럼 하나만 선택)

### Standings
- 전 세계 리그 순위표 (W-L / GD / 승률), 완료 경기 기준으로 항상 직접 재계산
- LCK 등 스플릿 넘어 누적되는 순위표 대응 (레전드/라이즈 그룹) — 정규시즌 라운드만 집계, 플레이오프 라운드는 제외
- 리그 선택 칩(lazy 로딩 + 캐싱)

### 리그 상세
- 탭 기반 레이아웃 (순위 / 일정 / 팀 / 선수 / 기록)
- 기록 탭: 서버(Firestore) 백필 데이터로 과거 시즌 조회 — 정규 리그(LCK/LPL/LEC 등)까지 지원, 연도 + 라운드 드롭다운
  (컵/정규시즌/플레이오프 등 시즌 구간이 여러 개라도 라운드가 안 섞이게 자동 구분, 매일 동기화되는 임시 기록과
  정식 백필 데이터가 겹치면 자동으로 중복 제거)

### Players
- 전 세계 선수 통합 목록, 포지션/리그 필터, 이름 검색
- 선수 상세: 시즌 스탯, 챔피언풀, 최근 경기 결과

### 검색
- 리그 / 팀 / 선수 통합 검색, 네이티브 `.searchable` 확장 애니메이션 (탭하면 검색창만 펼쳐지고, 직접 탭해야 키보드 표시)
- 애플 뮤직 스타일 카테고리 필터 칩(리그 / 팀 / 선수)으로 결과 좁히기
- 검색 결과에서 팀·선수 상세 바로 이동, 즐겨찾기 인라인 토글

### 팀 상세
- 탭 기반 레이아웃 (선수단 / 스탯 / 상대 전적 / 최근경기)
- 선수단: 최근 경기 실제 출전 명단 기준으로 현재 주전 우선 표시, 나머지는 "기타 등록 선수"로 분리 (Riot API 자체엔 주전/후보 구분이 없어 포지션당 여러 명이 그대로 옴)
- 스탯: 시즌 승률, 평균 게임시간, 15분 골드 격차, 퍼스트 블러드·드래곤·바론 획득률 (Oracle's Elixir 팀 단위 집계)
  카드를 탭하면 전투/오브젝트/골드·라인전/시야 4개 카테고리로 나눈 상세 지표(킬·CKPM, 첫타워·전령·그럽스·장로,
  골드 점유 지수·초반/중후반 게임 지수, 와드 지표 등)를 시트로 확인 가능. 현재 시즌 안에 라운드/컵 등
  구간이 여러 개면 드롭다운으로 골라볼 수 있음
- 국제대회·컵대회에서 진입해도 팀의 정규 소속 리그 기준으로 자동 정규화

### 선수 상세
- 탭 기반 레이아웃 (통계 / 챔피언풀 / 최근경기)
- 챔피언별 누적 승률 추이는 Swift Charts 기반 곡선+그라디언트 채움 차트(승/패는 점 색으로 표시),
  게임별 KDA 기록, 챔피언풀 목록엔 승률 막대바로 한눈에 비교 가능. 게임별 기록은 Oracle's Elixir
  데이터가 있는 리그면 그쪽을 우선 사용(안 되면 Leaguepedia로 자동 폴백)
- 시즌 스탯은 Oracle's Elixir 데이터가 있는 리그면 그쪽을 우선 사용 — 킬관여율(KP)·데미지/골드
  기여도·10분 골드·CS 격차 등 더 상세한 지표를 제공하고, 팀 스탯 탭과 같은 시즌 집계 테이블 기준이라
  경기 수가 팀/선수 화면 간에 어긋나지 않음(Leaguepedia만 있던 예전엔 선수마다 위키 기록 완성도가
  달라 같은 경기를 뛰고도 경기 수가 다르게 보일 수 있었음). 시즌 스탯 카드를 탭하면 팀 스탯처럼
  킬관여율·라인전 격차·딜/골드 기여도·시야 지표를 카테고리별 상세 시트로 확인 가능, 팀 스탯과 동일하게
  현재 시즌 내 구간 드롭다운으로 전환 가능

### 경기 상세
- 실시간 팀 스탯 (킬 / 골드 / 타워 / 바론), 게임별 선수 KDA·골드·CS
- 드래곤은 개수뿐 아니라 **어떤 드래곤을 먹었는지 종류까지** 표시 (화염/바다/바람/대지/마공/화공/장로)
- 선수를 탭하면 **세트별 맞라이너 대결**을 확인 — 같은 라인에서 맞붙은 상대와 나란히 놓고
  KDA·킬 관여·딜 비중·CS·골드·방어력·마법저항을 좌우 막대로 비교, 골드 격차를 함께 표시.
  딜 비중엔 팀 내 순위가 붙고, 아이템 빌드·스킬 마스터 순서·시야는 접어뒀다가 펼쳐 봄
  (G1/G2/… 세트 탭으로 전환, 고른 세트만 조회하고 캐싱)
- 밴 카드 (Riot API에 밴 정보가 없으면 Oracle's Elixir 드래프트 데이터로 보완,
  그것도 없으면 Leaguepedia로 최종 폴백)
- 킬 타임라인은 현재 표시되지 않음 — Riot이 라이브 스탯 피드에서 킬 이벤트(`events`)를
  제거해 데이터 소스가 사라졌다. 코드는 남아 있고, 복구 방안은 CLAUDE.md 참고
- 완료 경기 상세는 서버가 영구 캐싱 — 여러 사용자가 봐도 Riot API는 최초 1회만 호출
- 게임 상세 스탯을 못 가져온 경우 빈 화면 대신 재시도 카드 표시

### Favorites
- 팀 / 선수 즐겨찾기 (SwiftData), Today 상단 별 아이콘(시트)으로 진입 — 팀 동일성은 Riot 고유 ID 기준(같은 조직의 1군/2군 팀은 코드가 같아도 구분됨)
- 대표 팀 지정 → 앱 전체 Tint 색상 적용
- Live Activity: 잠금화면 · Dynamic Island 실시간 스코어, 세트 변경 시 알림 배너
- 경기 종료 시 "경기종료" 상태로 최종 스코어를 한 번 더 보여준 뒤 15분 후 자동 종료

### 앱 메뉴
- 경기 알림 시간 설정 (1분 / 5분 / 10분 / 30분 / 1시간 전)
- 경기 시작 / 세트 종료 / 세트 시작 / 경기 종료 알림 4종
- 앱 사용 설명서, 이용약관/개인정보처리방침, 버전 정보

### 백그라운드 푸시 알림
- 서버(`syncLive`)가 경기 시작/세트 변경/종료를 감지해 FCM으로 원격 푸시 발송 (앱이 꺼져 있어도 수신 목표)
- 서버·앱 연동 코드는 완료됐지만, 무료 Apple ID 제약으로 실기기 원격 푸시 검증은 아직 — 자세한 내용은 CLAUDE.md 참고

### 과거 시즌 백필 (완료)
- Oracle's Elixir 비공식 API로 앱이 지원하는 12개 리그·대회(LCK/LPL/LEC/LCS/PCS/VCS/CBLOL/LJL/LLA + Worlds/MSI/KeSPA Cup)의 과거 시즌을 게임별 상세 스탯까지 포함해 서버에 백필 완료

### 홈 화면 · 잠금화면 위젯 (LOLIVEWidgets)
- Small / Medium / Large 사이즈 + 잠금화면 accessory 3종
- 즐겨찾기 팀의 다음 경기, 진행 중이면 실시간 스코어까지 표시
- Small은 즐겨찾기 화면에서 지정한 "대표 팀"을 항상 고정으로 표시(Medium 캐러셀과 무관), Medium/Large는 여러 팀 넘겨보기 지원
- 위젯 탭 → 해당 팀 경기 상세로 딥링크 (`lolive://match/<teamCode>`)
- 홈 화면 테마(틴트) 모드·Dynamic Type·VoiceOver 대응, Live Activity 잠금화면 배너는 라이트/다크 모드에 맞춰 자동 전환

## 앱 구조

레이어(App / Core / Data / Domain)와 기능(Features)으로 나눈 구조입니다.
기능 하나가 어디에 있는지는 `Features/<기능 이름>/` 한 곳만 보면 됩니다.

```
LOLIVE/
├── App/
│   ├── Resource/       — Assets.xcassets
│   └── Source/         — LOLIVEApp(진입점), AppDelegate(Firebase 설정 + APNs 등록)
├── Core/               — 기능에 안 묶이는 공통 토대
│   ├── DesignSystem/   — 테마·역할 색상, 공용 컴포넌트(Components/)
│   ├── Local/          — 디스크 캐시(Cache/), 알림·Live Activity(Notification/), App Groups 공유
│   └── Remote/         — 이미지 캐싱 로더
├── Data/               — 바깥 세상과 통신하는 계층
│   ├── API/            — Riot / Leaguepedia / OracleElixir / Firebase / DDragon
│   └── DB/             — Favorites(SwiftData)
├── Domain/             — 앱 안에서 쓰는 순수 모델 (Match / League / Team / Player)
└── Features/           — 화면 단위. 각 기능이 View/ 와 ViewModel/ 을 따로 가진다
    ├── Main/           — TabView 진입점(ContentView), 스플래시
    ├── Today · Leagues · Standings · Players · Search
    ├── TeamDetail · MatchDetail · Tournament · Favorites
    └── Onboarding · Settings

LOLIVEWidgets/          — Widget Extension (앱과 같은 레이어 구성)
├── App/Source/         — 위젯 번들 진입점
├── Core/Local/         — App Groups 공유 데이터, 고화질 로고 로더
├── Data/API/           — 위젯 전용 네트워크
├── Domain/Match/       — Live Activity attributes (앱 타겟과 물리적으로 복제됨)
└── Features/           — FavoriteTeam(홈 화면 위젯) / LiveActivity(잠금화면·Dynamic Island)

lolive-firebase/        — Firebase 백엔드 (Cloud Functions + Firestore)
```

## 앱 플로우

```
앱 실행
    └─ SplashView (1.5초)
           ├─ 온보딩 미완료 → OnboardingView → ContentView
           └─ 온보딩 완료  → ContentView
```

## Xcode 설정 (수동)

빌드 전에 아래 항목이 설정돼 있어야 합니다 (일부는 레포에 이미 커밋됨):

- **API Key**: `APIKeys.swift` (gitignore됨) — `RiotAPIKey` 상수 정의 필요
- **App Groups**: LOLIVE + LOLIVEWidgets 타겟 모두에 `group.lolive` 추가
- **Live Activity**: `NSSupportsLiveActivities` / `NSSupportsLiveActivitiesFrequentUpdates` = `YES`
- **Firebase**: `firebase-ios-sdk` 패키지(`FirebaseCore`/`FirebaseMessaging`/`FirebaseFunctions`) 추가, `GoogleService-Info.plist`를 `LOLIVE/`에 배치(gitignore됨, Firebase 콘솔에서 발급)
- **Push Notifications entitlement**: 현재 미적용 (무료 Apple ID 제약 — CLAUDE.md 참고)

## 테스트

`LOLIVETests` 타겟, Swift Testing 프레임워크. 77개 케이스 (핵심 ViewModel 로직 + 순수 함수).

```bash
xcodebuild test -scheme LOLIVE -destination 'platform=iOS Simulator,name=<기기명>' -only-testing:LOLIVETests
```

## CI/CD

`.github/workflows/ci.yml` — GitHub Actions, `main` push/PR마다 자동 실행.

1. `LOLIVE` 스킴 빌드 + `LOLIVETests` 77개 실행
2. `LOLIVEWidgetsExtension` 별도 빌드 (컴파일 체크만)
