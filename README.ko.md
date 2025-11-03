<div align="center">

<img src="logo.png" alt="ScreenMemo 로고" width="120"/>

# ScreenMemo

지능형 스크린 메모 & 정보 관리 도구

"화면엔 흔적 없이, 기억엔 흔적을"

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Flutter 기반의 지능형 스크린샷 관리 앱으로, 중요한 정보를 효율적으로 캡처·정리·회고할 수 있도록 돕습니다.

</div>

---

<p align="center">
  <b>언어</b>:
  <a href="README.md">简体中文</a> |
  <a href="README.en.md">English</a> |
  <a href="README.ja.md">日本語</a> |
  한국어
</p>

---

## 프로젝트 소개 및 활용 사례

ScreenMemo는 로컬 우선(Local-first)의 지능형 스크린샷 메모 및 검색 도구입니다. Android 기기의 화면을 자동으로 기록하고, OCR와 AI 요약을 통해 정보를 검색 가능·회고 가능·축적 가능하게 만들어 필요할 때 빠르게 단서를 되찾고 당시의 문맥을 복원할 수 있습니다.

할 수 있는 일:
- 다양한 앱에 나타났던 텍스트(기사 단편, 채팅 기록, 자막 등)를 복원합니다. 원본이 삭제되거나 철회되어도 로컬 기록에서 검색할 수 있습니다.
- "어디서 봤는지 기억나지 않는" 단서를 시간 범위와 앱 필터로 추적하여 당시 화면을 빠르게 찾습니다.
- 동일 시간대의 여러 스크린샷을 AI가 요약해 "일일 요약"을 생성합니다. 하루의 핵심 활동·주요 작업·요점을 돌아보는 데 유용합니다.
- 로컬 라이브러리를 내보내거나 백업하여 "두 번째 기억"을 마이그레이션·보관할 수 있습니다.

전형적인 활용 시나리오:
- 철회/삭제된 메시지나 페이지 내용을 회상하거나, 실수로 닫은 창의 정보를 되찾습니다.
- 키워드 검색으로 여러 날에 걸쳐 반복 등장하는 대사·용어·핵심 필드를 가로질러 찾아보고, 출현 횟수 파악과 빠른 회고를 지원합니다.
- 중요한 기간(프로젝트 수행, 졸업 논문, 리뷰/평가 준비)을 복기할 때 "일일 요약"으로 당일 핵심을 빠르게 파악하여 정리 비용을 낮춥니다.
- "기억 보물찾기": 과거에 놓친 디테일이나 영감을 되짚어 창작과 의사결정을 돕습니다.

---

## 오늘부터 당신의 개인 디지털 메모리를 구축하세요

왜 지금 기록을 시작해야 할까요?
- 다른 사람들은 이미 개인 AI를 훈련하고 있습니다
- 뒤처지지 마세요. 기록하지 않은 하루는 미래의 AI 도우미에게서 잃어버린 지식입니다

AI 격차
- 오늘부터 개인 데이터를 수집하는 사람은 AI가 더 강력해질 때 수년의 우위를 갖게 됩니다

흩어진 디지털 자아
- 소중한 개인 맥락은 여러 앱과 기기에 흩어져 있어 — ScreenMemo 없이는 통합적으로 활용하기 어렵습니다
---

## 동작 원리

