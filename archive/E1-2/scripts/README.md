# Scripts

| 스크립트 | 목적 | 요구 환경 |
|---|---|---|
| `setup_venv.sh` | `.venv` 생성 및 로컬 `src` 패키지 연결 | Python 3.10+, POSIX 셸 |
| `capture_terminal_evidence.py` | 프롬프트와 입력을 포함한 퀴즈 PTY·텍스트 기록과 해시 생성 | 준비된 `.venv` |
| `render_terminal_svgs.py` | 고정 텍스트 증거를 내용 높이에 맞는 제출 SVG로 변환 | Python 3.10+ |
| `rasterize_submission_svgs.py` | 고정 resvg·Noto CJK 이미지로 SVG를 PNG로 변환 | Docker |
| `capture_submission_screenshots.py` | 지정 tag에서 PTY → SVG → PNG 제출 증거 생성 | 준비된 `.venv`, Docker |
| `github_clone_pull_practice.sh` | 실제 GitHub origin에서 clone·push·pull 실습 | GitHub 쓰기 권한, Git, POSIX 셸 |
| `verify_public_origin.sh` | 깨끗한 컨테이너에서 origin 공개 접근 확인 | Docker, POSIX 셸 |
| `create_submission_tag.sh` | 제출 대상 annotated tag 생성·push | GitHub 쓰기 권한, 준비된 `.venv`, Docker |
| `refresh_submission_metadata.py` | 현재 origin과 tag의 공개 접근 증거 갱신 | 준비된 `.venv`, Docker |
| `verify_submission.py` | tag 원본 테스트와 제출 증거 일치 검증 | 준비된 `.venv`, Docker |

`setup_venv.sh`는 외부 의존성이 없는 프로젝트 특성에 맞춰 `venv --without-pip`를 사용하고, 가상환경의 `.pth`에 `quiz_game/src`를 연결합니다. 시스템 패키지를 설치하거나 네트워크에 접근하지 않습니다.

셸 실행 비트에 의존하지 않도록 모든 `.sh` 파일은 `sh scripts/파일명.sh` 형태로 실행합니다.

GitHub 실습은 실제 `origin/main`에 증거 커밋을 추가하므로 기본 실행을 거부하고 `--execute` 확인 인자를 요구합니다. 공개 접근 검증만 Docker의 깨끗한 컨테이너를 사용합니다. 자세한 절차는 [Git 실습 문서](../docs/git-practice.md)와 [증거 문서](../docs/evidence/README.md)를 참고하세요.
