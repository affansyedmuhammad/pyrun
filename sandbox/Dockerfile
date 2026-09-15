# The sandbox image: Python plus one pinned library, nothing from the app.
# Built by bin/sandbox-build. Every isolation flag is applied at `docker run`
# time by Sandbox::DockerRunner (docs/DESIGN.md §5.4), so this file only
# decides what is installed.
#
# Pinned by digest so a tag cannot change what runs underneath us. The digest
# is the multi-architecture index, valid on arm64 (Docker Desktop) and x86_64 (EC2).
FROM python:3.12-slim-bookworm@sha256:782412e85d0f0984994c290652577d4018aff08145c85b262bb63dc0c7522254

# Hash-verified install: pip refuses anything whose sha256 is not listed.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --require-hashes --no-deps -r /tmp/requirements.txt \
 && rm /tmp/requirements.txt \
 && find /usr/local/lib/python3.12 -name "__pycache__" -type d -prune -exec rm -rf {} + \
 && python3 -c "import numpy; print('numpy', numpy.__version__)"

# The runner also passes --user 65534:65534; this makes the image itself agree.
USER 65534:65534
WORKDIR /tmp

# The command is supplied by the runner (timeout + python3 -I -u -) and the code
# arrives on stdin, so nothing here changes when a limit changes.
ENTRYPOINT []
CMD ["python3", "-I", "-u", "-"]
