import AppFoundation
import CoreNetworking
import Foundation

// MARK: - The request

/// A typed endpoint the way CoreNetworking wants it: the type IS the request, and
/// `Response` says what `execute` gives back — no `typealias Parameters` filler, no
/// ambiguity to resolve at the call site (AUDITORIA-2026-09-01.md CN-15/CN-16).
public struct GetProfileRequest: BaseRequest {
    public struct Response: Decodable, Sendable {
        public let name: String
    }

    public let path = "/profile"
    public let method = HTTPMethod.get

    public init() {}
}

// MARK: - The domain model

public struct Profile: Sendable, Equatable {
    public let name: String
}

// MARK: - The view model

/// `BaseViewModel` subclass driven entirely through `performLoad { vm in ... }`
/// (AUDITORIA-2026-09-01.md AF-01/AF-03): `work` never captures `self`, so a screen that
/// fails and gets dismissed still deallocates, and `deinit` actually cancels an in-flight
/// load.
///
/// `ActionHandling` (AF-05, PRD-AF-05) makes `handle(_:)` the single entry point a
/// `ScreenContainer` content closure — or a test — uses: `load()` below is `private`, never
/// called directly from outside this file.
@MainActor
public final class ProfileViewModel: BaseViewModel, ActionHandling {
    public private(set) var profile: Profile?

    private let service: any APIServiceProtocol

    /// Every action `ProfileView` recognizes.
    public enum Action: Sendable {
        case load
    }

    public init(service: any APIServiceProtocol, errorPresenter: (any ErrorPresenting)? = nil) {
        self.service = service
        super.init(errorPresenter: errorPresenter)
    }

    public func handle(_ action: Action) {
        switch action {
        case .load: load()
        }
    }

    private func load() {
        performLoad { vm in
            let response = try await vm.service.execute(GetProfileRequest())
            vm.profile = Profile(name: response.name)
        }
    }
}

// MARK: - Wiring: AppService, the way a real app would configure it

/// Builds an `APIService` the way a production app would: a bearer token read fresh on
/// every request, and a retrier that refreshes the token and replays the request exactly
/// once on a 401 (AUDITORIA-2026-09-01.md CN-05).
public func makeAPIService(
    configuration: NetworkingConfiguration,
    transport: any HTTPTransport,
    tokenStore: TokenStore,
    clock: any Clock<Duration> = ContinuousClock()
) -> APIService {
    let refresher = TokenRefresher {
        // A real app would call its auth backend here.
        await tokenStore.save("refreshed-token")
    }
    return APIService(
        configuration: configuration,
        transport: transport,
        interceptors: [BearerTokenInterceptor { await tokenStore.currentToken }],
        retriers: [TokenRefreshRetrier(refresher: refresher)],
        clock: clock
    )
}

/// A minimal, in-memory token store — stands in for Keychain in this example.
public actor TokenStore {
    public private(set) var currentToken: String?

    public init(currentToken: String? = "expired-token") {
        self.currentToken = currentToken
    }

    public func save(_ token: String) {
        currentToken = token
    }
}
