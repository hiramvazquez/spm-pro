import Foundation

/// Polls `condition` until it is true or `timeout` elapses.
///
/// `ProfileViewModel.handle(_:)` is fire-and-forget (AF-05's `ActionHandling` contract:
/// `handle` returns `Void`, not the underlying `Task`) — tests observe completion through
/// `viewModel.phase`/`viewModel.profile` instead of awaiting a returned `Task`, the same way
/// a UI test would. Mirrors `AppFoundationTests/TestSupport.swift`'s helper of the same name.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() && clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}
