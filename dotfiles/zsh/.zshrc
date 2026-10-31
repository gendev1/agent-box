# zsh config. Lives in ~/agent-box/dotfiles/zsh; ~/.zshrc is a link to it.
# Machine-only or secret settings go in ~/.zshrc.local (not in the repo).

export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
export EDITOR=nvim

# History and completion
HISTFILE=~/.zsh_history HISTSIZE=50000 SAVEHIST=50000
setopt share_history hist_ignore_all_dups autocd interactive_comments
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
bindkey -e

# Up and Down search history for lines that start with what you typed
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

for f in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
         /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  [[ -f $f ]] && source $f
done
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'

# Tokyo Night everywhere
export BAT_THEME=tokyonight_night
export FZF_DEFAULT_OPTS='--color=bg+:#283457,bg:#16161e,border:#27a1b9,fg:#c0caf5,gutter:#16161e,header:#ff9e64,hl+:#2ac3de,hl:#2ac3de,info:#545c7e,marker:#bb9af7,pointer:#bb9af7,prompt:#7aa2f7,spinner:#bb9af7 --border=rounded --layout=reverse --height=40%'

command -v fzf      >/dev/null && fzf --zsh >/dev/null 2>&1 && eval "$(fzf --zsh)"   # Ctrl+R, Ctrl+T
command -v starship >/dev/null && eval "$(starship init zsh)"

# Ubuntu renames bat and fd
command -v batcat >/dev/null && alias bat=batcat cat='batcat --paging=never'
command -v fdfind >/dev/null && alias fd=fdfind
if command -v eza >/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -la --icons --git --group-directories-first'
  alias tree='eza --tree --icons'
fi
alias lg=lazygit top=btop vim=nvim
alias agents='sudo -iu agents'
alias snaps='sudo timeshift --list'
alias dots='cd ~/agent-box/dotfiles'

# From Omarchy (MIT, see LICENSE-omarchy), adapted for zsh and Ubuntu names.
alias ..='cd ..' ...='cd ../..' ....='cd ../../..'
alias g=git gcm='git commit -m' gcam='git commit -a -m' gcad='git commit -a --amend'
alias t='tmux attach || tmux new -s Work'
alias decompress='tar -xzf'
compress() { tar -czf "${1%/}.tar.gz" "${1%/}"; }
n() { if (( $# == 0 )); then nvim .; else nvim "$@"; fi; }
open() { xdg-open "$@" >/dev/null 2>&1 &! }
if command -v batcat >/dev/null; then
  alias ff="fzf --preview 'batcat --style=numbers --color=always {}'"
  export MANROFFOPT='-c' MANPAGER="sh -c 'col -bx | batcat -l man -p'"
fi
eff() { local f; f="$(ff)" && [[ -n $f ]] && $EDITOR "$f"; }

# ga <branch>: new worktree and branch next to this repo, then cd into it.
ga() {
  [[ -z $1 ]] && { echo "Usage: ga <branch>"; return 1; }
  local wt="../$(basename "$PWD")--$1"
  git worktree add -b "$1" "$wt" && cd "$wt"
}
# gd: remove the current worktree and its branch.
gd() {
  local cwd=$PWD wt=${PWD:t}
  local root=${wt%%--*} branch=${wt#*--}
  [[ $root == "$wt" ]] && { echo "Not in a ga worktree"; return 1; }
  read -q "?Remove worktree and branch $branch? [y/N] " || { echo; return 1; }
  echo
  cd "../$root" && git worktree remove "$cwd" --force && git branch -D "$branch"
}

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# A splash in the first terminal only
[[ -o interactive && $SHLVL -le 2 ]] && command -v fastfetch >/dev/null && fastfetch

# zoxide must come last: it checks that nothing changes cd after it.
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd cd)"
