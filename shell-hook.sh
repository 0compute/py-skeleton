set -euo pipefail

LINKS=(Makefile .envrc .taplo.toml .yamllint.yml)

gitignore() {
  local file
  for file in "$@"; do
    @grep@ -q "^/$file" .gitignore || echo "/$file" >>.gitignore
  done
}

[ -f .gitignore ] || touch .gitignore
gitignore .flake/ .pre-commit-config.yaml

FLAKE="@flake@"
@ln@ --symbolic --no-dereference --force "$FLAKE" .flake

for file in "${LINKS[@]}"; do
  [[ ! -f $file || -L $file ]] && {
    gitignore "$file"
    ln --symbolic --force "$FLAKE/$file" .
  }
done

# shellcheck disable=2016
hash=$(nix hash file pyproject.toml ./*.{nix,lock} | @sha1sum@ | @awk@ '{print $1}')

# XXX: do we need a hashed directory? multiple python versions could share the same
# root with different sitePackages, and with checking of bin/ for project.scripts we can
# do the install only as required
prefix="${XDG_CACHE_HOME:=$HOME/.cache}/pyproject-env/${PWD//\//%}/$hash"

PATH="$prefix/bin:$PATH"

export NIX_PYTHONPATH="$prefix/@sitePackages@:${NIX_PYTHONPATH:-}"

[ -d "$prefix" ] ||
  @pip@ install --no-deps --editable . --prefix "$prefix" --no-build-isolation >&2
