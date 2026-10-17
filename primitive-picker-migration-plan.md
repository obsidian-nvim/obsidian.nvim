# Primitive picker migration: review and bounded plan

Status: direction confirmed with the user after design grilling; implementation pending.
Review baseline: working tree on `refacotr/interface` at the time of the initial review.
Scope: primitive picker/interface housekeeping, shared previews, and quickfix improvements. Daily and date-related implementation work stays out.

## Recommendation

Continue the extraction into `obsidian.interfaces`. Finish the existing callers, standardize success-only selection callbacks, then share previews and migrate the remaining repeated picker compositions.

Confirmed additions:

- Add `resolvers.url_preview`, returning content rather than buffers. The built-in preview shows the URL and guidance to `:Obsidian help resolvers`, with no network request. Move Defuddle fetching into a recipe. This is an intentional behavior break.
- Give file/location browsers a default `send_to_qf` action on `<C-q>` and multi-selection. Default navigation opens one result or exports multiple results to quickfix; custom callbacks receive the complete selection unchanged.
- Preserve existing commands and cheap Lua forwarding shims. Live-buffer discovery/previews and eliminating discarded multi-selections are intentional improvements.
- Keep the migration bounded to the eight existing interfaces, shared previews, repeated note/location selection, and bookmark-group acquisition. One-off command/sync menus stay on generic `picker.select`.

Use one namespace with small primitive modules, not one large Lua file. Keep the data operations usable without loading a picker. Keep mutation and command workflows outside selection functions.

The older `primitive-uis-plan.md` contains useful boundaries, but its explorer registry, universal nodes, action dispatch, multiple views, and feature-branch sequencing exceed this task. Some starting assumptions are stale: properties and unlinked-mention actions already exist in this checkout. Do not make this housekeeping depend on highlights, a query language, a second view, or a new Neovim UI API.

The three goals can be met in sequence:

1. Reuse: consistent callbacks and explicit context.
2. Completeness: shared previews and preserved command behavior.
3. Customizability: UI-independent data, a small selection seam, and the concrete URL-preview content resolver, without designing a browser framework or adding speculative acquisition hooks.

## 1. Assessment of the initial WIP

### Keep

- Thin command wrappers for bookmarks, links, footnotes, and TOC are the right direction.
- Extracting templates and folders removes repeated action-local picker setup.
- Moving tag enumeration into `tag.list` gives several actions one data operation.
- Centralizing `preview_entry` removes duplicated position conversion.
- The picker facade is the right place for backend normalization; raw backend adapters can continue treating values as opaque.
- The property extraction preserves the cache-first path and fallback. Its existing seven action tests pass in isolation.
- Existing `picker.select` accepts arbitrary values and has formatting, preview, and mapping hooks. Reuse it rather than rebuilding its abstraction.

### Incomplete boundaries

The new modules mostly relocate code. They do not yet provide a consistent reusable interface:

| Module | Current shape | Missing boundary |
| --- | --- | --- |
| folders | callback gets `(directory, text)` | options, typed result, context/root capture |
| templates | callback gets paths | single-selection policy, options, preserved prompt |
| tags | optional callback gets tags and all occurrences | separate choosing tags from browsing occurrences; migrate action callers |
| headings | mandatory callback gets items | command supplies none; no default navigation |
| footnotes | selects and moves cursor | callback override and source-window/buffer capture |
| links | selects strings and follows one | loses source positions; no previews or callback override |
| bookmarks | loads JSON, resolves targets, previews, navigates, opens | separate storage/actions from picker composition; repair moved references |
| properties | loads/indexes data and runs three picker stages | reusable key/value/note operations and callback override |

Properties and bookmarks still put substantial domain work in `interfaces`. Conversely, `bookmarks.move_to_group`, `cache/api.lua`, and note/tag mappings in `picker/init.lua` still compose domain-specific UIs outside it. Treat those as subsequent extractions, not reasons to discard the WIP.

## 2. Low-hanging TODOs

### P0: finish the migration before adding features

