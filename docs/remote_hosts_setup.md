# Remote hosts: setup guide

ProcessLama can show the processes of other machines in their own tabs. It
connects with your OpenSSH client, copies a small helper program to the
host, and streams the process tree back. The helper runs as your SSH user
and never uses `sudo`.

This guide is published as `https://devmil.de/processlama/remote-hosts.html`;
the app's **Setup guide** buttons open that page.

## Requirements

**On this computer**

- OpenSSH 8.9 or newer (`ssh -V`). On Windows, the OpenSSH client feature.
- A key-based login that works without a prompt: a key without passphrase,
  or a key loaded into your agent. ProcessLama runs ssh with
  `BatchMode=yes`, so it never asks for passwords.
- The host key is already trusted: connect once with `ssh <alias>` in a
  terminal and accept it. ProcessLama runs ssh with
  `StrictHostKeyChecking=yes`.

**On the host**

| System | Architectures | Minimum |
| --- | --- | --- |
| Linux | x86_64, arm64 (aarch64) | glibc 2.34 (for example Ubuntu 22.04, Debian 12, Fedora 35, RHEL 9) |
| macOS | Apple silicon, Intel | macOS 13 |

Windows hosts are not supported yet.

## Your `~/.ssh/config`

ProcessLama stores only a host **alias**. User names, ports, keys and jump
hosts belong in `~/.ssh/config`, where ssh and your other tools use them too.

A plain host:

```sshconfig
Host build-box
    HostName build-box.example.net
    User deploy
    IdentityFile ~/.ssh/id_ed25519
```

A host on another port, with a key in the agent:

```sshconfig
Host nas
    HostName 192.0.2.10
    Port 2222
    User admin
```

A host behind a jump host (`ProxyJump`):

```sshconfig
Host bastion
    HostName bastion.example.net
    User jump

Host db-internal
    HostName 10.0.4.12
    User ops
    ProxyJump bastion
```

Check that `ssh <alias> true` returns without asking anything. Then use
the alias in ProcessLama.

## Adding a host

1. Click **+** at the end of the tab strip (or press Ctrl+T, ⌘T on macOS)
   and choose **Add remote host…**.
2. Enter the SSH host alias. The display name defaults to the alias.
3. Click **Test connection**. It reports one of:
   - *SSH unreachable*: ssh could not connect; run `ssh <alias>` in a
     terminal to see why.
   - *Helper missing* or *Helper outdated*: fine; the helper is installed
     when you open the tab.
   - *Unsupported platform*: the host is not one of the systems above.
   - *Ready*: the host's system and helper version.
4. Save. The host opens in a new tab.

Options per host:

- **Install helper automatically**: off by default. When off, ProcessLama
  shows the install dialog with the path, version, size and checksum
  first. Changing the alias turns it off again.
- **Reconnect automatically**: on by default. After a dropped connection
  ProcessLama retries after 2, 5, 15 and 30 seconds and then every minute,
  for up to 10 minutes.
- **Open on startup**: as at quit, always or never.
- **Background refresh**: how often a tab you are not looking at updates:
  slow (5 s, the default), live, or paused.

Tabs: Ctrl+1…9 (⌘1…9) select a tab, Ctrl+Shift+[ and ] cycle through them.
Drag a tab to reorder it; middle-click or its close button closes it.

## What is installed where

The helper goes to
`~/.local/lib/processlama/remote/<build>/processlama-remote-helper` on the
host, its icon cache to `~/.cache/processlama/remote-helper/`. Builds older
than 30 days are removed after a successful install of a newer build.

ProcessLama installs and starts the helper with fixed scripts and argument
arrays; it never interpolates host input into a shell command. The scripts
run under `/bin/sh` whatever your login shell is (bash, zsh, fish).

## Common problems

**The home directory does not allow running programs.** If `$HOME` is
mounted `noexec`, the install fails with *The home directory on this host
does not allow running programs (noexec)*. Ask the administrator to allow
executables in your home directory; ProcessLama does not install anywhere
else.

**Login scripts that print or read input.** Your shell's startup files run
before the helper starts. If `~/.bashrc` (or `~/.zshrc`) prints text,
ProcessLama skips it. If it **reads from standard input** (for example a
`read` prompt), the helper never starts and the tab reports *The helper did
not start*. Guard interactive parts with a check for an interactive shell:

```sh
case $- in
  *i*) ;;           # interactive: prompts are fine here
  *) return ;;
esac
```

**Only your own processes are visible.** Linux hosts mounted with
`hidepid=2` hide other users' processes. The tab then says *Showing only
your processes*. Processes of other users also show restricted files,
environment and I/O, as they do locally.

**The host key is not trusted yet.** Connect once with `ssh <alias>` and
accept the key.

## Network rates on Linux hosts

Per-process network rates on Linux need the ProcessLama network service, a
narrowly scoped eBPF sampler that runs as a systemd service. Machines that
have the ProcessLama RPM or DEB installed already have it.

For other Linux hosts, the downloads page lists the service under
**Network service for remote Linux hosts** as RPM, DEB and tar for x86_64
and arm64. In a remote tab without the service, the inspector's network
banner offers **Copy install command**, which copies a command that
downloads the tar of your ProcessLama version and runs its installer with
`sudo` on the host. Run it in an SSH session on the host; ProcessLama never
runs `sudo` itself.

## macOS hosts

An SSH session on macOS has no privacy permissions. The inspector shows
these sections as **Restricted** for processes of other users, including
root:

| Section | Your processes | Other users' and root's processes |
| --- | --- | --- |
| Files | available | restricted |
| Sockets | available | restricted |
| Threads | available | restricted |
| Security | available | available |

Network rates come from `nettop`, as on the Mac itself.

## When the connection drops

The tab keeps the last sample and marks it stale: a banner names the reason
and the time of the last sample and offers **Reconnect**, the status bar
shows *last updated*, and the history charts leave a gap. Processes are
never shown as ended only because the connection dropped; after the
reconnect the tab compares the new tree and keeps the selection and the
expanded rows.

## Removing the helper

In **Preferences → Remote hosts**, open the host's menu (**…**) and choose
**Remove helper from host…**. ProcessLama disconnects and deletes
`~/.local/lib/processlama` and `~/.cache/processlama` on the host. Removing
the profile alone leaves the helper on the host.

To remove it by hand:

```sh
ssh <alias> 'rm -rf ~/.local/lib/processlama ~/.cache/processlama'
```

## Privacy

ProcessLama stores only the alias and what the helper last reported
(system, architecture, helper version) for display. It stores no user
names, ports, keys or passwords, and its logs contain no host names,
aliases or command lines.
