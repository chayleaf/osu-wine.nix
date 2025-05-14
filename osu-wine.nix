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
  patch = wineUnstable.src.staging;
  build-inputs = pkgNames: extra: (mkBuildInputs wineUnstable.pkgArches pkgNames) ++ extra;
  patches = fetchFromGitHub {
    owner = "whrvt";
    repo = "wine-osu-patches";
    rev = "d8e838ab993128bb056d068687a96118e9e99bd9";
    hash = "sha256-UfzbnqSoONKLlEGWcMXRALaZS25VuBvdd+D/6xy6fsw=";
  };
  disabled = [
    "dsound-EAX"
    "ntdll-Junction_Points"
    "mountmgr-DosDevices"
    "ntdll-NtDevicePath"
    "ws2_32-af_unix"
    "eventfd_synchronization"
  ];
  env = {
    NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types";
  };
in
assert lib.versions.majorMinor wineUnstable.version == lib.versions.majorMinor patch.version;

(wineUnstable.override { wineRelease = "staging"; }).overrideAttrs (self: {
  inherit env;
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
      sanityCheck=
      # ps0322 breaks linking
      for patch in $(find ${patches} -regex '.*\.patch' | sort | grep -v ps0322); do
        if [[ "$patch" = */disable-ime-envvar.patch ]]; then
          patch="${./disable-ime-envvar.patch}"
          sanityCheck=1
        fi
        echo "Applying $patch"
        patch -p1 < "$patch"
      done
      [[ -z "$sanityCheck" ]] && exit 1
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
