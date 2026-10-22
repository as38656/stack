ARG SUITE=trixie
FROM debian:${SUITE}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git lsb-release make python3 rsync sudo xz-utils \
    && rm -rf /var/lib/apt/lists/*

# /stack is owned by the host user, not by root in the container.
RUN git config --system --add safe.directory '*'

ENV DEBIAN_FRONTEND=noninteractive
