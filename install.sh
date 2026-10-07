#!/usr/bin/env bash
# ==============================================================================
# agy-mem Installer: Autonomous Memory Engine for Google Antigravity (agy)
# ==============================================================================

set -e

# ANSI Colors
CYAN="\033[38;2;20;184;166m"
GOLD="\033[38;2;229;193;88m"
GREEN="\033[38;2;34;197;94m"
GRAY="\033[38;2;100;116;139m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "\n${BOLD}${GOLD}🧠 Installing agy-mem (Antigravity Memory Engine)...${RESET}\n"

# 1. Check Python 3
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${GRAY}Error: python3 is required but not installed.${RESET}"
    exit 1
fi

# 2. Check SQLite FTS5 support
if ! python3 -c "import sqlite3; conn = sqlite3.connect(':memory:'); conn.execute('CREATE VIRTUAL TABLE t USING fts5(c);')" >/dev/null 2>&1; then
    echo -e "${GRAY}Error: Python's sqlite3 module does not have FTS5 enabled.${RESET}"
    exit 1
fi

# 3. Target Install Path
INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "${INSTALL_DIR}"
TARGET="${INSTALL_DIR}/agy-mem"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/bin/agy-mem" ]; then
    cp "${SCRIPT_DIR}/bin/agy-mem" "${TARGET}"
else
    # Fallback to downloading directly if run via curl | bash
    curl -sSL "https://raw.githubusercontent.com/Cancellls/agy-mem/main/bin/agy-mem" -o "${TARGET}"
fi

chmod +x "${TARGET}"
echo -e "  ${GREEN}✓${RESET} Installed executable: ${BOLD}${TARGET}${RESET}"

# 4. Install Antigravity Skills (/recall & /mem)
SKILLS_DIR="${HOME}/.agent/skills"
mkdir -p "${SKILLS_DIR}/recall" "${SKILLS_DIR}/mem"

if [ -d "${SCRIPT_DIR}/skills" ]; then
    cp "${SCRIPT_DIR}/skills/recall/SKILL.md" "${SKILLS_DIR}/recall/SKILL.md"
    cp "${SCRIPT_DIR}/skills/mem/SKILL.md" "${SKILLS_DIR}/mem/SKILL.md"
else
    curl -sSL "https://raw.githubusercontent.com/Cancellls/agy-mem/main/skills/recall/SKILL.md" -o "${SKILLS_DIR}/recall/SKILL.md"
    curl -sSL "https://raw.githubusercontent.com/Cancellls/agy-mem/main/skills/mem/SKILL.md" -o "${SKILLS_DIR}/mem/SKILL.md"
fi
echo -e "  ${GREEN}✓${RESET} Registered skills: ${BOLD}/recall${RESET} and ${BOLD}/mem${RESET} in ${SKILLS_DIR}"

# 5. Register MCP Server in ~/.gemini/config/mcp_config.json
MCP_CONFIG="${HOME}/.gemini/config/mcp_config.json"
mkdir -p "$(dirname "${MCP_CONFIG}")"

python3 - <<EOF
import json, os

config_path = os.path.expanduser("${MCP_CONFIG}")
target_bin = os.path.expanduser("${TARGET}")

data = {"mcpServers": {}}
if os.path.exists(config_path):
    try:
        with open(config_path, "r") as f:
            data = json.load(f)
    except Exception:
        pass

if "mcpServers" not in data:
    data["mcpServers"] = {}

data["mcpServers"]["agy-mem"] = {
    "command": target_bin,
    "args": ["mcp"]
}

with open(config_path, "w") as f:
    json.dump(data, f, indent=2)
EOF

echo -e "  ${GREEN}✓${RESET} Registered MCP Server in: ${BOLD}${MCP_CONFIG}${RESET}"

# 6. Generate cached MCP schemas for Antigravity
MCP_SCHEMA_DIR="${HOME}/.gemini/antigravity-cli/mcp/agy-mem"
mkdir -p "${MCP_SCHEMA_DIR}"

