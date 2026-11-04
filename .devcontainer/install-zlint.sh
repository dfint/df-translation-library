#!/usr/bin/env bash
set -euo pipefail

case "$(uname -m)" in
  x86_64) asset_arch=x86_64 ;;
  aarch64|arm64) asset_arch=aarch64 ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

temp_file="$(mktemp)"
trap 'rm -f "$temp_file"' EXIT

curl -fsSL "https://github.com/DonIsaac/zlint/releases/download/v0.10.0/zlint-linux-${asset_arch}" -o "$temp_file"
install -m 0755 "$temp_file" /usr/local/bin/zlint