import AppFoundation
import CoreNetworking
import CoreNetworkingTestSupport
import Foundation
import Testing

@testable import IntegrationExample

/// Proof that the two packages compose without friction: a view model built purely
/// against `APIServiceProtocol` and `ErrorPresenting`, exercised against both a stub
/// (`MockAPIService`) and the real pipeline (`InMemoryTransport` + interceptors +
/// retriers), never importing anything internal from either package.
@Suite("IntegrationExample — ProfileViewModel")
struct ProfileFeatureTests {

    // MARK: - performLoad over MockAPIService

    @Test("A stubbed success reaches .content without touching the network pipeline")
    func stubbedSuccessReachesContent() async {
        let mock = MockAPIService()
        mock.stub(GetProfileRequest.self, returning: GetProfileRequest.Response(name: "Hiram"))

        let viewModel = ProfileViewModel(service: mock)
        await viewModel.load().value

        #expect(viewModel.phase == .content)
        #expect(viewModel.profile == Profile(name: "Hiram"))
    }

    @Test("A stubbed failure lands on .error")
    func stubbedFailureSurfacesError() async {
        let mock = MockAPIService()
        mock.stub(GetProfileRequest.self, throwing: .stub(code: .httpStatus, statusCode: 500))

        let viewModel = ProfileViewModel(service: mock, errorPresenter: AppErrorPresenter())
        await viewModel.load().value

        #expect(viewModel.hasError)
        #expect(viewModel.profile == nil)
    }

    // MARK: - performLoad over InMemoryTransport: 401 → refresh → 200

    @Test("A 401 refreshes the token and the retried request lands on .content")
    func unauthorizedRefreshesTokenAndRetrySucceeds() async throws {
        let transport = InMemoryTransport()
        let profileURL = URL(string: "https://unit.test/profile")!
        await transport.register(
            InMemoryTransport.Exchange(
                url: profileURL,
                responses: [
                    .response(status: 401),
                    .response(status: 200, body: #"{"name":"Hiram"}"#.data(using: .utf8)!)
                ]
            )
        )

        let clock = ManualClock()
        let tokenStore = TokenStore(currentToken: "expired-token")
        let service = makeAPIService(
            configuration: NetworkingConfiguration(baseURL: URL(string: "https://unit.test")!),
            transport: transport,
            tokenStore: tokenStore,
            clock: clock
        )

        let viewModel = ProfileViewModel(service: service, errorPresenter: AppErrorPresenter())
        let task = viewModel.load()

        // The retrier's `.retry` decision still sleeps through the injected clock (jittered
        // backoff, same as a plain `RetryPolicy` retry) — drive it by hand, no real wait
        // (CoreNetworking README, "ManualClock: retry sin esperar de verdad").
        await clock.waitUntilSleeping()
        clock.advance(by: .seconds(1))
        await task.value

        #expect(viewModel.phase == .content)
        #expect(viewModel.profile == Profile(name: "Hiram"))
        let recorded = await transport.recorded
        #expect(recorded.count == 2)
        // The retried request carries the refreshed token, not the expired one.
        #expect(recorded.last?.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
    }

    // MARK: - performLoad over InMemoryTransport: transport failure → .error with the presenter's copy

    @Test("A transport failure lands on .error with AppErrorPresenter's offline copy")
    func transportFailureSurfacesPresenterCopy() async {
        let transport = InMemoryTransport()
        let profileURL = URL(string: "https://unit.test/profile")!
        await transport.register(
            InMemoryTransport.Exchange(
                url: profileURL,
                response: .failure(URLError(.notConnectedToInternet))
            )
        )

        let service = makeAPIService(
            configuration: NetworkingConfiguration(baseURL: URL(string: "https://unit.test")!),
            transport: transport,
            tokenStore: TokenStore(),
            clock: ManualClock()
        )

        let viewModel = ProfileViewModel(service: service, errorPresenter: AppErrorPresenter())
        await viewModel.load().value

        guard case .error(let screenError) = viewModel.phase else {
            Issue.record("Expected .error, got \(viewModel.phase)")
            return
        }
        #expect(screenError.title == "No connection")
        #expect(screenError.message == "Check your network and try again.")
    }
}
