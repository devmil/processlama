#!/bin/sh
# Prepares one variant of the test host, then runs sshd in the foreground.
#   VARIANT=base | login-noise | login-stdin | noexec | hidepid | ebpf | zsh
set -eu
variant="${VARIANT:-base}"
home=/home/tester
case "$variant" in
  login-noise)
    # Before Ubuntu's early return for non-interactive shells, so ssh commands see it.
    sed -i '1i echo "Welcome to the remote hosts test host"; echo "Last login: never"' "$home/.bashrc"
    ;;
  login-stdin)
    # A login script that consumes standard input before the command runs.
    sed -i '1i read -r _ignored || true' "$home/.bashrc"
    ;;
  noexec)
    mount -t tmpfs -o noexec,nosuid,mode=0755,uid=1000,gid=1000 tmpfs "$home"
    ;;
  hidepid)
    mount -o remount,hidepid=2 /proc
    ;;
  zsh)
    # zsh as the login shell (the macOS default), and a stale helper build the
    # first connection must prune.
    usermod -s /usr/bin/zsh tester
    touch "$home/.zshrc"
    stale="$home/.local/lib/processlama/remote/0000000000000000000000000000000000000000"
    mkdir -p "$stale"
    touch -t 202001010000 "$stale"
    ;;
  ebpf)
    mkdir -p /run/processlama
    (while true; do
       printf '{"schema":1,"captured_at_unix_ms":%s000,"processes":[]}\n' "$(date +%s)" \
         > /run/processlama/network.json.tmp
       mv /run/processlama/network.json.tmp /run/processlama/network.json
       sleep 1
     done) &
    ;;
esac
chown -R tester:tester "$home" 2>/dev/null || true
exec /usr/sbin/sshd -D -e
