# 실제 GitHub clone/pull 실습

`scripts/github_clone_pull_practice.sh`는 현재 `git remote get-url origin`이 가리키는 실제 GitHub 저장소에서 과제의 clone과 pull 절차를 수행합니다.

이 작업은 `origin/main`에 커밋을 하나 추가하는 외부 변경입니다. 실수로 실행하지 않도록 `--execute`를 반드시 지정해야 합니다.

```bash
sh scripts/github_clone_pull_practice.sh --execute
```

실행 전 조건:

- 현재 브랜치가 `main`
- 작업 트리가 깨끗함
- 로컬 `main`과 `origin/main`이 동일함
- 현재 Git 자격 증명으로 origin에 push할 수 있음

실행 순서:

1. 현재 origin을 임시 디렉터리에 clone합니다.
2. clone한 저장소에서 `github-clone-pull.txt`를 commit·push합니다.
3. 기존 작업 디렉터리에서 `git pull --ff-only`을 실행합니다.
4. 커밋 해시와 증거 파일 내용이 같은지 확인합니다.

원격 URL을 하드코딩하지 않으므로 제출 저장소가 바뀌어도 현재 origin을 사용합니다. 임시 clone은 종료 시 삭제되지만 증거 커밋과 파일은 실제 GitHub 이력에 남습니다.
