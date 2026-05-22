# LOLIVE

리그 오브 레전드 e스포츠 경기 정보 iOS 앱

---

## 소개

전 세계 LoL 프로 경기 일정, 실시간 스코어, 팀·선수 정보 및 시즌 스탯을 한눈에 확인할 수 있는 iOS 앱입니다.

## 기술 스택

| 항목 | 내용 |
|------|------|
| 플랫폼 | iOS 17+ |
| 언어 | Swift 6.0 |
| UI | SwiftUI |
| 아키텍처 | MVVM + `@Observable` |
| 네트워크 | URLSession + async/await |
| 로컬 저장 | SwiftData |
| 알림 | UNUserNotificationCenter (로컬 알림) |
| 위젯 | ActivityKit + WidgetKit |
| 데이터 공유 | App Groups (main app ↔ widget) |

## 사용 API

| API | 용도 |
|-----|------|
| Riot Esports API (비공식) | 경기 일정, 라이브 스코어, 팀·선수 정보 |
| Leaguepedia MediaWiki Cargo API | 선수 시즌 스탯, 과거 대회 경기 기록 (2023년 이전 Worlds/MSI) |

## 주요 기능

### 대회 상세 (Worlds / MSI)
- 연도별 탭 자동 생성 (Riot API 커버 범위 + Leaguepedia 과거 데이터 합산)
- 라운드(플레이-인 / 그룹 / 8강 / 4강 / 결승 등) 칩 선택 → 날짜별 경기 목록
- 라운드 구분 없는 과거 데이터는 전체 경기 목록 표시 (칩 숨김)
- **3단계 데이터 로딩**:
  1. Riot API로 즉시 표시 (2023년 이후)
  2. Leaguepedia 연도 목록으로 과거 탭 즉시 추가 (1회 API 호출 + 30일 캐시)
  3. 탭 선택 시 해당 연도 경기 on-demand 로드 (캐시 히트 시 즉시 반환)
- 과거 경기 팀 로고: Leaguepedia Teams 테이블 배치 조회 → URL 패턴 폴백
- 앱 재진입 시 캐시된 과거 데이터 자동 복원 (화면 이탈 후 돌아와도 유지)

### Today
- FotMob 스타일 날짜 선택 스트립 (오늘 기준 ±5일, 시작 시 오늘 날짜 자동 중앙 정렬)
- 선택 날짜 기준 리그별 그룹화 경기 목록
- LIVE 경기 자동 감지 및 폴링 (오늘 날짜에서만 표시)
- 즐겨찾기 팀 경기만 필터링 (전체 / ★ 즐겨찾기 토글)
- 타이틀 · 날짜 스트립 · 필터 고정, 경기 목록만 스크롤

### Standings
- 전 세계 리그 순위표 (W / L / Win% 컬럼)
- 승률 색상 코딩: 60% 이상 파랑, 40% 미만 흐리게
- 순위 색상: 1위 금색, 2위 은색, 3위 동색
- 내부 정렬 기준: 순위 → 승수 → 세트 득실 → 팀명
- 리그 선택 칩 (lazy 로딩 + 캐싱)
- 팀 탭 → 팀 상세 페이지 이동

### Players
- 전 세계 선수 통합 목록
- 포지션 / 리그 필터 및 이름 검색
- 1군/2군 리그 중복 제거
- 선수 상세: 시즌 스탯, most픽 챔피언, 최근 경기 결과

### 검색
- 리그 / 팀 / 선수 통합 검색
- 검색 결과에서 팀·선수 상세 페이지 바로 이동
- 즐겨찾기 인라인 토글

### 팀 상세
- 로스터 (포지션 순 정렬, 선수 탭 → 선수 상세 이동)
- 최근 경기 결과 탭 → 경기 상세 이동

### 선수 상세
- 시즌 스탯: 승률, KDA, CS/분, 평균 킬/데스/어시스트
- most픽 챔피언 (최근 5경기 기준) + 챔피언 이미지
- 최근 경기 결과 탭 → 경기 상세 이동

