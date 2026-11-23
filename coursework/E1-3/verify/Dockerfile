FROM python:3.13.7-alpine3.22@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844

WORKDIR /work
ENV HOME=/tmp
COPY main.py data.json ./
COPY tests/test_*.py tests/
RUN chmod -R a+rX /work
USER 65532:65532
CMD ["python", "-B", "-m", "unittest", "discover", "-s", "tests", "-v"]
