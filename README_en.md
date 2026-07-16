# AgentConfig

[![GitHub Release](https://img.shields.io/github/v/release/iHongRen/AgentConfig?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) [![Downloads](https://img.shields.io/github/downloads/iHongRen/AgentConfig/total?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) ![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple) [![License](https://img.shields.io/github/license/iHongRen/AgentConfig?style=flat-square)](./LICENSE)

[中文](./README.md)

A native macOS app for managing Codex and Claude Code config files, with multi-profile switching.

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

- **Config Editor** — Syntax highlighting (JSON / JSONC / JSON5 / JSONL / YAML / TOML / Shell / Plain Text), Cmd+F search, JSON formatting, external change detection
- **Profile Manager** — One-click apply profiles to disk, managed `.zshrc` blocks isolated from your own config, transactional multi-file writes with auto-rollback on failure
- **Sidebar** — Auto-scans installed agent configs and shell env files, right-click to open in Finder / VSCode / copy path, drag files onto a category to add them

## Config Files

**Codex**：`~/.codex/config.toml`, `~/.codex/auth.json`

**Claude Code**：`~/.claude/settings.json`, `~/.claude.json`

**Shell env**：`.zshrc`, `.zprofile`, `.zshenv`, `.bashrc`, `.bash_profile`, etc 
