# ------------------------------------------------------------------------------
# SCM Breeze - Streamline your SCM workflow.
# Copyright 2011 Nathan Broadbent (http://madebynathan.com). All Rights Reserved.
# Released under the LGPL (GNU Lesser General Public License)
# ------------------------------------------------------------------------------

if sed -E 's///g' </dev/null &>/dev/null; then
  SED_REGEX_ARG="E"
elif sed -r 's///g' </dev/null &>/dev/null; then
  SED_REGEX_ARG="r"
else
  echo "Cannot determine extended regex argument for sed! (Doesn't respond to either -E or -r)"
fi

# Wrap common commands with numeric argument expansion.
# Prepends everything with exec_scmb_expand_args,
# even if commands are already aliases or functions
if [ "$shell_command_wrapping_enabled" = "true" ] || [ "$bash_command_wrapping_enabled" = "true" ]; then
  # Do it in a function so we don't bleed variables
  function _git_wrap_commands() {
    # Define 'whence' for bash, to get the value of an alias
    type whence >/dev/null 2>&1 || function whence() { LC_MESSAGES="C" type "$@" | sed -$SED_REGEX_ARG -e "s/.*is aliased to \`//" -e "s/'$//"; }
    local cmd=''
    for cmd in "${scmb_wrapped_shell_commands[@]}"; do
      if [ "${scmbDebug:-}" = "true" ]; then echo "SCMB: Wrapping $cmd..."; fi

      # Special check for 'cd', to make sure SCM Breeze is loaded after RVM
      if [ "$cmd" = 'cd' ]; then
        if [ -e "$HOME/.rvm" ] && ! type rvm >/dev/null 2>&1; then
          echo -e "\\033[0;31mSCM Breeze must be loaded \\033[1;31mafter\\033[0;31m RVM, otherwise there will be a conflict when RVM wraps the 'cd' command.\\033[0m"
          echo -e "\\033[0;31mPlease move the line that loads SCM Breeze to the bottom of your ~/.bashrc\\033[0m"
          continue
        fi
      fi

      case "$(LC_MESSAGES="C" type "$cmd" 2>&1)" in

      # Don't do anything if command already aliased, or not found.
      *'exec_scmb_expand_args'*)
        if [ "${scmbDebug:-}" = "true" ]; then echo "SCMB: $cmd is already wrapped"; fi
        ;;

      *'not found'*)
        if [ "${scmbDebug:-}" = "true" ]; then echo "SCMB: $cmd not found!"; fi
        ;;

      *'aliased to'* | *'is an alias for'*)
        if [ "${scmbDebug:-}" = "true" ]; then echo "SCMB: $cmd is an alias"; fi
        # Store original alias
        local original_alias="$(whence $cmd)"
        # Remove alias, so that we can find binary
        unalias "$cmd"

        # Detect original $cmd type, and escape
        case "$(LC_MESSAGES="C" type "$cmd" 2>&1)" in
        # Escape shell builtins with 'builtin'
        *'is a shell builtin'*) local escaped_cmd="builtin $cmd" ;;
        # Get full path for files with 'find_binary' function
        *) local escaped_cmd="$(find_binary $cmd)" ;;
        esac

        # Expand original command into full path, to avoid infinite loops
        local expanded_alias="$(echo $original_alias | sed -$SED_REGEX_ARG "s%(^| )$cmd($| )%\\1$escaped_cmd\\2%")"
        # Wrap previous alias with escaped command
        alias $cmd="exec_scmb_expand_args $expanded_alias"
        ;;

      *'is a'*'function'*)
        if [ "${scmbDebug:-}" = "true" ]; then echo "SCMB: $cmd is a function"; fi
        # Copy old function into new name
        eval "$(declare -f "$cmd" | sed -"$SED_REGEX_ARG" "s/^$cmd \\(\\)/__original_$cmd ()/")"
        # Remove function
        unset -f "$cmd"
        # Create function that wraps old function
        eval "${cmd}(){ exec_scmb_expand_args __original_${cmd} \"\$@\"; }"
        ;;

      *'is a shell builtin'*)
        if [ "${scmbDebug:-}" = "true" ]; then echo "SCMB: $cmd is a shell builtin"; fi
        # Handle shell builtin commands
        alias $cmd="exec_scmb_expand_args builtin $cmd"
        ;;

      *)
        if [ "${scmbDebug:-}" = "true" ]; then echo "SCMB: $cmd is an executable file"; fi
        # Otherwise, command is a regular script or binary,
        # and the full path can be found with 'find_binary' function
        alias $cmd="exec_scmb_expand_args '$(find_binary $cmd)'"
        ;;
      esac
    done
    # Clean up
    declare -f whence >/dev/null && unset -f whence
  }
  _git_wrap_commands
fi

