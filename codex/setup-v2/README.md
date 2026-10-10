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

bootstrap: generate '.env', build and start 'codex' conainer in detached mode
```sh
pushd ${HOME:?unknown}/data/github/ai-sandbox/codex/setup-v2
export PROJECT_ROOT=${HOME:?unknown}/data/gitlab/gameram # && pushd ${PROJECT_ROOT:?unknown} # workdir useful

bash -x ./bootstrap.sh ${PROJECT_ROOT:?unknown}

# manage container
docker compose ps
docker compose stop
docker compose start
# docker compose down # destroy container
# down preserves the Codex state volume; down -v deletes it. Exiting an interactive shell leaves the container running.

# run session
docker compose exec codex bash
pushd /workspace/gameram-dwh
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
Может использовать 'clickhouse-exp' хост для доступа к КХ бд: сеть работает.

Copy from codex window problem:
> Shift + mouse drag, then Ctrl+Shift+C, uses your host terminal’s selection and clipboard

use shift to bypass app hooks

`/raw on`
> This enables raw scrollback mode, which the official OpenAI documentation describes as making terminal selection and copying easier.
