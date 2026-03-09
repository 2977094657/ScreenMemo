<div align="center">

<img src="logo.png" alt="ScreenMemo 로고" width="120"/>

# ScreenMemo

지능형 스크린 메모 & 정보 관리 도구

"화면엔 흔적 없이, 기억엔 흔적을"

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)

로컬 우선(Local-first) 스크린샷 메모리 도구: 자동 캡처, OCR 전체 텍스트 검색, 필요할 때만 켜는 AI 요약/리플레이.

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

## 프로젝트 소개

ScreenMemo는 로컬 우선(Local-first) 스크린샷 메모 및 검색 도구입니다. 권한을 허용하면 Android 기기의 화면을 자동으로 기록하고, OCR로 검색할 수 있게 만듭니다. AI 요약은 선택 기능이며, 필요할 때만 켜서 일정 기간의 스크린샷을 “일일 요약” 같은 회고용 메모로 압축할 수 있습니다.

---

## 오늘부터 당신의 개인 디지털 기억을 구축하세요

**왜 지금 바로 시작해야 할까요?**
- **돌이킬 수 없는 지식의 손실**: 점점 더 많은 사람들이 일상 데이터로 개인 AI를 훈련시키기 시작하는 지금, 기록하지 않은 하루하루는 미래의 AI 비서가 "당신을 이해하는" 기반을 잃게 만듭니다.
- **조용히 벌어지는 시간의 복리**: 데이터는 하루아침에 쌓이지 않습니다. 오늘부터 디지털 표본을 축적하기 시작한 사람은 향후 AI가 질적 도약을 이룰 때 다른 누구도 따라잡을 수 없는 개인 전용 기억 저장소를 자연스럽게 갖게 됩니다.
- **흩어진 디지털 자아의 구출**: 당신의 가장 소중한 컨텍스트는 종종 여러 앱과 기기에 파편화되어 있습니다. ScreenMemo로 적절하게 수집하지 않으면, 이들은 결국 시간과 함께 흩어져 다시는 온전히 깨워질 수 없습니다.

---

## 동작 원리

1. 화면 수집: 사용자 권한 부여 후, Android 11+ 접근성 스크린샷 기능(`takeScreenshot`)을 기반으로 설정한 간격마다 전경 앱 화면을 캡처합니다. 앱/시간대별로 활성화·제외를 설정할 수 있습니다.
2. 로컬 저장: 원본 이미지를 앱의 개인 디렉터리에 저장하고, 타임스탬프·전경 앱 패키지명 등의 메타데이터를 로컬 DB(SQLite)에 기록하여 타임라인과 필터링을 지원합니다. 최근 버전부터 스크린샷/DB/캐시는 내부 `files/output` 아래에 저장되며, 로그는 디버깅/내보내기 용도로 앱 전용 외부 디렉터리(externalFiles/output/logs)에 저장됩니다. 앱은 시작 시 기존 외부 데이터를 자동으로 마이그레이션합니다.
3. 텍스트 추출(OCR): 새 스크린샷에 OCR(Android ML Kit)을 실행하여 텍스트를 추출하고 이미지와 인덱싱합니다. 전체 텍스트 검색이 가능합니다.
4. 인덱스와 검색: "시간/앱/키워드"에 기반한 역인덱스를 구축합니다. 검색 화면에서 키워드 일치·시간 범위·앱 필터를 제공하여 과거 화면을 빠르게 찾습니다.
5. AI 처리(선택): 동일 시간대의 여러 스크린샷을 집계·요약하여 "이벤트"와 "일일 요약"을 형성합니다. 다양한 모델 제공자를 선택·구성할 수 있습니다.
6. 프라이버시와 보안: 스크린샷/OCR/인덱스는 기본적으로 로컬에 저장됩니다. AI 요약은 사용자가 활성화한 경우에만 네트워크 요청이 발생합니다. 언제든 수집 일시정지·데이터 삭제·백업 내보내기가 가능합니다. NSFW 설정으로 민감한 콘텐츠 마스킹도 지원합니다.
7. 공간 관리: 정책에 따라 이미지 압축과 만료 정리를 수행하여 디스크 사용량을 자동으로 제어하고, 라이브러리 용량을 적정 수준으로 유지합니다.
8. 딥 링크: 검색/통계에서 이미지 뷰어나 특정 페이지로 깊은 링크 이동을 지원하여 당시 문맥으로 빠르게 돌아갑니다.
9. AI 요청 게이트웨이(AI 활성화 시): 모델 호출은 스트리밍 우선 게이트웨이로 통합되며, 문제 발생 시 비스트리밍으로 자동 폴백하여 다중 제공자 호환성을 높입니다.

