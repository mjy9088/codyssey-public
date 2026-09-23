# 재현 가능한 제출 증거

- [TTY 실행 증거](terminal-evidence.md)
- [비인증 origin 접근 검증](public-origin-access.md)

## clone과 pull 실습

Docker가 실행 중인 환경에서 다음 명령을 사용합니다.

```bash
sh scripts/github_clone_pull_practice.sh --execute
```

스크립트는 현재 origin을 별도 디렉터리에 clone하고, 증거 파일을 commit·push한 뒤 기존 작업 디렉터리에서 pull하여 해시와 내용을 검증합니다. 실제 `origin/main`을 변경하므로 제출 저장소가 확정된 뒤 한 번 실행합니다.

생성된 스냅샷과 `manifest.json`은 `snapshots/`에 있습니다. 매니페스트의 Git revision과 SHA-256을 통해 생성 시점과 파일 무결성을 확인할 수 있습니다.

최종 제출에서는 [제출 자료 절차](../submission/README.md)에 따라 annotated tag를 기준으로 메타데이터와 스크린샷을 갱신하고 검증합니다.
