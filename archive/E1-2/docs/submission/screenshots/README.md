# Screenshot files

자동 생성 파일은 `capture_submission_screenshots.py`가 지정한 Git tag를 임시 디렉터리에 추출하고, 그 원본의 실제 프로그램을 PTY에서 실행해 만듭니다. 프롬프트와 입력 echo가 포함된 고정 텍스트에서 SVG를 직접 생성하고, 고정 resvg·Noto CJK Docker 이미지로 PNG를 만듭니다. 따라서 Chromium과 호스트 글꼴에 의존하지 않습니다.

`svg-manifest.json`은 텍스트 → SVG 해시 연결을, `raster-manifest.json`은 SVG → PNG 해시 연결과 renderer 버전을 기록합니다.

`resvg`는 시스템 그래픽 라이브러리에 의존하지 않고 지원 플랫폼 사이의 픽셀 재현성을 목표로 하는 정적 SVG renderer입니다. 이 저장소는 공식 [`resvg`](https://github.com/linebender/resvg) revision과 Docker Official Images의 멀티아키텍처 [`rust`](https://hub.docker.com/_/rust), [`debian`](https://hub.docker.com/_/debian) manifest digest를 Dockerfile에 고정합니다.

`vscode-environment.png`만 실제 GUI 환경에서 수동으로 추가합니다. 권장 화면에는 다음 항목이 함께 보여야 합니다.

- VS Code에서 이 저장소를 연 상태
- 선택된 `.venv` Python interpreter
- Source Control 또는 GitHub 원격 연결 상태
- 비밀 토큰이나 개인정보가 노출되지 않은 터미널의 `python --version`
