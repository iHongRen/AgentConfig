# AgentConfig

[![GitHub Release](https://img.shields.io/github/v/release/iHongRen/AgentConfig?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) [![Downloads](https://img.shields.io/github/downloads/iHongRen/AgentConfig/total?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) ![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple) [![License](https://img.shields.io/github/license/iHongRen/AgentConfig?style=flat-square)](./LICENSE)

[English](./README_en.md)

原生 macOS App，集中管理 Codex、Claude Code 的配置文件，支持多套 Profile 快速切换。

![](./screenshots/screenshot_cn.png)

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/iHongRen/AgentConfig/main/install.sh | sh
```

或从 [GitHub Releases](https://github.com/iHongRen/AgentConfig/releases) 下载 `AgentConfig.dmg`。如遇安全提示：

```sh
xattr -dr com.apple.quarantine /Applications/AgentConfig.app
```

## 功能

- **配置编辑** — 语法高亮（JSON / JSONC / JSON5 / JSONL / YAML / TOML / Shell / 纯文本）、Cmd+F 搜索、JSON 格式化、外部变更检测
- **Profile 管理** — 多套方案一键写回磁盘，`.zshrc` 托管块独立分区不覆盖原有内容，多文件事务写入失败自动回滚
- **侧边栏** — 启动扫描已安装 Agent 的配置文件和 Shell 环境变量文件，右键菜单直达 Finder / VSCode / 复制路径，拖拽文件到分类即可收录

## 配置文件

**Codex**：`~/.codex/config.toml`、`~/.codex/auth.json`

**Claude Code**：`~/.claude/settings.json`、`~/.claude.json`

**Shell 环境变量**：`.zshrc`、`.zprofile`、`.zshenv`、`.bashrc`、`.bash_profile` 等