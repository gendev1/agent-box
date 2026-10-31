#!/usr/bin/env bash
# shellcheck disable=SC2015 # "a && echo || warn": echo cannot fail
# Installs your desktop tools and links the dotfiles into your home folder.
#
# Run as YOUR user, not root (it asks for sudo when it needs it):
#   bash ~/agent-box/dotfiles/install.sh
# Safe to run again. To add a tool, add it to a list below.
#
# The configs are linked with GNU Stow: each folder here (zsh, kitty, ...)
# mirrors your home folder, so editing ~/.zshrc edits the file in this repo.
# Files that already exist are moved to ~/.dotfiles-backup first.
#
# It never touches the agents user or the NVIDIA driver.

set -euo pipefail

# Stow packages: the folders in this directory to link into $HOME.
PACKAGES=(zsh starship kitty git tmux kde)

# Tools from the Ubuntu archive. A missing package is skipped.
APT_PACKAGES=(
  stow
  zsh zsh-autosuggestions zsh-syntax-highlighting
  kitty starship
  eza bat fd-find ripgrep fzf zoxide
  btop fastfetch lazygit tealdeer git-delta
  neovim wl-clipboard
  flatpak plasma-discover-backend-flatpak
  fonts-noto-color-emoji fonts-inter papirus-icon-theme
)

# Desktop apps from Flathub.
FLATPAKS=(
  com.spotify.Client
  md.obsidian.Obsidian
)

NERD_FONT="JetBrainsMono"

# Wallpapers from Omarchy's tokyo-night theme. The first one is applied; the
# rest show up in KDE's wallpaper picker.
WALLPAPER_URL="https://raw.githubusercontent.com/omacom/omarchy/quattro/themes/tokyo-night/backgrounds"
WALLPAPERS=(1-winding-road.webp 0-liftoff.webp 2-quattro.webp 3-swirl-buck.webp
  4-sunset-lake.webp 5-omakub.webp 6-oma-cityscape.jpg 7-oma.webp)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mskipped: %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ $EUID -eq 0 ]]; then
  echo "Run as your own user, not root: bash $0" >&2
  exit 1
fi

# --- Tools -------------------------------------------------------------------
log "Installing tools"
sudo apt-get update
for pkg in "${APT_PACKAGES[@]}"; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null && echo "  $pkg" || warn "$pkg failed to install"
  else
    warn "$pkg is not in the Ubuntu archive"
  fi
done
if ! have starship; then
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
fi

log "Installing apps from Flathub"
if have flatpak; then
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  for app in "${FLATPAKS[@]}"; do
    sudo flatpak install -y --noninteractive flathub "$app" >/dev/null && echo "  $app" || warn "$app"
  done
fi

log "Installing the Zed editor"
if ! have zed && [[ ! -x "$HOME/.local/bin/zed" ]]; then
  curl -fsSL https://zed.dev/install.sh | sh
fi

log "Installing the $NERD_FONT Nerd Font"
font_dir="$HOME/.local/share/fonts/$NERD_FONT"
if [[ ! -d "$font_dir" ]]; then
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${NERD_FONT}.tar.xz" -o "$tmp/font.tar.xz"
  mkdir -p "$font_dir"
  tar -C "$font_dir" -xf "$tmp/font.tar.xz"
  rm -rf "$tmp"
  fc-cache -f >/dev/null
fi

# --- Dotfiles ----------------------------------------------------------------
log "Linking dotfiles"
backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
for pkg in "${PACKAGES[@]}"; do
  # Move real files out of the way; files already linked here are left alone.
  while IFS= read -r -d '' file; do
    rel="${file#"$HERE/$pkg/"}"
    target="$HOME/$rel"
    # Skip anything that already resolves into this repo, even through a
    # linked parent folder, or the "backup" would move the repo's own file.
    if [[ -e "$target" && "$(realpath "$target")" != "$HERE/"* ]]; then
      mkdir -p "$backup/$(dirname "$rel")"
      mv "$target" "$backup/$rel"
      echo "  backed up ~/$rel"
    fi
  done < <(find "$HERE/$pkg" -type f -print0)
