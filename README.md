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
- (내부 정리) 라이브 경기에 리그 로고를 채워 넣는 `enrich()`가 `blockName`("Week 10" 등)을 누락시키던
  버그 수정 — 지금은 화면에서 안 쓰는 값이라 눈에 보이는 영향은 없었음
- 라이브·예정·완료 경기 동일 ID 중복 제거 (ForEach collision 방지)
- 즐겨찾기 팀 경기만 필터링 (전체 / ★ 즐겨찾기 토글) — 즐겨찾기가 없어도 필터 바는 항상 표시
- **LIVE 필터**: 필터 바에 LIVE 토글 추가 — 켜면 현재 진행 중인 경기만 리그 그룹째로 걸러서 보여줌.
  "전체 / ★ 즐겨찾기 / LIVE"는 라디오 버튼처럼 항상 하나만 선택되도록 동작 (동시에 여러 개가 켜져 보여 헷갈리던 문제 수정).
  즐겨찾기 화면에도 동일한 LIVE 필터를 추가해 즐겨찾기한 팀/선수 중 라이브 중인 항목만 볼 수 있음
- **Liquid Glass 시범 적용**: 필터 필(전체/★즐겨찾기/LIVE)에 iOS 26의 새 유리 재질(`glassEffect`)을
  시범 적용. `if #available(iOS 26.0, *)`로 분기해서 iOS 26 미만 기기는 기존 단색 캡슐 스타일 그대로
  유지 (배포 타깃 17.6은 안 바뀜). `GlassEffectContainer`는 일부러 안 씀 — 서로 배타적으로 선택하는
  필들이 눌릴 때 옆 필이랑 액체처럼 이어져 보여서 헷갈릴 수 있어, 각 필을 독립된 유리로 유지
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
- **승패·GD를 항상 완료 경기 스코어에서 직접 계산**(`Standing.reconciled`): Riot Standings API는 팀별로
  결과 반영 시점이 어긋날 수 있다는 걸 실측으로 확인함 — 같은 경기인데 한쪽 팀(T1) 기록만 갱신되고
  반대쪽(Gen.G)은 안 반영돼 두 팀의 총 경기 수 자체가 안 맞는 경우가 실제로 있었음. 그래서 Riot이
  내려주는 개별 승패 숫자를 그대로 믿지 않고, 완료된 경기 스코어를 직접 집계해 그룹별 승수 → 세트 득실
  → 팀명 순으로 항상 재계산·재정렬한다 (기존엔 전 팀이 0승0패로 묶여 내려오는 케스파컵류 대회에서만
  재계산했는데, 개별 승패가 내려와도 서로 안 맞을 수 있다는 걸 확인해 범위를 넓힘). 완료된 경기가
  하나도 없으면(시즌 시작 전) Riot 원본 순위를 그대로 사용. Standings·리그 상세 순위 탭이 로직을 공유

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
- 탭바 Search 탭으로 접근 (`role: .search` — iOS 26에서 나머지 탭과 분리된 원형 유리 버튼으로 표시)
- **네이티브 검색창 확장 애니메이션**: 직접 만든 텍스트필드 대신 SwiftUI `.searchable(text:)`를 사용 —
  Search 탭을 누르면 원형 버튼이 시스템이 그려주는 검색창으로 늘어남 (애플 표준 Search Role 동작).
  이 효과가 나오려면 Search 탭의 콘텐츠가 자체 `NavigationStack`을 가져야 해서 `SearchView`에
  추가함 — 이전엔 tab 6개라 "더보기" 안에 있었던 탓에 자체 `NavigationStack`을 일부러 안 뒀었는데,
  Search가 5개 탭 중 하나로 직접 노출되면서 필요해짐