- [ ] `lua/obsidian/actions.lua:1517-1563`: replace removed `pick_tags` and `gather_tag_picker_list` references. Keep the occurrence callback argument order explicit; the moved helper reversed the old order.
- [ ] `lua/obsidian/commands/tags.lua:3-4`: preserve `data.fargs`. Route through the action workflow so explicit tags and the cursor-tag shortcut still work.
- [ ] `lua/obsidian/interfaces/headings.lua:31`: restore default navigation or make the command provide the selection callback. Cancellation should not log “no headings found”; check empty discovery before opening the picker.
- [ ] `lua/obsidian/interfaces/bookmarks.lua:190`: replace obsolete `M.pick` for group navigation.
- [ ] `lua/obsidian/interfaces/bookmarks.lua:240,244`: bind move/delete mappings to the bookmark operations. These callbacks are nil after the move.
- [ ] Preserve `bookmarks.pick` and `footnotes.pick` through thin forwarding shims and test them. This migration does not intentionally break those APIs.
- [ ] Restore the `Templates` prompt for new-from-template and make template acquisition single-select. Current callers consume only the first while `find_files` enables multiple selection.
- [ ] Remove imports orphaned by this extraction after wiring callers.

Keep this commit behavioral: do not mix in property type changes, query parsing, new scopes, or a resolver registry expansion.

### P1: small shared improvements

- [ ] Make folder and template interfaces accept options rather than adding positional arguments.
- [ ] Add callback overrides for links, footnotes, and property results.
- [ ] Use one explicit single/multiple selection policy: templates and move destinations stay single-select; tags remain multi-select; file/location browsers support multiple choices.
- [ ] Share default navigation: one result opens; multiple results export to quickfix. Custom callbacks retain the full array without automatic interception.
- [ ] Add default `send_to_qf` on `<C-q>` for eligible file/location browsers. Reuse and extend `picker.util.open_notes` where appropriate; do not duplicate quickfix export logic across interfaces/backends.
- [ ] Replace remaining hand-written location-preview callbacks in backlinks, follow-link, TOC, and workspace selection after preview tests cover their shapes.
- [ ] Extract bookmark file reading into a domain operation used by both browsing and mutations; avoid a second unguarded JSON/file-loading path in the interface.
- [ ] Capture the caller buffer/window and workspace before asynchronous selection. Validate them before insertion/navigation; do not act on whichever buffer happens to be current later.

## 3. Small interface contract

### Responsibilities

```text
commands           parse arguments and choose the action
    actions        capture context, choose workflow, mutate/open
        resolvers  optional input acquisition (existing action hooks)
            interfaces.<primitive>  built-in selection and presentation
                picker             backend adapters and generic UI mechanics

domain/search/cache APIs supply data to interfaces and custom consumers
shared preview helpers supply preview specs to interfaces
    resolvers.url_preview supplies reusable URL content, not picker buffers
```

Resolvers do not have to sit in every path. A browse command can call an interface wrapper. An action with explicit input can skip acquisition.

Keep these rules:

- Domain modules expose typed data and operations without requiring a picker.
- Interfaces own labels, prompts, previews, selection mappings, and staged picker navigation.
- Actions own edits, note creation, file moves, and open strategies.
- A callback override replaces the default action; it does not run in addition to it. Explicit `send_to_qf` is a separate action and does not also invoke the success callback.
- Selectors own empty-state messages and errors. Consumers do not receive an error argument or handle unsuccessful selections.
- Ordinary cancellation stays quiet; preserve workflow-specific “Aborted” messages only where appropriate.
- Previewing does not open URLs, create notes, prompt for creation, or modify source text.

### Confirmed selection API

Use `pick(opts, on_choice)` for selection with no implicit mutation. Retain `open` as a thin default browsing wrapper where useful.

```lua
interfaces.templates.pick({
  bufnr = source_buf,
  allow_multiple = false,
  picker = { prompt = "Choose template" },
}, function(paths)
  insert_template(paths[1])
end)
```

Contract:

- Invoke `on_choice` at most once, only after successful selection, with a nonempty array of the documented primitive value. Single selection still returns an array.
- Cancellation, empty discovery, and failure do not invoke the consumer callback. Interfaces handle contextual information/errors, including async failures; consumers need no repeated guards.
- Normalize backend outcomes inside the interface. Cancellation must still trigger internal cleanup even though it does not invoke the consumer.
- Capture source context before selection: `bufnr`, `winid`, `workspace_dir`, and a resource-specific scope only where needed. Validate captured targets before acting.
- Use live source buffers for current-note discovery and previews, including unsaved edits. Use disk for unloaded files.
- Nest per-call presentation overrides under `picker`; keep source/query options outside it. No global per-primitive interface configuration in this migration.
- Merge selection/query mappings by key. Caller entries win; `false` removes one default mapping; `no_default_mappings = true` omits primitive defaults. Ordinary options such as `prompt` and `format_item` replace defaults.
- Preserve useful primitive records and existing result types. Do not reduce a link occurrence to a string or a property value to its display label.
- Templates and folder-destination acquisition stay single-select; tags remain multi-select. File/location browsing supports multi-selection. Explicit callbacks receive the full selection rather than triggering automatic quickfix handling.

