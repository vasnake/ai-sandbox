# syntax=docker/dockerfile:1
FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       bash build-essential ca-certificates curl git gnupg groff less \
       python3 python3-dev python3-venv ripgrep unzip zip \
       bubblewrap \
    && rm -rf /var/lib/apt/lists/*

# Install Codex outside the persistent home volume
RUN curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
    && CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
       CODEX_NON_INTERACTIVE=true sh /tmp/install-codex.sh \
    && chmod -R a+rX /opt/codex \
    && rm /tmp/install-codex.sh

# Ubuntu 24.04 may already have a user with UID 1000; let useradd select a free UID.
RUN useradd --create-home --shell /bin/bash dev \
    && mkdir -p /workspace /home/dev/.codex /home/dev/.aws /home/dev/.local/bin \
    && chown -R dev:dev /workspace /home/dev

USER dev
WORKDIR /workspace

# Fail the build if any installation is unusable by the runtime user.
RUN codex --version && python3 --version