- **탭 선택 즉시 키보드 자동 표시**: `.searchable`만으로는 검색창이 펼쳐지기만 하고 키보드는 안 뜸.
  `isPresented` 바인딩으로 탭 선택 시점을 감지해보려 했으나 실기기에서 탭 선택만으로는 바뀌지 않는 걸
  확인 → `ContentView`가 탭 선택마다 올려주는 `searchFocusTrigger` 카운터를 신호로 받아 iOS 18+ 전용
  `.searchFocused`로 직접 포커스를 줘서 탭 누르자마자 바로 타이핑 가능하게 함. iOS 17 폴백 탭바에선
  이 모디파이어 자체가 없어서 기존처럼 수동 탭 후 입력. 포커스 주기 전 넣어뒀던 150ms 지연은
  체감 반응 속도를 떨어뜨려서 제거
- **앱 첫 실행 후 첫 Search 탭 선택 시 포커스가 안 잡히던 버그 수정**: 첫 진입 땐 검색창 뷰가 그
  순간 막 생성되는 중이라 포커스 요청이 씹히고, 두 번째 탭부터 정상 동작했음(이미 뷰가 존재해서).
  포커스 요청 직후 200ms 뒤 아직 안 잡혀있으면 한 번 더 시도하도록 수정 — 이미 잡혀 있으면(2회차
  이후) 그대로라 체감 반응 속도엔 영향 없음
- **탭 전환 애니메이션 제거(실험적)**: Search 원형 버튼 → 검색창으로 부풀어 오르는 iOS 네이티브 모핑
  애니메이션이 느리게 느껴진다는 피드백으로, `ContentView`에 `.transaction(value: selectedTab) { $0.disablesAnimations = true }`를
  붙여서 `selectedTab`이 바뀌는 트랜잭션 자체의 애니메이션을 꺼서 모든 탭 전환(Search 포함)이 애니메이션
  없이 즉시 일어나게 함 — 부드럽게 펼쳐지는 대신 뜸을 듯 바로 나타남. 실기기 확인 후 어색하면 되돌릴 수 있음
- **X(취소) 버튼 → Today 탭으로 이동**: `.tabViewStyle(.sidebarAdaptable)`를 쓰면 아이패드 사이드바
  지원은 생기지만, 그 대가로 검색 활성화 시 시스템이 검색창 옆에 "이전 탭으로 돌아가기"용 원형
  홈 아이콘을 자동으로 붙여줌(제거 불가) — X 버튼(그냥 키보드만 닫힘)과 기능이 겹쳐 혼란스러워서
  `.sidebarAdaptable`을 빼기로 함(아이패드는 사이드바 대신 일반 하단 탭바로 표시). 대신 `isPresented`
  바인딩이 true→false로 바뀌는 시점(X 버튼 탭)을 감지해서 Today 탭(`selectedTab = 0`)으로 직접
  이동시킴 — 검색 취소 = 홈으로
- 리그 / 팀 / 선수 통합 검색
- 검색 결과에서 팀·선수 상세 페이지 바로 이동
- 즐겨찾기 인라인 토글
- 팀 검색 인덱싱 시 케스파컵처럼 지역이 "한국"으로 찍히는 국내 컵 대회는 팀의 정규 소속 리그(LCK 등)보다
  후순위로 정렬 — 안 그러면 네트워크 응답 순서에 따라 팀이 컵 대회 소속으로 잘못 표시될 수 있음.
  `search_teams`/`search_players`는 12시간 디스크 캐시라 수정 후에도 캐시 만료 전까지는 기존 값이 남아있을 수 있음
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
- **불완전한 상세 정보가 캐시에 영구 고정되던 버그 수정**: 목록 스코어는 Leaguepedia 보정으로 완료 처리됐는데
  Riot의 상세 API(`getEventDetails`)는 아직 안 채워진 경우(밴픽·승자 없음), 그 "빈" 응답을 30일 캐시에
  그대로 저장해버려서 나중에 Riot이 채워줘도 계속 빈 상태로 보이던 버그. 이제 게임 중 하나라도
  완료+승자 확정 상태가 아니면 캐싱하지 않고, 다음 진입 시 다시 시도한다
