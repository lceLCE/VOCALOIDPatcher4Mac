#!/bin/zsh
set -eu
cd -- "${0:A:h}"
check_build="$PWD/.check-build"
mkdir -p "$check_build"
xcrun clang -fobjc-arc -Wall -Wextra -Werror check_jobs.m -framework AppKit -o "$check_build/jobs"
xcrun clang -fobjc-arc -Wall -Wextra -Werror check_spectrum.m -framework AppKit -framework AudioUnit -framework Accelerate -o "$check_build/spectrum"
xcrun clang -fobjc-arc -Wall -Wextra -Werror check_render_settings.m -framework AppKit -framework AVFoundation -framework QuartzCore -framework CoreMedia -framework UniformTypeIdentifiers -o "$check_build/rendering"
xcrun clang -fobjc-arc -Wall -Wextra -Werror check_render_visibility.m -framework AppKit -framework AVFoundation -framework QuartzCore -framework CoreMedia -framework UniformTypeIdentifiers -o "$check_build/visibility"
xcrun clang -fobjc-arc -Wall -Wextra -Werror check_native_options.m -framework AppKit -framework CoreGraphics -framework QuartzCore -o "$check_build/native-options"
xcrun clang -fobjc-arc -Wall -Wextra -Werror conversion/check-import-options.m -framework AppKit -o "$check_build/import-options"
xcrun clang -Wall -Wextra -Werror check_dyld.c -o "$check_build/dyld"
"$check_build/jobs"
"$check_build/spectrum"
"$check_build/rendering" "$check_build/render-settings.plist"
"$check_build/native-options"
"$check_build/visibility"
"$check_build/import-options"
DYLD_INSERT_LIBRARIES="$PWD/VOCALOIDPatcher.dylib" "$check_build/dyld"
conversion/.venv/bin/python conversion/check.py

conversion/.venv/bin/python check_install.py