### 경기 상세
- 실시간 팀 스탯 (킬 / 골드 / 타워 / 드래곤 / 바론)
- 게임별 선수 KDA, 골드, CS + 챔피언 이미지
- 밴 카드: 게임별 blue/red 사이드 밴 챔피언 표시 (Riot API 데이터)
- 팀 로고 탭 → 팀 상세 페이지 이동

### Favorites
- SwiftData 기반 팀 / 선수 즐겨찾기
- 즐겨찾기한 팀의 LIVE 경기 실시간 뱃지 + 스코어
- **대표 팀 설정**: 팀 행 길게 누르면 대표 팀 지정 → 앱 전체 Tint 색상 적용
- Live Activity: 잠금화면 실시간 스코어 + Dynamic Island

### 앱 메뉴 (AppMenu)
- 경기 알림 시간 설정 (Picker: 1분 / 5분 / 10분 / 30분 / 1시간 전)
- 알림 변경 시 즐겨찾기 팀 전체 알림 자동 재스케줄링
- 앱 설정 페이지 이동 (이용약관, 개인정보처리방침, 앱 사용 설명서, 버전 정보)

### 홈 화면 위젯 (LOLIVEWidgets)
- 즐겨찾기한 팀의 다음 경기 일정 표시
- Small / Medium / **Large** 사이즈 지원
- Large: 즐겨찾기 팀 전체 목록 (최대 5팀) 한눈에 표시
- 경기 1시간 이내 시 카운트다운 타이머 표시
- 여러 팀 캐러셀 (App Intents)
- 위젯 탭 → 팀 상세 딥링크 (`lolive://team/<id>`)
- 다크/라이트 모드 자동 대응

## 앱 플로우

```
앱 실행
    └─ SplashView (1.5초)
           ├─ 온보딩 미완료 → OnboardingView → ContentView
           └─ 온보딩 완료  → ContentView
```

## 대회 일정 아키텍처 (Worlds / MSI)

Riot API는 2023년 이후 데이터만 제공하므로, 과거 대회는 Leaguepedia Cargo API로 보완합니다.

```
TournamentDetailViewModel.load()
    ├─ [Phase 1] Riot API → 즉시 화면 표시 (isLoading = false)
    │
    ├─ [Phase 2] Leaguepedia.historicalYears()
    │      └─ OverviewPage 목록 1회 조회 → 연도 탭 즉시 추가
    │             └─ fetchMatchesFromCacheOnly() → 캐시 데이터 바로 allMatches에 병합
    │
    └─ [Phase 3] partialYears 보완 (Riot 경기 수 < 20인 연도)
           └─ Leaguepedia.fetchMatches() → deduplicateAgainstRiot()

연도 탭 선택 (캐시 미스 시)
    └─ selectTournament() → isLoadingHistoricalMatches = true
           └─ loadHistoricalYear()
                  └─ fetchMatches() → allMatches 병합 → isLoadingHistoricalMatches = false
```

- OverviewPage 목록: 24시간 TTL 디스크 캐시
- 경기 데이터: 30일 TTL 디스크 캐시 (OverviewPage 단위, 캐시 키 `histv2_` prefix)
- 팀 로고: Leaguepedia Teams 테이블 배치 조회 → `Special:FilePath/` URL 패턴 폴백
- Rate limit: API 호출 간 2.5초 대기 (actor 기반 순서 보장)
- 빈 결과는 디스크에 저장하지 않아 재시도 가능

## 시즌 스탯 아키텍처

Leaguepedia의 rate limit 이슈를 해결하기 위해 아래 구조를 적용했습니다.

```
선수 목록 로드 완료
    └─ Task.detached(background)
           └─ LeaguepediaService.preloadLeagueStats(league)
                  ├─ currentOverviewPage() → Cargo API (캐시)
                  ├─ allPlayerStats() → 500행씩 페이지네이션 배치 로드
                  └─ LeaguepediaCache.setAllPlayerStats() → 메모리 + 디스크 (24시간 TTL)

선수 상세 진입
    └─ SeasonStatsView.task
           └─ playerSeasonStats(summonerName:league:)
                  ├─ 캐시 히트 → 즉시 반환
                  └─ 캐시 미스 → allPlayerStats() 호출 (이미 로드된 경우 즉시)
```

