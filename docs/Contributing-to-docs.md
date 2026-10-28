---
title: "Contributing to the Documentation"
tags:
  - contributing
  - documentation
---

Documentation lives in the repository's `docs/` directory and is published as a Quartz site. Changes are welcome through pull requests.

## Preview locally

Install Git, Node.js, npm, and Make, then run:

```sh
make docs-serve
```

Quartz is cloned into the ignored `deps/quartz/` directory on first use. The local site is served at <http://localhost:9876>. Run `make docs-site` to build without serving; output is in `deps/quartz/public/`.

## Write and link pages

- Use one YAML frontmatter block at the top of each page with a human-readable `title` and relevant lowercase `tags`.
- Let the Quartz page title supply the H1; begin page content with section headings (`##`).
- Link related documentation with Obsidian wikilinks, for example `[[Link]]` or `[[LSP#Code Actions|LSP code actions]]`.
- Group pages through meaningful tags and add links where they help readers move between related topics.

The site build deploys to GitHub Pages from stable release tags; prereleases do not replace the published documentation. See the repository's [GitHub Pages setup guide](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/.github/RELEASE_PROCESS.md#github-pages-setup).