- **완료 경기 상세 서버 영구 캐싱**: 로컬 디스크 캐시 미스 시, Riot에 바로 물어보는 대신 서버
  (`getMatchDetail` Callable)부터 확인. `syncLive`가 경기 종료를 감지하는 즉시 밴픽·게임별 승자를
  한 번만 가져와 Firestore(`matchDetails`)에 영구 저장해두기 때문에, 서버가 이미 캐싱해둔 경기라면
  기기가 Riot을 다시 호출할 필요가 없음 — 사용자가 몇 명이든 그 경기에 대한 Riot 호출은 서버가 최초
  1회만 함. 경기 종료 직후엔 Riot 상세가 아직 안 채워진 경우가 있어서, 서버도 "완료+승자 확정" 확인
  후에만 저장하고 아니면 `pendingMatchDetails`에 등록해 다음 폴링(1분)마다 재시도(24시간 후 포기).
  서버에도 없는 경우(백필 이전 오래된 경기 등)에만 기존처럼 Riot 직접 호출로 폴백
- 선수 탭 → `PlayerDetailView`(이 경기 게임별 KDA만 표시, 인게임 데이터 기반이라 즐겨찾기 불가)
  - 툴바 "프로필 보기" → 양 팀 로스터 조회로 정식 `Player` 해석 → `LeaguePlayerDetailView`(시즌 스탯·챔피언풀·즐겨찾기)로 이동
  - 매칭 실패 시 알림으로 안내 (크래시 없이 원래 화면 유지)

### Favorites
- **탭바가 아닌 Today 상단 별 아이콘(시트)으로 진입**: 탭 5개 제한 때문에 Search를 분리된 원형 버튼으로
  쓰려면 메인 탭을 4개(Today/Leagues/Standings/Players)까지만 유지해야 해서, Favorites 탭을 없애고
  Today 상단 헤더의 별 아이콘 → 시트로 여는 방식으로 옮김 (기존엔 탭 6개라 이 화면과 Search 둘 다 iOS
  "더보기" 탭 안에 자동 편입돼 있었음). 시트라 자체 `NavigationStack` + "닫기" 버튼을 가짐
