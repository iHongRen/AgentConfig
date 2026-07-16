# AGENTS.md

# AgentConfig — Project-specific

A native macOS app (SwiftUI + AppKit) for managing AI coding agent configuration files and agent profiles (Codex, Claude Code).

## Build

```
xcodebuild -project AgentConfig/AgentConfig.xcodeproj -scheme AgentConfig -configuration Debug build
```

## Project defaults

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — **all Swift code defaults to `@MainActor`**. Don't add `@MainActor` annotations, they're redundant.
- macOS deployment target: 14.0
- App Sandbox: disabled. Hardened Runtime: enabled.
- No Swift Package Manager dependencies.
- The Xcode project uses a filesystem-synchronized root group, so adding/removing Swift files under `AgentConfig/AgentConfig` is picked up by the target without manually editing `project.pbxproj` in ordinary cases.

## Tests

**There are no tests.** No XCTest target exists. When asked to add tests, create a test target in Xcode first.

## Architecture

**MVVM** with protocol-based service injection into ViewModels. `AppViewModel` is shared with sidebar/settings views via `environmentObject`; other ViewModels are passed explicitly through initializers.

```
Views (SwiftUI + AppKit via NSViewRepresentable)
  └─ ViewModels (@MainActor, ObservableObject, @Published)
      └─ Services (protocols, injected via init)
          └─ Models (plain structs/enums)
```

### Layout

`NavigationSplitView` with two columns: sidebar (`SidebarView` + `FileListView`) and detail pane. The detail pane switches between `EditorView` (for config files), `CodexProfileEditorView`, and `ClaudeProfileEditorView` based on sidebar selection. Responsive: sidebar auto-collapses when window width < 760pt.

### Key components

- **AgentConfigApp.swift** — `@main` entry point, `AppDelegate` (posts `appDidBecomeActive` for file-watcher refresh), `CommandCoordinator` (bridges editor callbacks to menu commands), `MainContentView`. Owns all `@StateObject` ViewModels: `AppViewModel`, `EditorViewModel`, `CodexProfileViewModel`, `ClaudeProfileViewModel`, `CommandCoordinator`.
- **ContentView.swift** — Placeholder view (not used in main flow).
- **AppViewModel** — central coordinator: owns AgentScanner, FileService, AppSettings. Handles file selection, custom paths, hide/show files. Defines `CategorySelection` enum (`.agent` / `.env`).
- **EditorViewModel** — file editing (load/save/undo/redo/search/JSON format), external change detection, source runner for shell files. Content is a `@Published` two-way binding to the NSTextView.
- **CodexProfileViewModel** — manages Codex profile selection, editing, persistence, and applying profiles to disk.
- **ClaudeProfileViewModel** — manages Claude Code profile selection, editing, persistence, and applying profiles to disk. Mirrors `CodexProfileViewModel` structure.
- **SidebarView** — shows environment files, known agent files, custom-added files, missing files, plus profile subsections under Codex and Claude Code agents.
- **FileListView** — middle column within the sidebar area; lists files for the selected category with creation buttons for missing files and unsaved-change indicators.
- **EditorView / CodeEditorView** — `NSTextView` wrapped via `NSViewRepresentable`. Syntax highlighting via `SyntaxHighlighter` (`NSTextStorageDelegate`, regex-based). Comment toggle via `CommentingTextView` (Cmd+/ for `#`, `//`, `%` prefixes based on `FileType`).
- **EditorToolbarView** — top toolbar showing filename (with unsaved indicator), JSON format button, and inline format-error location.
- **SearchBarView** — VSCode-style search bar with keyword highlighting, prev/next navigation, and case-sensitivity toggle.
- **AgentProfileEditorView** — generic, reusable profile editor driven by `AgentProfileEditorProfile` / `AgentProfileEditorField` value types. Used by both `CodexProfileEditorView` and `ClaudeProfileEditorView`.
- **AgentProfileCodeEditor** — resizable code editor cards for `AgentProfileEditorView`, with drag-to-resize handles and height persistence.
- **CodexProfileEditorView** — adapts `AgentProfileEditorView` for Codex profiles (config TOML, auth JSON, zshrc exports).
- **ClaudeProfileEditorView** — adapts `AgentProfileEditorView` for Claude Code profiles (settings JSON, claude.json, zshrc exports).
- **ProfileFieldHelpButton** — small `?` button that shows a popover with field help text.
- **CommentingTextView** — `NSTextView` subclass handling Cmd+/ comment toggling, dispatching to `FileType.lineCommentPrefix`.
- **SettingsView** — appearance (light/dark/system) and language (en/zh-Hans/system) settings.
- **AboutView** — app info, version, build number, author credits.
- **AgentScanner** — scans `~` for known agent config files using definitions from `AgentDefinitions` (2 enabled: Claude Code, Codex; 3 commented-out: Gemini CLI, OpenCode CLI, Qwen Code).
- **FileWatcher** — `DispatchSourceFileSystemObject` with 500ms debounce for external change detection.
- **AppSettings** — `UserDefaults` wrapper for appearance, language, customPaths, hiddenFiles, and per-category added file paths.
- **AppError** — `LocalizedError` enum: `fileReadFailed`, `fileWriteFailed`, `jsonFormatError`.
- **FileType** — enum covering `json`, `jsonc`, `json5`, `jsonl`, `yaml`, `toml`, `shell`, `plainText`. Drives syntax highlighting, comment prefixes, and SF Symbol icons.
- **i18n** — `NSLocalizedString` with en and zh-Hans. Language switching via `UserDefaults.standard.set(..., forKey: "AppleLanguages")` + view-tree rebuild through `languageChangeID`.

