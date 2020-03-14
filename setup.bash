#!/usr/bin/env bash

set -euo pipefail

HELP_PLUGIN_NAME="Name for your plugin, starting with \`asdf-\`, eg. \`asdf-foo\`"
HELP_TOOL_CHECK="Shell command for testing correct tool installation. eg. \`foo --version\` or \`foo --help\`"
HELP_TOOL_HOMEPAGE="Tool homepage. eg. https://example.org"

ask_for() {
  local prompt="$1"
  local default_value="${2:-}"
  local alternatives="${3:-"[$default_value]"}"
  local value=""
  while [ -z "$value" ]; do
    echo "$prompt" >&2
    if [ "[]" != "$alternatives" ]; then
      echo -n "$alternatives " >&2
    fi
    echo -n "> " >&2
    read -r value
    echo >&2
    if [ -z "$value" ] && [ -n "$default_value" ]; then
      value="$default_value"
    fi
  done
  echo "$value"
}

download_license() {
  local keyword file
  keyword="$1"
  file="$2"
  curl -qsL "https://raw.githubusercontent.com/github/choosealicense.com/gh-pages/_licenses/${keyword}.txt" |
    extract_license >"$file"
}

extract_license() {
  awk '/^---/{f=1+f} f==2 && /^$/ {f=3} f==3'
}

test_url() {
  curl -fqsL -I "$1" | head -n 1 | grep 200 >/dev/null
}

ask_license() {
  local license keyword

  echo "Please choose a LICENSE keyword."
  echo
  echo "See available license keywords at"
  echo "https://help.github.com/en/github/creating-cloning-and-archiving-repositories/licensing-a-repository#searching-github-by-license-type"

  while true; do
    license="$(ask_for "License keyword:" "apache-2.0" "mit/[apache-2.0]/agpl-3.0/unlicense")"
    keyword=$(echo "$license" | tr '[:upper:]' '[:lower:]')

    url="https://choosealicense.com/licenses/$keyword/"
    if test_url "$url"; then
      break
    else
      echo "Invalid license keyword: $license"
    fi
  done

  echo "$keyword"
}

set_placeholder() {
  local name value out file tmpfile
  name="$1"
  value="$2"
  out="$3"

  git grep -l -F --untracked "$name" -- "$out" |
    while IFS=$'\n' read -r file; do
      tmpfile="$file.sed"
      sed "s#$name#$value#g" "$file" >"$tmpfile" && mv "$tmpfile" "$file"
    done
}

setup() {
  local cwd out tool_name check_command author_name github_username tool_homepage ok

  cwd="$PWD"
  out="$cwd/out"

  # ask for arguments not given via CLI
  tool_name="${1:-$(ask_for "$HELP_PLUGIN_NAME")}"
  tool_name="${tool_name/asdf-/}"
  tool_homepage="${2:-$(ask_for "$HELP_TOOL_HOMEPAGE")}"
  check_command="${3:-$(ask_for "$HELP_TOOL_CHECK" "$tool_name --help")}"
  author_name="${4:-$(ask_for "Author name" "$(git config user.name 2>/dev/null)")}"
  github_username="${5:-$(ask_for "GitHub username")}"
  license_keyword="${6:-$(ask_license)}"
  license_keyword="$(echo "$license_keyword" | tr '[:upper:]' '[:lower:]')"
  shift 6

  cat <<-EOF
Setting up plugin: asdf-$tool_name

author:        $author_name
repo:          https://github.com/$github_username/asdf-$tool_name
license:       https://choosealicense.com/licenses/$license_keyword/
homepage:      $tool_homepage
test command:  \`$check_command\`

After confirmation, the \`master\` will be replaced with the generated
template using the above information. Please ensure all seems correct.
EOF

  ok="${1:-$(ask_for "Do you want to continue?" "" "y/N")}"
  shift 1
  if [ "y" != "$ok" ]; then
    echo "Nothing done."
  else
    (
      set -e
      # previous cleanup to ensure we can run this program many times
      git branch template 2>/dev/null || true
      git checkout -f template
      git worktree remove -f out 2>/dev/null || true
      git branch -D out 2>/dev/null || true

      # checkout a new worktree and replace placeholders there
      git worktree add --detach out

      cd "$out"
      git checkout --orphan out
      git rm -rf "$out" >/dev/null
      git read-tree --prefix=/ -u template:template/

      download_license "$license_keyword" "$out/LICENSE"

      set_placeholder "<YOUR TOOL>" "$tool_name" "$out"
      set_placeholder "<TOOL HOMEPAGE>" "$tool_homepage" "$out"
      set_placeholder "<TOOL CHECK>" "$check_command" "$out"
      set_placeholder "<YOUR NAME>" "$author_name" "$out"
      set_placeholder "<YOUR GITHUB USERNAME>" "$github_username" "$out"

      git add "$out"
      git commit -m "Generate asdf-$tool_name plugin from template."

      cd "$cwd"
      git branch -M out master
      git worktree remove -f out
      git checkout -f master

      echo "All done."
      echo "Your master branch has been reset to an initial commit."
      echo "You might want to push using \`--force-with-lease\` to origin/master"
    ) || cd "$cwd"
  fi
}

setup "$@"
