#!/bin/bash
# Generate a secure random token for authentication

TOKEN=$(openssl rand -base64 32)
echo "Generated token:"
echo "$TOKEN"
echo ""
echo "Add to your environment:"
echo "export FLOWGATE_TOKEN=\"$TOKEN\""
echo ""
echo "Add to your shell profile (~/.bashrc, ~/.zshrc):"
echo "echo 'export FLOWGATE_TOKEN=\"$TOKEN\"' >> ~/.zshrc"
