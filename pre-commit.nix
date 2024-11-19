{
  pkgs,
  python,
  formatter,
}:
(with pkgs; [
  {
    package = formatter;
    types = [ "nix" ];
  }
  {
    package = deadnix;
    args = [ "--edit" ];
    types = [ "nix" ];
  }
  {
    package = statix;
    args = [ "fix" ];
    pass_filenames = false;
    types = [ "nix" ];
  }
  {
    package = taplo;
    args = [ "format" ];
    types = [ "toml" ];
  }
  { package = typos; }
  {
    package = yamlfix;
    args = [
      "--exclude=.pre-commit-config.yaml"
      "."
    ];
    types = [ "yaml" ];
  }
  {
    package = yamllint;
    args = [ "." ];
    types = [ "yaml" ];
  }
])
++ (
  let
    py =
      attrs:
      attrs
      // {
        types_or = [
          "python"
          "pyi"
        ];
      };
  in
  with python.pkgs;
  [
    (py {
      name = "ruff check";
      package = ruff;
      # ERA001: catch commented-out code - here because we don't want it for normal dev
      # ISC001: check for implicitly concatenated strings - disabled for format
      args = [
        "check"
        "--fix"
        "--extend-select=ERA001,ISC001"
        "--unfixable=ERA001"
      ];
    })
    (py {
      name = "ruff format";
      package = ruff;
      args = [ "format" ];
    })
    (py {
      package = mypy;
      id = "dmypy";
      args = [
        "run"
        "."
      ];
      pass_filenames = false;
    })
    (py {
      package = vulture;
      args = [ "." ];
      pass_filenames = false;
    })
  ]
)