- 리그 전체 스탯을 한 번의 배치 요청으로 수집 → API 호출 최소화
- 디스크 캐시(24시간 TTL)로 재실행 시 API 호출 없음
- `SeasonStatsView`가 자체 `.task`로 로딩 → ViewModel 의존성 없음, SwiftUI lifecycle 자동 취소

## GameWindow 캐시 아키텍처

완료된 게임의 윈도우 데이터는 변하지 않으므로 디스크에 영구 캐시합니다.

```
경기 상세 진입
    └─ MatchDetailViewModel.load()
           └─ 각 게임별 TaskGroup 병렬 로드
                  ├─ completed 게임 → GameWindowCache 우선 조회
                  │      ├─ 캐시 히트 → 즉시 반환
                  │      └─ 캐시 미스 → LiveStats API → 디스크 저장
                  └─ inProgress 게임 → LiveStats API (캐시 없음)
```

## 앱 구조

```
LOLIVE/
├── Sources/
│   ├── Models/
│   │   ├── League, Match, Player, Team, Standing
│   │   ├── Favorites (SwiftData)
│   │   ├── GameWindow (라이브 스탯)
│   │   └── MatchActivityAttributes (Live Activity)
│   ├── Services/
│   │   ├── RiotEsportsService   — 경기/팀/선수 API
│   │   ├── LeaguepediaService   — 시즌 스탯, 배치 캐싱
│   │   ├── LiveStatsService     — 게임 윈도우 데이터
│   │   ├── LiveActivityService  — Dynamic Island / 잠금화면
│   │   ├── MatchNotificationService — 로컬 알림
│   │   └── SharedDataService    — App Groups 동기화
│   ├── ViewModels/
│   │   ├── TodayViewModel           — 경기 목록 + 라이브 폴링
│   │   ├── TournamentDetailViewModel — 대회 일정 (Riot + Leaguepedia 3단계)
│   │   ├── StandingsViewModel       — 리그 순위
│   │   ├── PlayersViewModel         — 선수 목록 + 필터
│   │   ├── SearchViewModel          — 통합 검색
│   │   ├── LeagueDetailViewModel
│   │   ├── TeamDetailViewModel
│   │   ├── LeaguePlayerDetailViewModel — 챔피언/경기 데이터
│   │   └── MatchDetailViewModel     — 경기 상세 + 폴링
│   └── Views/
│       ├── TodayView, StandingsView, PlayersView
│       ├── SearchView, FavoritesView
│       ├── AppMenuView, AppSettingsView
│       ├── LeagueDetailView, TournamentDetailView
│       ├── TeamDetailView, LeaguePlayerDetailView, SeasonStatsView
│       ├── MatchDetailView, PlayerDetailView
│       └── MatchCardView, LeagueSectionHeader, CachedAsyncImage, ...
├── ContentView.swift        — TabView 진입점 + 딥링크 처리
├── LOLIVEApp.swift          — 앱 진입점
└── LOLIVEWidgets/           — Widget Extension
    ├── FavoriteTeamWidget.swift
    ├── MatchLiveActivityWidget.swift
    ├── WidgetNetworkService.swift
    ├── SharedDataService.swift
    └── LOLIVEWidgetsBundle.swift
```

## Xcode 설정 (수동)

- **App Groups**: LOLIVE + LOLIVEWidgets 타겟 모두에 `group.lolive` 추가
- **URL Scheme**: LOLIVE 타겟 Info → URL Types에 `lolive` 추가
- **NSSupportsLiveActivities**: LOLIVE 타겟 Info에 `YES` 설정
- **NSSupportsLiveActivitiesFrequentUpdates**: LOLIVE 타겟 Info에 `YES` 설정
- **API Key**: `APIKeys.swift` (gitignore됨) — `RiotAPIKey` 상수 정의 필요
