# Codyssey AI All-in-One

[코디세이 AI 올인원](https://codyssey.kr/) 과정 관련 공개 가능한 모든 코드를 다룹니다.

매번 초기화되는 교육장 PC는 터미널에서 [아래 스크립트 실행](environment/codyssey-init/README.md)으로 빠르게 개발환경으로 설정할 수 있습니다. 많은 사용&피드백 부탁드립니다.

```sh
curl -fsSL bit.ly/cody-init | sh
```

<!-- This section alone is intentionally in Korean -->

[Environment setup documentation](environment/codyssey-init/README.md).

## Local development tools

Install the shared command-line tools with [mise](https://mise.jdx.dev/):

```sh
mise install
```

The repository configuration pins Node.js, pnpm, Python, uv, and ShellCheck.
See [Coursework development](docs/COURSEWORK_DEVELOPMENT.md) for per-course setup,
local verification, runnable demos, and the Docker development shell. Use
`just submit B6-3` to prepare a standalone submission locally; it does not push.
