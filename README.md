# AgentConfig

[![GitHub Release](https://img.shields.io/github/v/release/iHongRen/AgentConfig?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) [![Downloads](https://img.shields.io/github/downloads/iHongRen/AgentConfig/total?style=flat-square)](https://github.com/iHongRen/AgentConfig/releases) ![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple) [![License](https://img.shields.io/github/license/iHongRen/AgentConfig?style=flat-square)](./LICENSE)

[English](./README_en.md)

原生 macOS App，集中管理 Codex、Claude Code 等 AI 编程工具的配置文件和 API Key，支持多套配置快速切换。

![](./screenshots/screenshot_cn.png)

## 功能

- 多账号 API Key 一键切换
- Profile 独立分区管理
- 可视化增删环境变量
- 多格式语法高亮编辑
- Cmd+F 搜索与格式化
- 外部变更自动检测
- 侧边栏右键快捷操作
- 拖拽文件快速收录

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/iHongRen/AgentConfig/main/install.sh | sh
```

或从 [GitHub Releases](https://github.com/iHongRen/AgentConfig/releases) 下载 `AgentConfig.dmg`。如遇安全提示：

```sh
xattr -dr com.apple.quarantine /Applications/AgentConfig.app
```

## 安全

本应用**无网络请求**，所有数据完全存储在本地，不会上传或泄露你的 API Key 和配置信息。
