set -euo pipefail

LINKS=(Makefile .envrc .taplo.toml .yamllint.yml)

flake="$1"
sitePackages="$2"
preCommit="$3"

gitignore() {
  local file
  for file in "$@"; do
    grep -q "^/$file" .gitignore || echo "/$file" >>.gitignore
  done
}

[[ -f .gitignore ]] || touch .gitignore
gitignore .flake
[[ $preCommit == 1 ]] || gitignore .pre-commit-config.yaml

ln --symbolic --no-dereference --force "$flake" .flake
for file in "${LINKS[@]}"; do
  [[ ! -f $file || -L $file ]] && {
    gitignore "$file"
    ln --symbolic --force "$flake/$file" .
  }
done

hash=$(nix hash file pyproject.toml ./*.{nix,lock} | sha1sum | awk '{print $1}')

prefix="${XDG_CACHE_HOME:=$HOME/.cache}/pyproject-env/${PWD//\//%}/$hash"

export PATH="$prefix/bin:$PATH"

export NIX_PYTHONPATH="$prefix/$sitePackages:${NIX_PYTHONPATH:-}"

[[ -d $prefix ]] ||
  pip install --no-deps --editable . --prefix "$prefix" --no-build-isolation >&2
