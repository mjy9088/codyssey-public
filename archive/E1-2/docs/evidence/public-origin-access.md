# 공개 origin 접근 검증

다음 명령은 `git remote get-url origin`으로 주소를 가져오고 호스트 파일을 전혀 마운트하지 않은 새 컨테이너를 실행합니다. 컨테이너 내부에서도 `env -i`로 이미지의 환경을 모두 제거한 뒤 경로, 원격 주소와 명시적인 Git 비인증 설정만 전달해 `git ls-remote`를 실행합니다.

```bash
sh scripts/verify_public_origin.sh
```

origin URL에 사용자 정보가 포함되어 있거나 인증 없이 `HEAD`와 `main`을 조회할 수 없으면 실패합니다. tag를 인자로 주면 그 tag도 원격에서 조회합니다. 향후 새로운 인증 관련 환경변수가 추가되더라도 허용 목록에 없으므로 컨테이너 안의 Git 프로세스에 전달되지 않습니다. 기본값은 버전이 고정된 Git 클라이언트 image `docker.gitea.com/gitea:1.24.7`이며 Gitea 서버는 실행하지 않습니다.

검증 당시의 출력은 `snapshots/public-origin.txt`에 보존합니다.
