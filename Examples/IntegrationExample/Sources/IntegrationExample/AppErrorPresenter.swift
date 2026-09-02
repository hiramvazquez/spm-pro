import AppFoundation
import CoreNetworking
import Foundation

/// The error envelope this hypothetical backend returns for failures it doesn't already
/// classify through a well-known HTTP status — `{"error": {"code": "...", "detail": "..."}}`.
/// A real app decodes ITS OWN envelope this way; CoreNetworking never interprets the body
/// itself, only keeps it in `APIError.response`.
public struct ServerProblem: Decodable, Sendable, Equatable {
    public struct Body: Decodable, Sendable, Equatable {
        public let code: String
        public let detail: String
    }
    public let error: Body
}

/// The single adapter this app needs to pair AppFoundation with CoreNetworking: neither
/// package knows about the other, and this is the one place that maps `APIError.category`
/// to `ScreenError` copy (PRD-X-02, AUDITORIA-2026-09-01.md §4).
///
/// Register it once at app startup:
/// ```swift
/// BaseViewModel.errorPresenter = AppErrorPresenter()
/// ```
public struct AppErrorPresenter: ErrorPresenting {
    public init() {}

    public func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError {
        guard let apiError = error as? APIError else {
            return DefaultErrorPresenter().screenError(for: error, fallbackTitle: fallbackTitle, retry: retry)
        }

        switch apiError.category {
        case .offline:
            return ScreenError(
                title: "No connection",
                message: "Check your network and try again.",
                retry: retry
            )
        case .unauthorized:
            return ScreenError(
                title: "Session expired",
                message: "Please sign in again."
            )
        case .untrustedServer:
            return ScreenError(
                title: "Insecure connection",
                message: "We couldn't verify the server's identity."
            )
        default:
            // The app decodes its OWN error envelope with its OWN decoder — CoreNetworking
            // only kept the raw body (`decodeBody`, AUDITORIA-2026-09-01.md CN-02).
            if let problem = try? apiError.decodeBody(ServerProblem.self) {
                return ScreenError(title: "Something went wrong", message: problem.error.detail, retry: retry)
            }
            return DefaultErrorPresenter().screenError(for: error, fallbackTitle: fallbackTitle, retry: retry)
        }
    }
}
