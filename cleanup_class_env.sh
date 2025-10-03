#!/bin/bash

# Instructor cleanup script for shared conda/mamba environment & kernel

set -euo pipefail

CONFIG_FILE="env.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file $CONFIG_FILE not found."
    exit 1
fi
source "$CONFIG_FILE"

ENV_DIR="$TURBO_DIR/envs/$KERNEL_NAME"
KERNEL_DIR="$TURBO_DIR/shared_jupyter_kernels"
KERNEL_SPEC_DIR="$KERNEL_DIR/share/jupyter/kernels/$KERNEL_NAME"

read -p "Are you sure you want to DELETE the environment at $ENV_DIR and kernel at $KERNEL_SPEC_DIR [y/N]? " yn
case "$yn" in
    [Yy]*) ;;
    *) echo "Aborted."; exit 0 ;;
esac

# Delete conda env (mamba removes the directory)
if [ -d "$ENV_DIR" ]; then
    echo "Deleting conda/mamba env at $ENV_DIR..."
    rm -rf "$ENV_DIR"
    echo "Environment deleted."
else
    echo "Environment directory $ENV_DIR not found."
fi

# Delete kernel spec directory (shared)
if [ -d "$KERNEL_SPEC_DIR" ]; then
    echo "Deleting kernelspec at $KERNEL_SPEC_DIR..."
    rm -rf "$KERNEL_SPEC_DIR"
    echo "Kernelspec deleted."
else
    echo "Kernelspec directory $KERNEL_SPEC_DIR not found."
fi

echo "✔️ Cleanup complete."

