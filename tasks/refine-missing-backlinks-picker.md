# Refine Missing-Link Discovery Commands

## Context

PR #930 adds commands for discovering unlinked incoming and outgoing mentions.
Review by `neo451` identified naming and picker-flow issues before merging:

- `incoming` and `outgoing` collide conceptually with existing linked incoming/outgoing commands.
- Default picker action should navigate to a location; link conversion should remain an explicit action.
- Outgoing results should group by target note instead of listing every mention/target combination in one picker.

## Requirements

### Command names

- Rename new user-facing commands to `find_incoming` and `find_outgoing`.
- Update command registration, handlers, help text, and documentation consistently.
- Keep existing linked-backlink and linked-outgoing commands distinct.

### Incoming picker

- Preserve current behavior of finding unlinked mentions of current note title or aliases in other notes.
- Picker default action remains link conversion, preserving multi-selection behavior from PR #930.
- Add `<C-o>` picker mapping to navigate to selected mention location without converting it.
- Navigation must support the picker backends used by the plugin and preview the selected file/location.
- `<C-o>` must not apply link changes.

### Outgoing picker

- Scan current note for unlinked mentions of other cached notes or aliases.
- First picker selects target note, not individual mention/target transformations.
- Target entries must identify target note and provide a useful note preview.
- After target selection, open a second picker containing matching locations in current note.
- Location picker supports single and multiple selection, then applies link conversion using existing link formatting/configuration.
- Do not show one entry for every target candidate at every location in the first picker.
- A target with no linkable locations must not appear in target picker.

## Example

For current note:

```markdown
# neovim and history of editors

neovim vs emacs
```

And targets:

```text
history/neovim.md
history/emacs.md
workflow/neovim.md
```

The first picker presents target notes, such as `history/neovim.md`,
`history/emacs.md`, and `workflow/neovim.md`. Selecting
`history/neovim.md` opens a location picker for matching `neovim` mentions.
The first picker must not present separate entries for each location/target
combination.

## Acceptance Criteria

- `:Obsidian find_incoming` and `:Obsidian find_outgoing` are registered and documented.
- Existing `:Obsidian backlinks` behavior is unchanged.
- Incoming picker `<CR>` converts selected mentions as before.
- Incoming picker `<C-o>` opens selected mention location and leaves file contents unchanged.
- Outgoing target picker groups all matching locations under selected target note.
- Outgoing location picker supports multi-select and converts selected locations only.
- Existing-link, inline-code, fenced-code, URL, and frontmatter exclusions remain intact.
- Title and alias matches remain case-insensitive and preserve current link-style/link-format configuration.
- Tests cover command registration, incoming navigation, target grouping, second-stage location selection, multi-select conversion, aliases, and exclusion rules.

## Out Of Scope

- Multi-selecting target notes and opening multiple location pickers sequentially.
- A picker action for link conversion from the target picker itself.
- `only_first_link` or any workflow preference limiting matches.
- Reworking inlay hints or link-suggestion detection outside changes required by the picker flow.
- Changing existing linked incoming/outgoing commands.

## Implementation Notes

- Reuse `obsidian.note.link_suggestion` for mention detection and conversion.
- Reuse existing picker preview/navigation helpers and backend mapping conventions.
- Keep target selection and location selection as separate picker stages so each stage has one clear item type.
- Do not add compatibility aliases for the pre-review names unless command compatibility is required by maintainers; this feature is not merged yet.