- SwiftData 기반 팀 / 선수 즐겨찾기
- 팀 동일성 teamCode 기준 — MSI·LCK 컨텍스트 상관없이 동일 팀 중복 저장 방지, 소속 리그는 홈 리그로 자동 저장
- 즐겨찾기한 팀의 LIVE 경기 실시간 뱃지 + 스코어 (폰트 크기를 경기 카드/경기 상세의 LIVE 배지와 동일하게 통일)
- 즐겨찾기한 선수 행에 현재 LIVE 경기 정보 실시간 표시
- **대표 팀 설정**: 팀 행 길게 누르면 대표 팀 지정 → 앱 전체 Tint 색상 적용
- Live Activity: 잠금화면 실시간 스코어 (`[로고] 팀명 스코어–스코어 팀명 [로고]`) + Dynamic Island
  - 팀 로고: 고화질 로고(최대 300px, 비율 유지·업스케일 방지)를 App Group에 저장 → 위젯이 파일 직접 로드
  - ActivityKit attributes 4KB 제한 대응: attributes에는 예산(900B/장) 내 최대 해상도 썸네일만 폴백으로 포함, 원본 이미지 URL은 attributes에 담지 않음 (`attributesTooLarge` 방지 — base64 인코딩 시 원본보다 약 37% 커지는 걸 감안하지 않아 로고가 복잡한 팀에서 실제로 거부당하던 버그 수정)
  - 폴링: ContentView 레벨에서 실행 — 탭 전환·앱 재포그라운드 시에도 중단 없이 유지
  - **예약 시각부터 즉시 표시**: 경기 startTime 도달 시 API 확인 전에도 `isLive: false` pre-live Activity 시작 → "🕐 시작 중..." 표시. API가 inProgress 확인하면 실시간 스코어로 전환
  - 조기 시작 대응: API 딜레이 없이 예약 시각 기준으로 즉시 잠금화면·Dynamic Island에 대전 정보 표시
  - **세트 변경 알림 배너**: 매 폴링마다 조용히 갱신되던 것과 달리, 세트 번호(Game)가 바뀌는 순간엔 다이나믹 아일랜드/잠금화면에 배너+알림음 표시 (`AlertConfiguration`)
  - **Riot 라이브 피드가 멈춘 경우 대응**: `esports-api.../getLive`가 `inProgress`로 계속 보고해도 실제로는
    Riot의 인게임 피드(`feed.lolesports.com`) 자체가 멈춰서 갱신이 안 되는 경우가 있다 (직접 확인함 — 특정
    경기에서 40분 넘게 프레임이 안 들어온 사례, `getEventDetails`도 함께 멈춰있어 Riot 쪽 API가 전부 동시에
    안 따라잡는 상태였음). 스코어/세트 번호는 원래 세트가 끝나야만 바뀌는 값이라 "안 바뀐다"는 걸로 멈춤을
    판단할 수 없어서, 인게임 피드의 `gameState == "finished"`(즉시 신뢰 가능) 또는 5분간 프레임 무갱신을
    "멈춤" 신호로 사용한다. 멈춘 것으로 확인되면 Leaguepedia `MatchSchedule`과 대조 — 이 테이블은 시리즈가
    안 끝나도 Team1Score/Team2Score를 세트가 끝날 때마다 갱신해준다는 걸 실측으로 확인함(`Winner`만
    시리즈 전체가 끝나야 채워짐). 이전엔 Winner가 비어있으면 무조건 `.unstarted`로 취급해 이미 나와 있는
    부분 스코어까지 버리던 버그가 있었는데, 스코어가 있으면 `.inProgress`로 인식하도록 수정. 시리즈가
    끝났으면 완료 처리(결과 알림·Live Activity 종료·목록 이동), 세트만 끝났으면 스코어만 갱신하고 계속
    라이브로 표시. Leaguepedia도 아직 그대로면 점수를 지어내지 않고 5분마다 재시도만 한다.
  - **라이브에서 사라지는 순간 최종 확인**: Riot이 스코어를 끝까지 안 주고 라이브 목록에서만 빼버리는
    경우(실제 사례) 대응 — 즐겨찾기 경기가 사라지는 그 순간 보정값이 없으면 Leaguepedia를 한 번 더
    확인해 최종 점수로 결과 알림·완료 처리
  - **콜드 스타트 사각지대 대응**: 앱을 재시작하면 "라이브에서 사라지는 순간"을 목격할 기회 자체가
    없어서(직전 상태가 없음) 위 보정이 안 먹힌다. 그래서 스케줄 API(`getSchedule`) 차원에서도 별도로
    보완: `inProgress`인데 90분 넘게 스코어 변화가 없는 경기를 Leaguepedia로 대조 (기존엔 `unstarted`
    3시간 초과·`completed`+0:0만 봤음)
  - **당겨서 새로고침이 캐시 때문에 실제로는 아무것도 안 하던 문제 수정**: 일정 데이터가 15분 캐시라
    당겨도 캐시를 그대로 반환해서 Leaguepedia 보정도 다시 안 타고 있었음 — `loadTodayMatches(forceRefresh:)`
    추가, pull-to-refresh는 일정 캐시를 지우고 진짜로 다시 받아오도록 수정. (Leaguepedia 결과 캐시까지
    추적 중인 모든 리그에 대해 한꺼번에 지우려는 시도는 새로고침 한 번에 Leaguepedia를 왕창 두드리게 돼
    서버 레이트리밋에 걸리는 부작용이 있어 제거 — 일정 캐시만 지워도 실제로 대조가 필요한 리그에
    한해서만 자연스럽게 Leaguepedia 호출이 일어난다)
  - **"현재 대회 페이지"를 잘못 고르던 근본 버그 수정**: Leaguepedia에서 진행 중인 대회의 결과를 가져올 때
    "가장 최근 시작일(DateStart) 순 첫 번째" 페이지를 골랐는데, 정규시즌 도중에도 플레이오프 페이지가
    미래 날짜로 이미 등록돼 있어서 정렬하면 플레이오프가 맨 위로 와버렸다 — 그 결과 실제 경기가 있는
    정규시즌 페이지 대신 텅 빈 플레이오프 페이지에서 결과를 찾고 있었음 (Xcode 콘솔 진단 로그로 실측
    확인: "API 조회 0건"). `LPTournamentEntry`에 `dateStart` 추가, "이미 시작한 대회 중 가장 최근 것"을
    고르도록 수정
  - **Leaguepedia 보정이 화면 전체를 막던 문제 수정 (2단계 로딩)**: 이전엔 일정 새로고침이 Leaguepedia
    보정까지 다 끝나야 화면에 반영됐는데, 레이트리밋 재시도(최대 36초)에 걸리는 리그가 여러 개 겹치면
    체감상 새로고침이 아주 느려졌다. `fetchScheduleRaw`(보정 없는 Riot 원본만)를 추가해 1단계로 화면을
    즉시 채우고, `fetchSchedule`(보정 포함)은 백그라운드에서 마저 돌려 끝나는 대로 화면을 한 번 더
    갱신하도록 분리

