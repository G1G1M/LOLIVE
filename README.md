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
| UI | SwiftUI (다크모드 고정 — `.preferredColorScheme(.dark)` + `Info.plist UIUserInterfaceStyle=Dark`로 시스템 UI까지 이중 고정) |
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
- 결과 없음 화면을 공용 `EmptyStateView`로 교체 (기존엔 자체 구현이라 아이콘 크기·색상이 다른 화면들과 미묘하게 달랐음)

### Today
- FotMob 스타일 날짜 선택 스트립 (과거 5일 ~ 예정 경기 마지막 날짜까지 동적 확장)
- 날짜 탭 시 해당 날짜로 스트립 자동 스크롤 (애니메이션)
- 선택 날짜 기준 리그별 그룹화 경기 목록
- LIVE 경기 자동 감지 및 폴링 (오늘 날짜에서만 표시)
- **LIVE 판정 이중화**: `getLive` 전용 API가 일부 대회에서 비어있게 응답할 때를 대비해, 스케줄 상태가 `inProgress`면
  `getLive` 목록에 없어도 LIVE로 표시 (`MatchCardView` 공통 적용 → 리그 상세 일정·대회 상세도 동일하게 개선됨.
  즐겨찾기 화면의 실시간 스코어 표시도 같은 방식으로 대체 판정)
- live fetch와 schedule fetch 독립 실행 — live 실패/지연이 경기 일정 표시에 영향 없음
- 라이브·예정·완료 경기 동일 ID 중복 제거 (ForEach collision 방지)
- 즐겨찾기 팀 경기만 필터링 (전체 / ★ 즐겨찾기 토글) — 즐겨찾기가 없어도 필터 바는 항상 표시
- **LIVE 필터**: 필터 바에 LIVE 토글 추가 — 켜면 현재 진행 중인 경기만 리그 그룹째로 걸러서 보여줌.
  "전체 / ★ 즐겨찾기 / LIVE"는 라디오 버튼처럼 항상 하나만 선택되도록 동작 (동시에 여러 개가 켜져 보여 헷갈리던 문제 수정).
  즐겨찾기 화면에도 동일한 LIVE 필터를 추가해 즐겨찾기한 팀/선수 중 라이브 중인 항목만 볼 수 있음
- 예정 경기(unstarted) 날짜 제한 없음 — API가 반환하는 모든 미래 경기 표시
- 타이틀 · 날짜 스트립 · 필터 고정, 경기 목록만 스크롤
- 빈 상태 화면(경기 없음/즐겨찾기 없음/라이브 없음)을 즐겨찾기 화면과 동일한 공용 `EmptyStateView`로 통일
  (기존엔 Today만 자체 구현이라 아이콘 크기·색상·위치가 즐겨찾기 화면과 미묘하게 달랐음)
- 경기 카드(`MatchCardView`) 모서리 반경을 다른 카드 컴포넌트와 동일한 16으로 통일 (기존엔 14로만 미묘하게 달랐음)
- 라이브 경기가 종료되는 순간 화면에서 사라지지 않도록 로컬에서 즉시 완료 상태로 승격 (다음 전체 리로드 전까지도 유지)
- `getSchedule` 과거 페이지(`pages.older`)까지 조회 — "오늘 기준" 첫 페이지만으로 누락되던 며칠 전 완료 경기 보강
- **Riot 결과 미보고 대회 보완**: 케스파컵 등 일부 대회는 Riot Esports API가 경기 후에도 결과를 제대로 안 채워줌
  → ① 시작 시각이 3시간 이상 지났는데도 `unstarted`로 멈춰있거나, ② `completed`인데 스코어(gameWins)가 없어 0:0으로 내려오는 경기가 감지되면
  Leaguepedia에서 같은 팀 조합·비슷한 시각의 실제 결과를 찾아 스코어·상태만 교체 (LoL 경기는 정상 종료 시 0:0일 수 없어 안전하게 판별 가능)
  → 정상적으로 결과가 갱신되는 리그(대부분)는 감지되는 게 없어 추가 API 호출 없이 그대로 반환
  → 팀 이름 매칭은 정확히 같을 때뿐 아니라 한쪽 이름이 다른 쪽에 포함되거나 Riot 팀 코드가 겹치는 경우까지 관대하게 인정
  (Leaguepedia의 팀 표기가 Riot 팀명과 완전히 같지 않은 경우 대응)

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
- 탭바 3번째 탭으로 직접 진입 가능 (리그 상세 내 순위 탭과는 별개 진입점, 데이터/스타일은 공유)
- **Riot 순위 미보고 대회 보완**: Riot Standings API가 전 팀을 0승 0패로 묶어 내려주는 대회(케스파컵 등) 감지 시
  (위 Today의 Leaguepedia 보완으로 채워진) 완료 경기 결과를 직접 집계해 그룹별 승수 → 세트 득실 → 팀명 순으로 순위 재계산
  → 정상적으로 개별 승패가 내려오는 리그는 Riot 원본 순위·타이브레이크 그대로 사용

