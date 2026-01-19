#!/bin/bash
# Fix keyfile permissions for MongoDB
# This script copies the keyfile to a location inside the container and sets proper permissions

if [ -f /keyfile-source ]; then
    echo "Copying keyfile and setting permissions..."
    cp /keyfile-source /tmp/keyfile
    chmod 400 /tmp/keyfile
    chown mongodb:mongodb /tmp/keyfile
    echo "Keyfile permissions fixed"
else
    echo "Warning: keyfile-source not found"
fi

# Call the original docker entrypoint with all arguments
exec python3 /usr/local/bin/docker-entrypoint.py "$@"
