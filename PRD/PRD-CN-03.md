# PRD-CN-03 — `HTTPTransport` inyectable, `Clock` en retry y mocks con secuencias

Paquete: CoreNetworking · Oleada 2 (tras CN-01) · Cubre: CN-11, CN-21, CN-22 · Rompe API pública: **sí** (init de `APIService`, `RetryPolicy` en `Duration`)

## Problema
El único punto de inyección bajo `APIService` es `URLProtocol` con registro estático global (guerra con Swift Testing
en paralelo); el retry duerme con reloj real y los tests miden tiempo de pared; el mock no puede simular secuencias
(500 → 200) y `MockAPIService.result: Any?` despista.

## Diseño

```swift
public protocol HTTPTransport: Sendable {
    /// Envía un request y devuelve body + respuesta HTTP. Lanza URLError/CancellationError/cualquier Error.
    func send(_ request: URLRequest, progress: TransferProgress?) async throws -> (Data, HTTPURLResponse)
}
public struct TransferProgress: Sendable { public let onUpload: (@Sendable (Double) -> Void)?; public let onDownload: (@Sendable (Double) -> Void)? }

public struct URLSessionTransport: HTTPTransport {
    public init(configuration: URLSessionConfiguration = .default, pinning: SSLPinningConfiguration? = nil)
    // Aquí vive la URLSession (una por transporte) y su delegate de sesión actual. CN-04 lo reemplaza por delegate por tarea.
}

public final class APIService: APIServiceProtocol {
    public init(configuration: NetworkingConfiguration,
                transport: any HTTPTransport,                      // sin default: la elección es del consumidor
                retryPolicy: RetryPolicy = RetryPolicy(),
                interceptors: [any RequestInterceptor] = [],
                clock: any Clock<Duration> = ContinuousClock())
    public convenience init(configuration:, retryPolicy:, interceptors:, sslPinning:)  // azúcar → URLSessionTransport
}
```
- `performWithRetry` usa `clock.sleep(for:)`; `RetryPolicy` pasa a `Duration` (`initialDelay: .milliseconds(500)`,
  `maxDelay: .seconds(16)`); `jitteredDelay` devuelve `Duration`. `retryAfter` de `APIError` ya es `Duration` (CN-01).
- `upload` y `download` pasan por `transport.send` con `TransferProgress` (el body de upload va en `URLRequest.httpBody`
  en esta fase; CN-04 lo cambia por `upload(for:from:)` con delegate). `download` sigue en memoria hasta CN-04.
- `NetworkingConfiguration.protocolClasses` se mantiene **solo** en el `convenience init` (lo consume `URLSessionTransport`), marcado `@available(*, deprecated, message: "Usa InMemoryTransport para unidad y URLSessionTransport(configuration:) para integración")`.

TestSupport:
```swift
public actor InMemoryTransport: HTTPTransport {    // actor: estado mutable compartido entre el test y el pipeline (aquí SÍ toca)
    public struct Exchange: Sendable { method, url, responses: [Outcome] /* se consumen en orden; el último se repite */ }
    public enum Outcome: Sendable { case response(status: Int, headers: [String:String] = [:], body: Data = Data(), latency: Duration? = nil); case failure(any Error) }
    public func register(_ exchange: Exchange)
    public var recorded: [URLRequest]      // con body legible (no stream)
}
```
- `MockURLProtocol`: se conserva para integración; gana `responses: [MockResponse]` (secuencia) manteniendo compatibilidad con `response:`.
- `MockAPIService`: stubs tipados por tipo de request: `stub<R: BaseRequest, T>(_ requestType: R.Type, returning: T)` y `stub(_:throwing: APIError)`; `result: Any?` se elimina.
- Tests de retry: `ManualClock` en `CoreNetworkingTestSupport` (público, reutilizable por apps) → cero sleeps reales.

## Ficheros
Sources: `APIService.swift` (init, `performWithRetry`, closures de transporte), nuevo `Transport/HTTPTransport.swift`, nuevo `Transport/URLSessionTransport.swift` (mueve la creación de sesión y el `deinit` desde `APIService`), `RetryPolicy.swift`, `NetworkingConfiguration.swift` (deprecación).
TestSupport: nuevo `InMemoryTransport.swift`, nuevo `ManualClock.swift`, `MockURLProtocol.swift` (secuencias), `MockAPIService.swift`, `MockAPIHelper.swift`.
Tests: `RetryBehaviorTests.swift` (migrar a `InMemoryTransport` + `ManualClock`), `CancellationTests.swift`, `PipelineTests.swift` (dejar 2-3 con `MockURLProtocol` como integración, resto a `InMemoryTransport`), `RetryPolicyTests.swift`.
README: «Uso básico», «Retry», «Testing».

## Criterios de aceptación
- [ ] Test «500, 500, 200 → éxito con 3 requests» usando `InMemoryTransport` con secuencia.
- [ ] `RetryBehaviorTests` no contiene `ContinuousClock.now` ni mide tiempo de pared; todo con `ManualClock.advance`.
- [ ] Ningún test nuevo usa `MockURLProtocol.removeAll()`; `grep -rn "Task.sleep" Tests` solo en tests de integración de `MockURLProtocol` (latencia).
- [ ] `swift test --parallel` verde 5 veces seguidas (script en el resumen final).
- [ ] `APIService` no crea `URLSession`; `URLSessionTransport` sí y la invalida en `deinit`.
- [ ] README «Testing» muestra `InMemoryTransport` como camino principal y `MockURLProtocol` como integración.

## Fuera de alcance
Delegate por tarea y pinning e2e (CN-04). `RequestRetrier` (CN-06).
