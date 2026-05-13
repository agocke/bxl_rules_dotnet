#!/usr/bin/env bash
# Run the bxl_rules_dotnet DScript test suite.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
REQUIRED_BXL_VERSION="0.2.0-ci.5.b2e4b6e"

case "$(uname -s)" in
    Linux*)   ARCH_DIR="linux-x64" ;;
    Darwin*)  ARCH_DIR="osx-x64"   ;;
    MINGW*|MSYS*|CYGWIN*) ARCH_DIR="win-x64" ;;
    *) echo "ERROR: unsupported host OS: $(uname -s)" >&2; exit 1 ;;
esac

INSTALL_CMD="dotnet tool install -g agtest.bxl.tool --version $REQUIRED_BXL_VERSION"
BXL_CMD=""
BXL_BIN_HINT=""

if [[ -d "$HOME/.dotnet/tools/.store/agtest.bxl.tool/$REQUIRED_BXL_VERSION" ]]; then
    while IFS= read -r candidate; do
        if [[ -d "$candidate/Sdk/Sdk.Transformers" && -x "$candidate/bxl" ]]; then
            BXL_BIN_HINT="$candidate"
            BXL_CMD="$candidate/bxl"
            break
        fi
    done < <(find "$HOME/.dotnet/tools/.store/agtest.bxl.tool/$REQUIRED_BXL_VERSION" -type d -path "*/tools/net*/$ARCH_DIR" 2>/dev/null)
fi

if [[ -z "$BXL_CMD" ]]; then
    BXL_SHIM="$(command -v bxl || true)"
    if [[ -z "$BXL_SHIM" ]]; then
        echo "ERROR: could not find 'bxl' on PATH." >&2
        echo "Install bxl: $INSTALL_CMD" >&2
        exit 1
    fi

    BXL_CMD="$BXL_SHIM"
    BXL_BIN_HINT="$(dirname "$(realpath "$BXL_SHIM")")"
    if [[ ! -d "$BXL_BIN_HINT/Sdk/Sdk.Transformers" ]]; then
        for store_root in "$BXL_BIN_HINT/.store" "$HOME/.dotnet/tools/.store"; do
            if [[ ! -d "$store_root" ]]; then
                continue
            fi

            while IFS= read -r candidate; do
                if [[ -d "$candidate/Sdk/Sdk.Transformers" ]]; then
                    BXL_BIN_HINT="$candidate"
                    break 2
                fi
            done < <(find "$store_root" -type d -path "*/tools/net*/$ARCH_DIR" 2>/dev/null)
        done
    fi
fi

if [[ ! -d "$BXL_BIN_HINT/Sdk/Sdk.Transformers" ]]; then
    echo "ERROR: could not locate the bxl SDK directory (looked under $BXL_BIN_HINT)." >&2
    echo "Install bxl: $INSTALL_CMD" >&2
    exit 1
fi

export BUILDXL_BIN="$BXL_BIN_HINT"

echo "BUILDXL_BIN = $BUILDXL_BIN"

CONFIG_FILE="config.dsc"

echo "Running bxl on $REPO_ROOT/$CONFIG_FILE ..."

cd "$REPO_ROOT"
"$BXL_CMD" /c:"$CONFIG_FILE" /phase:Schedule /sandboxKind:None /enableLinuxEBPFSandbox- "$@"
