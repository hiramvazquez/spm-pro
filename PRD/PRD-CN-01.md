# PRD-CN-01 — Modelo de error unificado y extensible

Paquete: CoreNetworking · Oleada 1 · Cubre: CN-02, CN-03, CN-04, CN-12, CN-20 · Rompe API pública: **sí** (antes de 1.0)

## Problema
`APIError` es un enum cerrado con `.unknown`, `.custom` que asume `{"message"}`, sin body/headers en `.httpStatus`,
`Equatable` que declara iguales errores distintos, e `isRetryable` que reintenta sin red. `TransportError` es un
segundo `Error` público para la misma capa (401=403, `.connectionInterrupted` = pinning). Detalle: auditoría §2.1 y §4.

## Objetivo
Un único tipo `APIError` (struct) que conserve **todo** (request, respuesta completa, error subyacente), sea
**extensible** sin romper a los consumidores, clasifique vía `category`, y permita a la app decodificar su propio
sobre de error. `TransportError` desaparece.

## Diseño

```swift
public struct APIError: Error, Sendable {
    public struct Code: Hashable, Sendable, CustomStringConvertible {
        public let rawValue: String
        public init(_ rawValue: String)
        public static let invalidURL, invalidResponse, transport, cancelled, untrustedServer,
                          httpStatus, encoding, decoding, interceptor, unexpected: Code
    }
    public struct RequestSummary: Sendable, Hashable { public let method: HTTPMethod; public let url: URL? }
    public struct ResponseSummary: Sendable {
        public let statusCode: Int
        public let headers: [String: String]      // claves normalizadas en minúsculas
        public let body: Data
        public func header(_ name: String) -> String?   // case-insensitive
    }
    public let code: Code
    public let request: RequestSummary?
    public let response: ResponseSummary?
    public let underlying: (any Error)?

    public init(code: Code, request: RequestSummary? = nil, response: ResponseSummary? = nil, underlying: (any Error)? = nil)

    // Derivadas
    public var statusCode: Int? { response?.statusCode }
    public var retryAfter: Duration?          // parse de Retry-After (segundos u HTTP-date); en iOS 18+/macOS 15+ usar Date(_, strategy: .http)
    public var isRetryable: Bool              // transport: timedOut, networkConnectionLost, cannotConnectToHost, dnsLookupFailed, cannotFindHost. NO notConnectedToInternet. httpStatus: 5xx, 408, 429
    public var isCancellation: Bool { code == .cancelled }
    public var urlError: URLError? { underlying as? URLError }
    public var category: Category
    public enum Category: Sendable, Hashable, CaseIterable {
        case offline, timeout, unauthorized, forbidden, notFound, rateLimited, client, server,
             untrustedServer, cancelled, decoding, unknown
    }
    public func decodeBody<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T
    // lanza APIError(code: .decoding) si no hay body; propaga DecodingError envuelto
}
extension APIError: CustomStringConvertible { /* técnica, sin body ni mensaje de servidor */ }
extension APIError: LocalizedError {
    // errorDescription neutro y localizable (EN+ES via Localizable.xcstrings del paquete): "No hay conexión a internet.",
    // "El servidor no respondió a tiempo.", "Error del servidor (503).", … NUNCA "error 9".
}
```

Reglas de `category`:
- `.transport` + `URLError.notConnectedToInternet | dataNotAllowed | internationalRoamingOff` → `.offline`
- `.transport` + `timedOut` → `.timeout`; `networkConnectionLost | cannotConnectToHost | dnsLookupFailed | cannotFindHost` → `.offline`? **No**: → `.unknown` salvo que se acuerde otra cosa; documentar la tabla completa en el doc comment.
- `.httpStatus`: 401 → `.unauthorized`, 403 → `.forbidden`, 404 → `.notFound`, 429 → `.rateLimited`, 400…499 → `.client`, 500…599 → `.server`
- `.untrustedServer` → `.untrustedServer`; `.cancelled` → `.cancelled`; `.decoding` → `.decoding`; resto → `.unknown`

