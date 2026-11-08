# Register the Obsidian URI handler

Registering the handler makes links from browsers, launchers, and other applications open in obsidian.nvim.

> [!warning]
> Your operating system chooses one default application for `obsidian://`. Installing this handler can replace the Obsidian desktop app. The installers refuse to replace another handler unless you pass `--force` or `-Force`, and they record a previous per-user handler for uninstall.

The browser does not own this association. Register the scheme with the operating system, then approve the browser's external-application prompt.

## Before installation

1. Confirm that `nvim` starts with the configuration that calls `require("obsidian").setup()`.
2. Confirm that all URI target vaults appear in your `workspaces` configuration.
3. Run commands below from the obsidian.nvim checkout.

The installer records the current Neovim executable. Set `NVIM` during installation if you use a wrapper or a non-default binary:

```sh
NVIM=/path/to/nvim ./scripts/uri/install-linux.sh install --force
```

A URI-launched process must initialize obsidian.nvim without opening a Markdown file first. If your plugin manager loads obsidian.nvim only for Markdown buffers, add a startup condition for `vim.env.OBSIDIAN_NVIM_URI`.

## Linux

Requirements:

- `xdg-mime`
- A terminal supported by `xdg-terminal-exec`, Kitty, Alacritty, WezTerm, Foot, Ghostty, GNOME Terminal, Konsole, or xterm

Check the current association:

```sh
./scripts/uri/install-linux.sh status
```

Install when no other application owns the scheme:

```sh
./scripts/uri/install-linux.sh install
```

Replace an existing handler, including the Obsidian desktop app:

```sh
./scripts/uri/install-linux.sh install --force
```

The installer creates:

```text
~/.local/bin/obsidian-nvim-uri
~/.local/bin/obsidian-nvim-uri.nvim
~/.local/share/applications/obsidian-nvim-uri.desktop
```

It respects `XDG_BIN_HOME`, `XDG_DATA_HOME`, and `XDG_STATE_HOME`. The desktop entry uses `%u` as one argument and has `Terminal=false`; the launcher chooses between headless execution and a terminal.

Test the registered handler:

```sh
./scripts/uri/install-linux.sh test
```

You can inspect the association directly:

```sh
xdg-mime query default x-scheme-handler/obsidian
```

The expected value is `obsidian-nvim-uri.desktop`.

### NixOS and Home Manager

The installer works in a mutable home directory when `xdg-mime` is available. For a declarative setup, package `scripts/uri/obsidian-nvim-uri`, write the selected Neovim path to an adjacent `obsidian-nvim-uri.nvim` file, and use this desktop entry:

```nix
xdg.desktopEntries.obsidian-nvim-uri = {
  name = "Obsidian (Neovim)";
  exec = "obsidian-nvim-uri %u";
  terminal = false;
  noDisplay = true;
  type = "Application";
  mimeType = [ "x-scheme-handler/obsidian" ];
};

xdg.mimeApps = {
  enable = true;
  defaultApplications."x-scheme-handler/obsidian" =
    "obsidian-nvim-uri.desktop";
};
```

Place both launcher files on the generated profile's executable path. The `.nvim` file contains one absolute path, such as `${pkgs.neovim}/bin/nvim`.

## macOS

Requirements:

