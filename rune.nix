{ 
  lib
, stdenv
, fetchzip
, flutter324
, protobuf_26
, protoc-gen-prost
, makeDesktopItem
, cargo
, rustPlatform
, rustc
, targetFlutterPlatform ? "linux"
, buildDartApplication
}:

let
  pubspecLock = lib.importJSON ./pubspec.lock.json;

  protoc-gen-dart = buildDartApplication rec {
    pname = "protoc-gen-dart";
    version = "21.1.2";

    src = fetchzip {
      url = "https://github.com/google/protobuf.dart/archive/refs/tags/protoc_plugin-v21.1.2.tar.gz";
      sha256 = "sha256-luptbRgOtOBapWmyIJ35GqOClpcmDuKSPu3QoDfp2FU=";
    };
    sourceRoot = "${src.name}/protoc_plugin";

    pubspecLock = lib.importJSON ./pubspec.protoc.lock.json;

    meta = with lib; {
      description = "Protobuf plugin for generating Dart code";
      mainProgram = "protoc-gen-dart";
      homepage = "https://pub.dev/packages/protoc_plugin";
      license = licenses.bsd3;
    };
  };
in
flutter324.buildFlutterApplication (rec {
  pname = "rune-${targetFlutterPlatform}";
  version = "1.20.0";

  src = fetchzip {
    url = "https://github.com/Losses/rune/archive/refs/tags/v0.0.0-dev.5.tar.gz";
    sha256 = "sha256-9eYVgIfCbU2aWp3INPLNWr21fvsKAR2w794iARKY23g=";
  };

  gitHashes = {
    fluent_ui = "sha256-87wJgWP4DGsVOxc4PhCMDg+ro9faHKZXy2LQtFqbmso=";
  };

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
  };

  inherit pubspecLock;

  inherit targetFlutterPlatform;

  meta = with lib; {
    description = "Experience timeless melodies with a music player that blends classic design with modern technology.";
    homepage = "https://github.com/losses/rune";
    license = licenses.mpl20;
    mainProgram = "player";
    maintainers = with maintainers; [ losses ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ sourceTypes.fromSource ];
  };
} // lib.optionalAttrs (targetFlutterPlatform == "linux") {
  nativeBuildInputs = [ protobuf_26 protoc-gen-prost protoc-gen-dart ]; # , imagemagick

  # runtimeDependencies = [ pulseaudio ];

  # extraWrapProgramArgs = "--prefix PATH : ${zenity}/bin";

  desktopItem = makeDesktopItem {
    name = "Rune";
    exec = "player";
    icon = "rune";
    desktopName = "Rune";
    genericName = "Player your favorite music";
    categories = ["Audio"];
  };

  preBuild = ''
    echo =================================
    echo GENERATING PROTOBUF CODE
    echo =================================
    packageRun rinf message

  '';
})

  # postInstall = ''
  #   FAV=$out/app/data/flutter_assets/assets/favicon.png
  #   ICO=$out/share/icons

  #   install -D $FAV $ICO/fluffychat.png
  #   mkdir $out/share/applications
  #   cp $desktopItem/share/applications/*.desktop $out/share/applications
  #   for size in 24 32 42 64 128 256 512; do
  #     D=$ICO/hicolor/''${s}x''${s}/apps
  #     mkdir -p $D
  #     convert $FAV -resize ''${size}x''${size} $D/fluffychat.png
  #   done

  #   patchelf --add-rpath ${libwebrtcRpath} $out/app/lib/libwebrtc.so
  # '';