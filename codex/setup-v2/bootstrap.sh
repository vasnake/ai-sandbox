#!/usr/bin/env bash
set -euo pipefail

# path to the host workspace directory containing repositories to be mounted into the container
if [[ $# -ne 1 ]]; then
  printf 'Usage: bash bootstrap.sh /absolute/path/to/host/repositories\n' >&2
  exit 2
fi

workspace_dir="$(realpath -e -- "$1")"

# this script directory is the root of the codex container setup
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# beware: 'vlk' is working only for me
host_uid="$(id -u vlk)"
host_gid="$(id -g vlk)"

printf "DEV_UID=%s\nDEV_GID=%s\nWORKSPACE_DIR='%s'\n" \
  "$host_uid" "$host_gid" "$workspace_dir"

# checks

[[ "$host_uid" -gt 0 && "$host_gid" -gt 0 ]] || { echo 'Expected a non-root vlk account.' >&2; exit 1; }

[[ -d "$workspace_dir" ]] || { echo 'Workspace must be an existing directory.' >&2; exit 1; }

# Single-quoted .env values preserve spaces, # and $ literally.
if [[ "$workspace_dir" == *"'"* || "$workspace_dir" == *$'\n'* || "$workspace_dir" == *$'\r'* ]]; then
  echo 'Workspace paths containing quotes or line breaks are not supported by this script.' >&2
  exit 1
fi

docker compose version >/dev/null
docker network inspect airflow-network >/dev/null

# These are generated Compose inputs, not host system environment variables.
printf "DEV_UID=%s\nDEV_GID=%s\nWORKSPACE_DIR='%s'\n" \
  "$host_uid" "$host_gid" "$workspace_dir" > "$script_dir/.env"

# build the container

cd -- "$script_dir" # -- prevents the path from being interpreted as an option

unset DEV_UID DEV_GID WORKSPACE_DIR # Avoid inherited shell values overriding the generated .env file.
docker compose config # --quiet # validate the Compose file and print the effective configuration

docker compose build --pull # build the container, pulling the latest base image

# start the container in detached mode, so that it can be used for subsequent commands
docker compose up -d

# check that the container is running and has the expected user and permissions
docker compose exec -T codex id # vlk UID:GID should match the host user
# check that the workspace and codex config directories are writable and that codex is installed
docker compose exec -T codex bash -c 'test -w /workspace && test -w /home/dev/.codex && codex --version'
printf '\nReady. Enter with: docker compose exec codex bash\n'