### 리그 상세
- **탭 기반 레이아웃**: 탭 바(순위 / 일정 / 팀 / 선수) — 각 탭은 `LeagueDetailView+Standings`/`+Schedule`/`+Teams` extension으로 분리
- 탭바 선택 밑줄·배경색을 `TeamDetailView`/`LeaguePlayerDetailView`와 동일한 구조로 통일
  (기존엔 구조가 달라 밑줄이 텍스트와 어긋나 보이고 배경색도 미묘하게 달랐음)

### Players
- 전 세계 선수 통합 목록
- 포지션 / 리그 필터 및 이름 검색
- 1군/2군 리그 중복 제거
- 이미지 없는 선수: 통일된 플레이스홀더 아이콘 표시 (Riot API 기본 실루엣 이미지 밝기 감지로 자동 대체)
- 선수 상세: 시즌 스탯, most픽 챔피언, 최근 경기 결과
- 선수명 대소문자 불일치 보정: Riot summonerName ↔ Leaguepedia Link 케이싱 차이를 대소문자 무시 폴백으로 자동 매칭
- 포지션 배지(TOP/JGL/MID/BOT/SUP 라벨·색상)는 `RoleStyle` 공용 헬퍼로 통일 — 화면마다 따로 구현되어 있던 동일 로직을 제거

### 검색
- 탭바 Search 탭으로 접근 (6번째 탭 → iOS "더보기" 탭 안에 자동 편입)
- 리그 / 팀 / 선수 통합 검색
- 검색 결과에서 팀·선수 상세 페이지 바로 이동
- 즐겨찾기 인라인 토글
- 팀 검색 인덱싱 시 케스파컵처럼 지역이 "한국"으로 찍히는 국내 컵 대회는 팀의 정규 소속 리그(LCK 등)보다
  후순위로 정렬 — 안 그러면 네트워크 응답 순서에 따라 팀이 컵 대회 소속으로 잘못 표시될 수 있음.
  `search_teams`/`search_players`는 12시간 디스크 캐시라 수정 후에도 캐시 만료 전까지는 기존 값이 남아있을 수 있음
- **"더보기" 탭 네비게이션**: iOS가 하단 탭 5개 초과 시 나머지를 자동으로 "더보기" 목록에 넣는데,
  그 목록이 이미 자체 네비게이션 컨테이너를 제공하므로 이 화면엔 별도 `NavigationStack`을 두지 않음
  (겹치면 백버튼이 2개 표시됨). 타이틀도 커스텀 헤더 대신 `.navigationTitle`로 표준 위치(백버튼과 같은 줄)에 표시
- 팀 검색(`TeamSearchView`)의 즐겨찾기 별 아이콘 크기를 통합 검색(`SearchView`)과 동일하게 통일 (기존엔 `TeamSearchView`만 더 크게 표시됨)
- 포지션 배지도 `RoleStyle` 공용 헬퍼 사용으로 통일 (선수 목록과 동일)
- 리그 목록(`LeaguesView`)의 리그 로고 크기를 검색 화면과 동일한 36×36으로 통일 (기존엔 32×32로 더 작았음)

### 팀 상세
- **탭 기반 레이아웃**: 상단 고정 헤더(팀 로고 + 이름 + 순위) + 탭 바(선수단 / 상대 전적 / 최근경기)
- **선수단**: 포지션 순 정렬, 선수 탭 → 선수 상세 이동
- **상대 전적**: 상대팀별 누적 W-L + 승률 — 현재 리그/대회 내 경기만 집계
- **최근경기**: 1열 리스트 — W/L 배지 + 상대팀 로고·이름 + 날짜 + 스코어, 최대 30경기, 탭 → 경기 상세 이동
  - 대회 상관없이 통합 표시 (현재 리그 전체 시즌 스케줄 + 다른 대회 경기까지 병합)