An array contract prevents today's mix of varargs, `(directory, text)`, strings, quickfix entries, and callback-less opening. Document each primitive's result type; avoid a universal record or node type.

Add only the tiny common helpers needed by multiple interfaces, such as success filtering and option merging. Do not introduce a provider base class.

This success-only callback contract is specific to primitive selectors. Resolvers retain their asynchronous `done(result, err)` completion contract.

### Data operations to expose

Reuse current APIs before creating new modules:

- Tags: enumeration, normalized identities, matching occurrences. `tag.list` should accept explicit scope/options and have annotations; let the search layer retain responsibility for discovery.
- Properties: records, keys/counts, values/counts, notes matching a key/value. Move these out of the picker module, preserving cache and no-cache behavior.
- Bookmarks: read/list, resolve a target against a workspace, enumerate group children, add/delete/move.
- Links: retain source occurrence and parsed reference, resolve targets without opening or creating anything.
- Headings/footnotes: enumerate current-buffer locations using existing parsers/document APIs where possible. Preserve LSP integration as an adapter rather than requiring a client for domain access.

Do not add stable IDs, hierarchy protocols, refresh sessions, or action registries until a consumer requires them.

## 4. Preview unification

Use one shared preview namespace/module for mechanics. Keep `{ buf, pos, pos_end }` as the rendering boundary. It already works with the picker adapters; a richer media schema has no current consumer here.

### First helpers

- `path`: file or directory, with readable missing/unreadable fallback.
- `location`: path or source buffer plus position/range.
- `text`: scratch content and filetype; removes repeated buffer setup.
- `url`: shared rendering of content from `resolvers.url_preview`, with a built-in plain-URL fallback and no default network access.

Primitive-specific preview functions remain thin adapters: bookmark group summaries and property summaries do not need a global type dispatcher.

### Correctness before coverage

- Normalize `obsidian.Range` and LSP ranges through explicit conversion. Current `picker.util.preview_entry` dereferences `range.start`, but bookmark entries carry `section.range` with `start_row`. This is an inherited assumption copied into the shared helper; centralization should fix it.
- Document byte columns, one-based quickfix columns, zero-based preview columns, and half-open range ends. Use existing `Range`/`Pos` utilities. Cover non-ASCII and end-of-document ranges.
- Prefer loaded/live buffer contents for current-note and location previews. Current `preview_path` reads disk, so previews can disagree with unsaved edits.
- Bound file reads and handle missing, unreadable, binary, and large files without throwing into a picker backend.
- Define scratch-buffer ownership and cleanup. Validate buffers before async updates and discard stale requests. Do not depend on `bufhidden=wipe` for buffers that were allocated but never displayed.

### Filename inference in the picker facade

The WIP's automatic preview for entries with `filename` is useful. Keep raw backend adapters opaque and test the facade separately.

Before treating this as complete:

- Guard each previewed value so mixed lists are safe. Inspecting only the first item is not a general dispatch scheme.
- Support and annotate `preview_item = false` as an explicit opt-out. Today `preview_item` only documents functions.
- Preserve custom previews for missing notes and heterogeneous bookmarks.
- Test through the real facade. A mocked `picker.select` plus a test-local preview fallback does not prove default preview injection works.

### URL preview resolver: confirmed intentional break

Add `resolvers.url_preview(ctx, done)` and route URL previews through one shared adapter wherever they are needed, including links and bookmarks. The context includes the URL; capture any needed source context before asynchronous work.

Return content rather than a picker buffer:

```lua
-- Built-in url_preview resolver; no network request.
done {
  lines = {
    ctx.url,
    "",
    "Customize URL previews with resolvers.url_preview.",
    "See :Obsidian help resolvers",
  },
  filetype = "markdown",
}
```

