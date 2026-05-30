# AGENTS.md

# AgentConfig — Project-specific

A native macOS app (SwiftUI + AppKit) for managing AI coding agent configuration files and Codex profiles.

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

### Key components

- **AgentConfigApp.swift** — `@main` entry point, `AppDelegate`, `CommandCoordinator`, `MainContentView`. The app is a single `NavigationSplitView` with sidebar and detail panes. It owns `AppViewModel`, `EditorViewModel`, `CodexProfileViewModel`, and menu command coordination.
- **AppViewModel** — central coordinator: owns AgentScanner, FileService, AppSettings. Handles file selection, custom paths, hide/show files.
- **EditorViewModel** — file editing (load/save/undo/redo/search/JSON format), external change detection, source runner for shell files. Content is a `@Published` two-way binding to the NSTextView.
- **CodexProfileViewModel** — manages Codex profile selection, editing, persistence, validation, and applying profiles to disk.
- **CodexProfileService** — stores profiles in Application Support and applies the selected profile to `~/.codex/config.toml`, `~/.codex/auth.json`, and a managed block in `~/.zshrc`.
- **SidebarView** — shows environment files, known agent files, custom-added files, missing files, and a Codex Profiles subsection under the Codex agent.
- **EditorView / CodeEditorView** — `NSTextView` wrapped via `NSViewRepresentable`. Syntax highlighting via `SyntaxHighlighter` (`NSTextStorageDelegate`, regex-based).
- **CodexProfileEditorView** — detail pane for editing profile name, config TOML, auth JSON, zshrc exports, previewing affected files, and applying the profile.
- **AgentScanner** — scans `~` for known agent config files using definitions from `AgentDefinitions` (currently 5 default agents: Claude Code, Codex, Gemini CLI, OpenCode CLI, Qwen Code).
- **FileWatcher** — `DispatchSourceFileSystemObject` with 500ms debounce for external change detection.
- **AppSettings** — `UserDefaults` wrapper for appearance, language, autoSource, customPaths, hiddenFiles, and per-category added file paths.
- **i18n** — `NSLocalizedString` with en and zh-Hans. Language switching via `UserDefaults.standard.set(..., forKey: "AppleLanguages")`.

### Service protocols

Each service is defined as a protocol + implementation:

| Protocol | Implementation | Role |
|----------|---------------|------|
| `AgentScannerProtocol` | `AgentScanner` | Discover config files on disk |
| `FileServiceProtocol` | `FileService` | Read/write/create/delete files |
| `SourceRunnerProtocol` | `SourceRunner` | Run `source` on shell files |
| `FileWatcherProtocol` | `FileWatcher` | Watch open files for external changes |
| `CodexProfileServiceProtocol` | `CodexProfileService` | Persist and apply Codex profiles |

### Data flow

1. App launch → `AppViewModel.refresh()` → `AgentScanner.scan()` → categories + files in sidebar
2. User clicks file → `AppViewModel.selectedFile` changes → `EditorView` loads via `EditorViewModel.load(file:)`
3. Cmd+S → `EditorViewModel.save()` → `FileService.write()` → optional `SourceRunner.source()` for shell files
4. User selects a Codex profile → `CodexProfileViewModel.selectedProfile` changes → detail pane switches to `CodexProfileEditorView`
5. User applies profile → `CodexProfileViewModel.applySelected()` → `CodexProfileService.apply(profile:)` writes Codex config/auth files and updates the managed `.zshrc` block

### Adding a new agent

1. Add entries to `AgentDefinitions.swift` static arrays
2. Add icon image to `Assets.xcassets`
3. Update i18n strings for both en and zh-Hans if user-facing copy is added

### Removed features

- There is no Git history/restore service in the app. Do not reintroduce `GitService`, `GitViewModel`, `GitHistoryView`, or Git error cases unless explicitly requested.
- There is no configuration examples pane. Do not reintroduce `ConfigExamples`, `ConfigExample`, or `ConfigExamplesPaneView` unless explicitly requested.