- 데이터 소스: `fetchSchedule`(오늘 기준 제한 윈도우) 대신 `fetchAllSchedule`(과거 페이지 전체 순회)로 전체 시즌 확보
  + 진입한 화면(TodayViewModel 등)이 이미 들고 있는 교차 리그 경기를 주입 — 어느 화면에서 들어와도 동일하게 채워짐
- **홈 리그 자동 보정**: MSI/Worlds 같은 국제 대회뿐 아니라 케스파컵처럼 지역이 "한국"으로 찍히는 국내 컵 대회에서
  진입해도, 팀의 정규 소속 리그(LCK 등) 기준으로 선수단·상대전적·즐겨찾기 소속 리그를 표시 (`resolvedHomeLeague`)

### 선수 상세
- **탭 기반 레이아웃**: 상단 고정 헤더(사진 + 소환사명 + 역할) + 탭 바(통계 / 챔피언풀 / 최근경기)
- **통계 탭**: 시즌 스탯(승률·KDA·CS/분·킬/데스/어시) + K/D/A 비율 가로 바 시각화 + 최근 5경기 폼(W/L 블록)
- **챔피언풀 탭**: 게임 수·승률·KDA 테이블, 챔피언 탭 → 승률 추이 시트
  - 누적 승률 꺾은선 그래프 (점 색: 승=파랑, 패=빨강)
  - 게임별 W/L 블록 스크롤 + 날짜·KDA 기록 리스트
- **최근경기 탭**: 상대팀·날짜·스코어·승패 배지, 탭 → 경기 상세 이동
  - W/L 배지·날짜 폰트를 팀 상세의 최근경기 카드와 동일한 스타일로 통일 (기존엔 막대+"승/패" 캡슐이라는 다른 시각 언어를 썼음)
- Leaguepedia 로딩 중 스피너, 완료 시 순차 표시 (초기값 `isLoadingStats = true`로 "없음" 플래시 방지)

### 경기 상세
- LIVE 배지(글꼴·패딩·배경 투명도)를 경기 카드(`MatchCardView`)와 동일한 스타일로 통일 (기존엔 두 화면의 크기가 미묘하게 달랐음)
- **상태 배지에 날짜/시간 + 리그명 통합 표시**: 경기 종료엔 "날짜 시간", LIVE엔 "업데이트 n분 전" 앞에, 예정엔 시간 배지 아래에 리그명을 함께 표시
  → 화면 하단에 따로 있던 "정보" 카드(시작 시간·리그 행)는 내용이 전부 위로 옮겨져 제거함 (LIVE의 "마지막 업데이트" 행도 상태 배지와 중복이라 함께 정리)
- 실시간 팀 스탯 (킬 / 골드 / 타워 / 드래곤 / 바론)
- 승패 판정: `getEventDetails` API의 `outcome` 필드 우선 사용 → 없으면 inhibitors > towers > gold > kills 계층 fallback
- 게임별 선수 KDA, 골드, CS + 챔피언 이미지 (고정 너비로 줄바꿈 없이 통일된 레이아웃)
- 경기 상세 내 팀 탭 → 팀 상세 이동 (예정·진행·완료 경기 모두 선수단 정상 표시)
- MSI·Worlds 컨텍스트에서 팀 상세 진입 시 홈 리그(LCK 등) 기준으로 선수단·최근경기 로드
- 밴 카드: 게임별 blue/red 사이드 밴 챔피언 표시 (Riot API 데이터)
- 미시작 경기: 로딩 스피너 없이 "경기 예정" 카드 + 시작 시간 표시
- 게임 대기 상태: "드래프트 대기 중" 대신 "경기 시작 전" + 시계 아이콘으로 표시
- 게임 시리즈 픽커: G1/G2 텍스트 + 상태 점 (라이브 빨간 점 / 완료 파란 점 / 예정 텍스트), 선택 시 전체 버튼 영역 터치 가능
- 경기 종료 배지 아래 경기 날짜 표시
- 팀 로고 탭 → 팀 상세 페이지 이동
- **킬 타임라인**: 게임별 킬 이벤트를 시간 축 위에 표시 (Blue/Red 점, 분 단위 레이블) — 완료 경기 30일 캐시
- 선수 탭 → `PlayerDetailView`(이 경기 게임별 KDA만 표시, 인게임 데이터 기반이라 즐겨찾기 불가)
  - 툴바 "프로필 보기" → 양 팀 로스터 조회로 정식 `Player` 해석 → `LeaguePlayerDetailView`(시즌 스탯·챔피언풀·즐겨찾기)로 이동
  - 매칭 실패 시 알림으로 안내 (크래시 없이 원래 화면 유지)

