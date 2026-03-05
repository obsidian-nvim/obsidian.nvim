# Obsidian URI

obsidian.nvim can handle [Obsidian URI](https://help.obsidian.md/Concepts/Obsidian+URI) protocol links (`obsidian://`), letting you open notes, create notes, search, and more -- all from outside Neovim.

## Supported Actions

| Action             | Description                                       | Status      |
| ------------------ | ------------------------------------------------- | ----------- |
| `open`             | Open a vault or note (with heading/block anchors) | Supported   |
| `new`              | Create a note (with content, clipboard, silent)   | Supported   |
| `daily`            | Open or create today's daily note                 | Supported   |
| `unique`           | Create a note with auto-generated ID              | Supported   |
| `search`           | Open search with optional query                   | Supported   |
| `choose-vault`     | Open workspace picker                             | Supported   |
| `hook-get-address` | Copy current note link to clipboard               | Best-effort |

### Not supported

- **Vault ID** (`vault=ef6ca3e3b524d22f`): Obsidian vault IDs are internal to the Obsidian app and will be supported in later updates.
- **`paneType=window`**: will be supported in later updates.

## OS-Level URI Handler

To make `obsidian://` links from browsers and other apps open in Neovim, you need to register a handler script with your OS.

### The Handler Script

Create a script that receives the URI and launches Neovim. This script works on Linux and macOS:

```sh
#!/bin/sh
# obsidian-uri-handler
# TODO:
```

Make it executable and place it on your `$PATH`:

```sh
chmod +x obsidian-uri-handler
cp obsidian-uri-handler ~/.local/bin/
```

### Linux (xdg-mime)

Create `~/.local/share/applications/obsidian-nvim.desktop`:

```ini
[Desktop Entry]
Name=Obsidian (Neovim)
Comment=Handle obsidian:// URIs in Neovim with obsidian.nvim
Exec=obsidian-uri-handler %u
Terminal=true
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/obsidian
Categories=Utility;TextEditor;
```

Register it:

```sh
xdg-mime default obsidian-nvim.desktop x-scheme-handler/obsidian
```

#### NixOS (home-manager)

```nix
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/obsidian" = "obsidian-nvim.desktop";
    };
  };

  xdg.desktopEntries.obsidian-nvim = {
    name = "Obsidian (Neovim)";
    comment = "Handle obsidian:// URIs in Neovim with obsidian.nvim";
    exec = "obsidian-uri-handler %u";
    terminal = true;
    type = "Application";
    noDisplay = true;
    mimeType = ["x-scheme-handler/obsidian"];
    categories = ["Utility" "TextEditor"];
  };
}
```

### macOS

The handler script above supports macOS terminals (iTerm2, Terminal.app). Register it as a URI handler:

1. Create the `obsidian-uri-handler` script (see above)
2. Make it executable: `chmod +x obsidian-uri-handler`
3. Copy to a location on your PATH: `cp obsidian-uri-handler ~/.local/bin/`
4. Create a simple wrapper app using **Automator**:
   - Open **Automator** > **New Document** > **Application**
   - Add a **Run Shell Script** action
   - Set **Pass input** to "as arguments"
   - Paste: `~/.local/bin/obsidian-uri-handler "$1"`
   - Save as `ObsidianNvim.app` in `/Applications`

5. Register the URI scheme:

```sh
# Option 1: duti (recommended)
brew install duti
duti -s com.apple.Automator.ObsidianNvim obsidian

# Option 2: RCDefaultApp (older but works)
# Download from https://www.rubicode.com/Software/RCDefaultApp/
```

The script will detect and use iTerm2 or Terminal.app automatically.

### Windows

Create `obsidian-uri-handler.bat`:

```batch
@echo off
start "" nvim "+lua require('obsidian.uri').handle('%1')"
```

The `start ""` opens nvim in a new window and exits the batch file immediately.

Register via registry (run as administrator, or create a `.reg` file):

```reg
Windows Registry Editor Version 5.00

[HKEY_CLASSES_ROOT\obsidian]
@="URL:Obsidian Protocol"
"URL Protocol"=""

[HKEY_CLASSES_ROOT\obsidian\shell\open\command]
@="\"C:\\path\\to\\obsidian-uri-handler.bat\" \"%1\""
```

**Windows Terminal** variant (if you prefer Windows Terminal):

```batch
@echo off
wt nvim "+lua require('obsidian.uri').handle('%1')"
```

## Browser Integration

### Firefox

Firefox handles custom URI schemes natively. The first time you click an `obsidian://` link, Firefox will ask which application to use. Select your handler script or `.desktop` entry.

To reset the handler: go to `about:preferences` > **Applications** > search for `obsidian` > change the action.

To add a handler manually in `about:config`:

1. Navigate to `about:config`
2. Set `network.protocol-handler.expose.obsidian` to `false`
3. Next time you click an `obsidian://` link, Firefox will prompt you to choose a handler

### Chrome / Chromium

Chrome auto-detects registered URI handlers from the OS. After registering the `.desktop` file (Linux) or app (macOS), clicking an `obsidian://` link in any webpage will open it in Neovim.

To reset: go to `chrome://settings/handlers` and remove the entry.

## Web Clipper

The [Obsidian Web Clipper](https://obsidian.md/clipper) browser extension sends `obsidian://new` URIs to save web pages as notes. With the URI handler registered, clipped pages go directly into your Neovim-managed vault.

A typical Web Clipper URI looks like:

```
obsidian://new?file=Clippings%2FPage%20Title&silent=true&clipboard&content=fallback%20content
```

This creates `Clippings/Page Title.md` in your vault. The clipper puts the formatted content in your clipboard (`clipboard` flag), with a `content` fallback if clipboard access fails. The `silent` flag means no UI is shown -- the handler script detects this and runs Neovim in headless mode.

## Calling from Neovim

Inside a running Neovim session with obsidian.nvim loaded:

```vim
:Obsidian uri obsidian://open?vault=my%20vault&file=my%20note
:Obsidian uri obsidian://daily
:Obsidian uri obsidian://search?query=TODO
:Obsidian uri obsidian://new?name=quick-note&content=Hello
```

Or from Lua:

```lua
require("obsidian.uri").handle "obsidian://daily"
```
