# fixpoint.nvim

[![CI](https://github.com/sindrip/fixpoint.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/sindrip/fixpoint.nvim/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A collection of in-process LSP servers for Neovim (0.12+). No external binaries, no spawned processes -- everything runs inside your Neovim instance.

## Servers

| Server | Description |
|---|---|
| `fixpoint_fswatcher` | Watches open files for external changes and reloads buffers via debounced `checktime` |
| `fixpoint_format` | Formatting server (stub) |

## Installation

Requires Neovim >= 0.12

```lua
vim.pack.add({ "https://github.com/sindrip/fixpoint.nvim" })
```

## Usage

Enable the servers you want:

```lua
vim.lsp.enable("fixpoint_fswatcher")
vim.lsp.enable("fixpoint_format")
```

## Development

Tools are managed with [mise](https://mise.jdx.dev/):

```sh
mise install    # installs lefthook, lua-language-server, stylua
mise test       # runs typecheck + tests
```