### Favorites
- 탭바 6번째 탭 → iOS "더보기" 탭 안에 자동 편입 (Search와 동일한 이유로 `NavigationStack` 미사용,
  타이틀·"+" 버튼은 `.navigationTitle` + 툴바로 백버튼과 같은 줄에 표시)
- SwiftData 기반 팀 / 선수 즐겨찾기
- 팀 동일성 teamCode 기준 — MSI·LCK 컨텍스트 상관없이 동일 팀 중복 저장 방지, 소속 리그는 홈 리그로 자동 저장
- 즐겨찾기한 팀의 LIVE 경기 실시간 뱃지 + 스코어 (폰트 크기를 경기 카드/경기 상세의 LIVE 배지와 동일하게 통일)
- 즐겨찾기한 선수 행에 현재 LIVE 경기 정보 실시간 표시
- **대표 팀 설정**: 팀 행 길게 누르면 대표 팀 지정 → 앱 전체 Tint 색상 적용
- Live Activity: 잠금화면 실시간 스코어 (`[로고] 팀명 스코어–스코어 팀명 [로고]`) + Dynamic Island
  - 팀 로고: 고화질 로고(최대 300px, 비율 유지·업스케일 방지)를 App Group에 저장 → 위젯이 파일 직접 로드
  - ActivityKit attributes 4KB 제한 대응: attributes에는 예산(1.5KB/장) 내 최대 해상도 썸네일만 폴백으로 포함 (`attributesTooLarge` 방지)
  - 폴링: ContentView 레벨에서 실행 — 탭 전환·앱 재포그라운드 시에도 중단 없이 유지
  - **예약 시각부터 즉시 표시**: 경기 startTime 도달 시 API 확인 전에도 `isLive: false` pre-live Activity 시작 → "🕐 시작 중..." 표시. API가 inProgress 확인하면 실시간 스코어로 전환
  - 조기 시작 대응: API 딜레이 없이 예약 시각 기준으로 즉시 잠금화면·Dynamic Island에 대전 정보 표시
  - **세트 변경 알림 배너**: 매 폴링마다 조용히 갱신되던 것과 달리, 세트 번호(Game)가 바뀌는 순간엔 다이나믹 아일랜드/잠금화면에 배너+알림음 표시 (`AlertConfiguration`)

### 앱 메뉴 (AppMenu)
- 경기 알림 시간 설정 (Picker: 1분 / 5분 / 10분 / 30분 / 1시간 전)
- 알림 변경 시 즐겨찾기 팀 전체 알림 자동 재스케줄링
- **즐겨찾기 팀 경기 진행 알림 4종**: 경기 시작 / 세트 종료 / 세트 시작 / 경기 종료(승패) — 30초 폴링에서 라이브 목록 등장·세트 번호(`currentSet`) 증가를 감지해 각각 로컬 알림 발송 (이전엔 경기 전 알림 + 경기 종료 알림만 존재)
- 앱 설정 페이지 이동 (이용약관, 개인정보처리방침, 앱 사용 설명서, 버전 정보)
- 앱 설정 하단 법적 고지 — Riot Games 비제휴 팬 앱 명시 (한/영)
- **DEBUG 전용 테스트 섹션** (배포 빌드 미포함): 테스트 알림 5초 발송 / Live Activity 시작·스코어 업데이트·종료 — 실제 경기 시간 없이 알림·위젯 검증 가능