### 앱 메뉴 (AppMenu)
- 경기 알림 시간 설정 (Picker: 1분 / 5분 / 10분 / 30분 / 1시간 전)
- 알림 변경 시 즐겨찾기 팀 전체 알림 자동 재스케줄링
- **즐겨찾기 팀 경기 진행 알림 4종**: 경기 시작 / 세트 종료 / 세트 시작 / 경기 종료(승패) — 30초 폴링에서 라이브 목록 등장·세트 번호(`currentSet`) 증가를 감지해 각각 로컬 알림 발송 (이전엔 경기 전 알림 + 경기 종료 알림만 존재)
- 앱 설정 페이지 이동 (이용약관, 개인정보처리방침, 앱 사용 설명서, 버전 정보)
- 앱 설정 하단 법적 고지 — Riot Games 비제휴 팬 앱 명시 (한/영)
- **DEBUG 전용 테스트 섹션** (배포 빌드 미포함): 테스트 알림 5초 발송 / 경기 시작·종료 알림 즉시 발송 / Live Activity 시작·스코어 업데이트(세트 종료·시작 알림 + Dynamic Island 배너 동시 트리거)·종료 — 실제 경기 시간 없이 알림·Live Activity·위젯 검증 가능
- **실시간 폴링 진단 로그** (`[LivePoll]` 태그, DEBUG 전용): 실제 라이브 경기로 검증할 때 Xcode 콘솔에서 팀 코드로 필터링하면 매 폴링(30초)마다 즐겨찾기 경기의 스코어·세트·상태, 경기 시작/세트 변경/결과 알림 발송 시점, `fetchLive()` 실패 여부를 바로 확인 가능

### 백그라운드 푸시 알림 (서버·앱 연동 완료)
기존 알림 4종(위 참고)은 `TodayViewModel.startLivePolling()`의 30초 클라이언트 폴링 기반이라 앱이
foreground로 살아있을 때만 동작 — 백그라운드 진입 시 iOS가 프로세스를 정지시켜 폴링도 멈추고,
앱을 다시 열 때 그동안 놓친 변화를 뒤늦게 감지한다. 앱이 꺼져 있어도 즉시 알림을 받으려면 서버가
대신 감시하다 원격 푸시(APNs)를 보내는 구조가 필요해서, `lolive-firebase` 백엔드에 아래 기능을 추가:
- **`syncLive`(1분 주기 스케줄 함수) 확장**: 직전 폴링 때 저장해둔 `liveMatches` 스냅샷과 비교해
  경기 시작(신규 라이브 등장) / 세트 변경(`currentSet` 증가) / 경기 종료(라이브에서 사라짐) 3가지
  전환을 감지 → 해당 경기 두 팀 중 하나라도 즐겨찾기한 기기에 FCM으로 푸시 발송 (`functions/src/push.ts`).
  세트 종료·시작은 클라이언트와 달리 서버가 같은 시점에 동시에 발견하므로(1분 주기라 실시간으로
  둘을 따로 못 잡음) 알림 두 번이 아니라 "Game N 종료 · Game N+1 시작" 하나로 합쳐서 보냄
