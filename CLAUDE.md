# Junco — Claude Code Instructions

## Build & Test

```bash
swift build          # debug build
swift test           # run all tests (473 tests, ~1s)
swift build -c release --arch arm64  # release build
```

## Linting

All code changes must pass `swiftlint --strict` before pushing. The full rule config is in `.swiftlint.yml`. Run it locally to catch violations before CI does.

## CI Compatibility

The CI runner uses `macos-26` with Xcode 26.3, but the **host OS is older than macOS 26**. The package hard-links `FoundationModels.framework` (via `platforms: [.macOS("26.0")]`), which only exists on macOS 26+. This means `swift build` works (cross-compilation) but `swift test` crashes at `dlopen` — the test binary can't load. CI runs build + lint only; tests run locally on macOS 26.

APIs introduced in newer SDK betas (e.g. `SystemLanguageModel.tokenCount`, `.contextSize`) require a **double guard**:

```swift
#if compiler(>=6.3)          // hides from older SDK at compile time
if #available(macOS 26.4, iOS 26.4, *) {  // runtime availability check
    // new API here
}
#endif
// fallback here
```

- `#if compiler(...)` — compile-time gate, prevents type-check errors on older SDKs
- `#available(...)` — runtime gate, satisfies the local compiler's availability checker
- Neither alone is sufficient; both are required
