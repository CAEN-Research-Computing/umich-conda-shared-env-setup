#!/bin/bash

# Instructor setup script for shared conda/mamba environment & kernel

set -euo pipefail

# Config file must be named 'env.conf' for consistency
CONFIG_FILE="env.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file $CONFIG_FILE not found."
    exit 1
fi
source "$CONFIG_FILE"

# Derive paths
ENV_DIR="$TURBO_DIR/envs/$KERNEL_NAME"
KERNEL_DIR="$TURBO_DIR/envs/shared_jupyter_kernels"
KERNEL_SPEC_DIR="$KERNEL_DIR/share/jupyter/kernels/$KERNEL_NAME"

# Print effective configuration for verification
echo "Configuration:"
echo "  ENV_DIR:      $ENV_DIR"
echo "  ENV_YML:      $ENV_YML"
echo "  KERNEL_DIR:   $KERNEL_DIR"
echo "  KERNEL_NAME:  $KERNEL_NAME"
echo "  DISPLAY_NAME: $DISPLAY_NAME"
echo "  KERNEL_SPEC_DIR: $KERNEL_SPEC_DIR"

# Load Mamba module (ensure this matches your cluster environment)
module load mamba/py3.12

# Check environment.yml
if [ ! -f "$ENV_YML" ]; then
    echo "ERROR: environment.yml file not found at $ENV_YML"
    exit 2
fi

# Create or update environment
if [ -d "$ENV_DIR" ]; then
    echo "Updating existing environment at $ENV_DIR"
    mamba env update --prefix "$ENV_DIR" --file "$ENV_YML" --prune
else
    echo "Creating environment at $ENV_DIR"
    mamba env create --prefix "$ENV_DIR" --file "$ENV_YML"
fi

# Activate environment
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$ENV_DIR"

# Ensure kernel directory exists
mkdir -p "$KERNEL_DIR"

# Remove any old kernel spec
if [ -d "$KERNEL_SPEC_DIR" ]; then
    echo "Removing old kernelspec at $KERNEL_SPEC_DIR"
    rm -rf "$KERNEL_SPEC_DIR"
fi

# Install or update the Jupyter kernel
echo "Installing kernelspec at $KERNEL_DIR..."
python -m ipykernel install --prefix="$KERNEL_DIR" --name="$KERNEL_NAME" --display-name="$DISPLAY_NAME"

# Ensure permissions for shared use
chmod -R 750 "$ENV_DIR"
chmod -R 750 "$KERNEL_DIR"

echo "✔️ Done. Shared environment and Jupyter kernel are ready."