- **`registerDeviceToken`(신규 Callable)**: 기기의 FCM 토큰 + 즐겨찾기 팀 코드 배열을 `deviceTokens`
  컬렉션에 저장. 팀 코드는 대문자로 정규화. Firestore 규칙상 클라이언트 직접 읽기/쓰기 금지, 이
  Callable(Admin SDK로 규칙 우회)로만 씀
- 만료된 토큰(재설치·삭제 등)은 FCM 발송 응답에서 `registration-token-not-registered` 에러로 걸러
  자동 삭제
- 비용: FCM·APNs 자체는 완전 무료. `syncLive` 호출 빈도(1분 주기)는 그대로라 Cloud Functions
  무료 한도(월 200만 회) 안에서 여유롭게 처리됨
- **앱 쪽 연동**: `AppDelegate.swift`(`FirebaseApp.configure()` + APNs 등록) + `LOLIVEApp`에
  `@UIApplicationDelegateAdaptor` 연결. `PushNotificationService.swift`가 FCM 토큰을 받아
  `registerDeviceToken` Callable로 서버에 등록 — `ContentView`의 즐겨찾기 변경 지점(`.task`,
  `.onChange(of: favoriteTeams)`)에서 최신 즐겨찾기 팀 코드로 재등록 트리거
- **아직 실기기에서 "앱 완전 종료 상태로 푸시 도착" 검증은 안 해봄** — 다음 라이브 경기로 확인 필요

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

### 탭바 (iOS 18+ / iOS 26+ 이중 대응)

`ContentView`의 `TabView`는 iOS 버전에 따라 두 가지 구현을 씀 (`#available` 분기):
- **iOS 18 이상**: 새 `Tab(_:systemImage:value:)` 기반 API + `.tabViewStyle(.sidebarAdaptable)`.
  아이패드에서 사이드바로 자동 전환, 탭 순서/표시 여부를 사용자가 직접 편집 가능 (예전 `.tabItem`
  방식엔 없던 기능). iOS 26에서는 하단 탭바 자체도 시스템이 자동으로 새 유리 재질로 그려줌
  (앱 쪽 코드 변경 불필요). Search 탭은 `role: .search`를 줘서 iOS 26에서 나머지 탭 캡슐과
  분리된 원형 유리 버튼으로 따로 표시됨 (애플 표준 Search Role 탭바 스타일).
- **iOS 17**: 배포 타깃(17.6)을 지원해야 해서 기존 `.tabItem` 방식 그대로 유지.
- **탭 5개 제한**: iOS는 탭바에 최대 5개까지만 바로 보여주고 초과분은 자동으로 "더보기"에 몰아넣는데,
  `role: .search` 탭도 이 5개 슬롯 중 하나로 계산된다. 기존엔 메인 탭 5개(Today/Leagues/Standings/
  Players/Favorites) + Search로 총 6개라 Search의 "분리된 원형 버튼" 효과가 전혀 안 보이고 Favorites·
  Search 둘 다 "더보기"에 접혀 들어가는 문제가 있었음 → Favorites를 탭바에서 빼고 Today 상단
  별 아이콘(시트)으로 옮겨서 탭을 Today/Leagues/Standings/Players + Search 5개로 줄임. 이제
  Search가 의도대로 독립된 원형 유리 버튼으로 표시됨

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

### 캐시 키 중앙 관리 (`CacheKey`)