### Service protocols

Each service is defined as a protocol + implementation:

| Protocol | Implementation | Role |
|----------|---------------|------|
| `AgentScannerProtocol` | `AgentScanner` | Discover config files on disk |
| `FileServiceProtocol` | `FileService` | Read/write/create/delete files |
| `FileWatcherProtocol` | `FileWatcher` | Watch open files for external changes |
| `CodexProfileServiceProtocol` | `CodexProfileService` | Persist and apply Codex profiles (`~/.codex/config.toml`, `~/.codex/auth.json`, managed `.zshrc` block). Writes are transactional with rollback on failure. |
| `ClaudeProfileServiceProtocol` | `ClaudeProfileService` | Persist and apply Claude Code profiles (`~/.claude/settings.json`, deep-merge `.claude.json` into disk copy, managed `.zshrc` block). Writes are transactional with rollback on failure. |

### Data flow

1. App launch → `AppViewModel.refresh()` → `AgentScanner.scan()` → categories + files in sidebar
2. User clicks file → `AppViewModel.selectedFile` changes → `EditorView` loads via `EditorViewModel.load(file:)`
3. Cmd+S → `EditorViewModel.save()` → `FileService.write()`
4. User selects a Codex profile → `CodexProfileViewModel.selectedProfile` changes → detail pane shows `CodexProfileEditorView`
5. User selects a Claude profile → `ClaudeProfileViewModel.selectedProfile` changes → detail pane shows `ClaudeProfileEditorView`
6. User applies profile → `CodexProfileService.apply(profile:)` writes agent config and managed `.zshrc` block; `ClaudeProfileService.apply(profile:)` writes `settings.json`, deep-merges `.claude.json` with disk, and updates managed `.zshrc` block

### Adding a new agent

1. In `AgentDefinitions.swift`, uncomment the existing agent definition (Gemini CLI, OpenCode CLI, Qwen Code are already defined but commented out) or add a new `AgentDefinition` to the `allAgents` array
2. Add icon image to `Assets.xcassets`
3. Update i18n strings for both en and zh-Hans if user-facing copy is added

### Adding a new agent profile type

1. Create `Model` struct (e.g. `ClaudeProfile`) with `Identifiable`, `Codable`, `Equatable`
2. Create `ServiceProtocol` + implementation (persist to Application Support, apply to target files)
3. Create `ViewModel` (mirrors `CodexProfileViewModel` / `ClaudeProfileViewModel` pattern)
4. Create thin editor view that maps profile fields to `AgentProfileEditorProfile` / `AgentProfileEditorField` and delegates to `AgentProfileEditorView`
5. Add `@StateObject` in `AgentConfigApp`, pass to `MainContentView` and `SidebarView`
6. Add selection check in `MainContentView` detail-pane routing

###  DO NOT send optional commentary