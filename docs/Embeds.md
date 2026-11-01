---
title: "Embeds"
tags:
  - editor
  - embeds
  - markdown
---

Obsidian.nvim renders Markdown note embeds as virtual lines below the embed link. The source buffer stays unchanged.

## Note embeds

Whole-note embeds support wiki and Markdown syntax:

```markdown
![[Project Notes]]
![Project Notes](Project%20Notes.md)
```

The preview omits frontmatter and shows up to 10 lines. Put the cursor on the embed and use:

- `<C-a>` to scroll the preview forward, moving its contents up.
- `<C-x>` to scroll the preview backward, moving its contents down.
- A count to move several lines, such as `3<C-a>`.

Outside a rendered note embed, these mappings retain Neovim's normal increment and decrement behavior.

## Heading embeds

A heading fragment renders only that section:

```markdown
![[Project Notes#Milestones]]
![[#Milestones]]
```

The second form targets a heading in the current note. The preview includes the heading, its content, and nested subsections. Heading previews are not limited to 10 lines. A missing heading displays `Heading not found: NAME` below the embed.

## Block embeds

A block fragment renders the paragraph or block carrying the block ID:

```markdown
![[Project Notes#^release-checklist]]
![[#^release-checklist]]
```

The second form targets the current note. Block previews are not truncated. A missing block displays `Block not found: ^ID` below the embed.

## Renderer roadmap

| Content        | Status    | Notes                                                                                |
| -------------- | --------- | ------------------------------------------------------------------------------------ |
| Markdown notes | Available | Whole notes are paged; heading and block fragments render their complete ranges.     |
| Images         | Planned   | Built-in inline rendering is planned. See [[Images]] for `snacks.image` integration. |
| Audio          | Planned   | Playback controls need a dedicated inline interface.                                 |
| PDF            | Planned   | The renderer will need page selection and terminal-compatible output.                |
| Search queries | Planned   | This covers Obsidian `query` code blocks and their result lists.                     |
| Mermaid        | Planned   | This covers rendered `mermaid` code blocks.                                          |

## Canvas and Bases

Inline Canvas and Bases rendering is not feasible with the current extmark preview model and neovim TUI in general, hence is currently not planned.

## See also

[[Actions]] · [[Images]] · [[Link]] · [[Note]]
