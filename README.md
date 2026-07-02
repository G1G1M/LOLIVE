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
| UI | SwiftUI (다크모드 고정) |
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
- FotMob 스타일 날짜 선택 스트립 (과거 5일 ~ 예정 경기 마지막 날짜까지 동적 확장)
- 날짜 탭 시 해당 날짜로 스트립 자동 스크롤 (애니메이션)
- 선택 날짜 기준 리그별 그룹화 경기 목록
- LIVE 경기 자동 감지 및 폴링 (오늘 날짜에서만 표시)
- live fetch와 schedule fetch 독립 실행 — live 실패/지연이 경기 일정 표시에 영향 없음
- 라이브·예정·완료 경기 동일 ID 중복 제거 (ForEach collision 방지)
- 즐겨찾기 팀 경기만 필터링 (전체 / ★ 즐겨찾기 토글)
- 예정 경기(unstarted) 날짜 제한 없음 — API가 반환하는 모든 미래 경기 표시
- 타이틀 · 날짜 스트립 · 필터 고정, 경기 목록만 스크롤

### Standings
- 전 세계 리그 순위표 (W-L / GD / Win% 컬럼)
- W-L: 승(파랑) - 패(빨강) 표기, 모노스페이스 숫자로 정렬 보장
- GD: 세트 득실차 (+/-), 순위 정렬 기준으로 활용
- 순위 색상: 1위 금색, 2위 은색, 3위 동색
- 내부 정렬 기준: 순위 → 승수 → 세트 득실 → 팀명
- LPL 그룹 A/B 섹션 헤더 자동 분리 표시
- 리그 선택 칩 (lazy 로딩 + 캐싱), 리그 전환 시 디스크 캐시 즉시 표시
- 팀 탭 → 팀 상세 페이지 이동
- 리그 상세의 순위 탭과 동일한 UI/데이터 구조 공유

### Players
- 전 세계 선수 통합 목록
- 포지션 / 리그 필터 및 이름 검색
- 1군/2군 리그 중복 제거
- 선수 상세: 시즌 스탯, most픽 챔피언, 최근 경기 결과

### 검색
- 탭바 Search 탭으로 즉시 접근 (5번째 탭 → fullScreenCover 전환)
- 리그 / 팀 / 선수 통합 검색
- 검색 결과에서 팀·선수 상세 페이지 바로 이동
- 즐겨찾기 인라인 토글

### 팀 상세
- **탭 기반 레이아웃**: 상단 고정 헤더(팀 로고 + 이름 + 순위) + 탭 바(선수단 / 상대 전적 / 최근경기)
- **선수단**: 포지션 순 정렬, 선수 탭 → 선수 상세 이동
- **상대 전적**: 상대팀별 누적 W-L + 승률
- **최근경기**: 1열 리스트 — W/L 배지 + 상대팀 로고·이름 + 날짜 + 스코어, 최대 30경기, 탭 → 경기 상세 이동

### 선수 상세
- **탭 기반 레이아웃**: 상단 고정 헤더(사진 + 소환사명 + 역할) + 탭 바(통계 / 챔피언풀 / 최근경기)
- **통계 탭**: 시즌 스탯(승률·KDA·CS/분·킬/데스/어시) + K/D/A 비율 가로 바 시각화 + 최근 5경기 폼(W/L 블록)
- **챔피언풀 탭**: 게임 수·승률·KDA 테이블, 챔피언 탭 → 승률 추이 시트
  - 누적 승률 꺾은선 그래프 (점 색: 승=파랑, 패=빨강)
  - 게임별 W/L 블록 스크롤 + 날짜·KDA 기록 리스트
- **최근경기 탭**: 상대팀·날짜·스코어·승패 배지, 탭 → 경기 상세 이동
- Leaguepedia 로딩 중 스피너, 완료 시 순차 표시 (초기값 `isLoadingStats = true`로 "없음" 플래시 방지)

### 경기 상세
- 실시간 팀 스탯 (킬 / 골드 / 타워 / 드래곤 / 바론)
- 승패 판정: `getEventDetails` API의 `outcome` 필드 우선 사용 → 없으면 inhibitors > towers > gold > kills 계층 fallback
- 게임별 선수 KDA, 골드, CS + 챔피언 이미지 (고정 너비로 줄바꿈 없이 통일된 레이아웃)
- 경기 상세 내 팀 탭 → 팀 상세 이동 (예정 경기 포함 선수단 정상 표시)
- 밴 카드: 게임별 blue/red 사이드 밴 챔피언 표시 (Riot API 데이터)
- 미시작 경기: 로딩 스피너 없이 "경기 예정" 카드 + 시작 시간 표시
- 게임 시리즈 픽커: G1/G2 텍스트 + 상태 점 (라이브 빨간 점 / 완료 파란 점 / 예정 텍스트), 선택 시 전체 버튼 영역 터치 가능
- 경기 종료 배지 아래 경기 날짜 표시
- 팀 로고 탭 → 팀 상세 페이지 이동
- **킬 타임라인**: 게임별 킬 이벤트를 시간 축 위에 표시 (Blue/Red 점, 분 단위 레이블) — 완료 경기 30일 캐시

