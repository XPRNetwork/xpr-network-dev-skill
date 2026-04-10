#!/bin/bash

# XPR Network Developer Skill Installer for Claude Code
# This script installs the skill by creating a symlink in ~/.claude/skills/

set -e

SKILL_NAME="xpr-network-dev"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$SCRIPT_DIR/skill"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
SKILL_LINK="$CLAUDE_SKILLS_DIR/$SKILL_NAME"

echo "XPR Network Developer Skill Installer"
echo "======================================"
echo ""

# Check if skill directory exists
if [ ! -d "$SKILL_DIR" ]; then
    echo "Error: skill directory not found at $SKILL_DIR"
    exit 1
fi

# Check if SKILL.md exists
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
    echo "Error: SKILL.md not found at $SKILL_DIR/SKILL.md"
    exit 1
fi

# Create ~/.claude/skills/ directory if it doesn't exist
if [ ! -d "$CLAUDE_SKILLS_DIR" ]; then
    echo "Creating $CLAUDE_SKILLS_DIR ..."
    mkdir -p "$CLAUDE_SKILLS_DIR"
fi

# Handle existing installation
if [ -e "$SKILL_LINK" ] || [ -L "$SKILL_LINK" ]; then
    if [ -L "$SKILL_LINK" ]; then
        EXISTING_TARGET="$(readlink "$SKILL_LINK")"
        if [ "$EXISTING_TARGET" = "$SKILL_DIR" ]; then
            echo "Skill '$SKILL_NAME' is already installed and up to date."
            echo ""
            echo "Skill location: $SKILL_DIR"
            echo "Symlink: $SKILL_LINK -> $SKILL_DIR"
            echo ""
            echo "To update the skill content, run: git pull"
            exit 0
        fi
        echo "Updating existing symlink (was pointing to $EXISTING_TARGET)..."
        rm "$SKILL_LINK"
    else
        echo "Error: $SKILL_LINK already exists and is not a symlink."
        echo "Remove it manually and re-run this installer."
        exit 1
    fi
fi

# Create symlink
ln -s "$SKILL_DIR" "$SKILL_LINK"

echo "Installation complete!"
echo ""
echo "Skill '$SKILL_NAME' is now available in Claude Code."
echo "Symlink: $SKILL_LINK -> $SKILL_DIR"
echo ""
echo "Usage:"
echo "  - Invoke directly:      /xpr-network-dev"
echo "  - Claude auto-invokes when relevant to XPR Network development"
echo ""
echo "To update the skill content in the future, run:"
echo "  git pull   (inside the xpr-network-dev-skill directory)"
echo ""
echo "Try asking Claude:"
echo "  - How do I deploy a smart contract on XPR Network?"
echo "  - Query a table using proton CLI"
echo "  - Create a token transfer action"
echo ""
