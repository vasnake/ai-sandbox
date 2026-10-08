#!/bin/bash
# not a script per se, but a set of commands to run in a shell to build and run the codex-sandbox docker image

pushd  ${HOME:?unknows}/ai_sandbox/codex/; exit 0

# docker build --pull -t codex-sandbox . # pull the latest base image, ignore cached
docker build -t codex-sandbox .

docker run -it --rm codex-sandbox bash # check, exit and remove

# remove any existing containers based on the codex-sandbox image
docker ps -aq --filter ancestor=codex-sandbox | xargs -r docker rm -f

# end of simple checks

# run w/o workspace mounted from host
docker run -it --name codex-sandbox-session1 codex-sandbox bash # start a new session
docker start -ai codex-sandbox-session1 # continue the session

# run with workspace mounted from host

# start a new session, with workspace mounted from host
docker run -it --name codex-sandbox-session1 \
 --mount type=bind,src=${HOME:?unknown}/data/gitlab/gameram,dst=/workspace \
 codex-sandbox bash

docker start -ai codex-sandbox-session1 # continue the session

# the container and its files survive a host reboot.
# Files persist; running processes and the active Codex session are interrupted.
# After restarting the container, use codex resume to continue a saved conversation

# example given me by chatgpt to run a container in detached mode, with volumes for home and workspace

# docker run -d \
#   --name codex-dev \
#   --init \
#   --restart unless-stopped \
#   --cap-drop ALL \
#   --security-opt no-new-privileges=true \
#   --mount type=volume,source=codex-dev-home,target=/home/dev \
#   --mount type=volume,source=codex-dev-workspace,target=/workspace \
#   codex-dev

git config --global user.email "codex@localhost"
git config --global user.name "codex"

# inside the container
codex login
codex login status

# sudo not working, very secure :)
sudo apt install bubblewrap # problems due to 'sandbox' inside container

# on the host, do backup like so
mkdir -p ~/codex-session1-backup
chmod 700 ~/codex-session1-backup
docker cp codex-sandbox-session1:/home/dev/.codex/auth.json ~/codex-session1-backup/auth.json
chmod 600 ~/codex-session1-backup/auth.json

# root access (sudo), like so (run on host)
docker exec -u root codex-sandbox-session1 bash -c \
 'apt-get update && apt-get install -y --no-install-recommends bubblewrap'


# container
pushd /workspace/gameram-dwh/gameram_dbt
codex --sandbox danger-full-access --ask-for-approval on-request
# works, but with GUID/UID mismatch, so the container cannot write to the mounted workspace

# save the works
docker exec -u root codex-sandbox-session1 bash -c \
 'cp /tmp/codex_session1.tar.gz /workspace/'

# docker stop codex-sandbox-session1
docker commit codex-sandbox-session1 codex-sandbox-session1-261007v1



# left for later

# bubblewrap sandbox restrictions: not working under two layers

# not working
docker exec -u root codex-sandbox-session1 bash -c \
 'sysctl -w kernel.apparmor_restrict_unprivileged_userns=0'

# diagnostics

docker exec -u dev codex-sandbox-session1 \
  bwrap --ro-bind / / --unshare-user -- /bin/true
# bwrap: No permissions to create new namespace, likely because the kernel does not allow non-privileged user namespaces

# Container security settings
docker inspect codex-sandbox-session1 --format \
  'AppArmor={{.AppArmorProfile}} SecurityOpt={{json .HostConfig.SecurityOpt}}'
# AppArmor=docker-default SecurityOpt=null

# Host namespace settings
sysctl kernel.apparmor_restrict_unprivileged_userns \
       user.max_user_namespaces
# kernel.apparmor_restrict_unprivileged_userns = 1
# user.max_user_namespaces = 239192

# AppArmor denials from the recent test
sudo journalctl -k --since "10 minutes ago" --no-pager \
  | grep -Ei 'apparmor|userns|denied'
# empty

# make a snapshot of the container for debugging
docker commit codex-sandbox-session1 codex-sandbox-debug
# run test
docker run --rm \
  --user dev \
  --network none \
  --security-opt seccomp=unconfined \
  codex-sandbox-debug \
  bwrap --ro-bind / / --unshare-user -- /bin/true
# No output and exit code 0: seccomp was blocking this test.
# Same error: AppArmor or another namespace restriction remains involved.

# output:
vlk@vlk-SER:~/ai_sandbox/codex$  docker run --rm \
  --user dev \
  --network none \
  --security-opt seccomp=unconfined \
  codex-sandbox-debug \
  bwrap --ro-bind / / --unshare-user -- /bin/true
bwrap: Failed to make / slave: Permission denied
vlk@vlk-SER:~/ai_sandbox/codex$ echo $?
1

# disable second option
docker run --rm \
  --user dev \
  --network none \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  codex-sandbox-debug \
  bwrap --ro-bind / / --unshare-user -- /bin/true

echo $?
