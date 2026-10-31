#!/usr/bin/env bash
# Sets up a fresh Kubuntu LTS install as an always-on box for coding agents.
#
# Run once as root:  sudo bash setup.sh
# Safe to run again; each step checks what is already done.
#
# What it does:
#   1. Updates the system and installs base tools.
#   2. Sets up Timeshift snapshots (daily + weekly, and one now).
#   3. Turns on automatic security updates, but never for NVIDIA or kernels
#      once an NVIDIA driver is installed.
#   4. Turns off sleep and enables SSH.
#   5. Installs Tailscale, the GitHub CLI, and Go.
#   6. Creates the "agents" user with a memory and CPU cap, and installs
#      Bun, Claude Code, and opencode for it.
#
# It does NOT install an NVIDIA driver. See README.md before you do.

set -euo pipefail

AGENT_USER="${AGENT_USER:-agents}"
AGENT_MEMORY_MAX="${AGENT_MEMORY_MAX:-24G}"   # hard cap for everything the agents run
AGENT_MEMORY_HIGH="${AGENT_MEMORY_HIGH:-22G}" # the kernel starts reclaiming here

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning: %s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 1
fi
# shellcheck source=/dev/null
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script is for Kubuntu/Ubuntu. Found: ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive

# --- 1. Base system ----------------------------------------------------------
log "Updating the system"
apt-get update
apt-get full-upgrade -y
apt-get install -y \
  openssh-server git curl ca-certificates gnupg build-essential \
  jq tmux htop unzip timeshift unattended-upgrades

# --- 2. Snapshots ------------------------------------------------------------
log "Setting up Timeshift snapshots"
root_source="$(findmnt -no SOURCE /)"
root_device="${root_source%%\[*}"
if [[ "$(findmnt -no FSTYPE /)" == "btrfs" && "$root_source" == *"[/@]" ]]; then
  mode="--btrfs"
  echo "Root is btrfs with an @ subvolume: snapshots are instant."
else
  mode="--rsync"
  echo "Root is not btrfs with an @ subvolume: using rsync snapshots."
fi

if [[ ! -f /etc/timeshift/timeshift.json ]]; then
  timeshift --create --scripted $mode --snapshot-device "$root_device" \
    --comments "clean install" --tags O
fi

# Save the snapshot device and mode. "timeshift --create" does not write
# them, and without them Timeshift stays in first-run mode.
# Keep 5 daily and 3 weekly snapshots. /home is not included, so snapshots
# hold the system only, not the agents' worktrees.
config=/etc/timeshift/timeshift.json
root_uuid="$(blkid -s UUID -o value "$root_device")"
if [[ "$mode" == "--btrfs" ]]; then btrfs_mode=true; else btrfs_mode=false; fi
tmp="$(mktemp)"
jq --arg uuid "$root_uuid" --arg btrfs "$btrfs_mode" \
  '.backup_device_uuid = $uuid | .btrfs_mode = $btrfs | .include_btrfs_home = "false"
  | .do_first_run = "false"
  | .schedule_daily = "true" | .count_daily = "5"
  | .schedule_weekly = "true" | .count_weekly = "3"
  | .schedule_monthly = "false" | .schedule_hourly = "false" | .schedule_boot = "false"' \
  "$config" >"$tmp"
install -m 644 "$tmp" "$config"
rm -f "$tmp"
# Timeshift checks its schedule from cron.
echo '0 * * * * root timeshift --check --scripted >/dev/null 2>&1' >/etc/cron.d/timeshift-hourly
chmod 644 /etc/cron.d/timeshift-hourly

# Use this instead of "apt full-upgrade" for anything risky (drivers, kernels).
cat >/usr/local/sbin/upgrade-safely <<'EOF'
#!/bin/sh
# Takes a snapshot, then upgrades. If the upgrade breaks something,
# restore with: sudo timeshift --restore
set -e
timeshift --create --scripted --comments "before upgrade $(date +%F)" --tags O
apt-get update
apt-get full-upgrade "$@"
echo "Done. To undo: sudo timeshift --restore (pick the 'before upgrade' snapshot)."
EOF
chmod 755 /usr/local/sbin/upgrade-safely

