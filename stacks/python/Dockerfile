# python stack pack — the deploy image (REQ-351, REQ-390; P6 R20).
# The base image is pinned by digest: the multi-arch index of python:3.12-slim as looked up on 2026-10-04 with
#   docker buildx imagetools inspect python:3.12-slim
# Re-pin on purpose (the same command, then edit the digest below) — a moving tag would change a release's image
# without a commit; /retrospective's pinned-download bump lists this digest (owner: the maintainer). The repository
# link (org.opencontainers.image.source) is passed at build time by scripts/release-image.sh, since a Dockerfile
# cannot know its repository.
# The image installs, in order: the project's runtime dependencies from the hash-pinned requirements-runtime.txt
# (--require-hashes --no-deps --only-binary :all:: wheels only, every file's bytes pinned, so nothing unpinned resolves
# from PyPI at tag time — an sdist would be built under pip's build isolation, whose build requirements are installed
# unhashed, so a dependency that ships no wheel for the image's platform fails the build instead; an empty lock installs
# nothing), then the release's wheel alone (--no-deps --no-index), then pip check, which fails the build when
# the wheel declares a dependency the lock lacks. The release's code runs as the numeric non-root user 10001, which owns
# its working directory /app (an app may write there; the installed packages stay root's). A project
# that adds a dependency lists it in requirements-runtime.in and regenerates the lock:
#   uv pip compile --generate-hashes --universal --python-version 3.12 requirements-runtime.in -o requirements-runtime.txt
FROM python:3.12-slim@sha256:02108f5d322dd89f1c9e552442c25acb0543dfdbc455693a5599624f20d9155d

WORKDIR /app
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app \
 && chown 10001:10001 /app
COPY requirements-runtime.txt /tmp/
RUN pip install --no-cache-dir --require-hashes --no-deps --only-binary :all: -r /tmp/requirements-runtime.txt
COPY dist/*.whl /tmp/
RUN pip install --no-cache-dir --no-deps --no-index /tmp/*.whl && pip check && rm -rf /tmp/*.whl /tmp/requirements-runtime.txt

USER 10001
CMD ["python", "-m", "__PKG__"]
