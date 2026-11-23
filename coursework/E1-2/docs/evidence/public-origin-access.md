# 공개 origin 접근 검증

다음 명령은 `git remote get-url origin`으로 주소를 가져오고 호스트 파일을 전혀 마운트하지 않은 새 컨테이너를 실행합니다. 컨테이너 내부에서도 `env -i`로 이미지의 환경을 모두 제거한 뒤 경로, 원격 주소와 명시적인 Git 비인증 설정만 전달해 `git ls-remote`를 실행합니다.

```bash
sh scripts/verify_public_origin.sh
```

The check fails if the origin URL contains user information or anonymous access
cannot read `HEAD` and `main`. Supplying one tag name also checks that tag. Only
the explicitly allowlisted environment reaches Git in the container, so future
host authentication variables are excluded. The default Git client image is
pinned by version and OCI index digest as
`docker.gitea.com/gitea:1.24.7@sha256:918955f16b1e91732af6c449bb2db3a34271748dbed1ccfbae48f8a2fb5480b8`;
the command does not start a Gitea server.

검증 당시의 출력은 `snapshots/public-origin.txt`에 보존합니다.
