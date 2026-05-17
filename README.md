# LOLIVE

리그 오브 레전드 e스포츠 경기 정보 앱

---

## 소개

전 세계 LoL 프로 경기 일정, 실시간 스코어, 팀 및 선수 정보를 한눈에 확인할 수 있는 iOS 앱입니다.

## 기술 스택

- **플랫폼**: iOS 17+
- **언어**: Swift 6.0
- **UI**: SwiftUI
- **아키텍처**: MVVM + `@Observable`
- **네트워크**: URLSession + async/await
- **로컬 저장**: SwiftData
- **알림**: UNUserNotificationCenter (로컬 알림)
- **위젯**: ActivityKit + WidgetKit (Live Activity / Dynamic Island / 홈 화면 위젯)
- **앱 확장**: App Intents (위젯 캐러셀 인터랙션)
- **데이터 공유**: App Groups (main app ↔ widget)
- **데이터**: Riot Esports API (비공식)

## 주요 기능

### Today
- 오늘의 경기 실시간 조회
- LIVE 경기 자동 감지 및 폴링
- 예정/진행중/완료 경기 섹션 구분
- 날짜별/리그별 그룹화

### Leagues
- 전 세계 리그 목록 (지역별 정렬, 검색)
- 리그별 순위, 일정, 팀, 선수 탭
- 경기 일정 날짜+블록 단위 그룹화

### Players
- 전 세계 선수 통합 목록
- 포지션 / 리그 필터 및 이름 검색
- 1군/2군 리그 중복 제거 (선수 정확 분류)
- 선수 상세: most픽 챔피언, 최근 경기 결과

### 경기 상세
- 실시간 팀 스탯 (킬/골드/타워/드래곤/바론)
- 게임별 선수 KDA, 골드, CS
- 팀 로고 탭 → 팀 상세 페이지 이동

### Standings
- 전 세계 리그 순위표
- 리그 선택 칩 (lazy 로딩 + 캐싱)
- 순위 / 팀 / 승 / 패 / 승률 표시
- 팀 탭 → 팀 상세 페이지 이동

### Favorites
- SwiftData 기반 팀/선수 즐겨찾기 저장
- 즐겨찾기한 팀의 LIVE 경기 실시간 뱃지 + 스코어
- 경기 시작 1시간 전 로컬 알림 자동 스케줄링
- Live Activity: 잠금화면 실시간 스코어 + Dynamic Island

### 홈 화면 위젯 (LOLIVEWidgets)
- 즐겨찾기한 팀의 다음 경기 일정 표시
- Small: 팀 로고 + 리그 + 다음 경기 정보 (FotMob 스타일)
- Medium: 3열 레이아웃 — 팀A | 시간/리그 | 팀B (FotMob 스타일)
- 여러 팀 캐러셀: 좌우 버튼으로 팀 전환 (App Intents)
- 위젯 탭 → 해당 팀 상세 페이지 딥링크 (`lolive://team/<id>`)
- App Groups로 즐겨찾기 데이터 실시간 동기화

### 팀 상세
- 로스터 (포지션 순 정렬)
- 최근 경기 결과

## 앱 구조

```
LOLIVE/
├── Sources/
│   ├── Models/          # League, Match, Player, Team, Standing, Favorites, MatchActivityAttributes 등
│   ├── Services/        # RiotEsportsService, LiveStatsService, MatchNotificationService, LiveActivityService, SharedDataService
│   ├── ViewModels/      # 각 화면별 ViewModel (@Observable)
│   └── Views/           # SwiftUI Views
├── ContentView.swift    # TabView 진입점 + 딥링크 처리
├── LOLIVEApp.swift      # 앱 진입점, URL scheme 처리
└── LOLIVEWidgets/       # Widget Extension
    ├── FavoriteTeamWidget.swift      # 홈 화면 위젯 (캐러셀, 딥링크)
    ├── MatchLiveActivityWidget.swift # Live Activity / Dynamic Island
    ├── WidgetNetworkService.swift    # 위젯용 네트워크 서비스
    ├── SharedDataService.swift       # App Groups 데이터 읽기
    └── LOLIVEWidgetsBundle.swift     # 위젯 번들
```

## Xcode 설정 (수동)

- **App Groups**: LOLIVE + LOLIVEWidgets 타겟 모두에 `group.lolive` 추가
- **URL Scheme**: LOLIVE 타겟 Info → URL Types에 `lolive` 추가
- **NSSupportsLiveActivities**: LOLIVE 타겟 Info에 `YES` 설정
- **NSSupportsLiveActivitiesFrequentUpdates**: LOLIVE 타겟 Info에 `YES` 설정