### Favorites
- SwiftData 기반 팀 / 선수 즐겨찾기
- 즐겨찾기한 팀의 LIVE 경기 실시간 뱃지 + 스코어
- 즐겨찾기한 선수 행에 현재 LIVE 경기 정보 실시간 표시
- **대표 팀 설정**: 팀 행 길게 누르면 대표 팀 지정 → 앱 전체 Tint 색상 적용
- Live Activity: 잠금화면 실시간 스코어 (`[로고] 팀명 스코어–스코어 팀명 [로고]`) + Dynamic Island
  - 팀 로고: `MatchActivityAttributes`에 30×30 PNG 썸네일 직접 포함 → 크로스프로세스 파일 공유 불필요
  - 폴링: ContentView 레벨에서 실행 — 탭 전환·앱 재포그라운드 시에도 중단 없이 유지

### 앱 메뉴 (AppMenu)
- 경기 알림 시간 설정 (Picker: 1분 / 5분 / 10분 / 30분 / 1시간 전)
- 알림 변경 시 즐겨찾기 팀 전체 알림 자동 재스케줄링
- 앱 설정 페이지 이동 (이용약관, 개인정보처리방침, 앱 사용 설명서, 버전 정보)
- 앱 설정 하단 법적 고지 — Riot Games 비제휴 팬 앱 명시 (한/영)

### 홈 화면 위젯 (LOLIVEWidgets)
- 즐겨찾기한 팀의 다음 경기 일정 표시
- Small / Medium / **Large** 사이즈 지원
- Large: 즐겨찾기 팀 전체 목록 (최대 5팀) 한눈에 표시
- 경기 1시간 이내 시 카운트다운 타이머 표시 (중앙정렬, 숫자 변경 시 레이아웃 고정)
- 여러 팀 캐러셀 (App Intents)
- 위젯 탭 → 팀 상세 딥링크 (`lolive://team/<id>`)
- 다크/라이트 모드 자동 대응
- **잠금화면 accessory 위젯**: `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` 3종

## 앱 플로우

```
앱 실행
    └─ SplashView (1.5초)
           ├─ 온보딩 미완료 → OnboardingView → ContentView
           └─ 온보딩 완료  → ContentView
```

### 온보딩 선수 이미지 로딩

- 디스크 캐시 복원 시 `playerImageURLs`가 비어있으면 Leaguepedia에서 재시도 후 캐시 갱신
- 이미지 URL 없을 때 `ChampionImageView`로 폴백 (챔피언 아이콘 표시)

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
- `TournamentDTO.endDate` Optional 처리 — 진행 중인 토너먼트는 API가 null 반환 → 시작일 이후 경기 전체 표시
- Rate limit: 단일 shared actor 0.5s 간격 직렬화 (포그라운드·백그라운드 공유 큐)
- 빈 결과는 디스크에 저장하지 않아 재시도 가능

## 디스크 캐시 아키텍처

앱 재실행 시 로딩 스피너 없이 즉시 데이터를 표시하기 위해 전 계층에 디스크 캐시를 적용했습니다.

### 캐시 레이어

| 데이터 | 캐시 키 | TTL | 저장소 |
|--------|---------|-----|--------|
| 리그 목록 | `leagues` | 24h | AppDiskCache |
| 경기 일정 | `schedule_{leagueId}` | 15분 | AppDiskCache |
| 토너먼트 | `tournaments_{leagueId}` | 24h | AppDiskCache |
| 순위 | `standings_{tournamentId}` | 1h | AppDiskCache |
| 팀 로스터 | `roster_{teamId}` | 12h | AppDiskCache |
| 선수 목록 전체 | `players_all` | 12h | AppDiskCache |
| 검색 데이터 | `search_teams` / `search_players` | 12h | AppDiskCache |
| 경기 상세 | `event_detail_v2_{matchId}` | 30일 | AppDiskCache |
| 이미지 | SHA256 해시 파일명 | 영구 | ~/Library/Caches/image_cache/ |
| 리그 선수 목록 | `league_players_{leagueId}` | 12h | AppDiskCache |
| 벤 정보 | `lp_bans_{riotGameId}` | 30일 | AppDiskCache |
| 선수 프로필 이미지 | `lp_playerimg_{name}` | 7일 | AppDiskCache |
| OverviewPage | `overview_pages.json` | 24h | LeaguepediaStats/ |
| 선수 이름 목록 | `playernames_{league}.json` | 24h | LeaguepediaStats/ |
| 시즌 스탯 전체 | `{overviewPage}.json` | 24h | LeaguepediaStats/ |
| 챔피언 픽 전체 | `champ_batch_{overviewPage}.json` | 24h | LeaguepediaStats/ |
| 챔피언 픽 (개별) | `champs_{key}.json` | 24h | LeaguepediaStats/ |
| 과거 경기 | `histv2_{key}.json` | 30일 | LeaguepediaStats/ |

