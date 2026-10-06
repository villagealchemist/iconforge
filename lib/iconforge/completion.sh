#!/usr/bin/env bash

completion_help() {
  cat <<'HELP'
Print shell completion code. This command does not edit shell startup files.
Usage: iconforge completion <bash|zsh|fish>

Bash: source <(iconforge completion bash)
Zsh:  source <(iconforge completion zsh)
Fish: iconforge completion fish | source

Completions include commands, configuration keys, common flags, and paths.
They do not scan or change applications.
HELP
}

cmd_completion() {
  [[ $# -eq 1 ]] || { completion_help; return 2; }
  case "$1" in
    -h|--help) completion_help ;;
    bash)
      cat <<'BASH_COMPLETION'
_iconforge_complete() {
  local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD-1]}"
  local choices="" candidate
  COMPREPLY=()
  case "$COMP_CWORD:$previous" in
    1:*) choices='forge config inspect apply restore refresh nuke doctor capabilities completion help' ;;
    *:config) choices='set get unset show path' ;;
    *:set|*:get|*:unset) choices='the-forge the-hearth default-directory' ;;
    *:completion) choices='bash zsh fish' ;;
    *:--strategy|*:-s) choices='native internal-icns' ;;
    *)
      if [[ "$current" == -* ]]; then
        case "${COMP_WORDS[1]}" in
          apply) choices='--icon --from --app-root --all --strategy --nuke --refresh --dry-run --verbose --help' ;;
          forge) choices='--output --keep-png --recursive --force --dry-run --help' ;;
          *) choices='--help' ;;
        esac
      fi
      ;;
  esac
  if [[ -n "$choices" ]]; then
    while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -W "$choices" -- "$current")
  else
    while IFS= read -r candidate; do COMPREPLY+=("$candidate"); done < <(compgen -f -- "$current")
  fi
}
complete -o filenames -o bashdefault -o default -F _iconforge_complete iconforge
BASH_COMPLETION
      ;;
    zsh)
      cat <<'ZSH_COMPLETION'
# Run compinit in your shell before sourcing this completion.
_iconforge() {
  local -a commands
  commands=(forge config inspect apply restore refresh nuke doctor capabilities completion help)
  if (( CURRENT == 2 )); then
    compadd -- $commands
  elif [[ ${words[2]} == config && CURRENT == 3 ]]; then
    compadd set get unset show path
  elif [[ ${words[2]} == config && CURRENT == 4 && ${words[3]} != show && ${words[3]} != path ]]; then
    compadd the-forge the-hearth default-directory
  elif [[ ${words[2]} == completion ]]; then
    compadd bash zsh fish
  elif [[ ${words[CURRENT-1]} == --strategy || ${words[CURRENT-1]} == -s ]]; then
    compadd native internal-icns
  else
    case ${words[2]} in
      apply) _arguments '--icon[ICNS file]:icon:_files -g "*.icns"' '--from[Icon library]:directory:_files -/' '--app-root[Extra app root]:directory:_files -/' '--all[Apply all]' '--nuke[Refresh caches]' '--refresh[Refresh caches]' '--dry-run[Preview]' '--verbose[Show details]' '--strategy[Strategy]:strategy:(native internal-icns)' '--help[Help]' '*:application:_files' ;;
      forge) _arguments '--output[Output directory]:directory:_files -/' '--keep-png[Keep PNG]' '--recursive[Recurse]' '--force[Replace outputs]' '--dry-run[Preview]' '--help[Help]' '*:image:_files' ;;
      *) _files ;;
    esac
  fi
}
compdef _iconforge iconforge
ZSH_COMPLETION
      ;;
    fish)
      cat <<'FISH_COMPLETION'
complete -c iconforge -f -n '__fish_use_subcommand' -a 'forge config inspect apply restore refresh nuke doctor capabilities completion help'
complete -c iconforge -f -n '__fish_seen_subcommand_from config; and not __fish_seen_subcommand_from set get unset show path' -a 'set get unset show path'
complete -c iconforge -f -n '__fish_seen_subcommand_from config; and __fish_seen_subcommand_from set get unset' -a 'the-forge the-hearth default-directory'
complete -c iconforge -f -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
complete -c iconforge -s h -l help -d 'Show help'
complete -c iconforge -n '__fish_seen_subcommand_from apply forge restore refresh nuke' -s d -l dry-run -d 'Preview changes'
complete -c iconforge -n '__fish_seen_subcommand_from apply' -l from -r -a '(__fish_complete_directories)' -d 'Icon library'
complete -c iconforge -n '__fish_seen_subcommand_from apply' -s i -l icon -r -F -d 'Explicit ICNS file'
complete -c iconforge -n '__fish_seen_subcommand_from apply' -s a -l all -d 'Apply all icons'
complete -c iconforge -n '__fish_seen_subcommand_from apply' -s s -l strategy -r -f -a 'native internal-icns'
complete -c iconforge -n '__fish_seen_subcommand_from apply restore' -s n -l nuke -d 'Refresh caches'
complete -c iconforge -n '__fish_seen_subcommand_from apply' -s v -l verbose -d 'Show details'
complete -c iconforge -n '__fish_seen_subcommand_from forge' -s o -l output -r -a '(__fish_complete_directories)'
complete -c iconforge -n '__fish_seen_subcommand_from forge' -s k -l keep-png
complete -c iconforge -n '__fish_seen_subcommand_from forge' -s r -l recursive
complete -c iconforge -n '__fish_seen_subcommand_from forge' -s f -l force
FISH_COMPLETION
      ;;
    *) usage_fail "Unsupported shell: $1. Choose bash, zsh, or fish."; return 2 ;;
  esac
}
