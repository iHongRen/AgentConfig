# AgentConfig

[![GitHub Release](https://img.shields.io/github/v/release/iHongRen/AgentConfig?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) [![Downloads](https://img.shields.io/github/downloads/iHongRen/AgentConfig/total?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) ![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple) [![License](https://img.shields.io/github/license/iHongRen/AgentConfig?style=flat-square)](./LICENSE)

[English](./README_en.md)

原生 macOS App，集中管理 Codex、Claude Code、OpenCode、Qwen Code 等 AI 编程工具的配置文件和 API Key，支持多套配置快速切换。

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

- 支持 Codex、Claude Code、OpenCode、Qwen Code 四类 Agent Profile
- 多账号 API Key 一键切换
- Profile 独立分区管理
- 可视化增删环境变量
- 多格式语法高亮编辑
- Cmd+F 搜索与格式化
- 外部变更自动检测
- `.zshrc` 托管块写入，不覆盖原有内容
- 配置写入失败自动回滚
- 侧边栏右键快捷操作
- 拖拽文件快速收录

## 支持的配置文件

| Agent | 文件 |
|-------|------|
| **Codex** | `~/.codex/config.toml`、`~/.codex/auth.json` |
| **Claude Code** | `~/.claude/settings.json`、`~/.claude.json` |
| **OpenCode** | `~/.config/opencode/opencode.json`、`~/.local/share/opencode/auth.json` |
| **Qwen Code** | `~/.qwen/settings.json`、`~/.qwen/settings.json.env` |
| **环境变量** | `.zshrc`、`.zprofile`、`.bashrc`、`.bash_profile` 等 |

OpenCode 扫描时同时兼容常见的 `opencode.jsonc` 路径，应用 Profile 时统一写入 `~/.config/opencode/opencode.json`。


## 安全

本应用**无网络请求**，所有数据完全存储在本地，不会上传或泄露你的 API Key 和配置信息。
