#!/bin/bash
set -e

echo "MongoDB Community Search - Setup Script"
echo "========================================"

# Generate keyfile if it doesn't exist
if [ ! -f keyfile ]; then
    echo "Generating keyfile..."
    openssl rand -base64 756 > keyfile
    chmod 400 keyfile
    echo "✓ Keyfile generated successfully"
else
    echo "✓ Keyfile already exists"
fi

# Create password file
MONGOT_PASSWORD="${MONGOT_PASSWORD:-mongotPassword}"
echo "Creating password file..."
echo -n "$MONGOT_PASSWORD" > passwordFile
chmod 600 passwordFile
echo "✓ Password file created successfully"

echo ""
echo "Setup complete! You can now run:"
echo "  docker-compose up mongod mongot -d"
echo ""
echo "Alternatively, run the full stack with:"
echo "  ./start-monitoring.sh"