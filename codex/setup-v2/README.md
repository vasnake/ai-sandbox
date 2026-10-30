# 2026-10-09 setup-v2

Первая версия была не очень удачная, две основные проблемы
- GID:UID пользователя dev в контейнере не матчится с овнером файлов в воркспейсе, который mount с хоста.
- нет докер-композ файла, неудобно управлять, в частности, подключить в сеть к уже существующим контейнерам (clickhouse)

The setup provides:
- Ubuntu 24.04, Codex, Git/SSH, Python/venv, and basic build tools.
- dev with vlk’s actual UID/GID, without changing host repository ownership.
- Your host repository directory mounted read/write at /workspace.
- The existing airflow-network, declared external.
- 16 GiB RAM limit—a ceiling, not a reservation. Docker Docs
- Persistent Codex credentials, configuration, and history in a named volume.
- run codex with danger-full-access with on-request approvals, retaining Docker’s default security policies.

bootstrap: generate '.env', build image and start 'codex' conainer in detached mode
```sh
pushd ${HOME:?unknown}/data/github/ai-sandbox/codex/setup-v2
export PROJECT_ROOT=${HOME:?unknown}/data/gitlab/gameram # && pushd ${PROJECT_ROOT:?unknown} # workdir useful

# build and start
bash -x ./bootstrap.sh ${PROJECT_ROOT:?unknown}
```

how to use it after it is ready
```sh
# manage container
docker compose ps # stop # start # exec codex bash
docker compose stop
docker compose start
# docker compose down # destroy container
# 'down' preserves the Codex state volume; 'down -v' deletes it.
# Exiting an interactive shell leaves the container running.

# run session
docker compose start
docker compose exec codex bash

# in container
pushd /workspace/gameram-dwh # data
pushd /workspace/data # gameram-dwh
codex
```

## login

логин через чат, как в версии1
```sh
codex login

# Open the printed sign-in link in your host browser. If the redirect to
# http://127.0.0.1:1455/auth/callback?code=ac_...Xq0
# fails, copy the COMPLETE callback URL from the browser's address bar.
# Open a second host terminal in the Compose directory

docker compose exec codex bash
read -r -s -p 'Paste full callback URL: ' callback_url
printf '\n'
curl --noproxy '*' --silent --show-error "$callback_url"
codex login status

```

## first session
```sh
docker compose exec codex bash
pushd /workspace/gameram-dwh
codex
```

## results

Great, just as I want it.

Есть rw доступ к файлам проектов: маппинг UID, GID работает.
Может использовать 'clickhouse-exp' хост для доступа к КХ бд: docker сеть работает.

Проблема: запуск докер-контейнеров не работает, интеграционные тесты с testcontainers не запускаются.

Copy from codex window problem: use shift to bypass app hooks
> Shift + mouse drag, then Ctrl+Shift+C, uses your host terminal’s selection and clipboard

`/raw on`
> This enables raw scrollback mode, which the official OpenAI documentation describes as making terminal selection and copying easier.

# 2026-10-12 cleanup

Remove unused docker images

current image: `codex-dev:ubuntu24-v2`
```sh
docker ps -a | grep codex
# 28be4693c741   codex-sandbox                                "bash"                   5 days ago     Exited (0) 4 days ago                  codex-sandbox-session1
docker rm 28be4693c741

docker image ls | grep codex
codex-dev:ubuntu24-v2                                                                            d5060b257577       1.27GB          333MB   U
codex-sandbox-debug:latest                                                                       6ebd87418b3a        2.3GB          635MB
codex-sandbox-session1-261007v1:latest                                                           796d9c9ae09f       4.24GB         1.19GB
codex-sandbox:latest                                                                             064944147a44       1.34GB          349MB

docker image ls --format '{{.Repository}}:{{.Tag}}' | \
  grep '^codex-sandbox' | \
  xargs -r echo docker image rm

```

# 2026-10-30 codex update

codex при запуске стал показывать уведомление о доступном апдейте.

Апдейт можно сделать деструктивно, уничтожив данные в контейнере (которые не в монтированных волюмах):
```sh
docker compose build --pull --no-cache codex
docker compose up -d --no-deps codex

# --no-cache forces Docker to rerun the installer instead of reusing the layer containing 0.162.1.
# --pull refreshes the Ubuntu base image too.
# up recreates the container using the rebuilt image, preserving mounted volumes

# verify
docker compose exec codex codex --version
docker compose exec codex codex login status
```

