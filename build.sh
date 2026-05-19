#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-dev}"

case "$MODE" in
    dev)
        odin build src/ -out:kine -debug -strict-style -vet
        ;;
    release)
        odin build src/ -out:kine -o:speed -no-bounds-check
        ;;
    run)
        odin build src/ -out:kine -debug -strict-style -vet && ./kine "${@:2}"
        ;;
    *)
        echo "Usage: $0 [dev|release|run]"
        exit 1
        ;;
esac
