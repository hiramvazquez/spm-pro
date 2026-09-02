# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### AppFoundation

#### Changed

- **Breaking:** `Debouncer` and `Throttler` are now `@MainActor final class` instead
  of `actor`, and no longer generic over `Clock` (`Debouncer<C>` → `Debouncer`). The
  clock is `any Clock<Duration>`. `debounce(_:)` is synchronous and its operation is
  no longer `@Sendable`; `deinit` cancels any in-flight work (AF-19).
- **Breaking:** `AppEnvironment` is now an `enum` namespace instead of a `struct`.
  `physicalMemoryFormatted` uses `.formatted(.byteCount(style: .memory))` instead of
  `String(format:)` (AF-20).
- Default strings moved from `Resources/{en,es}.lproj/Localizable.strings` to a
  single `Resources/Localizable.xcstrings` String Catalog with the same keys and
  values (AF-21).

#### Removed

- **Breaking:** `Debouncer.init(milliseconds:)` — use `.milliseconds(n)` instead.
- **Breaking:** `AppEnvironment.isTestOrPreview` — detecting the test runner or
  Xcode Previews by heuristic in production code is unsupported; inject the
  behaviour you want in tests instead (AF-20).
- **Breaking:** `AppEnvironment.debugInfo` / `AppEnvironment.printDebugInfo()`.