---

## Flutter 대화 컨텍스트 시스템(Codex-style)

> 설계 문서: `docs/CONTEXT_MEMORY.md`

- **3단계 저장**: UI tail(`ai_messages`) + 전체 전사(`ai_messages_full`) + 압축 메모리(`ai_conversations.summary/tool_memory_json`).
- **컨텍스트 주입**: 각 요청에 `<conversation_context>`(요약 + tool memory)를 주입하고, 최근 tail 전사를 prompt history로 추가합니다.
- **자동 압축**: 대화가 길어지면 롤링 요약을 생성해 반복/루프를 줄입니다.
- **관측 가능성**: 최근 프롬프트의 대략적인 토큰(bytes/4) 추정치를 기록하고, UI 패널에서 확인/수동 압축/초기화를 지원합니다.

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

- 딥 링크: 브라우저 링크를 자동 기록하고, 검색/통계에서 원클릭으로 원문 맥락에 복귀
- NSFW 마스킹: 일반적인 성인 도메인을 자동 마스킹하고, 규칙을 사용자 지정할 수 있습니다
- 앱별 설정: 앱별로 수집 전략(수집 여부, 주기, 해상도/압축 등) 구성. 게임/영상/독서 앱을 위한 최적화 프리셋 제공
- 테마/색상: 라이트/다크 및 시드 컬러 전환
- 요약: 일일/주간 요약, 페르소나(사용자 프로필) 아티클(스트리밍 출력)
- 저장소 분석: 앱 데이터/캐시/스크린샷/로그 사용량 내역

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

## 자동 릴리스 (GitHub Actions)

이 프로젝트는 태그 푸시 시 자동으로 빌드되어 GitHub Releases에 게시되도록 구성되어 있습니다. 일반적인 푸시나 커밋에서는 트리거되지 않으며 태그(예: `v1.0.0`)를 푸시할 때만 빌드됩니다.

### 릴리스 단계

```bash
git tag v1.0.0
git push origin v1.0.0
```

푸시 후, GitHub Actions는 **ABI별 분할된 Release APK**를 자동으로 빌드하고 동일한 이름의 Release를 생성하여 산출물(APK, `symbols-*.zip` 및 선택적 `mapping-*.txt`)을 첨부합니다.

버전 규칙: 태그(`v` 접두사 제외)는 `--build-name`으로, `github.run_number`는 `--build-number`로 사용됩니다.

### 선택 사항: 프로덕션 서명 구성 (권장)

Release APK를 (디버그 키가 아닌) 프로덕션 키스토어로 서명하려면 저장소의 `Settings -> Secrets and variables -> Actions`에 다음 시크릿을 추가하세요:

- `ANDROID_KEYSTORE_BASE64`: `jks`/`keystore` 파일의 Base64
- `ANDROID_KEYSTORE_PASSWORD`: 키스토어 비밀번호
- `ANDROID_KEY_ALIAS`: 키 별칭
- `ANDROID_KEY_PASSWORD`: 키 비밀번호

