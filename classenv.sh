#!/bin/bash
# classenv.sh -- instructor tool for a shared conda env + Jupyter kernel
#                on U-M Great Lakes (or any Lmod/NFS cluster).
#
#   ./classenv.sh setup [--rebuild]   create/update env + kernel + student join.sh
#   ./classenv.sh check               verify everything is healthy
#   ./classenv.sh cleanup             delete env, kernel and join.sh
#
# All settings live in env.conf (next to this script, or set CLASSENV_CONF).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CLASSENV_CONF:-$SCRIPT_DIR/env.conf}"

die() { echo "ERROR: $*" >&2; exit 1; }

load_config() {
    [ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    local v
    for v in KERNEL_NAME DISPLAY_NAME SHARE_DIR ENV_YML; do
        [ -n "${!v:-}" ] || die "$v is not set in $CONFIG_FILE"
    done
    [[ "$KERNEL_NAME" =~ ^[A-Za-z0-9._-]+$ ]] \
        || die "KERNEL_NAME may only contain letters, digits, '.', '_' and '-'"
    [[ "$SHARE_DIR" == /* && "$SHARE_DIR" != "/" ]] \
        || die "SHARE_DIR must be an absolute path (got '$SHARE_DIR')"

    SHARE_GROUP="${SHARE_GROUP:-}"
    MAMBA_MODULE="${MAMBA_MODULE-mamba}"
    case "$ENV_YML" in /*) ;; *) ENV_YML="$(dirname "$CONFIG_FILE")/$ENV_YML" ;; esac

    # One place where every path is derived -- no script can disagree with another.
    ENV_DIR="$SHARE_DIR/env"
    KERNEL_PREFIX="$SHARE_DIR/kernels"
    KERNEL_SPEC_DIR="$KERNEL_PREFIX/share/jupyter/kernels/$KERNEL_NAME"
    PKGS_DIR="$SHARE_DIR/.pkgs"
    JOIN_SCRIPT="$SHARE_DIR/join.sh"
}

load_mamba() {
    if [ -n "$MAMBA_MODULE" ]; then
        # 'module' is a shell function; make sure it exists in non-login shells.
        if ! type module >/dev/null 2>&1; then
            set +u; source /etc/profile >/dev/null 2>&1 || true; set -u
        fi
        type module >/dev/null 2>&1 \
            || die "'module' command not found. Run on a cluster login/build node, or set MAMBA_MODULE=\"\" in env.conf if mamba is already on your PATH."
        set +u
        module load "$MAMBA_MODULE" || { set -u; die "Could not load module '$MAMBA_MODULE'. Run 'module spider mamba' and update MAMBA_MODULE in env.conf."; }
        set -u
    fi
    if command -v mamba >/dev/null 2>&1; then SOLVER=mamba
    elif command -v conda >/dev/null 2>&1; then SOLVER=conda
    else die "Neither mamba nor conda is on PATH (MAMBA_MODULE='$MAMBA_MODULE')."
    fi
}

warn_parent_perms() {
    # Students need execute (traverse) permission on every parent directory.
    local d perm
    d="$(dirname "$SHARE_DIR")"
    while [ "$d" != "/" ] && [ -d "$d" ]; do
        perm="$(stat -c %A "$d")"        # e.g. drwxr-x---
        if [ "${perm:6:1}" != "x" ] && [ "${perm:9:1}" != "x" ]; then
            echo "WARNING: $d ($perm) has no group/other execute bit; students may not be able to reach $SHARE_DIR."
        fi
        d="$(dirname "$d")"
    done
}

write_join_script() {
    # Self-contained student script with this course's values baked in, so
    # students never need a copy of this repo or of env.conf.
    cat > "$JOIN_SCRIPT" <<EOF
#!/usr/bin/env bash
# Student helper for "$DISPLAY_NAME"
#   bash $JOIN_SCRIPT           register the kernel (safe to re-run)
#   bash $JOIN_SCRIPT --check   diagnose problems
#   bash $JOIN_SCRIPT --leave   remove the kernel from your account
set -euo pipefail
KERNEL_NAME="$KERNEL_NAME"
DISPLAY_NAME="$DISPLAY_NAME"
SHARE_DIR="$SHARE_DIR"
EOF
    cat >> "$JOIN_SCRIPT" <<'EOF'

SRC="$SHARE_DIR/kernels/share/jupyter/kernels/$KERNEL_NAME"
DEST_DIR="$HOME/.local/share/jupyter/kernels"
DEST="$DEST_DIR/$KERNEL_NAME"

join() {
    [ -r "$SRC/kernel.json" ] || {
        echo "ERROR: cannot read $SRC"
        echo "Ask your instructor to confirm you are in the right group and the kernel has been built."
        exit 2
    }
    if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
        echo "ERROR: $DEST exists and is a real directory, not a link. Move it aside and re-run."
        exit 3
    fi
    mkdir -p "$DEST_DIR"
    ln -sfn "$SRC" "$DEST"
    echo "Linked $DEST -> $SRC"
    echo "Done. Restart Jupyter (or refresh the kernel list) and pick '$DISPLAY_NAME'."
}

check() {
    local fail=0 py
    echo "Checking '$DISPLAY_NAME' ..."
    if [ -r "$SRC/kernel.json" ]; then echo "  OK   shared kernel spec is readable"
    else echo "  FAIL cannot read $SRC (wrong group? parent directory permissions? not built yet?)"; fail=1; fi

    if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then echo "  OK   kernel link exists in your home"
    else echo "  FAIL kernel link missing or stale -- run: bash $SHARE_DIR/join.sh"; fail=1; fi

    if [ -r "$SRC/kernel.json" ]; then
        py="$(grep -o '"/[^"]*python[^"]*"' "$SRC/kernel.json" | head -1 | tr -d '"')"
        if [ -x "$py" ] && "$py" -c 'import ipykernel' 2>/dev/null; then
            echo "  OK   kernel Python runs ($("$py" -V 2>&1))"
        else
            echo "  FAIL kernel Python not runnable: ${py:-<not found in kernel.json>}"; fail=1
        fi
    fi
    [ "$fail" -eq 0 ] && echo "All good." || echo "Send this output to your instructor."
    exit "$fail"
}

leave() {
    if [ -L "$DEST" ]; then rm -f "$DEST"; echo "Removed $DEST"; else echo "Nothing to remove."; fi
}

case "${1:-}" in
    ""|--join)  join ;;
    --check)    check ;;
    --leave)    leave ;;
    *)          echo "Usage: bash $0 [--check|--leave]"; exit 1 ;;
esac
EOF
    chmod 750 "$JOIN_SCRIPT"
}

patch_kernelspec() {
    # Jupyter starts the kernel WITHOUT activating the conda env, so the geo
    # stack can't find its data files (GDAL_DATA / PROJ_DATA) or helper binaries.
    # Bake those into kernel.json.
    "$ENV_DIR/bin/python" - "$KERNEL_SPEC_DIR/kernel.json" "$ENV_DIR" <<'PY'
import json, os, sys
path, env = sys.argv[1:3]
with open(path) as f:
    spec = json.load(f)
e = spec.setdefault("env", {})
e["PATH"] = env + "/bin:${PATH}"
for var, sub in (("GDAL_DATA", "share/gdal"), ("PROJ_DATA", "share/proj"), ("PROJ_LIB", "share/proj")):
    p = os.path.join(env, sub)
    if os.path.isdir(p):
        e[var] = p
with open(path, "w") as f:
    json.dump(spec, f, indent=1)
PY
}

cmd_setup() {
    local rebuild=0
    [ "${1:-}" = "--rebuild" ] && rebuild=1

    load_mamba
    [ -f "$ENV_YML" ] || die "Environment file not found: $ENV_YML"

    umask 027                       # new files: owner rw, group r, others nothing
    mkdir -p "$SHARE_DIR" "$KERNEL_PREFIX"
    # Keep the package cache next to the env instead of filling your home quota.
    export CONDA_PKGS_DIRS="$PKGS_DIR"

    echo "Configuration:"
    echo "  SHARE_DIR:  $SHARE_DIR"
    echo "  ENV_YML:    $ENV_YML"
    echo "  KERNEL:     $KERNEL_NAME  ($DISPLAY_NAME)"
    echo "  SOLVER:     $SOLVER"

    if [ "$rebuild" -eq 1 ] && [ -d "$ENV_DIR" ]; then
        [ -d "$ENV_DIR/conda-meta" ] || die "$ENV_DIR does not look like a conda env; refusing to delete it."
        echo "Rebuilding: removing $ENV_DIR"
        rm -rf -- "$ENV_DIR"
    fi

    if [ -d "$ENV_DIR/conda-meta" ]; then
        echo "Updating existing environment ..."
        "$SOLVER" env update --prefix "$ENV_DIR" --file "$ENV_YML"
    else
        echo "Creating environment ..."
        "$SOLVER" env create --prefix "$ENV_DIR" --file "$ENV_YML"
    fi

    echo "Installing kernelspec ..."
    "$ENV_DIR/bin/python" -m ipykernel install \
        --prefix "$KERNEL_PREFIX" --name "$KERNEL_NAME" --display-name "$DISPLAY_NAME"
    patch_kernelspec

    # Record exactly what was installed (handy for next year / bug reports).
    "$SOLVER" env export --prefix "$ENV_DIR" > "$SHARE_DIR/environment.exported.yml" 2>/dev/null \
        || echo "(note: could not write environment.exported.yml)"

    write_join_script

    echo "Setting permissions (owner: read/write, group: read-only, others: none) ..."
    [ -n "$SHARE_GROUP" ] && chgrp -R "$SHARE_GROUP" "$SHARE_DIR"
    chmod -R u+rwX,g+rX,go-w,o-rwx "$SHARE_DIR"
    warn_parent_perms

    echo
    echo "Done. Give students this one command:"
    echo "    bash $JOIN_SCRIPT"
    echo "Then verify with:  ./classenv.sh check"
}

cmd_check() {
    local fail=0 kpy nwritable
    ok()  { echo "  OK   $*"; }
    bad() { echo "  FAIL $*"; fail=1; }

    echo "Checking $SHARE_DIR"
    if [ -x "$ENV_DIR/bin/python" ]; then ok "environment python: $("$ENV_DIR/bin/python" -V 2>&1)"
    else bad "environment missing -- run ./classenv.sh setup"; fi

    if [ -f "$KERNEL_SPEC_DIR/kernel.json" ] && [ -x "$ENV_DIR/bin/python" ]; then
        kpy="$("$ENV_DIR/bin/python" -c 'import json,sys; print(json.load(open(sys.argv[1]))["argv"][0])' "$KERNEL_SPEC_DIR/kernel.json")"
        if [ "$kpy" = "$ENV_DIR/bin/python" ]; then ok "kernelspec points at the shared env"
        else bad "kernelspec points at $kpy (expected $ENV_DIR/bin/python) -- re-run setup"; fi
    else
        bad "kernelspec missing -- run ./classenv.sh setup"
    fi

    [ -x "$JOIN_SCRIPT" ] && ok "student script: $JOIN_SCRIPT" || bad "join.sh missing -- re-run setup"

    nwritable="$(find "$SHARE_DIR" ! -type l -perm /022 2>/dev/null | wc -l)"
    if [ "$nwritable" -eq 0 ]; then ok "nothing is group/world-writable (students are read-only)"
    else bad "$nwritable paths are group/world-writable -- re-run setup to fix permissions"; fi

    if [ -x "$ENV_DIR/bin/python" ]; then
        if "$ENV_DIR/bin/python" -m pip check >/dev/null 2>&1; then ok "pip check: no broken dependencies"
        else echo "  WARN pip check reports conflicts (run: $ENV_DIR/bin/python -m pip check)"; fi
    fi

    warn_parent_perms
    [ "$fail" -eq 0 ] && echo "Healthy." || echo "Problems found."
    return "$fail"
}

cmd_cleanup() {
    echo "This will permanently delete:"
    echo "  $ENV_DIR"
    echo "  $KERNEL_PREFIX"
    echo "  $PKGS_DIR"
    echo "  $JOIN_SCRIPT  (and environment.exported.yml)"
    read -r -p "Type the kernel name ($KERNEL_NAME) to confirm: " ans
    [ "$ans" = "$KERNEL_NAME" ] || { echo "Aborted."; exit 0; }
    rm -rf -- "$ENV_DIR" "$KERNEL_PREFIX" "$PKGS_DIR" "$JOIN_SCRIPT" "$SHARE_DIR/environment.exported.yml"
    rmdir "$SHARE_DIR" 2>/dev/null || true
    echo "Cleanup complete. Students can remove stale links with: bash join.sh --leave (or rm ~/.local/share/jupyter/kernels/$KERNEL_NAME)"
}

usage() {
    sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}

main() {
    local cmd="${1:-}"
    [ -n "$cmd" ] && shift
    case "$cmd" in
        setup)   load_config; cmd_setup "$@" ;;
        check)   load_config; cmd_check ;;
        cleanup) load_config; cmd_cleanup ;;
        *)       usage ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

