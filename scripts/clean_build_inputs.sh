#!/bin/zsh
# Move build output that landed inside the project folder out of the way.
#
# Xcode treats a DerivedData tree inside the package root as a package target
# ("xcode-derived" makes SwiftPM look for Sources/xcode-derived), and the SwiftPM
# binary artifact directory inside it as an artifact to download. Either one can
# fail a build with:
#
#   Assets.xcassets: error: Failed to write Swift generated asset symbols.
#       Failure Reason: Operation not permitted
#   Command Ld failed with a nonzero exit code
#
# This script relocates those trees to ~/Library/Developer/Xcode/DerivedData and
# is safe to run any number of times.
set -euo pipefail
setopt NULL_GLOB

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STASH="$HOME/Library/Developer/Xcode/DerivedData"

moved=0
relocate() {
    local relative="$1" name="$2"
    local source="$ROOT/$relative"
    [[ -e "$source" ]] || return 0

    local destination="$STASH/$name"
    [[ -e "$destination" ]] && destination="$destination-$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$STASH"
    mv "$source" "$destination"
    echo "moved: $relative -> $destination"
    moved=$((moved + 1))
}

# DerivedData trees written into the project (see README "Build & Run").
relocate ".build/xcode-derived" "IrisEditor-build"
relocate "build" "IrisEditor-build-2"

# SwiftPM workspace state left in a relocated DerivedData tree. Its
# "artifacts" section makes the build try to download a binary artifact
# named after the target and fail; this package has no artifact that needs it.
for state in "$STASH"/IrisEditor-build/Build/Intermediates.noindex/XCBuildData/*.xcbuilddata/swiftpm_workspace_state.json; do
    [[ -f "$state" ]] || continue
    if grep -q '"artifacts" *: *\[ *{' "$state" 2>/dev/null; then
        mv "$state" "$state.disabled"
        echo "disabled artifact state: $state"
        moved=$((moved + 1))
    fi
done

if [[ $moved -eq 0 ]]; then
    echo "clean: no build output inside the project folder"
fi
