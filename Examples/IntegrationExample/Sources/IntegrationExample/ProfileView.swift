import AppFoundation
import CoreNetworking

#if canImport(SwiftUI)
import SwiftUI

// MARK: - The view

/// The piece an integrator copies first (DC-AF-6, `AUDITORIA-2026-09-02-doblecheck.md` §3):
/// `ScreenContainer` bound to a `ProfileViewModel`, rendering its `.content`/`.loading`/
/// `.error` phases automatically and sending the one action this screen recognizes.
///
/// ## `.onAppear { send(.load) }`, not `.task { await viewModel.load { … } }`
///
/// `LoadableViewModel` offers both an unstructured, `Task`-owning `performLoad` (what
/// `ProfileViewModel.load()` uses internally) and a structured `load(_:)` meant to be
/// driven from `.task { await vm.load { … } } ` — see that type's doc comment. This view
/// uses the first, through `handle(.load)`, for two reasons specific to this screen:
///
/// - `ProfileViewModel.load()` is `private` (AF-05's `ActionHandling`: `handle(_:)` is the
///   only entry point a view or a test uses) — the work closure the structured variant
///   needs lives inside that private method, not at the call site, so `ProfileView` has no
///   closure to hand `.task` in the first place.
/// - The unstructured `performLoad`'s cancellation-on-`deinit` (AF-01/AF-03) is exactly
///   the semantics wanted here: a screen that's popped mid-load stops the request when the
///   view model deallocates, without needing the view's `.task` to still be attached.
///
/// Reach for `.task { await vm.load { … } }` instead when the work closure is written at
/// the call site (no private `ActionHandling` method in between) and cancellation should
/// strictly follow the view's own lifecycle (SwiftUI cancels a `.task` the instant its
/// view disappears — even before `deinit` would run).
public struct ProfileView: View {
    let viewModel: ProfileViewModel

    public init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScreenContainer(viewModel) { send in
            VStack(spacing: 16) {
                if let profile = viewModel.profile {
                    Text(profile.name)
                        .font(.title)
                }

                Button("Reload") {
                    send(.load)
                }
            }
            .padding()
            .onAppear {
                send(.load)
            }
        }
        .navigationTitle("Profile")
    }
}

// MARK: - A custom error appearance, installed through `Environment` (AF-15)

/// Proof that pluggable phase appearances (`LoadingViewStyle`/`ErrorViewStyle`/…) never
/// need type erasure at the call site: install one with `.errorViewStyle(_:)`, same as any
/// other `Environment` value.
struct ProfileErrorStyle: ErrorViewStyle {
    func makeBody(configuration: ErrorConfiguration) -> some View {
        VStack(spacing: 12) {
            Text(configuration.error.title)
                .font(.headline)
            Text(configuration.error.message)
                .foregroundStyle(.secondary)
            if let retry = configuration.error.retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}
#endif

// MARK: - Preview: DC-AF-6's other half — a stub, no real network pipeline

#if canImport(SwiftUI) && DEBUG
import CoreNetworkingTestSupport

/// A `ProfileView` wired to `MockAPIService` instead of a live `APIService` — what an
/// integrator's own preview looks like, no test target or network required.
struct ProfilePreview: View {
    let viewModel: ProfileViewModel

    init(name: String = "Hiram") {
        let mock = MockAPIService()
        mock.stub(GetProfileRequest.self, returning: GetProfileRequest.Response(name: name))
        self.viewModel = ProfileViewModel(service: mock)
    }

    var body: some View {
        NavigationStack {
            ProfileView(viewModel: viewModel)
                .errorViewStyle(ProfileErrorStyle())
        }
    }
}

#Preview {
    ProfilePreview()
}
#endif
