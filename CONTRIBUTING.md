# Contributing to `obsidian.nvim`

Thanks for considering contributing!
Please read this document to learn the various steps you should take before submitting a pull request.

## TL;DR

- Start an issue to discuss the planned changes
- To submit a pull request
  - Start developing your feature in a branch
  - Make sure that your codes complies the `obsidian.nvim` code style, run
    `make chores`
  - The PR should contain
    - The code changes
    - Tests for the code changes
    - Documentation for the code changes (in the code itself and in the `README.md`)
    - `CHANGELOG.md` entry for the code changes

## Details

Note: we automate tedious tasks using a `Makefile` in the root of the repository.
Just call `make` to see what you can do, or `make chores` to run the most important tasks on your code.

If you don't want to install the dependency need for some of the checks, you can also just open a PR to leverage GitHub actions for the check.

### Keeping the `CHANGELOG.md` up-to-date

This project maintains a [`CHANGELOG`](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/CHANGELOG.md)
with a format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

If your PR addresses a bug or makes any other substantial change,
please be sure to add an entry under the "Unreleased" section at the top of `CHANGELOG.md`.
Entries should always be in the form of a list item under a level-3 header of either "Added", "Fixed", "Changed", or "Removed" for the most part.
If the corresponding level-3 header for your item does not already exist in the "Unreleased" section, you should add it.

### Formatting code

TL;DR: `make style`

Lua code should be formatted using [StyLua](https://github.com/JohnnyMorganz/StyLua).
Once you have StyLua installed, you can run `make style` to automatically apply styling to all of the Lua files in this repo.

### Linting code

TL;DR: `make lint`

- We use [selene](https://github.com/Kampfkarren/selene) to lint the Lua code and [typos](https://github.com/crate-ci/typos) to catch typos.
- Once you have `selene` and `typos` installed, you can run `make lint` to get a report.

### Checking types

TL;DR: `make types`

- We use [EmmyLua Analyzer Rust](https://github.com/CppCXY/emmylua-analyzer-rust) to check the type annotations in the Lua code.
- Type-check warnings fail CI. Avoid `---@diagnostic disable`; when an external definition makes one unavoidable, keep it to one line and explain why.
- Project types must be namespaced. Reserve `obsidian.TypeName` for foundational public types and use `obsidian.<lowercase-domain>.<PascalCaseType>` otherwise.
- Put public and module interface types near the top of their owning module. Put private implementation records immediately before the implementation that owns them. Use a separate type-only file only when several sibling modules share a type and none clearly owns it.
- Use `snake_case` fields, retaining established Neovim names such as `bufnr` and `winnr`.

#### Source coordinates

Internal document coordinates use `obsidian.Pos` and `obsidian.Range`: rows and columns are zero-based, columns are byte offsets, and range ends are exclusive. Use `row` and `col` for scalar internal coordinates.

External coordinate names belong only at their adapters:

- Neovim cursor tuples use one-based `lnum` and zero-based byte `col`.
- Quickfix entries use `lnum`, `col`, `end_lnum`, and `end_col`.
- LSP structures use `line` and `character` and must be converted with `Pos`/`Range` helpers.
- Provider-specific fields such as ripgrep's `line_number`, `start`, and `end` stay in the provider module and are normalized before reaching callers.

Do not add duplicate convenience fields when a position can be derived from a `Pos` or `Range`. Document any unavoidable exception at the declaration.

### Running tests

TL;DR: `make test`

- Tests are written in the `tests/` folder and are run using [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md). The make command will download the dependencies for you.
  - For a reference of using mini.test, see [this guide](https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md).
- For async tests, use the helpers in `tests/helpers.lua`:
  - `h.child_await(child, lua, { desc = "..." })` for callback-style child-Neovim async code.
  - `h.child_wait(child, lua, { desc = "..." })` or focused helpers like `h.child_wait_for_buf_name()` for eventual child state.
  - Avoid raw `vim.wait()` and fixed sleeps in tests; always wait for a specific condition with a timeout message.

### Building the vim user documentation

TL;DR: `make user-docs`

- The Vimdoc help lives at `doc/obsidian.txt`, which is automatically generated from the `README.md` using [markdoc](https://github.com/OXY2DEV/markdoc.nvim)
- **Please only commit documentation changes to the `README.md`, not `doc/obsidian.txt`.**
- This step don't need to be done locally since CI will auto run.

### Building the vim API documentation

TL;DR: `make api-docs`

- The API docs lives in `doc/obsidian_api.txt` and is generated from the source code using [`mini.docs`](https://github.com/echasnovski/mini.doc).
- This step don't need to be done locally since CI will auto run.

### Contribute to the documentation

Documentation is maintained in [`docs/`](docs/) and published with Quartz. See the [documentation contribution guide](docs/Contributing-to-docs.md) for local preview and writing conventions.
