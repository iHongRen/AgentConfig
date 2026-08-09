# AgentConfig

[![GitHub Release](https://img.shields.io/github/v/release/iHongRen/AgentConfig?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) [![Downloads](https://img.shields.io/github/downloads/iHongRen/AgentConfig/total?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) ![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple) [![License](https://img.shields.io/github/license/iHongRen/AgentConfig?style=flat-square)](./LICENSE)

[中文](./README.md)

A native macOS app for managing Codex, Claude Code, OpenCode, and Qwen Code config files, API keys, and environment variables — with multi-profile switching.

![](./screenshots/screenshot_en.png)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/iHongRen/AgentConfig/main/install.sh | sh
```

Or download `AgentConfig.dmg` from [GitHub Releases](https://github.com/iHongRen/AgentConfig/releases). If blocked by macOS Gatekeeper:

```sh
xattr -dr com.apple.quarantine /Applications/AgentConfig.app
```

## Features

- Profile support for Codex, Claude Code, OpenCode, and Qwen Code
- Multi-account API key switching
- Isolated profile blocks
- Visual env var management
- Syntax highlighting editor
- Search & format (Cmd+F)
- External change detection
- Managed `.zshrc` blocks without overwriting your existing shell config
- Transactional config writes with rollback on failure
- Sidebar quick actions
- Drag & drop to add files

## Supported Config Files

| Agent | Files |
|-------|-------|
| **Codex** | `~/.codex/config.toml`, `~/.codex/auth.json` |
| **Claude Code** | `~/.claude/settings.json`, `~/.claude.json` |
| **OpenCode** | `~/.config/opencode/opencode.json`, `~/.local/share/opencode/auth.json` |
| **Qwen Code** | `~/.qwen/settings.json`, `~/.qwen/settings.json.env` |
| **Shell env** | `.zshrc`, `.zprofile`, `.bashrc`, `.bash_profile`, etc. |

OpenCode scanning also recognizes common `opencode.jsonc` locations, while applying a profile writes to `~/.config/opencode/opencode.json`.



## Security

This app makes **no network requests**. All data is stored entirely on your local machine — your API keys and configs are never uploaded or leaked.
