# Developer-config

Personal Windows developer environment bootstrap and maintenance toolkit.

## For Consumers

### What this repo does

- Installs packages from `packages/winget.txt`
- Installs VS Code extensions from `packages/vscode.txt`
- Links config files from `configs/` into your user profile
- Lets you sync, uninstall extras, and update through a TUI

### How to run

From repo root:

```powershell
.\run
```

This launches the interactive TUI.

### Main menu (current)

```text
1. Sync spec files (add/remove entries)
2. Uninstall extras (installed but not in spec)
3. Install to specification
4. Update packages and extensions
5. Exit
```

Main menu controls:

- `Up/Down` to move
- `Enter` to select
- `1-5` direct select
- `Esc` exit

List screen controls (options 1, 2, 4):

- `Up/Down` move
- `Space` toggle selection
- `A` select all
- `N` select none
- `R` refresh
- `Enter` apply selected
- `Esc` back

### Notes

- Install mode (`3`) requires elevation and opens an elevated PowerShell when needed.
- All per-item confirmation prompts default to `No` unless explicitly stated otherwise.

## For Developers

### Repo structure

- `run.ps1`: main interactive entrypoint
- `run.cmd`: convenience wrapper so `.\run` works
- `scripts/install.ps1`: full install orchestrator
- `scripts/sync-packages.ps1`: interactive sync against `packages/*.txt`
- `scripts/uninstall-extra.ps1`: interactive uninstall extras
- `installation-scripts/`: install helpers
- `packages/`: package/extension spec files
- `configs/`: source-of-truth config files to be linked

### How settings/profile syncing works

`scripts/install.ps1` calls `installation-scripts/install-configs.ps1`.

`install-configs.ps1` behavior:

- Compares existing user config vs repo config for:
  - VS Code settings
  - Windows Terminal settings
  - Git config
- For keys present in both but with different values: asks which value to keep.
- For keys only in user config: asks whether to add them to repo config.
- For git machine-specific identity keys (`user.name`, `user.email`, `user.signingkey`): does not merge them into repo config.
- For PowerShell profiles (`profile.ps1`): if target exists and is non-empty, asks before overwrite/link.
- Then creates/refreshes symlinks to the repo-managed files. If linking is blocked, falls back to hard link, then file copy.

### Per-machine git identity

`configs/git/.gitconfig` includes `~/.gitconfig.local`.

Option `3` now also manages `~/.gitconfig.local` by linking it to `configs/git/.gitconfig.local` in this repo.
If `configs/git/.gitconfig.local` does not exist, installer creates it from `configs/git/.gitconfig.local.example`.
The local file is git-ignored so each machine can keep its own identity.

Create it once per machine:

```ini
[user]
    name = Your Name
    email = your.email@example.com
```

An example template is available at `configs/git/.gitconfig.local.example`.

### Making changes safely

1. Edit files under `configs/` and/or `packages/`.
2. Run `.\run` and use:
   - `1` to update package spec files to match machine state (interactive)
   - `4` to update installed packages/extensions
   - `3` to apply installation + config linking
3. Validate behavior locally.

### Direct script usage (advanced)

- Full install:
  - `.\scripts\install.ps1`
- Sync specs:
  - `.\scripts\sync-packages.ps1`
- Uninstall extras:
  - `.\scripts\uninstall-extra.ps1`
- Config-only install/merge:
  - `.\installation-scripts\install-configs.ps1`
