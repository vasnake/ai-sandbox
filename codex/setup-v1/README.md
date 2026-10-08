# 2026-10-07 setup-v1

[dockerfile](./Dockerfile) для создания образа, в котором есть кодекс и пользователь 'dev';
воркспейс располагается в `/workspace` контейнера.

[shell commands](./codex-sandbox.sh) создание образа, запуск контейнера с возможностью выйти из него и войти обратно -- вернуться к состоянию на момент выхода.

### login

device-code не работает (не включено) а через чат не логинится, ибо урл ведет на 127.0.0.1
поэтому через два терминала с доступом к одному контейнеру

```sh
# first terminal window
docker start -ai codex-sandbox-session1 # continue the session
# in that first window:
codex login

# do login in host browser, get url back, save it
http://127.0.0.1:1455/auth/callback?code...9p4Ic

# in another window, run this
docker exec -it codex-sandbox-session1 bash
# and send the callback URL to the container, so that it can complete the login process
read -r -s -p 'Paste full callback URL: ' callback_url
printf '\n'
curl --noproxy '*' --silent --show-error "$callback_url" # >/dev/null
unset callback_url

# check
codex login status

# where is it? see auth.json
ll $HOME/.codex/
total 2888
drwxr-xr-x 1 dev dev    4096 Oct  7 14:09 ./
drwxr-x--- 1 dev dev    4096 Oct  7 13:37 ../
-rw-r--r-- 1 dev dev       0 Oct  7 13:39 .sqlite-maintenance.lock
drwxr-xr-x 3 dev dev    4096 Oct  7 13:38 .tmp/
drwx------ 2 dev dev    4096 Oct  7 13:38 app-server-control/
drwx------ 2 dev dev    4096 Oct  7 13:38 app-server-daemon/
-rw------- 1 dev dev    3945 Oct  7 14:09 auth.json
-rw------- 1 dev dev      42 Oct  7 13:38 config.toml
-rw-r--r-- 1 dev dev    4096 Oct  7 13:38 goals_1.sqlite
-rw-r--r-- 1 dev dev   32768 Oct  7 14:05 goals_1.sqlite-shm
-rw-r--r-- 1 dev dev   74192 Oct  7 13:38 goals_1.sqlite-wal
-rw-r--r-- 1 dev dev      36 Oct  7 13:38 installation_id
drwxr-xr-x 2 dev dev    4096 Oct  7 14:06 log/
-rw-r--r-- 1 dev dev   61440 Oct  7 13:48 logs_2.sqlite
-rw-r--r-- 1 dev dev   32768 Oct  7 14:05 logs_2.sqlite-shm
-rw-r--r-- 1 dev dev  486192 Oct  7 14:05 logs_2.sqlite-wal
-rw-r--r-- 1 dev dev   45056 Oct  7 13:58 memories_1.sqlite
drwxr-xr-x 3 dev dev    4096 Oct  7 13:38 packages/
-rw-r--r-- 1 dev dev    4096 Oct  7 13:38 queue_1.sqlite
-rw-r--r-- 1 dev dev   32768 Oct  7 13:38 queue_1.sqlite-shm
-rw-r--r-- 1 dev dev   82432 Oct  7 13:38 queue_1.sqlite-wal
drwxr-xr-x 3 dev dev    4096 Oct  7 13:38 skills/
-rw-r--r-- 1 dev dev    4096 Oct  7 13:38 state_5.sqlite
-rw-r--r-- 1 dev dev   32768 Oct  7 14:05 state_5.sqlite-shm
-rw-r--r-- 1 dev dev 1989992 Oct  7 13:38 state_5.sqlite-wal
drwxr-xr-x 1 dev dev    4096 Oct  6 16:37 tmp/
-rw-r--r-- 1 dev dev     105 Oct  7 13:38 version.json

```

### starting work on a project

> Put an AGENTS.md in each repository with its build/test commands, required Python or Java versions, and coding conventions. Codex loads repository instructions when starting within that project
- Work on one project: start in that repository’s root.
- Switch projects: exit and start another session in the other repository.
- Coordinate changes across repositories: start in /workspace and explicitly name the repositories involved.

проблема с bubblewrap (собственная песочница), у меня песочница в песочнице,
надо лечить через женитьбу профилей апп-армор и защиты докера,
но пока просто отключил внутреннюю песочницу через `codex --sandbox danger-full-access --ask-for-approval on-request`
https://learn.chatgpt.com/docs/sandboxing?surface=app#app-prerequisites

другая проблема: GID:UID пользователя не матчится с овнером файлов в воркспейсе, который mount с хоста.
в итоге агент может только читать файлы проекта.
это надо чинить, срочно.
