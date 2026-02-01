#!/bin/bash
# Install Cursor CLI agent on a Linux VPS (run as root over SSH)
# Usage: curl -fsS https://cursor.com/install | bash  (or run this script after copying)

set -e

echo "==> Installing Cursor CLI..."
curl https://cursor.com/install -fsSL | bash

# Add to PATH (root uses /root)
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

echo ""
echo "==> Verifying..."
"$HOME/.local/bin/agent" --version || true

echo ""
echo "==> Next steps (run these on the VPS):"
echo "  1. Get your Cursor API key: https://cursor.com/dashboard → Background Agents / API"
echo "  2. Set it: export CURSOR_API_KEY=your_api_key_here"
echo "  3. Or persist: echo 'export CURSOR_API_KEY=your_key' >> ~/.bashrc"
echo "  4. Test: agent -p 'list files in this directory'"
echo ""
echo "  For Cursor IDE to use this over SSH tunnel, connect via Remote-SSH;"
echo "  the agent binary will be available in the remote environment."