- Result content is a list of strings with an optional filetype. The consumer owns scratch-buffer creation, rendering, and cleanup.
- Preserve the resolver completion/error contract, including async support and callback-once behavior. Do not substitute the selector's success-only contract here.
- Failed, missing, or invalid custom results fall back to built-in URL/help content. Report actual errors once, without duplicate logging between the resolver and adapter. Preview failure does not prevent selecting/opening the item.
- Validate the preview target before async updates and discard stale results after replacement or closure.
- Resolve on preview demand, not while constructing every picker entry.
- Add a code comment at the shared adapter identifying it as the reuse point for later hover implementation. Do not implement hover now.

Move the current Defuddle implementation out of core's default behavior into a documented recipe using `resolvers.url_preview`. The recipe owns network fetching and timeouts. Include supported HTTP(S) targets, third-party disclosure and sensitive-URL cautions, and appropriate response-size/cache/in-flight controls. Default previews make no network request and open no external application.

Update resolver configuration annotations, validation, docs/help routing for `:Obsidian help resolvers`, and tests together. Mock custom resolver/network behavior in tests. Check async rendering across adapters, especially fzf's scratch-buffer handling.

## 5. Quickfix and multi-selection

### Eligibility and default action

Give file/location browsers a shared `send_to_qf` action mapped to `<C-q>` by default. Use the per-call mapping override rules above to replace or disable it.

Eligible choices represent files/notes, optionally with a location. Folder destinations, URLs, bookmark groups, and other non-file rows do not gain automatic quickfix eligibility. String values are not automatically file paths; interfaces know whether their records represent files. Keep mixed lists safe and do not pretend unsupported records are quickfix entries.

The explicit export action bypasses the normal success callback; do not both export and open/insert/mutate.

### Selection semantics

- File/location browsers support multi-selection, including the native picker backend.
- Default navigation opens one selected item. Multiple selected items go to quickfix rather than dropping all but the first.
- An explicit consumer callback receives the complete successful selection unchanged. Do not intercept its multi-selection with automatic quickfix handling.
- Template acquisition and move destinations retain single-selection policies. Tags remain multi-select for their own workflows.
- `<C-q>` exports marked items when marks exist; otherwise it exports all currently filtered results, not the original unfiltered source and not just the current row.
- Preserve filtered ordering and item identity across backend adapters. Obtain actual filtered results from each backend; do not approximate its matching algorithm in the facade.

### List lifecycle and conversion

- Close the picker, create a new titled quickfix list, and open it. Preserve existing quickfix history for `:colder`/`:cnewer`.
- Share export/conversion logic across interfaces and adapters. Reuse and extend `picker.util.open_notes` where useful rather than introducing another first-item-only default.
- Preserve filename, line/column, range/end positions, useful text, and original payloads where needed. Convert domain ranges at the quickfix boundary and retain payloads in `user_data` rather than requiring quickfix to understand native records.
- Keep source-aware navigation/open strategies for the single-result path.

### Required conformance tests

For native, Telescope, fzf-lua, mini.pick, and Snacks adapters, test:

- Marked export takes precedence over filtered results.
- With no marks, export uses the current filtered set and its order.
- Duplicate display labels do not collapse distinct results.
- Default single confirmation opens; default multi confirmation exports every selected result.
- Custom callbacks receive the entire selection without automatic export.
- Explicit `<C-q>` does not also invoke the normal callback.
- Mapping overrides and removal work, including disabling defaults.
- Non-file/mixed rows stay safe; no invalid quickfix conversions.
- Position/range/text conversion, list title, quickfix history, picker cleanup, and quickfix opening behave consistently.

## 6. Complete links as the first feature slice

`interfaces.links` is the best completeness target: it has a visible preview gap and can reuse bookmark URL work.

1. Retain `LinkMatch` data rather than mapping it to `.link` strings. Capture source buffer/path.
2. Preserve current unique-link listing behavior by default. Make occurrence listing a separate mode if needed; do not change it by accident.
3. Add source-context preview first. This works for missing and ambiguous targets and needs no network.
4. Add read-only target previews: note, heading/block, local file/folder, external URL, missing target, ambiguous target summary.
5. Keep selection behavior routed through the existing follow/open action. Pass captured source context so relative and same-note links resolve against the source.
6. Reuse the same target-resolution and preview adapters for bookmarks where semantics match.

Important existing limitations:

- `search.find_links` reads `note.path` from disk even when the caller obtained the note from a buffer. A current-note interface needs live-buffer discovery to include unsaved edits.
- `_definition.follow_link` performs opening, prompts, and creation. Do not call it during preview. Extract or use a read-only resolution operation.
- `link.resolve_link_path` chooses one path; an ambiguous-link preview must not silently treat it as the authoritative unique result.