# Function wrapper around 'll'
# Adds numbered shortcuts to output of ls -l, just like 'git status'
if [ "$shell_ls_aliases_enabled" = "true" ] && builtin command -v ruby >/dev/null 2>&1; then
  # Test if readlink supports -f option, test for greadlink on Mac, then fallback to perl
  if \readlink -f / >/dev/null 2>&1; then
    _abs_path_command=(readlink -f)
  elif greadlink -f / >/dev/null 2>&1; then
    _abs_path_command=(greadlink -f)
  else
    _abs_path_command=(perl -e 'use Cwd abs_path; print abs_path(shift)')
  fi

  unalias ll >/dev/null 2>&1
  unset -f ll >/dev/null 2>&1
  function ls_with_file_shortcuts {
    # BSD ls is different to Linux (GNU) ls
    if ! (\ls --version 2>/dev/null || echo "BSD") | grep GNU >/dev/null 2>&1; then
      # ls is BSD
      local _ls_bsd="BSD"
    fi

    local ll_output
    local ll_command # Ensure sort ordering of the two invocations is the same
    if [ "$_ls_bsd" != "BSD" ]; then
      ll_command=(\ls -hv --group-directories-first)
      ll_output="$("${ll_command[@]}" -l --color "$@")"
    else
      ll_command=(\ls)
      ll_output="$("${ll_command[@]}" -lG --color=always "$@")"
    fi

    if breeze_shell_is "zsh"; then
      # Ensure sh_word_split is on
      [[ -o shwordsplit ]] && SHWORDSPLIT_ON=true
      setopt shwordsplit
    fi

    # Get the directory that `ls` is being run relative to.
    # Only allow one directory to avoid incorrect $e# variables when listing
    # multiple directories (issue #274)
    local IFS=$'\n'
    local rel_path
    for arg in "$@"; do
      if [[ -e $arg ]]; then        # Path rather than option to ls
        if [[ -z $rel_path ]]; then # We are seeing our first pathname
          if [[ -d $arg ]]; then    # It's a directory
            rel_path=$arg
          else # It's a file, expand the current directory
            rel_path=.
          fi
        elif [[ -d $arg || (-f $arg && $rel_path != .) ]]; then
          if [[ -f $arg ]]; then arg=$PWD; fi # Get directory for current argument
          # We've already seen a different directory. Quit to avoid damage (issue #274)
          printf 'scm_breeze: Cannot list relative to both directories:\n  %s\n  %s\n' "$arg" "$rel_path" >&2
          printf 'Currently only listing a single directory is supported. See issue #274.\n' >&2
          return 1
        fi
      fi
    done
    rel_path=$("${_abs_path_command[@]}" ${rel_path:-$PWD})

    # Replace user/group with user symbol, if defined at ~/.user_sym
    # Before : -rw-rw-r-- 1 ndbroadbent ndbroadbent 1.1K Sep 19 21:39 scm_breeze.sh
    # After  : -rw-rw-r-- 1 𝐍  𝐍  1.1K Sep 19 21:39 scm_breeze.sh
    if [ -e "$HOME"/.user_sym ]; then
      # Little bit of ruby golf to rejustify the user/group/size columns after replacement
      # TODO(ghthor): Convert this to a cat <<EOF to improve readibility
      function rejustify_ls_columns() {
        ruby -e "o=STDIN.read;re=/^(([^ ]* +){2})(([^ ]* +){3})/;\
                 u,g,s=o.lines.map{|l|l[re,3]}.compact.map(&:split).transpose.map{|a|a.map(&:size).max+1};\
                 puts o.lines.map{|l|l.sub(re){|m|\"%s%-#{u}s %-#{g}s%#{s}s \"%[\$1,*\$3.split]}}"
      }

      local USER_SYM=$(/bin/cat $HOME/.user_sym)
      if [ -f "$HOME/.staff_sym" ]; then
        local STAFF_SYM=$(/bin/cat $HOME/.staff_sym)
        ll_output=$(echo "$ll_output" |
          \sed -$SED_REGEX_ARG "s/ $USER  staff/ $USER_SYM  $STAFF_SYM /g" |
          rejustify_ls_columns)
      else
        ll_output=$(echo "$ll_output" |
          \sed -$SED_REGEX_ARG "s/ $USER/ $USER_SYM /g" |
          rejustify_ls_columns)
      fi
    fi

    # Bail if there are two many lines to process
    if [ "$(echo "$ll_output" | wc -l)" -gt "50" ]; then
      echo -e '\033[33mToo many files to create shortcuts. Running plain ll command...\033[0m' >&2
      echo "$ll_output"
      return 1
    fi

    # Use ruby to inject numbers into ls output
    echo "$ll_output" | ruby -e "$(
      \cat <<EOF
output = STDIN.read
e = 1
re = /^(([^ ]* +){8})/
output.lines.each do |line|
  next unless line.match(re)
  puts line.sub(re, "\\\1\033[2;37m[\033[0m#{e}\033[2;37m]\033[0m" << (e < 10 ? "  " : " "))
  e += 1
end
EOF
    )"

    # Set numbered file shortcut in variable
    local e=1
    local ll_files=''
    local file=''

    # XXX FIXME XXX
    # There is a race condition here: If a file is removed between the above
    # and this second call of `ls` then the $e# variables can refer to the
    # wrong files.
    if [ -z $_ls_bsd ]; then
      ll_files="$(QUOTING_STYLE=literal "${ll_command[@]}" --color=never "$@")"
    else
      ll_files="$("${ll_command[@]}" --color=never "$@")"
    fi

    local IFS=$'\n'
    for file in $ll_files; do
      file=$rel_path/$file
      export $GIT_ENV_CHAR$e=$("${_abs_path_command[@]}" "$file")
      if [[ ${scmbDebug:-} = true ]]; then echo "Set \$$GIT_ENV_CHAR$e  => $file"; fi
      let e++
    done

    # Turn off shwordsplit unless it was on previously
    if breeze_shell_is "zsh" && [[ -z $SHWORDSPLIT_ON ]]; then unsetopt shwordsplit; fi
  }

  # Setup aliases
  alias ll="exec_scmb_expand_args ls_with_file_shortcuts"
  alias la="ll -A"
fi