done
# --no-folding links each file, never whole folders, so apps that write new
# files into ~/.config/<app> do not write them into this repo.
stow --dir "$HERE" --target "$HOME" --no-folding --restow "${PACKAGES[@]}"
echo "  linked: ${PACKAGES[*]}"

# btop rewrites its config on exit, so it is set here instead of linked.
btop_conf="$HOME/.config/btop/btop.conf"
mkdir -p "$(dirname "$btop_conf")"
touch "$btop_conf"
for setting in 'color_theme = "tokyo-night"' 'theme_background = False' 'rounded_corners = True' 'vim_keys = True'; do
  key="${setting%% =*}"
  if grep -q "^$key = " "$btop_conf"; then
    sed -i "s|^$key = .*|$setting|" "$btop_conf"
  else
    echo "$setting" >>"$btop_conf"
  fi
done

# bat and git diffs (delta) read the Tokyo Night theme from bat's cache.
if have batcat; then
  bat_themes="$(batcat --config-dir)/themes"
  mkdir -p "$bat_themes"
  curl -fsSL "https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/sublime/tokyonight_night.tmTheme" \
    -o "$bat_themes/tokyonight_night.tmTheme" && batcat cache --build >/dev/null || warn "bat theme"
fi

if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
  sudo chsh -s "$(command -v zsh)" "$USER"
fi
have tldr && tldr --update >/dev/null 2>&1 || true