> 워크플로는 기본적으로 GitHub 내장 `GITHUB_TOKEN`을 사용하여 Release를 게시합니다. 추가로 개인 토큰을 제공할 필요가 없습니다.

---

## 데스크톱 데이터 병합 도구

모바일에서 병합 가져오기는 성능상 한계가 있을 수 있어, Windows/macOS/Linux용 데스크톱 데이터 병합 도구를 제공합니다. 여러 개의 내보낸 ZIP 백업 파일을 PC에서 빠르게 병합할 수 있습니다.

### 기능

- 내보낸 ZIP 백업 파일을 여러 개 선택
- 출력 디렉터리 지정(병합된 데이터 저장 위치)
- 병합 진행률 및 상세 결과 표시
- 스크린샷/데이터베이스를 완전 병합

### 실행 파일 빌드

**Windows**:
```powershell
flutter build windows -t lib/main_desktop_merger.dart --release
```

**macOS**:
```bash
flutter build macos -t lib/main_desktop_merger.dart --release
```

**Linux**:
```bash
flutter build linux -t lib/main_desktop_merger.dart --release
```

### 산출물 위치

| 플랫폼 | 출력 디렉터리 |
|------|----------|
| Windows | `build/windows/x64/runner/Release/` |
| macOS | `build/macos/Build/Products/Release/` |
| Linux | `build/linux/x64/release/bundle/` |

> 산출물은 폴더 형태입니다. Windows의 경우 `screen_memo.exe`와 필요한 DLL이 포함되므로 폴더 전체를 복사해 실행할 수 있습니다.

---

## 권한 안내

앱은 필요에 따라 다음 권한을 안내합니다(기능에 따라 다를 수 있음):

| 권한 | 용도 | 필요성 |
|------|------|--------|
| 알림 | 포그라운드 서비스 상태/알림 표시 | 필수(백그라운드 캡처) |
| 접근성 서비스 | 자동 스크린샷(Android 11+ `takeScreenshot`) 및 전경 앱 인식 | 필수(자동 캡처) |
| 사용 통계 | 전경 앱 확인(Usage Stats) | 필수 |
| 사진/미디어 | 이미지/비디오를 갤러리에 저장 | 선택 |
| 정확한 알람 | 일일/주간 요약 알림 스케줄 | 선택 |

> 참고: 앱 데이터는 앱 전용 저장소에 저장되므로 기존 `READ/WRITE_EXTERNAL_STORAGE` 런타임 권한은 필요하지 않습니다. 권한은 필요한 시점에 안내되며, 언제든 시스템 설정에서 해제할 수 있습니다.

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

### i18n 감사(번역 누락/하드코딩 회귀 방지)

사용자에게 보이는 문구가 번역에서 빠지거나, 하드코딩 문자열이 다시 늘어나는 것을 막기 위해 감사 도구와 테스트 가드를 제공합니다.

- **ARB 일관성**: 모든 `lib/l10n/*.arb`는 템플릿(`app_en.arb`)과 key가 완전히 일치해야 합니다(누락/추가 모두 실패).
- **플랫폼 로컬라이징**: iOS/Android의 핵심 로컬라이징 선언/리소스가 누락되면 실패합니다.
- **Flutter UI 하드코딩 문자열**: baseline 모드로 **새로 추가된** 하드코딩 문자열만 차단합니다. 기존 항목은 baseline에 기록되어 점진적으로 줄일 수 있습니다.

검사 실행:
```bash
dart run tool/i18n_audit.dart --check
```

baseline 업데이트(정말로 레거시/예외인 경우에만):
```bash
dart run tool/i18n_audit.dart --update-baseline
```

무시 규칙(신중히 사용):
- 줄 끝에 `// i18n-ignore` 추가: 해당 줄 무시
- 파일 어디든 `// i18n-ignore-file` 추가: 파일 전체 무시

`flutter test`는 `test/i18n_audit_test.dart`를 자동 실행해 회귀를 막습니다.

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
