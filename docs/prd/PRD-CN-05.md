# PRD-CN-05 — Superficie de request/response y configuración de sesión

Paquete: CoreNetworking · Oleada 2 (tras CN-01; merge después de CN-03) · Cubre: CN-08, CN-09, CN-10, CN-13, CN-14, CN-15, CN-16, CN-17, CN-18 · Rompe API pública: **sí**

## Objetivo
Que definir un endpoint sea un tipo completo y sin ceremonia; que 204 funcione; que encoder/decoder y la sesión
sean del consumidor; y borrar todo lo que nadie usa.

## Diseño

```swift
public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE", head = "HEAD", options = "OPTIONS"; public var isIdempotent: Bool }

public protocol BaseRequest: Sendable {
    associatedtype Body: Encodable & Sendable = Never
    associatedtype Response: Decodable & Sendable = Empty
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }        // default [:]
    var body: Body? { get }                      // default nil
    var queryItems: [URLQueryItem] { get }       // default []
    var timeout: Duration { get }                // default .seconds(30)
    var allowsNonIdempotentRetry: Bool { get }   // default false
}
public struct Empty: Decodable, Sendable { public init() {} }   // 204 / body vacío / `{}`
```
- `APIServiceProtocol.execute<R: BaseRequest>(_ request: R) async throws(APIError) -> R.Response`. Mantener la
  sobrecarga `execute<R, T: Decodable>(_ request: R, as: T.Type)` para casos puntuales.
- Decodificación: si `R.Response == Empty` **o** (`data.isEmpty` y status 204/205) → `Empty()`. Si `data.isEmpty`
  y se esperaba otro tipo → `APIError(code: .decoding, …)` con mensaje claro.
- `buildURLRequest`: `Content-Type: application/json` **solo** si hay body; `Accept: application/json` siempre
  (sobrescribible por `headers`). Usar `URL.appending(path:)`. `timeout` en `Duration`.
- `NetworkingConfiguration` gana `makeEncoder: @Sendable () -> JSONEncoder` y `sessionConfiguration: @Sendable () -> URLSessionConfiguration`
  (default `.default` con `waitsForConnectivity = true`, `httpShouldSetCookies = false`, `httpCookieAcceptPolicy = .never`,
  `tlsMinimumSupportedProtocolVersion = .TLSv12`, documentado cada uno). `environment` se elimina.
  El README corrige el racional de `makeDecoder`: `JSONDecoder` es `Sendable`; la fábrica es una decisión de
  aislamiento por construcción, no una necesidad.
- `parseRetryAfter` (en `APIError`, CN-01): `if #available(iOS 18, macOS 15, *) { Date(value, strategy: .http) } else { DateFormatter estático en nonisolated(unsafe) let con comentario, o crear por llamada }`.
- Borrar: `BaseResponse.swift` completo (`Empty` va a `BaseRequest.swift`), `RequestParameters`, `EmptyParameters`,
  `RequestValidationError`, `validated()`, `isValid`, `debugValidated()`, `requestDescription`.

## Ficheros
Sources: `BaseRequest.swift` (reescritura), `BaseResponse.swift` (borrar), `NetworkingConfiguration.swift`, `APIServiceProtocol.swift`, `APIService.swift` (**solo** `execute`, `decode`, `buildURLRequest`; no tocar `performWithRetry` ni el transporte), `APIError.swift` (solo `retryAfter`/`parseRetryAfter`).
TestSupport: `MockAPIService.swift`, `MockAPIHelper.swift` (adaptar `HTTPMethod`).
Tests: todos los que definen requests (`typealias Parameters` → desaparece), `DecoderConfigurationTests.swift` (+ encoder), `PipelineTests.swift` (204, Accept, Content-Type), nuevo `RequestBuildingTests.swift`.
README: «Requests tipados», «El decoder es tuyo» (→ «Decoder, encoder y sesión son tuyos»), «Ejecutar».

## Criterios de aceptación
- [ ] Un `struct GetGames: BaseRequest { let path = "/games"; let method = HTTPMethod.get }` compila sin `typealias` y `execute(GetGames())` devuelve `Empty` si no declara `Response`.
- [ ] 204 sin body con `Response == Empty` → éxito; 200 con body vacío y `Response == [Game]` → `.decoding` con `response.body.isEmpty` (tests).
- [ ] GET no envía `Content-Type`; POST con body sí; ambos envían `Accept` (test sobre `recordedRequests`).
- [ ] `makeEncoder` con `.convertToSnakeCase` produce `{"game_title":…}` (test).
- [ ] `sessionConfiguration` inyectada llega a la `URLSession` (test: `protocolClasses` vía esa fábrica).
- [ ] `grep -rn "EmptyParameters\|RequestParameters\|BaseResponse\|validated()\|environment:" Sources Tests README.md` vacío.
- [ ] `HTTPMethod.GET` no compila (caso renombrado), README actualizado.