python3 - <<EOF
import os, json

mcp_dir = os.path.expanduser("${MCP_SCHEMA_DIR}")
tools = [
    {
        "name": "search",
        "description": "Search memory observations using full-text search with BM25 ranking.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query keywords or phrase"},
                "project": {"type": "string", "description": "Filter by project name"},
                "type": {"type": "string", "description": "Filter by observation type"},
                "limit": {"type": "number", "description": "Maximum number of results (default: 10)"}
            },
            "required": ["query"]
        }
    },
    {
        "name": "get_observations",
        "description": "Fetch full details for observation IDs returned by search.",
        "parameters": {
            "type": "object",
            "properties": {
                "ids": {"type": "array", "items": {"type": "integer"}, "description": "List of observation IDs"}
            },
            "required": ["ids"]
        }
    },
    {
        "name": "recall",
        "description": "High-level contextual memory retrieval formatted as markdown for agent prompt reasoning.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Topic or concept to recall"},
                "project": {"type": "string", "description": "Filter by project name"},
                "limit": {"type": "number", "description": "Number of memory items to return (default: 5)"}
            },
            "required": ["query"]
        }
    },
    {
        "name": "timeline",
        "description": "Get chronological timeline of historical milestones, decisions, and bugfixes.",
        "parameters": {
            "type": "object",
            "properties": {
                "project": {"type": "string", "description": "Filter by project name"},
                "limit": {"type": "number", "description": "Number of timeline events (default: 15)"}
            }
        }
    },
    {
        "name": "add_observation",
        "description": "Store a new architectural decision, bugfix, or user preference into memory.",
        "parameters": {
            "type": "object",
            "properties": {
                "project": {"type": "string", "description": "Project name"},
                "type": {"type": "string", "enum": ["architecture", "bugfix", "feature", "preference", "pattern"], "description": "Observation category"},
                "title": {"type": "string", "description": "Short, clear title"},
                "narrative": {"type": "string", "description": "Detailed description"},
                "facts": {"type": "string", "description": "Key bullet points"},
                "concepts": {"type": "string", "description": "Comma-separated concept tags"}
            },
            "required": ["project", "type", "title", "narrative"]
        }
    },
    {
        "name": "sync",
        "description": "Trigger an incremental sync to extract newly created observations.",
        "parameters": {
            "type": "object",
            "properties": {
                "full": {"type": "boolean", "description": "Force full rescan instead of incremental"}
            }
        }
    }
]

for t in tools:
    with open(os.path.join(mcp_dir, f"{t['name']}.json"), "w") as f:
        json.dump(t, f, indent=2)
EOF

echo -e "  ${GREEN}✓${RESET} Generated cached MCP tool schemas in ${MCP_SCHEMA_DIR}"

# 7. Run initial sync
echo -e "\n${CYAN}Running initial sync to backfill historical memory...${RESET}"
"${TARGET}" sync >/dev/null 2>&1 || true

# 8. Check PATH
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo -e "\n${GOLD}Notice:${RESET} ${INSTALL_DIR} is not in your PATH."
    echo -e "Add it to your shell configuration file (e.g. ~/.bashrc or ~/.zshrc):"
    echo -e "  export PATH=\"${INSTALL_DIR}:\$PATH\"\n"
fi

echo -e "${GREEN}${BOLD}✓ Installation Complete!${RESET}"
echo -e "\n${BOLD}Quick Start:${RESET}"
echo -e "  ${CYAN}agy-mem search \"<query>\"${RESET}     Search past decisions and bugfixes"
echo -e "  ${CYAN}agy-mem timeline${RESET}             View chronological project milestones"
echo -e "  ${CYAN}agy-mem status${RESET}               Show memory engine statistics"
echo -e "  In agy prompt: ${BOLD}/recall <topic>${RESET} or ${BOLD}/mem${RESET}\n"
