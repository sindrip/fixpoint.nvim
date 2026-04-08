# fixpoint.nvim architecture

A single Neovim plugin that ships a collection of in-process LSP servers. Each server is independently enabled via `vim.lsp.config` / `vim.lsp.enable` — no setup calls, no wrapper API. Users configure fixpoint servers exactly like they configure `lua_ls` or `rust_analyzer`.

Requires Neovim 0.12+.

---

## Repo layout

```
fixpoint.nvim/
├── lsp/
│   ├── fixpoint_format.lua
│   └── fixpoint_todocomments.lua
├── lua/
│   └── fixpoint/
│       ├── server.lua
│       ├── format/
│       │   ├── init.lua
│       │   ├── pipeline.lua
│       │   ├── proxy.lua
│       │   ├── types.lua
│       │   └── formatters/
│       │       ├── biome.lua
│       │       ├── prettier.lua
│       │       ├── prettierd.lua
│       │       ├── stylua.lua
│       │       ├── black.lua
│       │       ├── autopep8.lua
│       │       ├── ruff_format.lua
│       │       ├── isort.lua
│       │       ├── gofmt.lua
│       │       ├── gofumpt.lua
│       │       ├── goimports.lua
│       │       ├── golines.lua
│       │       ├── deno_fmt.lua
│       │       └── eslint_d.lua
│       └── todocomments/
│           └── init.lua
├── test/
│   ├── helpers.lua
│   ├── fixtures/
│   ├── format/
│   │   ├── resolve_test.lua
│   │   ├── compute_edits_test.lua
│   │   ├── format_test.lua
│   │   ├── proxy_test.lua
│   │   ├── pipeline_test.lua
│   │   └── formatter_test.lua
│   └── todocomments/
│       └── ...
├── doc/
│   └── fixpoint.txt
├── .github/workflows/ci.yml
├── Makefile
├── stylua.toml
├── .styluaignore
├── .luarc.json
├── mise.toml
├── LICENSE
└── README.md
```

---

## Layer responsibilities

### `lsp/` — config entry points

One file per server. The filename is the server name. Each file is a one-liner that returns the built config from the corresponding module:

```lua
-- lsp/fixpoint_format.lua
return require("fixpoint.format")

-- lsp/fixpoint_todocomments.lua
return require("fixpoint.todocomments")
```

Neovim discovers these automatically when fixpoint.nvim is on the runtimepath. The return value from each module is a table with `{ cmd, root_markers, single_file_support }` — produced by `Server:build()`.

No `plugin/` directory. No autocommands. No setup function. Users opt in with `vim.lsp.enable`.

### `lua/fixpoint/server.lua` — shared base class

The Server base class is the core of the plugin. Both existing repos already have nearly identical copies. The todocomments-ls version is the more complete one (has `pcall` wrapping in `handle_request` and `notify_reply_callback` support) and becomes the canonical version.

The class provides:

- `Server.new(name)` — creates a server instance with `requests` and `notifications` tables, pre-populated with `initialize`, `shutdown`, and `exit` handlers
- `on_init(params)` / `on_shutdown()` — lifecycle hooks the server overrides
- `handle_request(method, params, callback, notify_reply_callback)` — dispatches to `self.requests[method]`, wraps in `pcall`
- `handle_notify(method, params)` — dispatches to `self.notifications[method]`
- `build()` — returns the `vim.lsp.Config`-compatible table with `cmd` as a function

The `build()` method is the key integration point. It returns:

```lua
{
  cmd = function(dispatchers)
    -- creates a per-client instance via setmetatable({...}, { __index = proto })
    -- returns { request, notify, is_closing, terminate }
  end,
  root_markers = self.root_markers,
  single_file_support = self.single_file_support,
}
```

This is exactly the shape Neovim expects from `lsp/<name>.lua`. The `cmd` function receives dispatchers from the LSP client and returns a `vim.lsp.rpc.PublicClient`. The `setmetatable` pattern creates a fresh per-client instance that inherits from the server prototype — so each LSP client gets its own `dispatchers`, `closing`, and `request_id` state while sharing handler definitions.

### `lua/fixpoint/<server>/` — server implementations

Each server is a self-contained module that creates a `Server` instance, declares capabilities, registers handlers, and calls `build()`.