Test heading/block ranges, relative links, same-note links, aliases, duplicates, missing and ambiguous notes, external URLs, unsaved buffers, and cancellation.

## 7. Broader unifications, ordered by existing reuse

### A. Location results

Backlinks, TOC, workspace symbols, tag occurrences, property-note results, and unlinked mentions already have navigable locations. Share preview conversion and one-vs-many navigation behavior. Preserve payloads for mutation callbacks.

Keep occurrence results distinct from entity lists: “choose a tag” and “choose a tag occurrence” have different semantics.

### B. Tags and properties

Separate each browsing stage into reusable operations. Compose today's staged browser from those operations:

```text
tag identity -> matching locations
property key -> value -> matching notes
```

Then insertion and tagging reuse the first stage without opening a second browser. Property browsing can later return matching notes to a caller without opening one.

Keep current property string-comparison behavior during extraction. Type-aware equality is a follow-up behavior change: records should retain YAML types even if the current browser displays strings.

### C. Bookmark actions

Split “move bookmark to group” into acquiring a group and persisting the move. Keep the picker in the interface; expose the mutation with explicit bookmark/group identities in the domain module.

This also lets the existing bookmark picker mappings call reusable operations without depending on module-local UI functions. Reuse a group chooser rather than creating a second unrelated group picker.

### D. Note/resource selection

Move note-oriented composition out of generic picker mechanics over time:

- note/tag default mapping builders
- note search/find UI composition
- cache-derived note/missing-reference previews

`cache/api.lua:find_files` currently constructs entries, previews, opens a picker, and performs follow-up UI. First extract its data collection without changing behavior. Let an interface compose it with the fallback filesystem/search source.

Keep `picker.find_notes` and `grep_notes` as compatibility wrappers while callers migrate. Do not rewrite grep backend internals or add a search language as part of this work.

### E. Remaining selectors

Migrate workspace selection and generic file/resource selection when there is a repeated consumer. Command menus, sync-account menus, and one-off prompts can keep using generic `picker.select`; putting every menu into a primitive abstraction adds little value.

## 8. Resolver strategy

Keep existing attachment and hints contracts. Leave date/daily work untouched.

Add the confirmed `resolvers.url_preview` content resolver described above. It supplies presentation data rather than choosing input for an action. Document that distinction rather than forcing URL content into an acquisition result type.

Add no speculative tag, template, folder, or link-target acquisition hooks in this migration. Reusable data APIs and per-call picker options provide the current customization seam. A future action may justify an individual resolver with a documented typed result; that resolver should not require picker internals.

Keep resolver completion/error handling separate from selector success callbacks. Update configuration annotations, validation, tests, and resolver documentation together for the new URL hook.

Avoid a single `resolvers.ui` mega-hook or an explorer/view registry. UI-independent data operations plus callback-based selection preserve the future options.

## 9. Delivery sequence and checkpoints

### Commit 1: repair extraction

Finish tags, TOC, bookmark group/mappings, compatibility forwarding shims, and single-template acquisition with the preserved prompt. Add command-level argument and default-action tests.

Checkpoint: affected isolated tests and lint pass; existing commands keep defaults apart from the agreed improvements, and cancellation does nothing to source data.

### Commit 2: standardize existing interfaces

Implement `pick(opts, on_choice)`, nonempty success-only arrays, selector-owned errors/messages, quiet cancellation, source capture, mapping overrides, and callback replacement behavior. Convert the eight current interfaces and their callers. Extract property/bookmark data operations only as required to keep the boundary clear.

Checkpoint: stub-picker tests cover success, cancel, empty source, sync/async failure, single/multiple policy, default/mapping overrides, captured context, and custom callbacks without implicit side effects. Consumers need no error or empty-selection guards.

### Commit 3: shared previews

Centralize range/location/text/path handling, fix native-range support, use live buffers for current-note discovery and previews, and replace repeated preview callbacks. Retain guarded filename inference and implement `preview_item = false`.

Checkpoint: facade tests plus backend adapter tests verify positions, mixed lists, unsaved edits, custom overrides, disabled previews, and buffer cleanup.

### Commit 4: links and URL preview resolver

