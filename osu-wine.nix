{
  lib,
  stdenv,
  callPackage,
  autoconf,
  hexdump,
  perl,
  python3,
  wineUnstable,
  gitMinimal,
  path,
  nasm,
  fetchFromGitHub,
}:

with callPackage "${path}/pkgs/applications/emulators/wine/util.nix" { };

let
  patch = (callPackage ./sources.nix { }).staging;
  build-inputs = pkgNames: extra: (mkBuildInputs wineUnstable.pkgArches pkgNames) ++ extra;
  collectPatches =
    d:
    builtins.concatLists (
      lib.mapAttrsToList (
        k: v:
        (
          if v == "regular" && lib.hasSuffix ".patch" k then
            lib.toList
          else if v == "directory" && !lib.hasPrefix "." k then
            collectPatches
          else
            lib.const [ ]
        )
          "${d}/${k}"
      ) (builtins.readDir d)
    );
  # ps0322 breaks linking
  patchList =
    map (x: if lib.hasSuffix "/disable-ime-envvar.patch" x then ./disable-ime-envvar.patch else x)
      (
        builtins.filter (x: !lib.hasInfix "/ps0322-" x) (
          collectPatches (fetchFromGitHub {
            owner = "whrvt";
            repo = "wine-osu-patches";
            rev = "15f50183571e8c7068a70454cafd18a14ba56b12";
            hash = "sha256-EhsRzbarkB5EOnwm/mXybeohhruGGJPTFVJym3PmxZQ=";
          })
        )
      );
  disabled = [ "eventfd_synchronization" ];
in
assert lib.versions.majorMinor wineUnstable.version == lib.versions.majorMinor patch.version;

(wineUnstable.override { wineRelease = "staging"; }).overrideAttrs (self: {
  buildInputs = build-inputs (
    [
      "perl"
      "autoconf"
      "gitMinimal"
    ]
    ++ lib.optional stdenv.hostPlatform.isLinux "util-linux"
  ) self.buildInputs;
  nativeBuildInputs = [
    autoconf
    hexdump
    perl
    python3
    gitMinimal
    nasm
  ] ++ self.nativeBuildInputs;

  prePatch =
    self.prePatch or ""
    + ''
      patchShebangs tools
      cp -r ${patch}/patches ${patch}/staging .
      chmod +w patches
      patchShebangs ./patches/gitapply.sh
      python3 ./staging/patchinstall.py DESTDIR="$PWD" --all ${
        lib.concatMapStringsSep " " (ps: "-W ${ps}") (patch.disabledPatchsets ++ disabled)
      }
      for patch in ${builtins.concatStringsSep " " patchList}; do
        echo "Applying $patch"
        patch -p1 < "$patch"
      done
      find . -iregex ".*orig" -execdir rm '{'''}' '+' || true
      tools/make_requests
      tools/make_specfiles
      git init || true
      git add --all &>/dev/null || true
      git commit --allow-empty -m "pre" &>/dev/null || true
      tools/make_makefiles
      autoreconf -fi
      rm -rf .git
    '';
})
// {
  meta = wineUnstable.meta // {
    description = wineUnstable.meta.description + " (with osu-wine patches)";
  };
}
