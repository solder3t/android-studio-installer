# Android Studio Fedora Installer

Native installation and packaging utility for running **Android Studio** on Fedora Workstation.

This project supports installation via a direct shell script (`install.sh`) or a native Fedora RPM package built locally.

---

## 🛠️ Method A: Direct Script Installation

The easiest way to install Android Studio is by running the installer directly.

### Usage

**One-liner (No clone required):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/android-studio-fedora-installer/main/install.sh) [options]
```

**Local script:**
```bash
./install.sh [options]
```

### Command-Line Arguments
| Option | Argument | Description |
| :--- | :--- | :--- |
| `--user` | *None* | Install to user space (`~/.local`) without requiring root/sudo. |
| `--url` | `<url>` | Override the default download URL (useful when a newer patch is released). |
| `--dry-run` | *None* | Perform validation checks and download the package without writing any files. |
| `-y, --yes` | *None* | Automatically accept prompts during upgrades or reinstallations. |
| `-h, --help` | *None* | Display usage guide and exit. |

### Installation Paths & Scope
Depending on the install scope (system-wide vs. user-local):

*   **System-Wide (Default, requires `sudo`)**:
    *   **Installation Directory**: `/opt/android-studio`
    *   **Launcher Wrapper**: `/usr/local/bin/android-studio`
    *   **Desktop Launcher**: `/usr/share/applications/android-studio.desktop`
    *   **Icon**: `/usr/share/pixmaps/android-studio.png`
*   **User-Local (`--user`, passwordless)**:
    *   **Installation Directory**: `~/.local/share/android-studio`
    *   **Launcher Wrapper**: `~/.local/bin/android-studio`
    *   **Desktop Launcher**: `~/.local/share/applications/android-studio.desktop`
    *   **Icon**: `~/.local/share/pixmaps/android-studio.png`

*Note: If `~/.local/bin` is not in your `$PATH` during a user-local installation, the installer will display the shell configuration commands needed to add it.*

---

## 📦 Method B: RPM Package Distribution

You can build and install a native RPM package for Fedora using the provided spec file.

### 1. Install Build Prerequisites
```bash
sudo dnf install -y spectool rpkg tar gzip
```

### 2. Build the RPM
```bash
./build.sh
```

The output RPM will be generated in `~/rpkg/` (or the directory defined by `$OUTDIR`).

### 3. Install the RPM
```bash
sudo dnf install ~/rpkg/x86_64/android-studio-2026.1.1.10-*.rpm
```

---

## 🚀 Running Android Studio

| Method | Command |
| :--- | :--- |
| Terminal (script install) | `android-studio` |
| Terminal (RPM install) | `android-studio` |
| Application Menu | Search for **Android Studio** |

### First Launch

On first launch, Android Studio will guide you through:
1. **Android SDK Installation** — choose your SDK location (default: `~/Android/Sdk`)
2. **Component Downloads** — platform tools, build tools, emulator images
3. **UI Theme & Settings** — light/dark theme, keymap, plugins

---

## 🔄 Upgrading

Simply re-run the installer. It will detect the existing installation, prompt for confirmation, and replace it atomically with a safe backup/rollback in case of failure.

```bash
./install.sh        # interactive — detects existing version and asks to confirm
./install.sh -y     # non-interactive — auto-accepts the upgrade
```

To upgrade to a specific release:
```bash
./install.sh --url https://dl.google.com/dl/android/studio/ide-zips/<VERSION>/android-studio-<CODENAME>-linux.tar.gz
```

---

## 🧹 Uninstallation

### Script-Based Uninstallation
```bash
./uninstall.sh             # removes both system-wide and user-local installs
./uninstall.sh --user      # removes user-local install only
```

> **Note:** The Android SDK (`~/Android/Sdk`) and local configuration (`~/.android`) are **not** removed automatically. To clean them up:
> ```bash
> rm -rf ~/Android/Sdk ~/.android
> ```

### RPM-Based Uninstallation
```bash
sudo dnf remove android-studio
```

---

## 📋 System Requirements

| Requirement | Minimum |
| :--- | :--- |
| **OS** | Fedora 38+ (any recent Linux distro) |
| **Architecture** | x86_64 only (Android Studio has no official Linux ARM64 build) |
| **RAM** | 8 GB (16 GB recommended) |
| **Disk** | 8 GB free (for IDE + SDK + one emulator image) |
| **Java** | Bundled JDK — no system JDK required |
| **Display** | 1280×800 minimum resolution |

---

## ⚙️ Additional Fedora Tips

**Enable hardware acceleration for the emulator:**
```bash
sudo dnf install -y qemu-kvm
sudo usermod -aG kvm $USER
# Log out and back in for the group change to take effect
```

**Install missing SDK dependencies (if the emulator crashes):**
```bash
sudo dnf install -y libglu1-mesa libpulse libGL
```

---

## 📄 License
This installer project is open-source. The upstream Android Studio binaries packaged by this utility are proprietary and subject to the [Android Studio Terms of Service](https://developer.android.com/studio/terms).
