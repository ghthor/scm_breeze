# Detect shell
breeze_detect_shell() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    echo "zsh"
  else
    echo "bash"
  fi
}

breeze_shell_is() {
  [ "$(breeze_detect_shell)" = "$1" ] && return 0
  return 1
}
# Detect whether zsh 'shwordsplit' option is on by default.
if breeze_shell_is "zsh"; then
  zsh_shwordsplit=$( (setopt | grep -q shwordsplit) && echo "true")
fi

# Switch on/off shwordsplit for functions that require it.
zsh_compat() {
  if breeze_shell_is "zsh" && [ -z $zsh_shwordsplit ]; then
    setopt shwordsplit
  fi
}
zsh_reset() {
  if breeze_shell_is "zsh" && [ -z $zsh_shwordsplit ]; then
    unsetopt shwordsplit
  fi
}

# Enable/disable nullglob for zsh or bash
enable_nullglob() {
  if breeze_shell_is "zsh"; then
    setopt NULL_GLOB
  else
    shopt -s nullglob
  fi
}
disable_nullglob() {
  if breeze_shell_is "zsh"; then
    unsetopt NULL_GLOB
  else
    shopt -u nullglob
  fi
}

# Alias wrapper that ignores errors if alias is not defined.
_safe_alias(){ alias "$@" 2> /dev/null; }
_alias() {
  if [ -n "$1" ]; then
    local alias_str="$1"; local cmd="$2"
    _safe_alias $alias_str="$cmd"
  fi
}

# Quote the contents of "$@"
function token_quote {
    # Older versions of {ba,z}sh don't support the built-in quoting, so fall back to printf %q
  local quoted
  quoted=()  # Assign separately for zsh 5.0.2 of Ubuntu 14.04
  for token; do
    quoted+=( "$(printf '%q' "$token")" )
  done
  printf '%s\n' "${quoted[*]}"

  # Keep this code for use when minimum versions of {ba,z}sh can be increased.
  # See https://github.com/scmbreeze/scm_breeze/issues/260
  #
  # if breeze_detect_shell "bash"; then
  #   # ${parameter@operator} where parameter is ${@} and operator is 'Q'
  #   # https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
  #   eval "${@@Q}"
  # else  # zsh
  #   # http://zsh.sourceforge.net/Doc/Release/Expansion.html#Parameter-Expansion-Flags
  #   eval "${(q-)@}"
  # fi
}

# Quote "$@" before `eval` to prevent arbitrary code execution.
# Eg, the following will run `date`:
# evil() { eval "$@"; }; evil "echo" "foo;date"
function _safe_eval() {
  eval $(token_quote "$@")

  # Keep this code for use when minimum versions of {ba,z}sh can be increased.
  # See https://github.com/scmbreeze/scm_breeze/issues/260
  #
  # if breeze_detect_shell "bash"; then
  #   # ${parameter@operator} where parameter is ${@} and operator is 'Q'
  #   # https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
  #   eval "${@@Q}"
  # else  # zsh
  #   # http://zsh.sourceforge.net/Doc/Release/Expansion.html#Parameter-Expansion-Flags
  #   eval "${(q-)@}"
  # fi
}

find_binary() {
  if breeze_shell_is "zsh"; then
    builtin type -p "$1" | sed "s/$1 is //" | head -1
  else
    builtin type -P "$1"
  fi
}

export GIT_BINARY=$(find_binary git)

# Updates SCM Breeze from GitHub.
update_scm_breeze() {
  currDir=$PWD
  cd "$scmbDir"
  oldHEAD=$(git rev-parse HEAD 2> /dev/null)
  git pull origin master
  # Reload latest version of '_create_or_patch_scmbrc' function
  source "$scmbDir/lib/scm_breeze.sh"
  _create_or_patch_scmbrc $oldHEAD
  # Reload SCM Breeze
  source "$scmbDir/scm_breeze.sh"
  cd "$currDir"
}

# Create '~/.*.scmbrc' files, or attempt to patch them if passed a previous revision
_create_or_patch_scmbrc() {
  patchfile=$(mktemp -t tmp.XXXXXXXXXX)
  # Process '~/.scmbrc' and '~/.*.scmbrc'
  for prefix in "" "git."; do
    # Create file from example if it doesn't already exist
    if ! [ -e "$HOME/.$prefix""scmbrc" ]; then
      cp "$scmbDir/$prefix""scmbrc.example" "$HOME/.$prefix""scmbrc"
      printf "== '~/.$prefix""scmbrc' has been created. Please edit this file to change SCM Breeze settings.\n"
    # If file exists, attempt to update it with any new settings
    elif [ -n "$1" ]; then
      # Create diff of example file, substituting example file for user's config.
      git diff $1 "$prefix""scmbrc.example" | sed "s/$prefix""scmbrc.example/.$prefix""scmbrc/g" >| $patchfile
      if [ -s $patchfile ]; then  # If patchfile is not empty
        cd "$HOME"
        # If the patch cannot be applied cleanly, show the updates and tell user to update file manually.
        if ! patch -f "$HOME/.$prefix""scmbrc" $patchfile; then
          printf "== \033[0;31mUpdates could not be applied to '\033[1m~/.$prefix""scmbrc\033[0;31m'.\033[0m\n"
          printf "== Please look at the following changes and manually update '~/.$prefix""scmbrc', if necessary.\n\n"
          cat "$HOME/.$prefix""scmbrc.rej"
        fi
        cd "$scmbDir"
      fi
    fi
  done
}

# Update ~/.scmbrc, ~/.git.scmbrc, etc. from latest commit
alias update_scmbrc_from_latest_commit="_create_or_patch_scmbrc HEAD~"