Но можно сделать временный (пока живет контейнер) апдейт.
TLDR; сразу дам валидное итоговое решение:
```sh
docker compose exec --user root codex bash -o pipefail -c '
  curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
  && TAR_OPTIONS=--no-same-owner \
     CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
     CODEX_NON_INTERACTIVE=true sh /tmp/install-codex.sh \
  && chmod -R a+rX /opt/codex \
  && rm /tmp/install-codex.sh
'

docker compose exec --user root codex bash -c '
  rm -rfv /opt/codex/packages/standalone/releases/0.162.1-x86_64-unknown-linux-musl \
  && rm -f /tmp/install-codex.sh
'

docker compose exec codex codex --version # codex-cli 0.166.0
docker compose exec codex codex login status # Logged in using ChatGPT
```

Далее посмотрим на инвалидные:
```sh
# bad, не может поставить новый
docker compose exec --user root codex bash -o pipefail -c '
  curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
  && CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
    CODEX_NON_INTERACTIVE=true sh /tmp/install-codex.sh \
  && chmod -R a+rX /opt/codex \
  && rm /tmp/install-codex.sh
'
```
Это инвалидное решение:
```log
setup-v2$  docker compose exec --user root codex bash -o pipefail -c '
  curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
  && CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
    CODEX_NON_INTERACTIVE=true sh /tmp/install-codex.sh \
  && chmod -R a+rX /opt/codex \
  && rm /tmp/install-codex.sh
'
==> Updating Codex CLI from 0.162.1 to 0.166.0
==> Detected platform: Linux (x64)
==> Resolved version: 0.166.0
==> Downloading Codex CLI
==> Installing standalone package to /opt/codex/packages/standalone/releases/0.166.0-x86_64-unknown-linux-musl
tar: bin/codex: Cannot change ownership to uid 1001, gid 1001: Operation not permitted
...
tar: codex-resources: Cannot change ownership to uid 1001, gid 1001: Operation not permitted
tar: Exiting with failure status due to previous errors
```

> This comes from cap_drop: ALL in your Compose file. Root inside the container lacks CAP_CHOWN, but tar tries to restore the archive’s UID/GID (1001:1001).

Валидное решение:
```sh
docker compose exec --user root codex bash -o pipefail -c '
  curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
  && TAR_OPTIONS=--no-same-owner \
     CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
     CODEX_NON_INTERACTIVE=true sh /tmp/install-codex.sh \
  && chmod -R a+rX /opt/codex \
  && rm /tmp/install-codex.sh
'
```
Но не без проблем с зачисткой,
TLDR; проблема в миксе владельцев: что-то под рутом, что-то под девом. it's a mess:
```log
setup-v2$  docker compose exec --user root codex bash -o pipefail -c '
  curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
  && TAR_OPTIONS=--no-same-owner \
     CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin \
     CODEX_NON_INTERACTIVE=true sh /tmp/install-codex.sh \
  && chmod -R a+rX /opt/codex \
  && rm /tmp/install-codex.sh
'

==> Updating Codex CLI from 0.162.1 to 0.166.0
==> Detected platform: Linux (x64)
==> Resolved version: 0.166.0
==> Downloading Codex CLI
==> Installing standalone package to /opt/codex/packages/standalone/releases/0.166.0-x86_64-unknown-linux-musl
WARNING: Could not safely inspect old Codex releases; skipped remaining cleanup.
==> /usr/local/bin is already on PATH
==> Current terminal: codex
==> Future terminals: open a new terminal and run: codex
Codex CLI 0.166.0 installed successfully.
chmod: changing permissions of '/opt/codex/packages/standalone/releases/0.162.1-x86_64-unknown-linux-musl/codex-path': Operation not permitted
...
chmod: changing permissions of '/opt/codex/packages/standalone/releases/0.162.1-x86_64-unknown-linux-musl/codex-package.json': Operation not permitted
```

> The update succeeded. This line confirms it: 'Codex CLI 0.166.0 installed successfully.'
The subsequent `chmod -R` failed on files belonging to the old 0.162.1 release. Container root lacks CAP_FOWNER, which allows changing permissions on files owned by another user.

Ручная зачистка:
```sh
docker compose exec --user root codex bash -c '
  rm -rfv /opt/codex/packages/standalone/releases/0.162.1-x86_64-unknown-linux-musl \
  && rm -f /tmp/install-codex.sh
'
```

Проверка:
```sh
setup-v2$  docker compose exec codex codex --version
codex-cli 0.166.0

setup-v2$  docker compose exec codex codex login status
Logged in using ChatGPT
```
