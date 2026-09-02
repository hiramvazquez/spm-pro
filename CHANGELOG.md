# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### AppFoundation

#### Added

- `LoadableViewModel`, adopted by `BaseViewModel`: `performLoad`/`performActivity` (and
  the structured `load`/`activity` variants) now hand the view model to `work` as a
  parameter instead of relying on closure capture — the API shape that closes the
  `.error`-phase retention cycle (AF-01) and makes `deinit` actually cancel in-flight
  work (AF-03).
- `ErrorPresenting` / `DefaultErrorPresenter`: a single, app-configurable place to map
  errors to `ScreenError` copy (`BaseViewModel.errorPresenter`, overridable per instance
  via `BaseViewModel(errorPresenter:)`). Foreign errors that aren't `AppErrorConvertible`
  or `LocalizedError` now fall back to a generic, localized message instead of
  `error.localizedDescription` (AF-02).
- `CancellationRecognizing` / `DefaultCancellationRecognizer`: extensible cancellation
  detection beyond typed `CancellationError` (default also recognizes
  `URLError(.cancelled)`), configurable via `BaseViewModel.cancellationRecognizer` (AF-04).
- `L10n.genericErrorMessage` (EN + ES) — the fallback copy `DefaultErrorPresenter` shows
  for errors it can't otherwise present.
- `AppFoundationLogger.errors` — logs the technical detail of unpresentable errors
  (`.private`), never shown on screen.
- `BaseViewModel.clock` (injectable `any Clock<Duration>`, defaults to
  `ContinuousClock()`): the banner auto-dismiss timer no longer sleeps for real in tests.

#### Changed

- **Breaking:** `performLoad`/`performActivity` no longer accept a
  `() async throws -> Void` closure; `work` is now
  `@MainActor (Self) async throws -> Void`, receiving the view model as `vm`. Existing
  call sites must migrate from `performLoad { self.foo() }` to
  `performLoad { vm in vm.foo() }`.
- **Breaking:** `WrappedError.init` gains an injectable `now: () -> Date` parameter and
  uses `#fileID` instead of `#file` for its default `file` argument.
- `WrappedError` now conforms to `CustomDebugStringConvertible` (was a plain
  `debugDescription` property); its `Equatable` conformance is documented as comparing
  `context` + `code` + `underlying.localizedDescription` only, not a structural
  comparison of `underlying`.

#### Fixed

- **Critical:** a `BaseViewModel` in the `.error` phase never deallocated when `work`
  captured `self` (the documented pattern): `phase → ScreenError.retry → work → self`
  formed a permanent reference cycle. Closed by the `LoadableViewModel` API shape.
- `deinit` now actually cancels an in-flight `performLoad`/`performActivity`: since
  `work` no longer captures the view model, dropping the last external reference lets
  the view model deallocate, and its `deinit` cancels the owned `Task`.

