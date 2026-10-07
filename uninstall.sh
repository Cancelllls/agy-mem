#!/usr/bin/env bash
# ==============================================================================
# agy-mem Uninstaller
# ==============================================================================

set -e

INSTALL_DIR="${HOME}/.local/bin"
TARGET="${INSTALL_DIR}/agy-mem"
SKILLS_DIR="${HOME}/.agent/skills"
MCP_CONFIG="${HOME}/.gemini/config/mcp_config.json"
MCP_SCHEMA_DIR="${HOME}/.gemini/antigravity-cli/mcp/agy-mem"
DB_PATH="${HOME}/.gemini/antigravity-cli/memory.db"

echo "Uninstalling agy-mem..."

# 1. Remove binary
if [ -f "${TARGET}" ]; then
    rm -f "${TARGET}"
    echo "✓ Removed ${TARGET}"
fi

# 2. Remove skills
rm -rf "${SKILLS_DIR}/recall" "${SKILLS_DIR}/mem"
echo "✓ Removed skills /recall and /mem"

# 3. Remove MCP config entry
if [ -f "${MCP_CONFIG}" ]; then
    python3 - <<EOF
import json, os
path = os.path.expanduser("${MCP_CONFIG}")
if os.path.exists(path):
    try:
        with open(path, "r") as f:
            data = json.load(f)
        if "mcpServers" in data and "agy-mem" in data["mcpServers"]:
            del data["mcpServers"]["agy-mem"]
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
            print("✓ Removed agy-mem from mcp_config.json")
    except Exception:
        pass
EOF
fi

# 4. Remove cached schemas
rm -rf "${MCP_SCHEMA_DIR}"

echo ""
echo "agy-mem uninstalled successfully."
echo "Note: The database at ${DB_PATH} was kept. Run 'rm ${DB_PATH}' if you wish to delete stored memory."
