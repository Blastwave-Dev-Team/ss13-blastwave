#!/bin/bash
# Regenerates Rachnidian random name lists consumed by
# modular_nova/modules/customization/_globalvars/names.dm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMES_DIR="${SCRIPT_DIR}/../strings/names"

node "${SCRIPT_DIR}/rachnidnames.js" > "${NAMES_DIR}/rachnid_first.txt"
node "${SCRIPT_DIR}/rachnidnames.js" > "${NAMES_DIR}/rachnid_last.txt"