1. 화면 수집: 사용자 권한 부여 후, Android 11+ 접근성 스크린샷 기능(`takeScreenshot`)을 기반으로 설정한 간격마다 전경 앱 화면을 캡처합니다. 앱/시간대별로 활성화·제외를 설정할 수 있습니다.
2. 로컬 저장: 원본 이미지를 앱의 개인 디렉터리에 저장하고, 타임스탬프·전경 앱 패키지명 등의 메타데이터를 로컬 DB(SQLite)에 기록하여 타임라인과 필터링을 지원합니다.
3. 텍스트 추출(OCR): 새 스크린샷에 OCR을 실행하여 텍스트를 추출하고 이미지와 인덱싱합니다. 다국어 문자셋을 지원하여 전체 텍스트 검색이 가능합니다.
4. 인덱스와 검색: "시간/앱/키워드"에 기반한 역인덱스를 구축합니다. 검색 화면에서 키워드 일치·시간 범위·앱 필터를 제공하여 과거 화면을 빠르게 찾습니다.
5. AI 처리: 동일 시간대의 여러 스크린샷을 집계·요약하여 "이벤트"와 "일일 요약"을 형성합니다. 다양한 모델 제공자를 선택·구성할 수 있습니다.
6. 프라이버시와 보안: 모든 원시 데이터와 인덱스는 로컬에 저장됩니다. 언제든 수집 일시정지·데이터 삭제·백업 내보내기가 가능합니다. NSFW 설정으로 민감한 콘텐츠 마스킹도 지원합니다.
7. 공간 관리: 정책에 따라 이미지 압축과 만료 정리를 수행하여 디스크 사용량을 자동으로 제어하고, 라이브러리 용량을 적정 수준으로 유지합니다.
8. 딥 링크: 검색/통계에서 이미지 뷰어나 특정 페이지로 깊은 링크 이동을 지원하여 당시 문맥으로 빠르게 돌아갑니다.

---

## 앱 스크린샷

<table>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/home.jpg" alt="홈" width="240" loading="lazy" />
      <div align="center"><sub>홈</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/search.jpg" alt="검색" width="240" loading="lazy" />
      <div align="center"><sub>검색</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/timeLine.jpg" alt="타임라인" width="240" loading="lazy" />
      <div align="center"><sub>타임라인</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/daySummary.jpg" alt="일일 요약" width="240" loading="lazy" />
      <div align="center"><sub>일일 요약</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/event.jpg" alt="이벤트" width="240" loading="lazy" />
      <div align="center"><sub>이벤트</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/collect.jpg" alt="즐겨찾기" width="240" loading="lazy" />
      <div align="center"><sub>즐겨찾기</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/prompt.jpg" alt="프롬프트 관리" width="240" loading="lazy" />
      <div align="center"><sub>프롬프트 관리</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/addAi.jpg" alt="AI 추가" width="240" loading="lazy" />
      <div align="center"><sub>AI 추가</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/aiChat.jpg" alt="AI 채팅" width="240" loading="lazy" />
      <div align="center"><sub>AI 채팅</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/setting.jpg" alt="설정" width="240" loading="lazy" />
      <div align="center"><sub>설정</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw.jpg" alt="NSFW 필터링" width="240" loading="lazy" />
      <div align="center"><sub>NSFW 필터링</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/deepLink.jpg" alt="딥 링크" width="240" loading="lazy" />
      <div align="center"><sub>딥 링크</sub></div>
    </td>
  </tr>
</table>


### 주요 기능

- 딥 링크: 브라우저 링크 자동 기록 지원
- NSFW 마스킹: 일반적인 성인 도메인을 자동 마스킹, 사용자 지정 도메인 지원
- 앱별 설정: 앱별로 수집 전략(수집 여부, 주기, 해상도/압축 등) 구성. 게임/영상/독서 앱을 위한 최적화 프리셋 제공

---

## 자주 묻는 질문(FAQ)

<details>
<summary>월간 저장 공간 사용량은 어느 정도인가요?</summary>

- 예시: 이미지 압축을 약 50 KB/장으로 설정하고 1분에 1장 캡처 시, 30일 ≈ 43,200장, 약 2.1 GB/월
- 계산식: 월 사용량(GB) ≈ (60 ÷ 캡처 간격(초)) × 60 × 24 × 30 × 단일 이미지 크기(KB) ÷ 1024 ÷ 1024
- 절감 팁: 캡처 간격 증가(예: ≥ 60초/장), 이미지 압축 활성화, 만료 정리 활성화(최근 30/60일만 보관), 불필요한 앱/상황 제외
</details>

<details>
<summary>데이터가 클라우드로 업로드되나요?</summary>

- 기본적으로 모든 데이터(스크린샷, OCR 텍스트, 인덱스, 통계)는 로컬에만 저장되며 업로드되지 않습니다. 언제든 수집 일시정지, 데이터 삭제, 백업 내보내기가 가능합니다.
</details>

