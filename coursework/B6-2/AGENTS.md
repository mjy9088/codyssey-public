# Book catalog subtree

- Keep this directory independently executable with Docker Engine and Compose.
- Runtime direct dependencies are limited to FastAPI, Uvicorn, SQLAlchemy, Jinja2, and python-multipart.
- Persist CRUD state in SQLite through synchronous SQLAlchemy sessions injected with FastAPI Depends.
- Keep routers, services, repositories, models, templates, and static assets separated.
- Use only synthetic book records. Keep databases, screenshots, traces, reports, and logs untracked.
- QEMU verification must boot the real application in a guest without KVM, privileged mode, capabilities, bind mounts, or a Docker socket.
- Keep pure source files at or below 250 lines and preserve strict typing.
