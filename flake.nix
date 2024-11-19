{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-github-actions = {
      url = "github:nix-community/nix-github-actions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-pre-commit = {
      url = "github:kingarrrt/nix-pre-commit";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-nix = {
      url = "github:nix-community/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    {
      lib = {
        mkPythonProject =
          {
            projectRoot,
            packageOverrides,
            pre-commit ? import ./pre-commit.nix,
            dev-pkgs ? null,
          }:
          let
            project = inputs.pyproject-nix.lib.project.loadPyproject {
              inherit projectRoot;
            };
          out = inputs.flake-utils.lib.eachDefaultSystem (
            system:
            let

              pkgs = inputs.nixpkgs.legacyPackages.${system};
              inherit (pkgs) lib;

              formatter = pkgs.nixfmt-rfc-style;

              package =
                python:
                let
                  attrs = project.renderers.buildPythonPackage { inherit python; };
                in
                with python.pkgs;
                let
                  # replace dependencies with local overrides, local packages are defined in
                  # packageOverlays as "name-local"
                  localize =
                    packages:
                    builtins.map (
                      pkg:
                      let
                        local = "${pkg.pname}-local";
                      in
                      if builtins.hasAttr local python.pkgs then python.pkgs."${local}" else pkg
                    ) packages;
                in
                buildPythonPackage (
                  lib.recursiveUpdate attrs rec {
                    dependencies = localize attrs.dependencies;
                    optional-dependencies = lib.mapAttrs (_: localize) attrs.optional-dependencies;
                    checkInputs = optional-dependencies.test;
                  }
                );

              pyoverlay =
                python:
                python.override {
                  inherit packageOverrides;
                };

              shells =
                builtins.mapAttrs
                  (
                    _name: interpreter:
                    let
                      python = pyoverlay interpreter;
                      pkg = package python;
                    in
                    pkgs.mkShellNoCC {
                      inherit (python) name;
                      inherit
                        (inputs.nix-pre-commit.lib.${system}.mkLocalConfig (pre-commit {
                          inherit pkgs python formatter;
                        }))
                        packages
                        shellHook
                        ;
                      inputsFrom = [
                        (pkg.overridePythonAttrs {
                          nativeBuildInputs =
                            pkg.nativeBuildInputs
                            ++ (lib.optionals (pkg.optional-dependencies ? dev) pkg.optional-dependencies.dev)
                            ++ (lib.optionals (dev-pkgs != null) (dev-pkgs pkgs));
                          shellHook = ''
                            runHook preShellHook
                            hash=$(nix hash file pyproject.toml flake.lock *.nix \
                              | sha1sum \
                              | awk '{print $1}')
                            prefix="''${XDG_CACHE_HOME:-$HOME/.cache}/nixpkgs/pip-shell-hook/''${PWD//\//%}/$hash"
                            PATH="$prefix/bin:$PATH"
                            export NIX_PYTHONPATH="$prefix/${python.sitePackages}:''${NIX_PYTHONPATH-}"
                            [ -d "$prefix" ] || ${lib.getExe' python.pkgs.pip "pip"} install \
                              --no-deps --editable . --prefix "$prefix" --no-build-isolation >&2
                            runHook postShellHook
                          '';
                        })
                      ];
                    }
                  )
                  (
                    lib.filterAttrs (
                      name: python:
                      python ? implementation
                      && python.implementation == "cpython"
                      && (lib.all (
                        spec:
                        with inputs.pyproject-nix.lib;
                        pep440.comparators.${spec.op} (pep508.mkEnviron python).python_full_version.value spec.version
                      ) project.requires-python)
                      && (builtins.substring 7 15 name) != "Minimal"
                    ) pkgs.pythonInterpreters
                  );

              python = pyoverlay pkgs.python3;
            in
            # skip this one as there are no github runners
            if system == "aarch64-linux" then
              { }
            else
              {
                inherit formatter;

                devShells = shells // {
                  default = shells.${python.pythonAttr};
                };

                # XXX: filter out broken interpreters
                githubShells = lib.filterAttrs (
                  name: _value: name != "python313" && name != "python314"
                ) shells;

                packages.default = package python;
              }
          );

          in
          out
          // {
            githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
              checks = out.githubShells;
            };
          };
      };

      formatter.x86_64-linux = with inputs.nixpkgs.legacyPackages.x86_64-linux; nixfmt-rfc-style;
    };
}
