#!/bin/zsh
set -eu
cd -- "${0:A:h}"
xcrun clang -dynamiclib -arch arm64 -mmacosx-version-min=15.0 -fobjc-arc -Wall -Wextra -Werror \
  Patcher.m Rendering.m Spectrum.m FormatBridge.m NativeOptions.m \
  -framework AppKit -framework AVFoundation -framework QuartzCore \
  -framework CoreMedia -framework UniformTypeIdentifiers -framework AudioUnit -framework Accelerate \
  -o VOCALOIDPatcher.dylib
mkdir -p 'VOCALOID7 Patcher.app/Contents/MacOS'
xcrun clang -arch arm64 -mmacosx-version-min=15.0 -fobjc-arc -Wall -Wextra -Werror \
  Launcher.m -framework AppKit -o 'VOCALOID7 Patcher.app/Contents/MacOS/Launcher'
cp Launcher-Info.plist 'VOCALOID7 Patcher.app/Contents/Info.plist'
