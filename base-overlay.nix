self: super: with super; {

  # utility functions defined in the "x" namespace, on the basis that there is unlikely
  # to be a package named this
  x = rec {

    pkg-ref =
      pname:
      if builtins.hasAttr pname super then
        super.${pname}
      else
        self.${pname};

    override =
      pname: attrs:
      let
        pkg = pkg-ref pname;
      in
      (pkg.overridePythonAttrs attrs).overridePythonAttrs {
        pname = pkg.pname + "-override";
      };

    upgrade =
      pname: version: hash:
      let
        pkg = pkg-ref pname;
      in
      assert lib.assertMsg (
        builtins.compareVersions pkg.version version == -1
      ) "${pname} ${pkg.version} to ${version} is not an upgrade";
      override pname {
        inherit version;
        src = fetchPypi { inherit pname version hash; };
      };

    replace =
      name: packages:
      (builtins.filter (pkg: !(pkg ? pname && pkg.pname == name)) packages)
      ++ [ self."${name}-local" ];

  };

  # so that pytest dependency gets replaced with the hook
  pytest-local = pytestCheckHook;

}
