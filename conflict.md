---
title: "Troubleshoot Obsidian Sync"
site: "Obsidian Help"
source: "https://obsidian.md/help/sync/troubleshoot"
domain: "obsidian.md"
language: "en"
description: "This page lists uncommon issues you may encounter with Obsidian Sync and how to resolve them."
word_count: 866
---

This page lists uncommon issues you may encounter with [[Introduction to Obsidian Sync|Obsidian Sync]] and how to resolve them. Before proceeding, we recommend reviewing the [[Status icon and messages]] and [[Frequently asked questions]] pages.

## General

### Conflict resolution

A conflict happens when you change the same file on two or more devices before they sync. For example, you edit a note on your computer. Before that change uploads, you also change the same note on your phone.

Conflicts happen more often when you work offline. There are more changes and longer time between syncs, which increases the chance of conflicts.

#### How Obsidian Sync handles conflicts

When Obsidian Sync finds a conflict, the result depends on the file type:

- **Markdown files**: Obsidian Sync merges the changes using Google's [diff-match-patch](https://github.com/google/diff-match-patch) algorithm.
- **Other file types**: For all other files, including canvases, Obsidian uses a "last modified wins" approach. The most recently modified version replaces earlier versions.

For conflicts in Obsidian settings, such as plugin settings, Obsidian Sync merges the JSON files. It applies keys from the local JSON on top of the remote JSON.

#### Conflict resolution options

Starting in Obsidian 1.9.7, you can choose how to handle conflicts. To configure this setting:

1. Open **[[Settings]]**.
2. In the sidebar, select **Sync**.
3. Under **[[Sync settings and selective syncing#Conflict resolution|Conflict resolution]]**, choose your preferred option:
   - **Automatically merge** (default): Obsidian Sync combines all changes from different devices into a single file. This saves all edits, but it may sometimes create duplicate text or formatting problems. You will need to fix these manually.
   - **Create conflict file**: When Obsidian finds conflicting changes, it creates a separate conflict file instead of merging automatically. You can then review both versions and merge them yourself. This gives you full control over the final result.

> [!warning]+ Configure on all devices
> Conflict resolution settings are device-specific. You must configure your preferred option on each of your devices. This ensures the same behavior across all your synced devices.

**Conflict file naming pattern**

When you use the "Create conflict file" option, Obsidian creates a new file with this naming pattern:

```
original-note-name (Conflicted copy device-name YYYYMMDDHHMM).md
```

For example, if a conflict happens in a note called `Meeting notes.md`, the conflict file might be named:

```
Meeting notes (Conflicted copy MyMacBook2 202411281430).md
```

The conflict file contains the changes from the device where the conflict was detected. The original file keeps the remote version. You can compare both files and manually merge the content.

> [!info]+ Check the Sync log
> To check when conflicts happened, open the [[Status icon and messages#Sync activity log|Sync log]]. Filter for "Merge Conflicts" or search for "Conflict".

###  Sync deleted a note I just created on two devices

Obsidian Sync typically tries to [[#Conflict resolution|resolve conflicts]] by merging conflicting notes across devices. However, problems can happen for users who automatically create or change notes on startup. This includes [[Daily notes]] or when using the community plugin [Templater](https://github.com/SilentVoid13/Templater).

If you create a note locally on one device and, within a couple of minutes, Sync downloads a remote version of that same note, Sync will keep the remote version without merging the two. In this case, you can recover the local version using [[File recovery]].

### Sync will not sync my plugins and settings updates

Obsidian [[Frequently asked questions#Does Obsidian Sync live-reload my settings?|does not live-reload all settings]]. After you update settings or plugins, you need to restart Obsidian on other devices to see the changes. On mobile devices, you may need to force-quit the app.

> [!example]- Changing a theme
> - On your primary device (usually a computer), you change your theme back to the default from a custom theme.
> - The Sync log confirms the updated files were sent to the remote vault, but your mobile device still shows the custom theme.
> - On the mobile device, check the Sync log to confirm receipt of the updated `appearance.json` file.
> - Reload or restart Obsidian on the mobile device.
> - After reloading or restarting, the mobile device should display the same theme as your computer.

### My files keep disappearing from Sync as soon as I restore it

This issue is most common on Windows. Windows Defender may quarantine files with code blocks, which causes certain notes to disappear.

Another common cause is double-syncing. This happens when Obsidian Sync runs alongside another syncing service.

![[Switch to Obsidian Sync#Move your vault out of your third-party syncing service or cloud storage]]

---

Finally, this can happen when you restore a file on one device, but then it is removed from a secondary device. This happens when the filename has [[Status icon and messages#Skipped messages|illegal characters]].

## Android

**My device is deleting my attachments I receive through Sync**

This issue is likely due to Google or Android Photos managing your attachments. To prevent the system from changing files received via Sync, add a `.nomedia` [file to your vault](https://support.google.com/android/thread/60342076/what-are-these-nomedia-files?hl=en) on your Android device.

> [!tip]- Use a plugin
> The community plugin [Android Nomedia](https://obsidian.md/plugins?id=android-nomedia) makes this easier. Install it on your Android phone. Note that `.nomedia` files are not synced across devices through Obsidian Sync.