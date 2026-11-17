#!/bin/bash
set -euo pipefail
APP="${1:-dist/OrbSweep.app}"
codesign --verify --deep --strict "$APP"
architectures=$(lipo -archs "$APP/Contents/MacOS/OrbSweep")
echo "Verified architectures: $architectures"
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    for architecture in arm64 x86_64; do
        case " $architectures " in
            *" $architecture "*) ;;
            *) echo "Missing architecture: $architecture" >&2; exit 1 ;;
        esac
    done
fi
