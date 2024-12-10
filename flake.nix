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

    in

    inputs.flake-utils.lib.eachDefaultSystem (system: {
      devShells.default =
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        pkgs.mkShellNoCC {
          inherit (preCommit system pkgs pkgs.python3) packages shellHook;
        };
    })

    // {

      lib = {

        mkPythonProject =
          {
            # root of the project
            projectRoot,
            # whether to install pre-commit hook
            pre-commit ? true,
            # nixpkgs config
            nixpkgs ? { },
            # overlays to the python package set
            packageOverlays ? [ ],
            # function accepting `pkgs` arg that returns either a function or attrset
            # passed to package.overridePythonAttrs
            overridePkgAttrs ? null,
            # as above, passed to devShell.overridePythonAttrs
            overrideDevShellAttrs ? null,
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

                pkgs = import inputs.nixpkgs (nixpkgs // { inherit system; });

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
                    pkg = python.pkgs.buildPythonPackage (
                      let
                        attrs = project.renderers.buildPythonPackage { inherit python; };
                        # replace dependencies with local overrides, local packages are
                        # defined in overlays as "name-local"
                        localize =
                          packages:
                          builtins.map (pkg: python.pkgs."${pkg.pname}-local" or pkg) packages;
                      in
                      attrs
                      // rec {
                        dependencies = lib.optionals (
                          attrs ? dependencies
                        ) localize attrs.dependencies;
                        optional-dependencies = lib.optionalAttrs (
                          attrs ? optional-dependencies
                        ) lib.mapAttrs (_: localize) attrs.optional-dependencies;
                        checkInputs = optional-dependencies.test or [ ];
                        passthru.overlays = packageOverlays;
                      }
                    );
                  in
                  if overridePkgAttrs == null then
                    pkg
                  else
                    pkg.overridePythonAttrs (overridePkgAttrs pkgs);

                devShell =
                  python:
                  let
                    precommit = preCommit system pkgs python;
                    pkg = package python;
                  in
                  pkgs.mkShellNoCC {
                    inherit (python) name;
                    inputsFrom = [
                      (
                        if overrideDevShellAttrs == null then
                          pkg
                        else
                          pkg.overridePythonAttrs (overrideDevShellAttrs pkgs)
                      )
                    ];
                    packages =
                      (pkg.optional-dependencies.dev or [ ])
                      ++ (lib.optionals pre-commit precommit.packages)
                      # required by shellHook
                      ++ [ python.pkgs.pip ];
                    shellHook = ''
                      ${lib.optionalString pre-commit precommit.shellHook}
                      source ${./shell-hook.sh} ${./.} ${python.sitePackages} ${
                        if pre-commit then "1" else "0"
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