# --- 3. Automatic security updates -------------------------------------------
log "Turning on automatic security updates"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
# NVIDIA drivers and the kernel must update together, by hand, after a
# snapshot. This only matters once a proprietary NVIDIA driver is installed;
# until then the kernel keeps updating automatically.
if dpkg -l 'nvidia-driver-*' 2>/dev/null | grep -q '^ii'; then
  cat >/etc/apt/apt.conf.d/51-agent-box-blacklist <<'EOF'
Unattended-Upgrade::Package-Blacklist {
    "nvidia-";
    "libnvidia-";
    "linux-";
};
EOF
  echo "NVIDIA driver found: NVIDIA and kernel updates are now manual (use upgrade-safely)."
else
  rm -f /etc/apt/apt.conf.d/51-agent-box-blacklist
fi

# --- 4. Always on, reachable -------------------------------------------------
log "Turning off sleep and enabling SSH"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
systemctl enable --now ssh

# --- 5. Tools ----------------------------------------------------------------
log "Installing Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled

log "Installing the GitHub CLI"
if ! command -v gh >/dev/null; then
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    >/etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y gh
fi

log "Installing Go"
go_version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n 1)"
if [[ "$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}')" != "$go_version" ]]; then
  tmp="$(mktemp -d)"
  curl -fsSL "https://go.dev/dl/${go_version}.linux-$(dpkg --print-architecture).tar.gz" -o "$tmp/go.tgz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp/go.tgz"
  rm -rf "$tmp"
fi
# shellcheck disable=SC2016 # expands at login, not now
echo 'export PATH="$PATH:/usr/local/go/bin"' >/etc/profile.d/go.sh
/usr/local/go/bin/go version

# --- 6. The agents user ------------------------------------------------------
log "Creating the $AGENT_USER user"
if ! id "$AGENT_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$AGENT_USER"
fi
agent_uid="$(id -u "$AGENT_USER")"
agent_home="$(getent passwd "$AGENT_USER" | cut -d: -f6)"

# The agent runner runs as systemd user units; without lingering they stop at logout.
loginctl enable-linger "$AGENT_USER"

# One cap for everything the agents run, so the desktop stays usable.
install -d "/etc/systemd/system/user-${agent_uid}.slice.d"
cat >"/etc/systemd/system/user-${agent_uid}.slice.d/50-agent-limits.conf" <<EOF
[Slice]
MemoryHigh=${AGENT_MEMORY_HIGH}
MemoryMax=${AGENT_MEMORY_MAX}
CPUWeight=50
EOF
systemctl daemon-reload

log "Installing Bun, Claude Code, and opencode for $AGENT_USER"
as_agent() { sudo -u "$AGENT_USER" -H bash -lc "$1"; }
as_agent 'command -v bun >/dev/null || [ -x ~/.bun/bin/bun ] || curl -fsSL https://bun.sh/install | bash'
as_agent '[ -x ~/.local/bin/claude ] || curl -fsSL https://claude.ai/install.sh | bash'
as_agent '[ -x ~/.opencode/bin/opencode ] || curl -fsSL https://opencode.ai/install | bash'

# systemd user units do not read .bashrc, so give them the same PATH.
install -d -o "$AGENT_USER" -g "$AGENT_USER" "$agent_home/.config/environment.d"
cat >"$agent_home/.config/environment.d/10-path.conf" <<EOF
PATH=$agent_home/.local/bin:$agent_home/.bun/bin:$agent_home/.opencode/bin:$agent_home/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
chown "$AGENT_USER:$AGENT_USER" "$agent_home/.config/environment.d/10-path.conf"
if ! grep -q '# agent-box' "$agent_home/.bashrc"; then
  cat >>"$agent_home/.bashrc" <<'EOF'
# agent-box
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.opencode/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
EOF
fi

# --- Done --------------------------------------------------------------------
log "Taking a snapshot of the finished setup"
timeshift --create --scripted --comments "agent box set up" --tags O

log "Done"
cat <<EOF
Next steps (README.md has the details):
  1. sudo tailscale up --ssh          # sign in as the same user as your Mac
  2. sudo -iu $AGENT_USER             # then: gh auth login, claude, git config
  3. Clone and start your agent runner as $AGENT_USER (README section 6)
Snapshots: sudo timeshift --list
Risky upgrades: sudo upgrade-safely
EOF
