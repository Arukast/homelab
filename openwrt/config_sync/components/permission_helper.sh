#!/bin/sh

check_permission() {
    if [ -f "$SSH_KEY_PATH" ]; then
        perms=$(ls -ld "$SSH_KEY_PATH" | cut -c 2-4)
        if [ "$perms" != "rw-" ] && [ "$perms" != "r--" ]; then
            echo "Warning: SSH key permissions are too open. Setting to 600..."
            chmod 600 "$SSH_KEY_PATH" 2>/dev/null
        fi
    else
        echo "Error: SSH key not found at $SSH_KEY_PATH." >&2
        exit 1
    fi
}