# --- KDE: Tokyo Night --------------------------------------------------------
# KDE rewrites its own config files, so they are set with kwriteconfig6
# instead of linked.
log "Configuring KDE Plasma"
if have kwriteconfig6; then
  ui_font() { echo "Inter,$1,-1,5,$2,0,0,0,0,0,0,0,0,0,0,1"; }

  # Start from Breeze Dark, then recolor it. "default" is the Breeze Plasma
  # style that follows the color scheme, so panels turn Tokyo Night too.
  have plasma-apply-lookandfeel && plasma-apply-lookandfeel -a org.kde.breezedark.desktop >/dev/null 2>&1 || true
  have plasma-apply-colorscheme && plasma-apply-colorscheme TokyoNight >/dev/null || warn "color scheme"
  have plasma-apply-desktoptheme && plasma-apply-desktoptheme default >/dev/null || warn "Plasma style"

  changeicons="$(compgen -G '/usr/lib/*/libexec/plasma-changeicons' | head -n 1 || true)"
  if [[ -n "$changeicons" ]]; then
    "$changeicons" Papirus-Dark >/dev/null 2>&1 || warn "icons"
  else
    kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Dark
  fi

  # Inter for the interface, the Nerd Font for code.
  kwriteconfig6 --file kdeglobals --group General --key font "$(ui_font 10 400)"
  kwriteconfig6 --file kdeglobals --group General --key menuFont "$(ui_font 10 400)"
  kwriteconfig6 --file kdeglobals --group General --key toolBarFont "$(ui_font 10 400)"
  kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "$(ui_font 8 400)"
  kwriteconfig6 --file kdeglobals --group WM --key activeFont "$(ui_font 10 500)"
  kwriteconfig6 --file kdeglobals --group General --key fixed "JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  # Text like a Mac: grayscale smoothing, light hinting.
  kwriteconfig6 --file kdeglobals --group General --key XftAntialias true
  kwriteconfig6 --file kdeglobals --group General --key XftSubPixel none
  kwriteconfig6 --file kdeglobals --group General --key XftHintStyle hintslight
  kwriteconfig6 --file kcmfonts --group General --key hintstyle hintslight

  wallpaper_dir="$HOME/.local/share/wallpapers/omarchy-tokyo-night"
  mkdir -p "$wallpaper_dir"
  for wp in "${WALLPAPERS[@]}"; do
    [[ -f "$wallpaper_dir/$wp" ]] || curl -fsSL "$WALLPAPER_URL/$wp" -o "$wallpaper_dir/$wp" || warn "wallpaper $wp"
  done
  have plasma-apply-wallpaperimage &&
    plasma-apply-wallpaperimage "$wallpaper_dir/${WALLPAPERS[0]}" >/dev/null 2>&1 || warn "wallpaper"

  # Panels: a thin top bar and a full-width dock, both always visible.
  # See plasma-layout.js.
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    "$(cat "$HERE/plasma-layout.js")" >/dev/null 2>&1 || warn "panels (set them in the panel settings)"
  # Translucent panels. Plasma's script API ignores opacity, so set it in its
  # config; it applies at the next login.
  panel_ids="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    'panels().forEach(function (p) { print(p.id + " ") })' 2>/dev/null || true)"
  [[ -n "${panel_ids// /}" ]] || warn "translucent panels"
  for id in $panel_ids; do
    kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $id" --key panelOpacity 2
  done

  # kitty as the default terminal (Ctrl+Alt+T).
  kwriteconfig6 --file kdeglobals --group General --key TerminalApplication kitty
  kwriteconfig6 --file kdeglobals --group General --key TerminalService kitty.desktop
  # Konsole's own desktop file claims Ctrl+Alt+T; give it to kitty instead.
  kwriteconfig6 --file kglobalshortcutsrc --group services --group org.kde.konsole.desktop --key _launch none
  kwriteconfig6 --file kglobalshortcutsrc --group services --group kitty.desktop --key _launch "Ctrl+Alt+T"
  # And kitty in place of Konsole in the dock.
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    'panels().forEach(function (p) { p.widgets("org.kde.plasma.icontasks").forEach(function (w) { w.currentConfigGroup = ["General"]; var l = String(w.readConfig("launchers", "")); if (l.indexOf("org.kde.konsole.desktop") >= 0) { w.writeConfig("launchers", l.replace("applications:org.kde.konsole.desktop", "applications:kitty.desktop")); } }) })' \
    >/dev/null 2>&1 || warn "kitty in the dock"
  # --- Mac feel ---
  # Quicker animations; the Mac's are short and never make you wait.
  kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0.7
  # Minimize into the dock like a genie.
  kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled true
  kwriteconfig6 --file kwinrc --group Plugins --key squashEnabled false
  # Big, soft window shadows so the active window stands out.
  kwriteconfig6 --file breezerc --group Common --key ShadowSize ShadowVeryLarge
  kwriteconfig6 --file breezerc --group Common --key ShadowStrength 160
  # Fast key repeat.
  kwriteconfig6 --file kcminputrc --group Keyboard --key RepeatDelay 250
  kwriteconfig6 --file kcminputrc --group Keyboard --key RepeatRate 40
  # Mac-style title bars: red, yellow and green buttons on the left, title
  # centered (kde/.local/share/aurorae/themes/WhiteSur-TokyoNight).
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme __aurorae__svg__WhiteSur-TokyoNight
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
  # Never lock or sleep the screen by itself; this box is always on.
  kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
  qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
else
  warn "KDE settings (kwriteconfig6 not found; are you on Kubuntu?)"
fi

log "Done"
cat <<'EOF'
Log out and back in for the shell, fonts, and theme to apply.
Put your git name and email in ~/.gitconfig.local:
  git config --file ~/.gitconfig.local user.name  "Your Name"
  git config --file ~/.gitconfig.local user.email "you@example.com"

Try these:
  Ctrl+Alt+T     kitty
  Meta+T         KDE's tiling editor: draw zones, then Shift+drag windows into them
  Ctrl+R         fuzzy search your shell history
  cd <part>      jumps to a directory you visited before (zoxide)
  lg / top       lazygit / btop
  dots           go to your dotfiles
  agents         switch to the agents user
To undo the look: System Settings > Colors & Themes > Global Theme > Breeze.
EOF
