{
  lib,
  stdenv,
  symlinkJoin,
  krita-plugin-gmic,
  binaryPlugins ? lib.optional (!stdenv.hostPlatform.isDarwin) (
    # Default plugins provided by upstream appimage
    krita-plugin-gmic
  ),
  krita-unwrapped,
  wrapGAppsHook3,
}:
let
  isDarwin = stdenv.hostPlatform.isDarwin;
in
symlinkJoin {
  pname = "krita";
  inherit (krita-unwrapped) version buildInputs;

  nativeBuildInputs = lib.optionals (!isDarwin) (
    krita-unwrapped.nativeBuildInputs
    ++ [
      wrapGAppsHook3
    ]
  );

  paths = [ krita-unwrapped ] ++ binaryPlugins;

  postBuild =
    if isDarwin then
      ''
        mkdir -p $out/Applications
        ln -s ../bin/krita.app $out/Applications/Krita.app
        ln -s ../Applications/Krita.app/Contents/MacOS/krita $out/bin/krita
      ''
    else
      ''
        gappsWrapperArgsHook
        wrapQtApp "$out/bin/krita" \
          "''${gappsWrapperArgs[@]}" \
          --prefix PYTHONPATH : "$PYTHONPATH" \
          --set KRITA_PLUGIN_PATH "$out/lib/kritaplugins"
      '';

  meta = krita-unwrapped.meta // {
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };

  passthru = {
    inherit binaryPlugins;
    unwrapped = krita-unwrapped;
  };
}
