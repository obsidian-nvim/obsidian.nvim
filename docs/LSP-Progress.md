# LSP Progress

Tracking implementation status of [LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) features in `obsidian-ls`.

- `[x]` - Implemented
- `[ ]` - Not yet implemented, but feasible and meaningful for this plugin
- Plain list item - Not applicable, not meaningful, or redundant for an in-process LSP server

## Language Features

- [x] Go to Declaration (`textDocument/declaration`) - handled via `textDocument/definition`
- [x] Go to Definition (`textDocument/definition`) - follow wiki links, markdown links, header/block links, URIs, attachments
- [x] Find References (`textDocument/references`) - backlinks, tag references, header/block references across the vault
- [x] Document Symbols (`textDocument/documentSymbol`) - returns markdown headings
- [x] Rename (`textDocument/rename`) - rename notes and update all references across the vault
- [x] Prepare Rename (`textDocument/prepareRename`)
- [ ] Hover (`textDocument/hover`)
- [ ] Completion Proposals (`textDocument/completion`) - currently handled outside LSP via nvim-cmp/blink.cmp
- [ ] Completion Item Resolve (`completionItem/resolve`)
- [ ] Publish Diagnostics (`textDocument/publishDiagnostics`)
- [ ] Code Action (`textDocument/codeAction`)
- [ ] Code Action Resolve (`codeAction/resolve`)
- [ ] Document Link (`textDocument/documentLink`)
- [ ] Document Link Resolve (`documentLink/resolve`)
- [ ] Document Highlight (`textDocument/documentHighlight`)
- [ ] Code Lens (`textDocument/codeLens`)
- [ ] Code Lens Refresh (`codeLens/refresh`)
- [ ] Folding Range (`textDocument/foldingRange`)
- [ ] Selection Range (`textDocument/selectionRange`)
- [ ] Inlay Hint (`textDocument/inlayHint`)
- [ ] Inlay Hint Resolve (`inlayHint/resolve`)
- [ ] Inlay Hint Refresh (`workspace/inlayHint/refresh`)
- [ ] Formatting (`textDocument/formatting`)
- [ ] Range Formatting (`textDocument/rangeFormatting`)
- [ ] On Type Formatting (`textDocument/onTypeFormatting`)
- [ ] Linked Editing Range (`textDocument/linkedEditingRange`)
- [ ] Semantic Tokens (`textDocument/semanticTokens`) - highlighting currently handled via custom extmarks
- [ ] Document Color (`textDocument/documentColor`)
- [ ] Color Presentation (`textDocument/colorPresentation`)
- Pull Diagnostics (`textDocument/pullDiagnostics`) - redundant for in-process server, can push directly
- Go to Type Definition (`textDocument/typeDefinition`)
- Go to Implementation (`textDocument/implementation`)
- Prepare Call Hierarchy (`textDocument/prepareCallHierarchy`)
- Call Hierarchy Incoming Calls (`callHierarchy/incomingCalls`)
- Call Hierarchy Outgoing Calls (`callHierarchy/outgoingCalls`)
- Prepare Type Hierarchy (`textDocument/prepareTypeHierarchy`)
- Type Hierarchy Super Types (`typeHierarchy/supertypes`)
- Type Hierarchy Sub Types (`typeHierarchy/subtypes`)
- Signature Help (`textDocument/signatureHelp`)
- Inline Value (`textDocument/inlineValue`) - not supported by Neovim
- Inline Value Refresh (`workspace/inlineValue/refresh`) - not supported by Neovim
- Moniker (`textDocument/moniker`) - not supported by Neovim

## Workspace Features

- [x] Did Rename Files (`workspace/didRenameFiles`) - auto-updates all references when `.md` files are renamed
- [x] Apply Edit (`workspace/applyEdit`) - used by `didRenameFiles` to request the client apply workspace edits
- [x] Workspace Symbols (`workspace/symbol`)
- [x] Workspace Symbol Resolve (`workspace/symbolResolve`)
- [x] Execute Command (`workspace/executeCommand`) - runs all actions that this plugin can run in `actions.lua`
- [ ] Will Delete Files (`workspace/willDeleteFiles`) - for implementing [[Trash]] and remove file attachments functionality
- [ ] Will Create Files (`workspace/willCreateFiles`)
- [ ] Did Create Files (`workspace/didCreateFiles`)
- [ ] Will Rename Files (`workspace/willRenameFiles`)
- [ ] Did Delete Files (`workspace/didDeleteFiles`)
- [ ] Did Change Watched Files (`workspace/didChangeWatchedFiles`)
- Workspace Folders (`workspace/workspaceFolders`) - redundant for in-process server, already knows the workspace
- Did Change Workspace Folders (`workspace/didChangeWorkspaceFolders`) - redundant for in-process server
- Get Configuration (`workspace/configuration`) - redundant for in-process server, shares config directly
- Did Change Configuration (`workspace/didChangeConfiguration`) - redundant for in-process server

## Window Features

- [x] Create Work Done Progress (`window/workDoneProgress/create`) - sends `$/progress` during initialization
- Show Message Notification (`window/showMessage`) - redundant for in-process server, can call `vim.notify` directly
- Show Message Request (`window/showMessageRequest`) - redundant for in-process server, can call `vim.ui.select` directly
- Log Message (`window/logMessage`) - redundant for in-process server, uses internal logging
- Show Document (`window/showDocument`) - redundant for in-process server, can open buffers directly
- Cancel Work Done Progress (`window/workDoneProgress/cancel`) - client-side concern
- Telemetry Event (`telemetry/event`) - not supported by Neovim