Cambios de mapeo en `APIService.swift` (solo las regiones de `catch` y `map`; NO tocar el loop de retry ni el transporte):
- Non-2xx → `APIError(code: .httpStatus, request:, response: ResponseSummary(statusCode:headers:body:))`. Se elimina el intento de decodificar `APIMessageError`; `APIMessageError` se borra.
- `URLError.cancelled` → `.cancelled` (el caso pinning se resuelve en CN-04; aquí basta dejar el hook `code: .untrustedServer` definido).
- Cualquier otro error → `APIError(code: .unexpected, underlying: error)`. **Prohibido** perder el error.
- `decode` → `APIError(code: .decoding, request:, response:, underlying: decodingError)`; el body queda en `response` para diagnóstico.
- `RetryPolicy.shouldRetry` pasa a `@Sendable (APIError, Int) -> Bool`; `RetryPolicy` deja de ser `Equatable`.
- `RequestInterceptor.didFail(_:error:)` pasa a `error: APIError` (solo la firma; el rediseño del protocolo es CN-06).
- `LoggingInterceptor.didFail`: loguear `code` y `statusCode` con `.public`; nada del body ni de `underlying` con `.public`.
- `Logging.swift`: subsystem por defecto `Bundle.main.bundleIdentifier.map { "\($0).corenetworking" } ?? "corenetworking"`.

Borrar: `TransportError.swift`, `TransportErrorTests.swift`, `APIMessageError`, `APIError: Equatable`.
Test support: `CoreNetworkingTestSupport` gana `extension APIError { public static func stub(code:status:) }` y un
helper `#expect(error.code == .httpStatus)`-friendly (no `Equatable` en el tipo de producción).

## Ficheros
Sources: `APIError.swift` (reescritura), `TransportError.swift` (borrar), `APIService.swift` (solo `performOnce` catch/guards, `decode`, `buildURLRequest` catch), `RetryPolicy.swift` (firma `shouldRetry`, quitar `Equatable`), `RequestInterceptor.swift` (firma `didFail` + `LoggingInterceptor.didFail`), `Logging.swift`, `Resources/Localizable.xcstrings` (nuevo; añadir `defaultLocalization: "en"` y `resources: [.process("Resources")]` al target en `Package.swift`).
TestSupport: `MockAPIService.swift` (tipo de `error`), helper de stubs.
Tests: `TransportErrorTests.swift` (borrar), `RetryPolicyTests.swift` (sección APIError), `InterceptorTests.swift` (didFail), `PipelineTests.swift`, `TransferTests.swift`, nuevo `APIErrorTests.swift`.
README: secciones «Ejecutar», «Retry» (predicado), «Interceptores» (firma), nueva «Errores».

## Criterios de aceptación
- [ ] Un 422 con body `{"errors":[{"field":"email"}]}` llega al consumidor con `statusCode == 422` y `decodeBody(MyErrors.self)` funciona (test).
- [ ] Un `NSError` arbitrario lanzado por el transporte llega como `code == .unexpected` con `underlying` idéntico (test).
- [ ] `category` cubre la tabla completa (test parametrizado con `arguments:`), 401 ≠ 403.
- [ ] `isRetryable` es falso para `notConnectedToInternet` y verdadero para `dnsLookupFailed` (test).
- [ ] `APIError(code: .transport, underlying: URLError(.notConnectedToInternet)).localizedDescription` es una frase humana en EN y ES (test con `Locale`).
- [ ] `grep -rn "TransportError\|APIMessageError\|\.unknown\b" Sources Tests` vacío.
- [ ] Todos los `catch` del pipeline preservan `underlying`; `grep -n "APIError.unknown" Sources` vacío.
- [ ] README «Errores» explica `code`, `category`, `decodeBody`, `isCancellation` y la política de evolución (añadir `Code` no rompe).

## Fuera de alcance
Cableado del pinning (CN-04), `RequestRetrier` (CN-06), `Clock` (CN-03).
