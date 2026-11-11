# 블루투스 맞고 - 설치와 실행 안내

이 폴더는 앱의 소스 코드야. 폰에 설치하려면 먼저 APK 파일로 빌드해야 해.
빌드 방법은 두 가지고 둘 중 하나만 하면 돼.

- 방법 A: 내 PC에 Flutter를 설치해서 빌드 (한 번 설치하면 계속 쓸 수 있음)
- 방법 B: GitHub 클라우드에서 빌드 (PC에 아무것도 설치하지 않아도 됨)

---------------------------------------------------------------

## 방법 B. GitHub 클라우드 빌드 (설치 없음)

1. github.com 에 가입하고 로그인한다
2. 오른쪽 위 + 버튼 → New repository → 이름은 matgo → Private 선택 → Create repository
3. 만들어진 저장소 화면에서 "creating a new file" 또는 Add file → Create new file 을 누른다
4. 파일 이름 칸에 정확히 이렇게 입력한다: .github/workflows/build.yml
   (슬래시를 치면 폴더로 바뀐다)
5. 아래 큰 입력칸에 같이 보낸 build.yml 파일의 내용을 전부 붙여넣고 Commit changes → Commit
6. 저장소 첫 화면으로 돌아가 Add file → Upload files 를 누르고
   matgo_final.zip 파일을 압축 풀지 말고 그대로 올린다 → Commit changes
7. 위쪽 Actions 탭에 들어간다. build-apk 가 노란 불(진행 중)로 돌아간다. 5~10분 걸린다
   - 자동으로 안 시작하면 Actions → build-apk → Run workflow
   - 5번 커밋 때 한 번 실패한 기록이 있어도 괜찮다 (그때는 zip이 없었으니까)
8. 초록 체크가 뜨면 그 실행을 눌러서 맨 아래 Artifacts 의 matgo-apk 를 다운로드한다
9. 받은 zip을 열면 app-release.apk 가 들어 있다. 이게 앱이다

빨간 불(실패)이면 그 실행을 누르고 빨간 단계의 오류 문구를 그대로 복사해서 나한테 보내줘.
Artifacts 에 matgo-logs 가 있으면 같이 받아서 열어 봐. 코드 오류 목록이 들어 있다.

---------------------------------------------------------------

## 방법 A. 내 PC에서 빌드

1. Flutter SDK와 Android Studio 를 설치한다
   안내: https://docs.flutter.dev/get-started/install (운영체제를 고르고 Android 개발용으로 따라간다)
2. 터미널(명령 프롬프트)에서 flutter doctor 를 실행해서 Flutter와 Android toolchain 이 체크 표시가 될 때까지 안내대로 고친다
3. 이 폴더(matgo)를 풀어 둔 위치에서 아래를 차례로 실행한다

   flutter create --platforms=android --project-name matgo app
   cd app
   flutter pub add nearby_connections permission_handler

4. app/lib 과 app/test 폴더의 내용을 지우고 이 폴더의 lib, test 를 그대로 복사해 넣는다
5. app/android/app/src/main/AndroidManifest.xml 을 열어서
   android_manifest_permissions.xml 안의 uses-permission 줄들을 <application 태그 바로 위에 붙여넣는다
   (python이 있으면 python tools/patch_manifest.py <AndroidManifest 경로> android_manifest_permissions.xml 로 자동으로 된다)
6. 테스트와 분석 (선택)
   flutter test
   flutter analyze
7. APK 만들기
   flutter build apk --release
   결과: app/build/app/outputs/flutter-apk/app-release.apk

폰을 USB로 연결해서 바로 실행하려면 flutter run 을 쓴다.

---------------------------------------------------------------

## 폰에 설치하기 (내 폰과 친구 폰 모두)

1. app-release.apk 를 카톡이나 USB 등으로 폰에 옮긴다
2. 파일을 눌러 설치한다. "출처를 알 수 없는 앱" 허용 창이 뜨면 허용한다
3. Play 프로텍트가 경고하면 "무시하고 설치" 또는 "그래도 설치"를 누른다
4. 처음 실행하면 근처 기기 권한 창이 뜬다. 모두 허용한다
5. 블루투스와 위치(GPS)를 켠다. 위치가 꺼져 있으면 연결이 자주 끊긴다

---------------------------------------------------------------

## 실기기 2대 확인 체크리스트

[ ] 1. 폰 A에서 방 만들기, 폰 B에서 방 찾기 → 방을 누르면 양쪽 모두 게임판이 뜬다
[ ] 2. 패 하나를 누르면 올라오고 같은 월 바닥패가 노란 테두리로 표시된다
[ ] 3. 확정을 누르면 패가 나가고 더미에서 한 장이 뒤집힌다
[ ] 4. 상대 폰에서는 내 패가 뒷면으로만 보인다
[ ] 5. 바닥에 같은 월이 2장일 때 고르기 화면이 나온다
[ ] 6. 3점이 되면 고/스톱 버튼이 나온다. 고를 누르면 상대 차례로 넘어간다
[ ] 7. 스톱을 누르면 결과 화면에 점수와 계산 내역이 나온다
[ ] 8. 다시 하기를 누르면 새 판이 시작된다
[ ] 9. 진행 중에 한쪽 폰의 블루투스를 껐다 켜거나 멀리 떼어 놓았다가 가져오면
       "다시 연결하는 중" 화면 뒤에 같은 판이 이어진다
[ ] 10. 60초가 넘으면 "연결이 끊겼어" 화면에서 처음으로 돌아갈 수 있다
[ ] 11. 블루투스 또는 위치를 끄고 방 만들기를 누르면 안내 문구가 뜬다

문제가 생기면 몇 번에서 어떻게 됐는지와 화면에 나온 문구를 알려줘.

---------------------------------------------------------------

## 규칙과 수치

점수와 박 기준은 lib/game/config.dart 한 파일에 모여 있다. 동네마다 달라지는 값이라 평소 하던 규칙과 맞는지 확인해.

- 스톱 가능 점수 3점
- 광 3장 3점 (비광이 섞이면 2점) 4장 4점 5장 15점
- 고도리 5점 홍단 청단 초단 각 3점
- 열끗 띠 5장부터 1점 피 10장부터 1점 (쌍피는 2장으로 계산)
- 1고 +1 2고 +2 3고부터 고마다 ×2
- 광박: 이긴 쪽 광 점수가 있고 진 쪽 광이 0장이면 ×2
- 피박: 이긴 쪽 피 점수가 있고 진 쪽 피가 5장 이하면 ×2
- 뻑 먹기 따닥 쪽 싹쓸이: 상대 피 1장 가져오기
- 9월 열끗(술잔)은 열끗으로만 계산한다

## 아직 없는 것

- 흔들기 폭탄 총통 연뻑 자뻑 고박 멍박
- 누적 점수와 기록 저장 (판이 끝나면 점수가 사라진다)
- 방장 앱이 완전히 꺼지면 판을 복구할 수 없다 (잠깐 끊긴 경우만 복구된다)
