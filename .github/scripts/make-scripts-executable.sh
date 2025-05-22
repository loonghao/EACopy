#!/bin/bash
# Script to make all scripts in .github/scripts executable

echo "Making scripts executable..."

# Find all script files and make them executable
find .github/scripts -type f \( -name "*.sh" -o -name "*.ps1" \) -exec chmod +x {} \;

echo "✅ All scripts are now executable"

# List the scripts for verification
echo "Scripts found:"
find .github/scripts -type f \( -name "*.sh" -o -name "*.ps1" \) -exec ls -la {} \;
