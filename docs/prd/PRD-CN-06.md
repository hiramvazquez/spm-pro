# PRD-CN-06 — Interceptores v2, `RequestRetrier` y refresh de token

Paquete: CoreNetworking · Oleada 3 (tras CN-03/CN-05; merge después de CN-04) · Cubre: CN-05, CN-06 · Rompe API pública: **sí** (`RequestInterceptor`)

## Problema
`willSend` no puede fallar ni abortar; no existe «tras 401, refresca y reintenta»; `didReceive` no tiene identidad de
request y recibe `URLResponse`. Es el hueco funcional más grande para una app real.

## Diseño

```swift
public struct RequestContext: Sendable { public let id: UUID; public let request: URLRequest; public let attempt: Int; public let startedAt: ContinuousClock.Instant }

public protocol RequestInterceptor: Sendable {
    func willSend(_ request: URLRequest, context: RequestContext) async throws(APIError) -> URLRequest   // default: identidad
    func didReceive(_ response: HTTPURLResponse, data: Data, context: RequestContext) async                // default no-op
    func didFail(_ error: APIError, context: RequestContext) async                                         // default no-op
}
public enum RetryDecision: Sendable, Equatable { case doNotRetry; case retry; case retryAfter(Duration) }
public protocol RequestRetrier: Sendable {
    /// Se consulta ANTES que RetryPolicy. Si devuelve .retry, el request vuelve a pasar por willSend (nuevo token).
    func retry(_ error: APIError, context: RequestContext) async -> RetryDecision
}
```
- `APIService.init` gana `retriers: [any RequestRetrier] = []`. Orden por intento: `willSend` (todos, en orden; un
  `throw` aborta con `code: .interceptor` y `underlying`) → transporte → `didReceive` → validación de status → en
  error: `didFail` → `retriers` (primero que no devuelva `.doNotRetry` decide) → si ninguno, `RetryPolicy`.
  El límite `maxAttempts` aplica a ambos caminos.
- Built-in: `BearerTokenInterceptor(tokenProvider:)` y `TokenRefreshRetrier(refresher: any TokenRefreshing)`:
  ```swift
  public protocol TokenRefreshing: Sendable { func refreshToken() async throws }
  public actor TokenRefresher: TokenRefreshing {   // actor JUSTIFICADO: deduplica refreshes concurrentes (estado compartido entre N requests)
      public init(refresh: @escaping @Sendable () async throws -> Void)
      public func refreshToken() async throws        // si hay un refresh en vuelo, espera su resultado en vez de lanzar otro
  }
  ```
  `TokenRefreshRetrier.retry` → si `error.statusCode == 401 && context.attempt == 1` → `try await refresher.refreshToken()`; éxito → `.retry`; fallo → `.doNotRetry`.
- `LoggingInterceptor` usa `context.id` y mide duración con `context.startedAt` (`.private` para URL, `.public` para método/status/ms).
- La nota histórica sobre `PerformanceInterceptor` se elimina (ya es posible medir).

## Ficheros
Sources: `RequestInterceptor.swift` (reescritura), nuevo `Retry/RequestRetrier.swift`, nuevo `Auth/TokenRefresher.swift`, `APIService.swift` (**solo** `performWithRetry` y `performOnce`; no tocar transporte ni build/decode).
TestSupport: `RecordingInterceptor` (público, para que las apps prueben sus interceptores).
Tests: `InterceptorTests.swift` (reescritura), nuevo `RetrierTests.swift`, nuevo `TokenRefresherTests.swift`.
README: «Interceptores» (+ «Autenticación y refresh de token»).

## Criterios de aceptación
- [ ] `willSend` que lanza → el transporte no recibe nada, `code == .interceptor`, `didFail` se invoca una vez (test).
- [ ] 401 → refresh → 200: exactamente 2 requests, el segundo con el token nuevo en `Authorization` (test con `InMemoryTransport` secuencia + `TokenRefresher`).
- [ ] 10 requests concurrentes que reciben 401 → **un** único refresh (test con contador en el closure de refresh y `withTaskGroup`).
- [ ] Refresh que falla → `.doNotRetry`, el error original 401 llega al consumidor sin reintentos extra.
- [ ] `RetryDecision.retryAfter` manda sobre `RetryPolicy` y sobre `Retry-After` (test con `ManualClock`).
- [ ] `didReceive`/`didFail` reciben el mismo `context.id` para el mismo intento; distinto `attempt` por reintento.
- [ ] `grep -n "PerformanceInterceptor" Sources` vacío.