**Format server** (`lua/fixpoint/format/init.lua`) — the most complex server. Capabilities: `documentFormattingProvider`, `documentRangeFormattingProvider`, `textDocumentSync` (openClose). Uses `init_options` for configuration (not `settings`). On init, reads `formatters_by_ft` and optional `formatters` specs from `initializationOptions`. Starts a proxy that intercepts other LSP servers' formatting capabilities so all format requests flow through fixpoint. The pipeline resolves groups per-filetype, runs CLI formatters via `vim.system`, delegates LSP formatting/code actions to the original servers.

Supporting modules in the format directory:
- `pipeline.lua` — group resolution, CLI execution, edit computation (`vim.text.diff`), pipeline orchestration
- `proxy.lua` — intercepts `LspAttach`/`LspDetach`, steals `documentFormattingProvider` from other clients, tracks original capabilities for restoration on shutdown
- `types.lua` — LuaCATS type annotations
- `formatters/*.lua` — spec files (cmd, args, config_files) for each supported formatter

**Todo-comments server** (`lua/fixpoint/todocomments/init.lua`) — simpler server. Capabilities: `textDocumentSync` (change + openClose), `colorProvider`. Maintains an in-memory document store. On `didOpen`/`didChange`, scans buffer text for keyword patterns, verifies they're inside comments via treesitter (`get_string_parser`), publishes diagnostics via `dispatchers.notification`. Responds to `textDocument/documentColor` with colors resolved from highlight groups at runtime.

---

## User configuration

```lua
-- Enable both servers
vim.lsp.enable({ "fixpoint_format", "fixpoint_todocomments" })

-- Configure formatting pipelines
vim.lsp.config("fixpoint_format", {
  init_options = {
    formatters_by_ft = {
      typescript = {
        { "biome" },
        { "source.organizeImports", "prettier" },
      },
      go = {
        { "source.organizeImports", "textDocument/formatting" },
      },
      lua = {
        { "stylua" },
      },
    },
  },
})

-- todocomments works with zero config — just enable it
```

Note: the format server uses `init_options` (maps to `initializationOptions` in LSP), not `settings`. This is because the config is read once on `initialize` — the pipeline resolution happens eagerly per-filetype on first `didOpen`. This is a deliberate design choice from the original formatls.

---

## Server naming

Servers use `fixpoint_` prefix with underscores: `fixpoint_format`, `fixpoint_todocomments`. Underscores over hyphens because the filename is the server name and underscores are valid Lua identifiers. The prefix avoids collisions with other plugins' server definitions.

---

## Migration from existing repos

The migration is mostly mechanical — renaming `require` paths:

| Old path | New path |
|---|---|
| `formatls.server` | `fixpoint.server` |
| `formatls.pipeline` | `fixpoint.format.pipeline` |
| `formatls.proxy` | `fixpoint.format.proxy` |
| `formatls.formatters.biome` | `fixpoint.format.formatters.biome` |
| `formatls.health` | `fixpoint.health` (unified) |
| `todocomments-ls.server` | `fixpoint.server` |

The only real code change is merging the two `server.lua` files. The todocomments-ls version is the superset — it adds `pcall` protection in `handle_request` and `notify_reply_callback` support. The formatls version should adopt both.

---

## Health check

A single `:checkhealth fixpoint` that checks all enabled servers. Lives at `lua/fixpoint/health.lua`. Iterates `vim.lsp.get_clients` for names starting with `fixpoint_`, reports status for each. The format server's health logic (pipeline resolution per-buffer) moves here under a format-specific section.

---

## Open questions

**`bench` utility** — todocomments-ls currently bolts a `bench` function onto the built config object. This should move to `require("fixpoint.todocomments").bench()` or a dev-only command, not pollute the LSP config table.

**Config via `init_options` vs `settings`** — the format server uses `init_options` (read once on initialize). If we want live-reloadable config, `settings` with `workspace/didChangeConfiguration` is the LSP-standard approach. This is a future consideration — the current approach works and is simpler.

**Per-client vs singleton state** — `build()` creates per-client instances via `setmetatable`, but the todo-comments server stores documents in module-level tables (`documents`, `scan_cache`). This is fine for single-workspace use. Multiple workspaces with separate `root_dir` values would share the document store, which is correct for this server (it doesn't care about workspace boundaries). The format server's proxy is also initialized in `on_init` per-client, so it handles the multi-client case naturally.

**Adding new servers** — the pattern for adding a third server (e.g. document colors for hex/rgb/hsl, or a spelling server) is: create `lua/fixpoint/<name>/init.lua` that uses `fixpoint.server`, add `lsp/fixpoint_<name>.lua` as a one-liner. No changes to existing code.