- Xcode Command Line Tools, which provide `swiftc`
- [`duti`](https://github.com/moretension/duti)

```sh
xcode-select --install
brew install duti
```

Check, install, and test:

```sh
./scripts/uri/install-macos.sh status
./scripts/uri/install-macos.sh install --force
./scripts/uri/install-macos.sh test
```

The installer compiles a small AppKit URL receiver at:

```text
~/Applications/ObsidianNvimURI.app
```

The app declares the `obsidian` URL scheme in `Info.plist`. It passes the URL as one process argument to the shared launcher. Interactive actions open Terminal.app; `new` and `daily` requests containing `silent` run headlessly.

Set another application directory if needed:

```sh
OBSIDIAN_NVIM_APP_DIR=/Applications \
  ./scripts/uri/install-macos.sh install --force
```

Writing to `/Applications` may require elevated permissions. The default `~/Applications` path does not.

## Windows

Run the installer in PowerShell. It writes only to `HKEY_CURRENT_USER`, so it does not need administrator privileges.

```powershell
& .\scripts\uri\install-windows.ps1 -Command Status
& .\scripts\uri\install-windows.ps1 -Command Install -Force
& .\scripts\uri\install-windows.ps1 -Command Test
```

The installer copies the launcher to:

```text
%LOCALAPPDATA%\obsidian.nvim\obsidian-nvim-uri.ps1
```

It registers:

```text
HKEY_CURRENT_USER\Software\Classes\obsidian
```

The launcher uses Windows Terminal when `wt.exe` is available. Otherwise it starts Neovim in a separate process. Set a specific executable during installation with:

```powershell
$env:NVIM = 'C:\Tools\Neovim\bin\nvim.exe'
& .\scripts\uri\install-windows.ps1 -Command Install -Force
```

If PowerShell blocks the installer file, run the command once with an execution-policy override:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\uri\install-windows.ps1 -Command Install -Force
```

## Browser behavior

Use a clickable link when testing. Browsers may treat text pasted into the address bar as a search or block it without a user gesture.

[Test `obsidian://choose-vault`](obsidian://choose-vault)

### Firefox

Firefox asks for permission before opening an external protocol. Choose the registered system application and select the option to remember the choice if desired.

To reset a saved choice, open **Settings**, search for **Applications**, and find the `obsidian` content type. If Firefox does not prompt on Linux, setting `network.protocol-handler.expose.obsidian` to `false` in `about:config` can restore the application chooser. Treat that preference as troubleshooting rather than installation.

### Chrome, Chromium, Brave, and Edge

Chromium-based browsers use the operating-system association and show an external-application prompt. Their site protocol-handler settings do not replace the native `obsidian://` association.

Browser policy, popup blocking, or navigation without a user gesture can prevent a page from opening an external application. Test with the link above before debugging obsidian.nvim.

### Safari

Safari uses the macOS LaunchServices association and asks for confirmation before opening the registered application. Re-run the macOS install command if Safari continues to select the Obsidian desktop app.

### Web protocol registration is not available

A website cannot register itself as the `obsidian://` handler with `navigator.registerProtocolHandler()`. Browsers permit selected built-in schemes and custom schemes beginning with `web+`; `obsidian` does not meet those rules.

## Obsidian Web Clipper

The Web Clipper sends `new` or `daily` URIs.

In normal mode it:

1. Copies generated Markdown to the system clipboard.
2. Opens a URI containing `clipboard`.
3. Includes a short `content` error message in case the receiving application cannot read the clipboard.

obsidian.nvim reads the `+` register and falls back to `content` when that register is empty. Your Neovim clipboard provider must have access to the same graphical session as the browser.

When the extension cannot write to the clipboard, it sends the generated Markdown through `content`. Legacy mode also uses `content`; long pages can exceed browser or operating-system URI length limits.

The launcher recognizes `silent` on `new` and `daily` requests and runs Neovim headlessly. A silent request still loads your complete Neovim configuration and writes the note before exiting.

## Launcher behavior and security

The launchers put the received URI in `OBSIDIAN_NVIM_URI`. They execute a constant Lua command that reads `vim.env.OBSIDIAN_NVIM_URI`; URI text never becomes Lua or shell source.

The runtime also:

- Rejects non-`obsidian://` input.
- Rejects file traversal outside configured workspaces.
- Resolves symlinks before checking write boundaries.
- Returns a non-zero exit status when a headless handler fails.

Treat URI content as untrusted input. Keep confirmation enabled for file-modifying links followed inside notes:

```lua
uri = {
  enabled = true,
  require_confirmation = true,
}
```

The OS launcher does not prompt because `silent` Web Clipper requests cannot use an interactive confirmation. Installing the OS association grants `obsidian://` links permission to invoke the configured handlers.

## Troubleshooting

### `obsidian.nvim is not set up`

The URI command ran before your plugin configuration called `setup()`. Load obsidian.nvim during startup when `vim.env.OBSIDIAN_NVIM_URI` exists.

### Vault not found

Use a configured workspace name or vault root directory name. Vault IDs from the Obsidian app are not supported.

### Clipboard content is missing

Check `:checkhealth obsidian` and confirm that `"+p` reads the browser's clipboard. On Linux, the headless process also needs the correct `DISPLAY` or `WAYLAND_DISPLAY` environment.

### No terminal opens on Linux

Install `xdg-terminal-exec` or one of the supported terminal emulators. You can run the launcher from a terminal to inspect errors:

```sh
~/.local/bin/obsidian-nvim-uri 'obsidian://choose-vault'
```

### The Obsidian desktop app still opens

Check the current system association with the platform installer's `status` command. Close and reopen the browser after changing it.

## Uninstall and restore

Linux:

```sh
./scripts/uri/install-linux.sh uninstall
```

macOS:

```sh
./scripts/uri/install-macos.sh uninstall
```

Windows:

```powershell
& .\scripts\uri\install-windows.ps1 -Command Uninstall
```

Each installer restores the previous handler when it recorded one. If no previous handler existed, run the Obsidian desktop app or its installer to register it again.

## Platform references

- [Desktop Entry URL field codes](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html)
- [Apple custom URL schemes](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
- [Windows URI activation](https://learn.microsoft.com/en-us/windows/apps/develop/launch/handle-uri-activation)
- [Browser protocol-handler API](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/registerProtocolHandler)