<details>
<summary>민감한 앱을 제외하려면 어떻게 하나요?</summary>

- 설정에서 특정 앱의 수집을 비활성화하여 민감한 내용을 기록하지 않도록 할 수 있습니다.
</details>

<details>
<summary>배터리와 성능에 미치는 영향은 어떤가요?</summary>

- 주로 캡처 간격, 이미지 크기/압축, 전경 인식 빈도에 따라 달라집니다. 리소스 사용량을 줄이기 위해 압축과 만료 정리 활성화를 권장합니다.
</details>

<details>
<summary>백업/마이그레이션은 어떻게 하나요?</summary>

- "데이터 가져오기/내보내기"에서 에셋과 데이터베이스를 일괄 내보내기/가져오기하여 마이그레이션 또는 보관에 활용할 수 있습니다.
</details>

## 빠른 시작

### 요구 사항
- **Flutter SDK**: 3.8.1 이상
- **Dart SDK**: 3.8.1+
- **Android Studio** / **VS Code** + Flutter 플러그인
- **Android SDK**:
  - 최소 버전(minSdkVersion): 21
  - 대상 버전(targetSdkVersion): 34
- 플랫폼 요구: 자동 스크린샷은 Android 11(API 30)+의 접근성 `takeScreenshot`에 의존
- **JDK**: 11 이상

### 설치

1. **프로젝트 클론**
   ```bash
   git clone <repository-url>
   cd screen_memo
   ```

2. **의존성 설치**
   ```bash
   flutter pub get
   ```

3. **국제화 파일 생성**
   ```bash
   flutter gen-l10n
   ```

4. **앱 실행**(개발 모드)
   ```bash
   # Android 기기 연결 또는 에뮬레이터 실행
   flutter run
   ```

### 개발 명령

```bash
# Debug APK 빌드
flutter build apk --debug

# 기기에 설치
flutter install

# 로그 보기
adb logcat | findstr "ScreenMemo"  # Windows
adb logcat | grep "ScreenMemo"     # Linux/macOS

# 정적 분석
flutter analyze
```

---

## 릴리스 빌드

ABI 별로 분할된 최적화 APK(최소 용량) 생성:

```powershell
flutter clean
flutter pub get
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

**산출물 위치**:
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`
---

## 권한 안내

앱은 다음 권한을 필요로 합니다:

| 권한 | 용도 | 필요성 |
|------|------|--------|
| 저장소 | 스크린샷 및 데이터 파일 저장 | 필수 |
| 알림 | 서비스 상태 및 알림 표시 | 필수 |
| 접근성 서비스 | 자동 스크린샷 및 전경 앱 인식 | 필수 |
| 사용 통계 | 전경 앱 확인(Usage Stats) | 필수 |

> 모든 권한은 최초 실행 시 안내되며, 언제든 시스템 설정에서 해제할 수 있습니다.

---

## 국제화

지원 언어:
- 간체 중국어(기본)
- 영어
- 일본어
- 한국어

### 새 언어 추가

1. `lib/l10n/` 디렉터리에 새 `.arb` 파일 생성(예: `app_ko.arb`)
2. `app_en.arb` 내용을 복사해 번역
3. `flutter gen-l10n` 실행하여 코드 생성
4. `LocaleService`에 새 로캘 등록

---

## 기여 가이드

코드 기여, 이슈, 제안 모두 환영합니다!

1. 이 저장소를 Fork
2. 기능 브랜치 생성(`git checkout -b feature/AmazingFeature`)
3. 변경 커밋(`git commit -m 'feat: add some amazing feature'`)
4. 브랜치 푸시(`git push origin feature/AmazingFeature`)
5. Pull Request 생성

다음을 보장해 주세요:
- `flutter analyze` 통과
- 필요한 테스트 추가
- 관련 문서 업데이트

---

## 감사의 말

다음 오픈소스 프로젝트에 감사드립니다:
- [Flutter](https://flutter.dev) - UI 프레임워크
- [Google ML Kit](https://developers.google.com/ml-kit) - 텍스트 인식
- [SQLite](https://www.sqlite.org/) - 데이터베이스 엔진
- 모든 기여자와 의존 패키지 유지보수자
