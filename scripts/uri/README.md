# obsidian.nvim URI launchers

These files register and launch obsidian.nvim as the operating-system handler for `obsidian://` links.

User documentation: [`docs/Obsidian-URI-Registration.md`](../../docs/Obsidian-URI-Registration.md)

## Commands

Linux:

```sh
./scripts/uri/install-linux.sh install [--force]
./scripts/uri/install-linux.sh status
./scripts/uri/install-linux.sh test
./scripts/uri/install-linux.sh uninstall
```

macOS:

```sh
./scripts/uri/install-macos.sh install [--force]
./scripts/uri/install-macos.sh status
./scripts/uri/install-macos.sh test
./scripts/uri/install-macos.sh uninstall
```

Windows PowerShell:

```powershell
& .\scripts\uri\install-windows.ps1 -Command Install [-Force]
& .\scripts\uri\install-windows.ps1 -Command Status
& .\scripts\uri\install-windows.ps1 -Command Test
& .\scripts\uri\install-windows.ps1 -Command Uninstall
```

Set `NVIM` during installation to record a specific Neovim executable.

## Data boundary

The launchers pass the URI through `OBSIDIAN_NVIM_URI`. Do not replace this with a command that embeds the URI in `+lua`, a shell expression, or `eval`.

The POSIX launcher runs `new` and `daily` URIs containing `silent` with `--headless`. Other actions open an interactive terminal. The PowerShell launcher follows the same rule.

## Maintainer checks

```sh
shellcheck \
  scripts/uri/obsidian-nvim-uri \
  scripts/uri/install-linux.sh \
  scripts/uri/install-macos.sh
```

Test installers on their native operating systems before release. The macOS installer compiles `macos/ObsidianNvimURI.swift`; the Windows installer writes a per-user protocol association.