### 홈 화면·잠금화면 위젯 (LOLIVEWidgets)
- 즐겨찾기한 팀의 다음 경기 일정 표시
- Small / Medium / **Large** 사이즈 지원
- Large: 즐겨찾기 팀 전체 목록 (최대 5팀) 한눈에 표시
- 경기 1시간 이내 시 카운트다운 타이머 표시 (중앙정렬, 숫자 변경 시 레이아웃 고정)
- 여러 팀 캐러셀 (App Intents)
- 위젯 탭 → 해당 팀의 다음/진행 중 경기 상세 딥링크 (`lolive://match/<teamCode>`)
- MSI·Worlds 등 국제 대회 경기도 App Group 공유로 정상 표시 (홈 리그 API만 조회하던 문제 수정)
- 실제 경기 리그명 표시 (MSI 경기면 "MSI", LCK 경기면 "LCK")
- 다크/라이트 모드 자동 대응
- **잠금화면 accessory 위젯**: `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` 3종
- **조기 시작 감지**: 예정 1.5시간 이내 진입 시 `/getLive` API 직접 호출 → 예약 시각보다 일찍 시작하는 경기 즉시 반영
- **갱신 주기 최적화**: 라이브 중 15분 / 시작 1.5시간 이내 5분 / 그 이상은 (startTime − 1.5h) 시점에 갱신
- **예정 경기 캐시 만료 없음**: 앱을 오래 안 열어도 예정 경기 정보 유지 (startTime 전이면 TTL 미적용)
- App Group 캐시 없을 때 라이브 API fallback 자동 호출 → MSI·Worlds 라이브 경기도 위젯 표시 가능
- **라이브 스코어 표시**: 이전엔 라이브 중에도 "LIVE" 배지만 표시했는데, 이제 `1 - 0 · Game 2`처럼 실제 스코어·세트 번호까지 모든 사이즈(Small/Medium/Large/잠금화면 accessory)에 표시

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
- `CachedAsyncImage`: 메모리 → 디스크 → 네트워크 3단계 캐시, 정적 `loadImage(from:)` 메서드로 외부 공유
- `PlayerAvatarView`: URL nil·로드 실패·기본 실루엣(평균 밝기 < 15%) 모두 동일 플레이스홀더로 통일
- `LoadingView`: 전체화면 페이드인 로딩 인디케이터 (0.1초 딜레이, 캐시 즉시 로드 시 깜빡임 방지)

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

## 테스트

`LOLIVETests` 타겟, Swift Testing 프레임워크(`import Testing`) 사용. 총 44개 케이스.

| 대상 | 파일 | 내용 |
|------|------|------|
| `LeaguepediaService` 순수 함수 | `LOLIVETests.swift` | `escapeSql`/`parseBans`/`computeStats`/`findStats`/`findPicks`/`deduplicated` — 6개 스위트, 27개 케이스 |
| `TodayViewModel` | `ViewModelTests.swift` | `classify`(오늘/예정/완료 분류, 5일 컷오프, 정렬), `markCompleted`(라이브 종료 시 완료 승격) |
| `StandingsViewModel` | `ViewModelTests.swift` | `applyGD`(정상 리그는 Riot 원본 유지, 케스파컵처럼 전원 0-0이면 완료 경기로 재계산, 그룹별 독립 순위) |
| `TeamDetailViewModel` | `ViewModelTests.swift` | `applyMatches`(리그 내 상대전적 vs 대회 무관 최근경기, 교차 리그 병합, 중복 제거) |

- 네트워크가 필요한 함수는 `private` → `internal`로 가시성만 넓혀서 직접 호출 (동작 변화 없음, `RiotEsportsServiceProtocol`/`LiveStatsServiceProtocol` 같은 프로토콜 DI가 있는 경우 Mock 없이도 이 방식이 더 가벼움)
- 날짜 경계를 테스트할 땐 `Date()` 상대 오프셋 대신 "오늘 자정(KST)" 고정 기준점을 써야 함 — 안 그러면 자정 근처 실행 시 flaky해짐 (실제로 한 번 겪음)
- 커맨드라인 실행: `xcodebuild test -scheme LOLIVE -destination 'platform=iOS Simulator,name=<기기명>' -only-testing:LOLIVETests`
  (`LOLIVE.xcscheme`의 `TestAction`에 `LOLIVETests`가 `Testables`로 연결되어 있어야 함)

## CI/CD

`.github/workflows/ci.yml` — GitHub Actions, `main` push / PR마다 자동 실행.

1. `LOLIVE` 스킴 빌드 + `LOLIVETests` 44개 테스트 실행
2. `LOLIVEWidgetsExtension` 별도 빌드 (별도 스킴이라 위 테스트에 안 딸려옴 — 컴파일 깨짐만 감지, 테스트는 없음)

