#!/bin/bash
set -e

PLUGIN_FILE="sourcecord.sp"

if [ ! -f "$PLUGIN_FILE" ]; then
    echo "Error: Plugin file '$PLUGIN_FILE' not found!"
    exit 1
fi

VERSION=$(grep -oP '#define PLUGIN_VERSION "\K[^"]+' "$PLUGIN_FILE")

if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from $PLUGIN_FILE"
    echo "Make sure the file contains: #define PLUGIN_VERSION \"x.x.x\""
    exit 1
fi

echo "Found version: $VERSION"

if [[ $VERSION =~ ^[0-9]+\.[0-9]+.*$ ]]; then
    echo "Version format appears valid"
else
    echo "Warning: Version format may be invalid: $VERSION"
fi

if [ "$1" = "--github-output" ]; then
    echo "version=$VERSION" >> $GITHUB_OUTPUT
fi

echo "$VERSION"