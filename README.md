# Shared Conda/Mamba Environment and Kernel Setup  
### For U-M Great Lakes Cluster

Automate the creation, management, and clean-up of unified Conda (Mamba) environments and Jupyter kernels for course workflows on U-M’s Great Lakes cluster.

---

## Repository Contents

- `env.conf` — Config file for environment/kernel names and locations
- `my_environment.yml` — Environment YML with all required Conda and pip packages
- `setup_class_env.sh` — **Instructor:** Sets up or updates the shared environment and Jupyter kernel
- `student_kernel_setup.sh` — **Student:** Links the shared kernel and Turbo directory for personal use
- `cleanup_class_env.sh` — **Instructor:** Deletes the shared environment and kernel (for semester-end or reset)

---

## Usage

### 1. Preparation (Instructor, One-Time)
- Edit `env.conf` with your Turbo path, environment, and kernel names.
- Edit or create `my_environment.yml` listing the needed packages.

---

### 2. Create or Update the Shared Environment (Instructor Only)
- Make sure `setup_class_env.sh` points to the location of `env.conf` and `my_environment.yml`
  By default the `set_class_env.sh` script will look in the current directory for those files.


```bash
./setup_class_env.sh
```
*This creates/updates the shared Conda/Mamba environment and Jupyter kernel as set in `env.conf`.*

---

### 3. Student Setup

Each student runs the `studen_kernel_setup.sh` script from a login node:

```bash
./student_kernel_setup.sh
```
*This creates a symlink for the Jupyter kernel and convenient access to the Turbo share.*

Launch Jupyter Notebook/Lab:  
The kernel (e.g. `climate588 (shared)`) will appear in the kernel selection dropdown.

---

### 4. End-of-Semester Cleanup (Instructor Only)

```bash
./cleanup_class_env.sh
```
*You’ll be prompted to confirm. This removes the shared environment and Jupyter kernel.*

---

## Permissions

- **Instructor:** Should own env/kernel directories and have write access.
- **Students (group members):** Should have read and execute (`r-x`) access, but **not write**.
    Use:
    ```bash
    chmod -R 750 "$ENV_DIR"
    chmod -R 750 "$KERNEL_DIR"
    ```
    Replace `ENV_DIR`, and `KERNEL_DIR` as appropriate.

---

## Updating/Customizing

- **To add packages**: Edit `my_environment.yml`, then rerun:
    ```bash
    ./setup_class_env.sh
    ```
- **To change Python version**: Edit `python=...` in `my_environment.yml`, then rerun setup.
- **To start from scratch**: Run the cleanup script, then re-create.

---

## Troubleshooting

- **Kernel not visible in Jupyter?**
    - Check that the symlink exists and points to the class kernel directory:
        ```bash
        ls -l ~/.local/share/jupyter/kernels/
        ```
- **Permission denied?**
    - Ask instructor to adjust group permissions on Turbo files and folders.
- **Accidentally deleted your symlink?**
    - Just re-run:
        ```bash
        ./student_kernel_setup.sh
        ```

---

## FAQ

#### How can students install their own extra packages?
They should use:
```bash
pip install --user <package>
```
or create a personal Conda environment.

#### How do I remove the class kernel from my user space?
Remove the symlink with:
```bash
rm -f ~/.local/share/jupyter/kernels/$KERNEL_NAME
```
*(This only removes your local reference—others and the shared environment are unaffected.)*

---

## Maintainer
jsonk AT umich