- API 키는 워크플로 안에서 직접 파일을 생성 — `APIKeys.swift.template`은 플레이스홀더(`YOUR_API_KEY_HERE`)만 있어서 그대로는 못 씀.
  여기 들어가는 키는 CLAUDE.md에도 평문으로 적힌 공개된 비공식 Riot Esports API 키라 GitHub Secrets 없이 처리함
  (진짜 민감한 키를 추가할 땐 반드시 Secrets로 전환할 것)
- 시뮬레이터 기종은 하드코딩하지 않고 러너에 설치된 iPhone 시뮬레이터를 실행 시점에 동적으로 선택 (Xcode/시뮬레이터 버전이 바뀌어도 안 깨지게)
- CD(자동 배포)는 아직 없음 — 앱스토어 출시 이후 TestFlight 업로드 자동화 추가 고려

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
│   │   ├── RiotEsportsService           — 경기/팀/선수 API
│   │   ├── LeaguepediaService           — Leaguepedia 코어 (네트워크 인프라 + 리그명 매핑 + RateLimiter)
│   │   ├── LeaguepediaService+Stats     — 선수 스탯 / 챔피언픽 / 밴 / 프로필 이미지 (extension)
│   │   ├── LeaguepediaService+History   — 과거 대회 경기 데이터 (extension)
│   │   ├── LeaguepediaCargo             — Cargo API 응답 모델 + 공유 타입
│   │   ├── LeaguepediaCache             — 메모리 + 디스크 캐시 actor
│   │   ├── LiveStatsService             — 게임 윈도우 데이터
│   │   ├── LiveActivityService          — Dynamic Island / 잠금화면 (App Group 고화질 로고 저장)
│   │   ├── MatchNotificationService     — 로컬 알림
│   │   ├── AppPreloadService            — 앱 시작 시 경기 상세 + Leaguepedia 스탯 병렬 프리로드
│   │   └── SharedDataService            — App Groups 동기화
│   ├── ViewModels/
│   │   ├── TodayViewModel           — 경기 목록 + 라이브 폴링
│   │   ├── TournamentDetailViewModel — 대회 일정 (Riot + Leaguepedia 3단계)
│   │   ├── StandingsViewModel       — 리그 순위
│   │   ├── PlayersViewModel         — 선수 목록 + 필터
│   │   ├── SearchViewModel          — 통합 검색
│   │   ├── LeaguesViewModel         — 리그 목록 로드/필터/지역 그룹핑
│   │   ├── LeagueDetailViewModel
│   │   ├── TeamDetailViewModel
│   │   ├── LeaguePlayerDetailViewModel — 챔피언/경기 데이터
│   │   └── MatchDetailViewModel     — 경기 상세 + 폴링
│   └── Views/
│       ├── TodayView, StandingsView, PlayersView
│       ├── SearchView, FavoritesView
│       ├── AppMenuView, AppSettingsView (DEBUG 테스트 섹션 포함)
│       ├── LeaguesView, TournamentDetailView
│       ├── LeagueDetailView (+Standings / +Schedule / +Teams 탭별 extension 분리)
│       ├── TeamDetailView, LeaguePlayerDetailView, ChampionDetailSheet, SeasonStatsView
│       ├── MatchDetailView (+Draft / +Stats / +Timeline 기능별 extension 분리), PlayerDetailView
│       ├── StateViews (ErrorRetryView / EmptyStateView 공통 상태 컴포넌트, EmptyStateView는 선택적 액션 버튼 지원)
│       └── MatchCardView, LeagueSectionHeader, CachedAsyncImage, LoadingView, PlayerAvatarView, ...
├── ContentView.swift        — TabView 진입점 (Today/Leagues/Standings/Players/Favorites/Search 6탭,
│                              5개 초과라 Favorites·Search는 iOS가 자동으로 "더보기" 탭에 편입)
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
- **URL Scheme**: LOLIVE 타겟 `Info.plist`의 `CFBundleURLTypes`에 `lolive` 스킴 등록 (레포에 커밋됨)
- **다크모드 고정**: `Info.plist`의 `UIUserInterfaceStyle = Dark` (레포에 커밋됨, 앱 코드의 `.preferredColorScheme(.dark)`와 이중 적용)
- **NSSupportsLiveActivities**: LOLIVE 타겟 Info에 `YES` 설정
- **NSSupportsLiveActivitiesFrequentUpdates**: LOLIVE 타겟 Info에 `YES` 설정
- **API Key**: `APIKeys.swift` (gitignore됨) — `RiotAPIKey` 상수 정의 필요
