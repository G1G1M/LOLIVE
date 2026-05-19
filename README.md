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
| Leaguepedia MediaWiki Cargo API | 선수 시즌 스탯 (KDA, 승률, CS/분 등) |

## 주요 기능

### Today
- 오늘의 경기 실시간 조회
- LIVE 경기 자동 감지 및 폴링
- 예정 / 진행중 / 완료 경기 섹션 구분
- 날짜별 · 리그별 그룹화
- 즐겨찾기 팀 경기만 필터링

### Standings
- 전 세계 리그 순위표
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
- 경기 시작 1시간 전 로컬 알림 자동 스케줄링
- 즐겨찾기 추가 시점이 경기 1시간 이내이면 즉시 알림 발송
- **대표 팀 설정**: 팀 행 길게 누르면 대표 팀 지정 → 앱 전체 Tint 색상 적용
- Live Activity: 잠금화면 실시간 스코어 + Dynamic Island

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
│   │   ├── TodayViewModel       — 경기 목록 + 라이브 폴링
│   │   ├── StandingsViewModel   — 리그 순위
│   │   ├── PlayersViewModel     — 선수 목록 + 필터
│   │   ├── SearchViewModel      — 통합 검색
│   │   ├── LeagueDetailViewModel
│   │   ├── TeamDetailViewModel
│   │   ├── LeaguePlayerDetailViewModel — 챔피언/경기 데이터
│   │   └── MatchDetailViewModel — 경기 상세 + 폴링
│   └── Views/
│       ├── TodayView, StandingsView, PlayersView
│       ├── SearchView, FavoritesView
│       ├── LeagueDetailView, TeamDetailView
│       ├── LeaguePlayerDetailView, SeasonStatsView
│       ├── MatchDetailView, PlayerDetailView
│       └── MatchCardView, CachedAsyncImage, ...
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
