# syntax=docker/dockerfile:1
FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG HOST_UID
ARG HOST_GID

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       build-essential ca-certificates curl git less openssh-client \
       python3 python3-venv ripgrep unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu's base image may contain the unused ubuntu account at UID 1000.
# Resolve that collision inside the image; never change repository ownership.
RUN test -n "$HOST_UID" && test -n "$HOST_GID" \
    && test "$HOST_UID" -gt 0 && test "$HOST_GID" -gt 0 \
    && owner="$(getent passwd "$HOST_UID" | cut -d: -f1 || true)" \
    && if [ "$owner" = ubuntu ]; then \
         userdel ubuntu; \
       elif [ -n "$owner" ]; then \
         echo "Requested UID already belongs to $owner" >&2; exit 1; \
       fi \
    && if ! getent group "$HOST_GID" >/dev/null; then \
         groupadd --gid "$HOST_GID" dev; \
       fi \
    && useradd --uid "$HOST_UID" --gid "$HOST_GID" \
       --create-home --shell /bin/bash dev \
    && install -d -o "$HOST_UID" -g "$HOST_GID" /workspace /home/dev/.codex

# Official standalone Codex installer
RUN curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
    && CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
       CODEX_NON_INTERACTIVE=true sh /tmp/install-codex.sh \
    && chmod -R a+rX /opt/codex \
    && rm /tmp/install-codex.sh

# Docker supplies isolation; do not invoke the inner bubblewrap sandbox
RUN if [ ! -e /home/dev/.codex/config.toml ]; then \
   printf '%s\n' \
      'sandbox_mode = "danger-full-access"' \
      'approval_policy = "on-request"' \
      'cli_auth_credentials_store = "file"' \
      > /home/dev/.codex/config.toml; \
   fi \
   && chown "$HOST_UID:$HOST_GID" /home/dev/.codex/config.toml

ENV HOME=/home/dev
USER dev
WORKDIR /workspace

RUN codex --version && git --version && python3 --version
CMD ["sleep", "infinity"]
