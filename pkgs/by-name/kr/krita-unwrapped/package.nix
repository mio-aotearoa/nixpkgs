{
  stdenv,
  SDL2,
  boost,
  bzip2,
  cmake,
  curl,
  eigen_5,
  exiv2,
  fetchurl,
  fetchpatch,
  fftw,
  fribidi,
  giflib,
  gsl,
  immer,
  kseexpr,
  lager,
  lcms2,
  lib,
  libaom,
  libheif,
  libjxl,
  libmypaint,
  libraw,
  qt6,
  kdePackages,
  libunibreak,
  libwebp,
  opencolorio,
  openexr,
  openjpeg,
  pkg-config,
  python3Packages,
  xsimd,
  zug,
}:

let
  isDarwin = stdenv.hostPlatform.isDarwin;

  # KDE Frameworks 6 is only exercised on Linux and FreeBSD. Widen its metadata
  # here so the private Darwin scope can use the frameworks Krita needs.
  forAllPlatforms =
    drv:
    drv.overrideAttrs (old: {
      meta = (old.meta or { }) // {
        platforms = lib.platforms.all;
      };
    });

  withoutInputs =
    inputs: names: lib.filter (input: !(builtins.elem (lib.getName input) names)) inputs;

  waylandInputs = [
    "plasma-wayland-protocols"
    "qtwayland"
    "wayland"
    "wayland-protocols"
  ];

  kdePackages' =
    if isDarwin then
      kdePackages.overrideScope (
        self: super:
        let
          frameworks = builtins.listToAttrs (
            map (name: {
              inherit name;
              value = forAllPlatforms super.${name};
            }) (builtins.attrNames super.frameworks)
          );
        in
        frameworks
        // {
          mlt = forAllPlatforms super.mlt;
          poppler = forAllPlatforms super.poppler;
          libkdcraw = forAllPlatforms super.libkdcraw;
          quazip = forAllPlatforms super.quazip;
          kseexpr = forAllPlatforms super.kseexpr;

          kdoctools = forAllPlatforms (
            super.kdoctools.overrideAttrs (old: {
              # macOS' QStandardPaths ignores XDG_DATA_DIRS, exposing the
              # doubled datadir in kdoctools' compiled-in catalog path.
              patches = (old.patches or [ ]) ++ [ ./kdoctools-absolute-datadir.patch ];
            })
          );

          karchive = forAllPlatforms (
            super.karchive.overrideAttrs (old: {
              # Upstream requires BZip2 on every platform; nixpkgs currently
              # only receives it transitively on Linux.
              buildInputs = (old.buildInputs or [ ]) ++ [ bzip2 ];
            })
          );

          kguiaddons = forAllPlatforms (
            super.kguiaddons.overrideAttrs (old: {
              buildInputs = withoutInputs (old.buildInputs or [ ]) [ "qtwayland" ];
              propagatedBuildInputs = withoutInputs (old.propagatedBuildInputs or [ ]) waylandInputs;
            })
          );

          kwindowsystem = forAllPlatforms (
            super.kwindowsystem.overrideAttrs (old: {
              buildInputs = withoutInputs (old.buildInputs or [ ]) [ "qtwayland" ];
              propagatedBuildInputs = withoutInputs (old.propagatedBuildInputs or [ ]) waylandInputs;
            })
          );

          kio = forAllPlatforms (
            super.kio.overrideAttrs (old: {
              # KIO only uses ACL/xattr and Linux mount support on Linux.
              buildInputs = withoutInputs (old.buildInputs or [ ]) [
                "acl"
                "attr"
                "util-linux"
              ];
            })
          );

          kauth = forAllPlatforms (
            super.kauth.overrideAttrs (old: {
              # KAuth has a native macOS backend; polkit is Linux-only.
              propagatedBuildInputs = withoutInputs (old.propagatedBuildInputs or [ ]) [
                "polkit-qt-1"
              ];
            })
          );
        }
      )
    else
      kdePackages;

  # kseexpr is a top-level package, so point it at the private Darwin scope too.
  kseexpr' =
    if isDarwin then forAllPlatforms (kseexpr.override { kdePackages = kdePackages'; }) else kseexpr;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "krita-unwrapped";

  version = "6.0.4.1";
  src = fetchurl {
    url = "mirror://kde/stable/krita/${finalAttrs.version}/krita-${finalAttrs.version}.tar.gz";
    hash = "sha256-6v8AUhlYUDqh0+8SBtdeALV+1lmT6VNonwoEhQQn4tg=";
  };

  nativeBuildInputs = [
    cmake
    kdePackages'.extra-cmake-modules
    pkg-config
    python3Packages.sip
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    boost
    libraw
    fftw
    eigen_5
    exiv2
    fribidi
    lcms2
    gsl
    openexr
    lager
    libaom
    libheif

    giflib
    libjxl
    openjpeg
    opencolorio
    xsimd
    curl
    immer
    kseexpr'
    libmypaint
    libunibreak
    libwebp
    SDL2
    zug
    python3Packages.pyqt6

    qt6.qtmultimedia
    qt6.qttools
  ]
  ++ (with kdePackages'; [
    breeze-icons
    karchive
    kcompletion
    kconfig
    kcoreaddons
    kcrash
    kguiaddons
    ki18n
    kio
    kitemmodels
    kitemviews
    kwidgetsaddons
    kwindowsystem
    mlt
    poppler
    quazip
    libkdcraw
  ]);

  # Krita runs custom python scripts in CMake with custom PYTHONPATH which krita determined in their CMake script.
  # Patch the PYTHONPATH so python scripts can import sip successfully.
  postPatch =
    let
      pythonPath = python3Packages.makePythonPath (
        with python3Packages;
        [
          sip
          setuptools
        ]
      );
    in
    ''
      substituteInPlace cmake/modules/FindSIP.cmake \
        --replace 'PYTHONPATH=''${_sip_python_path}' 'PYTHONPATH=${pythonPath}'
      substituteInPlace cmake/modules/SIPMacros.cmake \
        --replace 'PYTHONPATH=''${_krita_python_path}' 'PYTHONPATH=${pythonPath}'

      substituteInPlace plugins/impex/jp2/jp2_converter.cc \
        --replace '<openjpeg.h>' '<${openjpeg.incDir}/openjpeg.h>'
    '';

  patches = [
    (fetchpatch {
      # Update SIP ABI to 13.8
      url = "https://invent.kde.org/graphics/krita/-/commit/30182dbfe789c9b44e5762978bf9ebb22c4f72b6.patch";
      hash = "sha256-IZNaRmDYnj7M+7gg3fqHrhI+t5fgE6/ecxWW6slvX4g=";
    })
    (fetchpatch {
      # qt 6.12 support
      # Fix invalid widget class name
      url = "https://invent.kde.org/graphics/krita/-/commit/3f5b2882017f4e12c9b021de0ea24e6dd2eb26dd.patch";
      hash = "sha256-Oq/ojwTYt2bmXQm0UuIVCIN+7PVgTO1WGbcFUnDDFIA=";
    })
  ]
  ++ lib.optionals isDarwin [
    # The Finder integration plugins use xcodebuild archive, which cannot run
    # in the Nix build sandbox.
    ./krita-skip-macos-integration.patch
    # Nix's Qt forwarding headers do not expose QMutex through <qmutex.h>.
    ./krita-qt6-macos-qmutex.patch
  ];

  cmakeBuildType = "RelWithDebInfo";

  cmakeFlags = [
    "-DBUILD_WITH_QT6=ON"
    "-DALLOW_UNSTABLE=QT6"
    "-DENABLE_UPDATERS=OFF"
    "-DBUILD_KRITA_QT_DESIGNER_PLUGINS=ON"
  ]
  ++ lib.optional isDarwin "-DKRITA_SKIP_MACOS_INTEGRATION=ON";

  meta = {
    description = "Free and open source painting application";
    homepage = "https://krita.org/";
    maintainers = with lib.maintainers; [
      sifmelcara
    ];
    mainProgram = "krita";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    license = lib.licenses.gpl3Only;
  };
})