Complete source/target link previews. Add `resolvers.url_preview` with plain-URL/help defaults and content results, route URL previews through it, and move Defuddle into a recipe. Reuse target previews in bookmarks. Add the future-hover reuse comment, not a hover implementation.

Checkpoint: previews cause no opening, creation, or source edits. The default URL path makes no network request. Failed/invalid custom results fall back with actual errors reported once. Docs/help, config validation/annotations, async stale-result handling, and recipe behavior have coverage.

### Commit 5: quickfix and backend selection parity

Implement shared `send_to_qf` on `<C-q>`, marked-or-filtered export, new titled lists preserving history, and close-picker/open-quickfix behavior. Enable native-picker multi-selection and establish backend parity. Wire one-open/many-quickfix defaults into eligible browsing workflows without intercepting custom callbacks.

Checkpoint: the conformance cases in section 5 pass across all adapters; selected results are not silently discarded. Single-acquisition workflows remain single-select.

### Commit 6: remaining proven composition reuse

Unify repeated note/location selection and bookmark group acquisition. Extract cache-backed selection data and migrate note/search wrappers incrementally. Add no speculative resolver hooks.

Checkpoint: generic picker adapters contain no new domain-specific logic; existing commands and forwarding shims remain available. Stop here unless another consumer provides evidence for a larger abstraction.

Each commit should be releasable. Keep this sequence focused rather than opening parallel workstreams for new views, query syntax, property semantics, media rendering, or new primitives. One-off command/sync menus stay outside the migration.

## 10. Brainstorm: improvements to existing code

| Existing code | Reuse opportunity |
| --- | --- |
| `search_tags`, `insert_tag`, `add_tag` | One tag chooser; callbacks browse occurrences, insert text, or update frontmatter. All share casing and cancellation rules. |
| `new_from_template`, `insert_template` | One single-template chooser and preview; each action retains its own title prompt and mutation. |
| `move_note` | Folder chooser returns an explicit destination record; action retains validation/rename logic and caller context. |
| `links`, `bookmarks` | Shared note/section/file/URL target previews; different default actions and labels. |
| TOC, footnotes | Shared live-buffer location previews and source-aware navigation; multi-selection exports all results to quickfix. |
| backlinks, workspace symbols | Shared one-open/many-quickfix default and `<C-q>` export, with preserved open strategy and no repeated preview lambdas. |
| outgoing/incoming unlinked mentions | Reuse target/location picking while preserving the existing stale-text validation and reverse-order mutation behavior. |
| property search | Reuse key/value stages for selection callbacks, such as choosing a filter, without opening a note. |
| quick switch and link insertion | Share note candidate discovery; opening and inserting remain caller-supplied operations. |
| missing-reference picker | Shared safe missing-target preview and reference locations without asking a cache module to render a UI. |

Possible later consumers: a tag tree using the tag data API, a bookmark buffer using group children, an outline using heading/footnote locations. These illustrate why retaining records helps; none is an implementation requirement for this migration.

## 11. Initial review validation

These are historical checks from the initial review, not validation of the confirmed design's unimplemented features. Updating this plan does not change source code or add passing feature tests.

Read the tracked diff, eight new interface modules, picker facade/utilities and adapter code, affected actions/commands, resolver implementation/docs, cache picker composition, and the older primitive-UI proposal.

Ran these suites in separate Neovim processes:

| Suite | Cases | Failures |
| --- | ---: | ---: |
| `tests/test_picker.lua` | 12 | 0 |
| `tests/picker/test_select.lua` | 16 | 0 |
| `tests/actions/test_search_tags.lua` | 2 | 2 |
| `tests/actions/test_search_properties.lua` | 7 | 0 |
| `tests/test_bookmarks.lua` | 12 | 2 |
| `tests/test_footnotes.lua` | 6 | 1 |
| Total | 55 | 5 |

The tag failures call removed helpers. Bookmark/footnote failures call removed `.pick` APIs. These results are not a full-suite or real third-party-picker integration guarantee.

A combined run also showed picker stub/module-state leakage between suites; the corresponding picker suites pass in fresh processes. Track test isolation separately from feature regressions.

Focused stub-driven reproductions confirm:

- TOC selection calls a nil callback.
- Bookmark group selection calls a missing `M.pick`.
- Bookmark move/delete mappings have nil callbacks.
- Shared entry preview throws for an `obsidian.Range`.

Focused Selene check reports five undefined-helper errors in `actions.lua` and two unused-import warnings. No source code changed during this review.
