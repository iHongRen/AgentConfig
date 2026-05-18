# CLAUDE.md

# AgentConfig — Project-specific

A native macOS app (SwiftUI + AppKit) for managing AI coding agent configuration files.

## Build

```
xcodebuild -project AgentConfig/AgentConfig.xcodeproj -scheme AgentConfig -configuration Debug build
```

## Project defaults

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — **all Swift code defaults to `@MainActor`**. Don't add `@MainActor` annotations, they're redundant.
- macOS deployment target: 14.0
- App Sandbox: disabled. Hardened Runtime: enabled.
- No Swift Package Manager dependencies.

## Tests

**There are no tests.** No XCTest target exists. When asked to add tests, create a test target in Xcode first.

## Architecture

**MVVM** with protocol-based dependency injection. No SwiftUI environment objects — services are passed explicitly via init.

```
Views (SwiftUI + AppKit via NSViewRepresentable)
  └─ ViewModels (@MainActor, ObservableObject, @Published)
      └─ Services (protocols, injected via init)
          └─ Models (plain structs/enums)
```

### Key components

- **AgentConfigApp.swift** — `@main` entry point, `AppDelegate`, `CommandCoordinator`, `MainContentView`. The app is a single `NavigationSplitView` (sidebar + editor).
- **AppViewModel** — central coordinator: owns AgentScanner, FileService, AppSettings. Handles file selection, custom paths, hide/show files.
- **EditorViewModel** — file editing (load/save/undo/redo/search/JSON format), external change detection, source runner for shell files. Content is a `@Published` two-way binding to the NSTextView.
- **GitViewModel** — git history: load commits, diff, restore to commit, init repo.
- **CodeEditorView** — NSTextView wrapped via `NSViewRepresentable`. Syntax highlighting via `SyntaxHighlighter` (NSTextStorageDelegate, regex-based).
- **AgentScanner** — scans `~` for known agent config files using definitions from `AgentDefinitions` (static registry of 15 agents).
- **GitService** — wraps `git` CLI via `Process`. Used for log, diff, show, init, stageAndCommit.
- **FileWatcher** — `DispatchSourceFileSystemObject` with 500ms debounce for external change detection.
- **AppSettings** — `UserDefaults` wrapper for appearance, language, autoSource, customPaths, hiddenFiles.
- **i18n** — `NSLocalizedString` with en and zh-Hans. Language switching via `UserDefaults.standard.set(..., forKey: "AppleLanguages")`.

### Service protocols

Each service is defined as a protocol + implementation:

| Protocol | Implementation | Role |
|----------|---------------|------|
| `AgentScannerProtocol` | `AgentScanner` | Discover config files on disk |
| `FileServiceProtocol` | `FileService` | Read/write/create/delete files |
| `GitServiceProtocol` | `GitService` | Git commands |
| `SourceRunnerProtocol` | `SourceRunner` | Run `source` on shell files |
| `ConfigExamplesProtocol` | `ConfigExamples` | Curated example snippets |

### Data flow

1. App launch → `AppViewModel.refresh()` → `AgentScanner.scan()` → categories + files in sidebar
2. User clicks file → `AppViewModel.selectedFile` changes → `EditorView` loads via `EditorViewModel.load(file:)`
3. Cmd+S → `EditorViewModel.save()` → `FileService.write()` → optional `SourceRunner.source()` for shell files
4. Git → `GitViewModel.loadHistory()` → `GitService.log()` → show in sheet modal

### Adding a new agent

1. Add entries to `AgentDefinitions.swift` static arrays
2. Add icon image to `Assets.xcassets`
3. Add example configs to `ConfigExamples.swift`
4. Update i18n strings for both en and zh-Hans