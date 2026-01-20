#!/bin/bash

# XPR Network Developer Skill Installer for Claude Code
# This script helps install the skill into your Claude Code environment

set -e

SKILL_NAME="xpr-network-dev"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$SCRIPT_DIR/skill"
CLAUDE_SETTINGS_DIR="$HOME/.claude"
CLAUDE_SETTINGS_FILE="$CLAUDE_SETTINGS_DIR/settings.json"

echo "XPR Network Developer Skill Installer"
echo "======================================"
echo ""

# Check if skill directory exists
if [ ! -d "$SKILL_DIR" ]; then
    echo "Error: skill directory not found at $SKILL_DIR"
    exit 1
fi

# Check if jq is available for JSON manipulation
if ! command -v jq &> /dev/null; then
    echo "Note: jq is not installed. Manual installation required."
    echo ""
    echo "To install manually, add this to your Claude Code settings:"
    echo ""
    echo "  File: $CLAUDE_SETTINGS_FILE"
    echo ""
    echo '  {'
    echo '    "skills": ['
    echo '      {'
    echo "        \"name\": \"$SKILL_NAME\","
    echo "        \"path\": \"$SKILL_DIR\""
    echo '      }'
    echo '    ]'
    echo '  }'
    echo ""
    exit 0
fi

# Create settings directory if it doesn't exist
if [ ! -d "$CLAUDE_SETTINGS_DIR" ]; then
    echo "Creating Claude settings directory..."
    mkdir -p "$CLAUDE_SETTINGS_DIR"
fi

# Create or update settings file
if [ ! -f "$CLAUDE_SETTINGS_FILE" ]; then
    echo "Creating new settings file..."
    echo '{
  "skills": [
    {
      "name": "'"$SKILL_NAME"'",
      "path": "'"$SKILL_DIR"'"
    }
  ]
}' > "$CLAUDE_SETTINGS_FILE"
    echo "Created $CLAUDE_SETTINGS_FILE"
else
    echo "Updating existing settings file..."

    # Check if skill already exists
    if jq -e ".skills[] | select(.name == \"$SKILL_NAME\")" "$CLAUDE_SETTINGS_FILE" > /dev/null 2>&1; then
        echo "Skill '$SKILL_NAME' already installed. Updating path..."
        jq "(.skills[] | select(.name == \"$SKILL_NAME\")).path = \"$SKILL_DIR\"" "$CLAUDE_SETTINGS_FILE" > "$CLAUDE_SETTINGS_FILE.tmp"
        mv "$CLAUDE_SETTINGS_FILE.tmp" "$CLAUDE_SETTINGS_FILE"
    else
        # Add skill to existing array or create skills array
        if jq -e ".skills" "$CLAUDE_SETTINGS_FILE" > /dev/null 2>&1; then
            jq ".skills += [{\"name\": \"$SKILL_NAME\", \"path\": \"$SKILL_DIR\"}]" "$CLAUDE_SETTINGS_FILE" > "$CLAUDE_SETTINGS_FILE.tmp"
        else
            jq ". + {\"skills\": [{\"name\": \"$SKILL_NAME\", \"path\": \"$SKILL_DIR\"}]}" "$CLAUDE_SETTINGS_FILE" > "$CLAUDE_SETTINGS_FILE.tmp"
        fi
        mv "$CLAUDE_SETTINGS_FILE.tmp" "$CLAUDE_SETTINGS_FILE"
    fi
    echo "Updated $CLAUDE_SETTINGS_FILE"
fi

echo ""
echo "Installation complete!"
echo ""
echo "The XPR Network Developer Skill is now available in Claude Code."
echo ""
echo "Skill location: $SKILL_DIR"
echo ""
echo "Try asking Claude:"
echo "  - How do I deploy a smart contract on XPR Network?"
echo "  - Query a table using proton CLI"
echo "  - Create a token transfer action"
echo ""
