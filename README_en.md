# AgentConfig

[![GitHub Release](https://img.shields.io/github/v/release/iHongRen/AgentConfig?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) [![Downloads](https://img.shields.io/github/downloads/iHongRen/AgentConfig/total?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) ![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple) [![License](https://img.shields.io/github/license/iHongRen/AgentConfig?style=flat-square)](./LICENSE)

[中文](./README.md)

A native macOS app for managing Codex and Claude Code config files, API keys, and environment variables — with multi-profile switching.

![](./screenshots/screenshot_en.png)

## Features

- Multi-account API key switching
- Isolated profile blocks
- Visual env var management
- Syntax highlighting editor
- Search & format (Cmd+F)
- External change detection
- Sidebar quick actions
- Drag & drop to add files

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/iHongRen/AgentConfig/main/install.sh | sh
```

Or download `AgentConfig.dmg` from [GitHub Releases](https://github.com/iHongRen/AgentConfig/releases). If blocked by macOS Gatekeeper:

```sh
xattr -dr com.apple.quarantine /Applications/AgentConfig.app
```

## Security

This app makes **no network requests**. All data is stored entirely on your local machine — your API keys and configs are never uploaded or leaked.
