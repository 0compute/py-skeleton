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
    let

      inherit (inputs.nixpkgs) lib;

      base-overlay = import ./base-overlay.nix;
      pre-commit = import ./pre-commit.nix;

      preCommit =
        system: pkgs: python:
        inputs.nix-pre-commit.lib.${system}.mkLocalConfig (pre-commit {
          inherit pkgs python;
        });

      pkgsFor = system: inputs.nixpkgs.legacyPackages.${system};

    in

    inputs.flake-utils.lib.eachDefaultSystem (system: {
      devShells.default =
        let
          pkgs = pkgsFor system;
        in
        pkgs.mkShellNoCC {
          inherit (preCommit system pkgs pkgs.python3) packages shellHook;
        };
    })

    // {

      lib = {

        mkPythonProject =
          {
            projectRoot,
            packageOverlays ? [ ],
            systemPkgs ? null,
            devPkgs ? null,
          }:
          let

            project = inputs.pyproject-nix.lib.project.loadPyproject {
              inherit projectRoot;
            };

            packageOverrides = lib.composeManyExtensions (
              [ base-overlay ] ++ packageOverlays
            );

            self = inputs.flake-utils.lib.eachDefaultSystem (
              system:
              let

                pkgs = pkgsFor system;

                pyEnv = python: python.override { inherit packageOverrides; };

                pythons = builtins.mapAttrs (_name: python: (pyEnv python)) (
                  lib.filterAttrs (
                    name: python:
                    with inputs.pyproject-nix.lib;
                    let
                      pythonVersion = (pep508.mkEnviron python).python_full_version.value;
                    in
                    python ? implementation
                    && python.implementation == "cpython"
                    && (lib.all (
                      spec: pep440.comparators.${spec.op} pythonVersion spec.version
                    ) project.requires-python)
                    # TODO: py313 up is broken pending
                    # https://github.com/NixOS/nixpkgs/pull/355071
                    # https://nixpk.gs/pr-tracker.html?pr=355071
                    && builtins.compareVersions pythonVersion.str "3.13" == -1
                    && (builtins.substring 7 15 name) != "Minimal"
                  ) pkgs.pythonInterpreters
                );

                package =
                  python:
                  let
                    attrs = project.renderers.buildPythonPackage { inherit python; };
                  in
                  with python.pkgs;
                  let
                    # replace dependencies with local overrides, local packages are
                    # defined in overlays as "name-local"
                    localize =
                      packages:
                      builtins.map (
                        pkg:
                        let
                          local = "${pkg.pname}-local";
                        in
                        if builtins.hasAttr local python.pkgs then
                          python.pkgs."${local}"
                        else
                          pkg
                      ) packages;
                  in
                  buildPythonPackage (
                    lib.recursiveUpdate attrs rec {
                      dependencies = lib.optionals (
                        attrs ? dependencies
                      ) localize attrs.dependencies;
                      optional-dependencies = lib.optionalAttrs (
                        attrs ? optional-dependencies
                      ) lib.mapAttrs (_: localize) attrs.optional-dependencies;
                      propagatedNativeBuildInputs = lib.optionals (systemPkgs != null) (
                        systemPkgs pkgs
                      );
                      checkInputs = optional-dependencies.test or [ ];
                      passthru = {
                        inherit packageOverlays python;
                      };
                    }
                  );

                devShell =
                  python:
                  let
                    pkg = package python;
                    pre-ccommit = preCommit system pkgs python;
                  in
                  pkgs.mkShellNoCC {
                    inherit (python) name;
                    inherit (pre-ccommit) packages;
                    inputsFrom = [
                      (pkg.overridePythonAttrs {
                        nativeBuildInputs =
                          pkg.nativeBuildInputs
                          ++ (pkg.optional-dependencies.dev or [ ])
                          ++ (lib.optionals (devPkgs != null) (devPkgs pkgs))
                          ++ (with pkgs; [
                            cachix
                            gnumake
                          ]);
                      })
                    ];
                    shellHook = ''
                      ${pre-ccommit.shellHook}
                      source ${
                        pkgs.substituteAll {
                          src = ./shell-hook.sh;
                          flake = ./.;
                          awk = lib.getExe pkgs.gawk;
                          grep = lib.getExe pkgs.gnugrep;
                          inherit (python) sitePackages;
                          ln = lib.getExe' pkgs.coreutils "ln";
                          pip = lib.getExe' python.pkgs.pip "pip";
                          sha1sum = lib.getExe' pkgs.coreutils "sha1sum";
                        }
                      }
                    '';

                  };

                devShells = builtins.mapAttrs (_name: devShell) pythons;

              in
              # skip this one as there are no github runners
              if system == "aarch64-linux" then
                { }
              else
                let
                  python = pyEnv pkgs.python3;
                in
                {
                  devShells = devShells // {
                    default = devShells.${python.pythonAttr};
                  };
                  packages.default = package python;
                }

            );

          in
          self
          // {
            githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
              checks = lib.mapAttrs (
                _system: pythons: builtins.removeAttrs pythons [ "default" ]
              ) self.devShells;
            };
          };

      };

    };
}
