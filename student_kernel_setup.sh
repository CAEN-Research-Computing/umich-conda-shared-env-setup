#!/bin/bash

# Student setup script: creates symlinks for Turbo and Jupyter kernel

set -euo pipefail

CONFIG_FILE="env.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file $CONFIG_FILE not found."
    exit 1
fi
source "$CONFIG_FILE"

# Derived paths
ENV_DIR="$TURBO_DIR/envs/$KERNEL_NAME"
KERNEL_DIR="$TURBO_DIR/envs/shared_jupyter_kernels"
KERNEL_SPEC_DIR="$KERNEL_DIR/share/jupyter/kernels/$KERNEL_NAME"

# 1. Link Turbo share in home (named after KERNEL_NAME for clarity)
TURBO_LINK="$HOME/$KERNEL_NAME"
if [ ! -e "$TURBO_LINK" ]; then
    ln -s "$TURBO_DIR" "$TURBO_LINK"
    echo "Linked $TURBO_DIR to $TURBO_LINK"
fi

# 2. Ensure user kernel directory exists
USER_KERNELS_DIR="$HOME/.local/share/jupyter/kernels"
mkdir -p "$USER_KERNELS_DIR"

# 3. Symlink the kernelspec so Jupyter sees it
KERNEL_SYMLINK="$USER_KERNELS_DIR/$KERNEL_NAME"
if [ ! -e "$KERNEL_SYMLINK" ]; then
    if [ -d "$KERNEL_SPEC_DIR" ]; then
        ln -s "$KERNEL_SPEC_DIR" "$KERNEL_SYMLINK"
        echo "Kernel linked as $KERNEL_SYMLINK"
    else
        echo "ERROR: Shared kernel spec directory $KERNEL_SPEC_DIR does not exist."
        echo "Contact your instructor or try again later."
        exit 2
    fi
else
    echo "Kernel already linked at $KERNEL_SYMLINK"
fi

echo "✔️ Setup complete. Restart your Jupyter Notebook/Lab and select '$DISPLAY_NAME' kernel."