여러 파일이 같은 캐시를 참조하는 키(`leagues`/`schedule_{id}`/`tournaments_{id}`/`standings_{id}`/`roster_{id}`/
`all_schedule_{id}`/`live`/`lp_playerimg_{name}`)는 문자열·TTL이 `AppDiskCache.swift`의 `CacheKey` enum
한 곳에만 정의돼 있고, `RiotEsportsService`와 각 ViewModel의 `preloadFromCache()`가 전부 이걸 참조합니다.
예전엔 서비스가 캐시를 쓰는 쪽과 ViewModel이 선로딩용으로 같은 캐시를 읽는 쪽에 키/TTL 리터럴이 각각
복사돼 있어서(예: `"leagues"` + `24 * 3600`이 8개 파일에 중복), 한쪽만 고치면 서로 어긋날 수 있었습니다.
이 정리 과정에서 `StandingsViewModel.refreshStandings()`가 `standings_{league.id}`를 지우고 있었는데
실제 저장 키는 `standings_{tournament.id}`라 캐시가 전혀 안 지워지던 버그도 함께 발견해 고쳤습니다.
(즐겨찾기 여부와 무관한 `players_all`/`search_teams`/`search_players`/`league_players_{id}`/
`event_detail_v2_{id}` 등은 한 파일에서만 읽고 쓰는 캐시라 중복 위험이 없어 `CacheKey`에는 포함하지 않았습니다.)

### 캐시 레이어

| 데이터 | 캐시 키 | TTL | 저장소 |
|--------|---------|-----|--------|
| 리그 목록 | `leagues` | 24h | AppDiskCache |
| 경기 일정 | `schedule_{leagueId}` | 15분 | AppDiskCache |
| 라이브 경기 (네트워크 장애 폴백 전용) | `live` | 5분 | AppDiskCache |
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

**완료 경기 프리로드 개수**: `TodayViewModel`/`LeagueDetailViewModel`/`TournamentDetailViewModel`/`AppPreloadService`
4곳이 전부 같은 정책("최근 완료 경기 몇 개까지 상세 데이터를 미리 받아둘지")을 쓰는데, `prefix(8)`로 각자 하드코딩돼
있던 걸 `MatchDetailViewModel.preloadCount`로 통합했습니다.

**위젯 라이브 체크 시작 시점**: `FavoriteTeamWidget.swift` 안에서 "예정 90분 전부터 라이브 API 확인 시작"이라는
같은 기준이 5곳에 `5400`(초)으로 반복돼 있던 걸 `FavoriteTeamProvider.earlyLiveCheckWindow` 상수로 통합했습니다.

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

### 라이브 데이터 캐시 · 앱↔위젯 공유

- `RiotEsportsService.fetchLive()`: 매 호출마다 결과를 `live` 키로 디스크에 저장. `/getLive` 요청이 네트워크 오류로
  실패하면 5분 이내 캐시가 있을 때 그걸로 폴백 (30초 폴링 특성상 5분이면 낡은 데이터를 오래 우려먹지 않음).
- **위젯 자체 API 호출 절감**: `ContentView.saveWidgetNextMatches()`가 즐겨찾기 팀뿐 아니라 지금 라이브 중인
  모든 팀(상대팀 포함)을 App Group에 공유 저장한다. `WidgetNetworkService.fetchAllLiveMatchInfo()`는 이
  스냅샷이 90초 이내로 신선하면 그대로 재사용하고 `/getLive` 호출을 건너뛴다 — 앱이 실행 중일 땐 위젯이
  같은 데이터를 또 요청하지 않게 되어 API 호출 횟수가 줄어든다. 스냅샷이 없거나 오래됐으면(앱이 백그라운드/
  종료 상태) 기존처럼 위젯이 직접 호출한다.

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
├── ContentView.swift        — TabView 진입점 (Today/Leagues/Standings/Players + Search role 5탭,
│                              Favorites는 탭에서 빠지고 Today 상단 별 아이콘 시트로 이동)
├── AppDelegate.swift        — FirebaseApp.configure() + APNs 등록 (@UIApplicationDelegateAdaptor)
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
- **Firebase 푸시 알림 SDK**: `firebase-ios-sdk` 패키지 추가 완료 (`FirebaseCore`/`FirebaseMessaging`/
  `FirebaseFunctions` 3개 제품이 LOLIVE 타겟에 연결됨, `Package.resolved` 커밋됨).
  `GoogleService-Info.plist`는 `LOLIVE/`에 있음(gitignore됨, 새로 세팅할 땐 Firebase 콘솔에서 다시 받아야 함)