### ViewModel 선로딩 패턴

```
앱 실행
    ├─ AppPreloadService.start()  — 경기 상세 + Leaguepedia 스탯 병렬 프리로드 (1초 지연)
    └─ 각 ViewModel.load()
           ├─ preloadFromCache() → 디스크 캐시 즉시 표시 (스피너 없음)
           └─ 백그라운드 API fetch → 조용히 갱신
```

- 캐시 부분 히트(일부 리그만 캐시됨)도 있는 것만 즉시 표시
- `CachedAsyncImage`: 메모리 → 디스크 → 네트워크 3단계 캐시

### API 오류 대응 (Stale 캐시 폴백)

API 호출이 실패하더라도 TTL이 만료된 기존 캐시가 있으면 데이터를 표시합니다.

```
API 실패
    ├─ 유효 캐시 있음 → 기존 데이터 그대로 유지 (에러 화면 미표시)
    ├─ 만료된 캐시 있음 → AppDiskCache.getStale() → 오래된 데이터라도 표시
    └─ 캐시 없음 → 에러 메시지 표시
```

## 시즌 스탯 / 챔피언 픽 아키텍처

Leaguepedia rate limit(API 호출 간 2.5초 대기) 이슈를 배치 로딩으로 해결합니다.

```
앱 실행 3초 후 (AppPreloadService)
    ├─ preloadMatchDetails()        — 1군 리그 최근 완료 경기 상세 (병렬)
    └─ preloadLeaguepediaStats()    — 1군 리그 시즌 스탯 + 챔피언 픽 (순차)
           └─ LeaguepediaService.preloadLeagueStats(league)
                  ├─ currentOverviewPage() → 디스크 캐시 (24h TTL)
                  ├─ allPlayerStats()      → 500행씩 배치, 디스크 캐시 (24h TTL)
                  └─ allChampionPicks()    → 500행씩 배치, 디스크 캐시 (24h TTL)

선수 상세 진입
    ├─ async let scheduleTask   (Riot API, 병렬 시작)
    ├─ async let seasonStatsTask (Leaguepedia, 병렬 시작)
    └─ async let picksTask      (Leaguepedia, 병렬 시작)
           │
           ├─ scheduleTask 완료 즉시 → recentResults 표시 (Leaguepedia 대기 없음)
           └─ seasonStats / picks 완료 → 순차 반영 (배치 캐시 히트 시 즉시)

※ 신시즌 초반 대응: candidateOverviewPages()가 최근 3개 OverviewPage를 순서대로 시도
   → 현재 시즌 데이터 없으면 직전 시즌으로 자동 fallback
   → 종료일 미등록 토너먼트(진행 중)도 정상 감지
```

- 앱 시작 1초 후 AppPreloadService가 Leaguepedia 스탯을 백그라운드 선로딩 → 선수 상세 진입 시 캐시 히트로 즉시 표시
- 리그 전체 스탯·픽을 배치 1회 요청으로 수집 → 선수별 개별 API 호출 제거
- 앱 재실행 시 디스크 캐시로 API 호출 없이 즉시 반환
- `OverviewPage`도 디스크 캐시 → cold start 시 rate limit 대기 제거
- Rate limiter 단일 shared actor 0.5s: foreground/background 공유 큐로 동시 호출 방지
- candidateOverviewPages 결과 메모리 캐시 → 같은 리그 중복 API 호출 제거
- API 실패·취소 시 nil 캐싱 방지 → 재진입 시 재요청 정상 동작

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
│   │   ├── AppPreloadService    — 앱 시작 시 경기 상세 + Leaguepedia 스탯 병렬 프리로드
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
├── ContentView.swift        — TabView 진입점 (Today/Leagues/Players/Favorites/Search 5탭)
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
