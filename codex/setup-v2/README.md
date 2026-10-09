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
- danger-full-access with on-request approvals, retaining Docker’s default security policies.

bootstrap: generate '.env', build and start 'codex' conainer in detached mode
```sh
pushd ${HOME:?unknown}/data/github/ai-sandbox/codex/setup-v2
export PROJECT_ROOT=${HOME:?unknown}/data/gitlab/gameram # && pushd ${PROJECT_ROOT:?unknown} # workdir useful

bash -x ./bootstrap.sh ${PROJECT_ROOT:?unknown}

# manage container
docker compose ps
docker compose stop
docker compose start
docker compose down
# down preserves the Codex state volume; down -v deletes it. Exiting an interactive shell leaves the container running.

# run session
docker compose exec codex bash

```
