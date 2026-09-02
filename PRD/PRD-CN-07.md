# PRD-CN-07 — Pulido de CoreNetworking tras el doble check

Paquete: CoreNetworking · Oleada 6 · Cubre: DC-CN-1…DC-CN-7 (`AUDITORIA-2026-09-02-doblecheck.md` §2) · Rompe API pública: **sí** (`upload`, `Category`)

## Cambios
1. **`upload` alineado con `execute`**: `func upload<Request: BaseRequest>(_ request: Request, data: Data, progress: …) async throws(APIError) -> Request.Response` (+ sobrecarga `as:` como `execute`). Eliminar la firma `upload(request:data:progress:) -> Response` en `APIServiceProtocol`, `APIService`, `MockAPIService`.
2. **`download(_:to:)` por el pipeline compartido**: `performWithRetry` recibe un transporte que devuelve `(Data(), response)` y escribe en `destination`; el `catch` de pinning y los interceptores dejan de estar duplicados. Reintento permitido (cada intento reescribe atómicamente); documentar que un `download` a medias reintenta desde cero. Borrar el comentario "kept separate to avoid touching the region CN-06 owns".
3. **`APIError.Category.unreachable`** para `networkConnectionLost`, `cannotConnectToHost`, `dnsLookupFailed`, `cannotFindHost`, `cannotConnectToHost`; tabla del doc comment y `errorDescription` (EN/ES en el catálogo: "No se pudo conectar con el servidor.") actualizados; test parametrizado.
4. **`APIError.Code.unstubbed`** en `CoreNetworkingTestSupport` (`extension APIError.Code { public static let unstubbed = Code("testSupport.unstubbed") }`); `MockAPIService` lo lanza cuando no hay stub o el tipo no coincide, con `underlying` que nombra el request y el tipo esperado.
5. **Sin PRDs en el código**: eliminar toda mención a `CN-0x`/`X-0x`/`AF-0x` de `Sources/` (`grep -rn "CN-0\|X-0\|AF-0" Sources` vacío). Los racionales se conservan reescritos en presente.
6. **`protocolClasses` deprecado**: `@available(*, deprecated, message: "Configura protocolClasses en sessionConfiguration")`; los tests de integración con `MockURLProtocol` pasan a `sessionConfiguration`. README «Testing» actualizado.
7. `Empty: Equatable`; `RequestSummary.init(URLRequest)` guarda el método desconocido como `.get` **solo** si `httpMethod == nil`; con un método no listado, `HTTPMethod(rawValue:)` falla → añadir `case custom(String)`? **No**: mantener el enum cerrado y documentar que métodos fuera de la lista no son soportados (WebDAV no es objetivo). Solo corregir el doc.

## Ficheros
`Sources/CoreNetworking/{APIServiceProtocol,APIService,APIError,BaseRequest,Configuration/NetworkingConfiguration}.swift`, `Sources/CoreNetworking/Resources/Localizable.xcstrings`, `Sources/CoreNetworkingTestSupport/{MockAPIService,MockAPIHelper}.swift`, tests afectados (`TransferTests`, `APIErrorTests`, `PipelineTests`, `PinningPipelineTests`, `DecoderConfigurationTests`), README (secciones «Upload / Download», «Errores», «Testing»), `CHANGELOG.md` (`## [Unreleased]`; **no** reabrir 1.0.0: estos cambios entran en 1.0.0 porque aún no hay tag — mover la sección `[1.0.0]` a `[Unreleased]` es responsabilidad de X-03; aquí solo añadir entradas bajo `[Unreleased]`).

## Criterios de aceptación
- [ ] `grep -rn "upload(request:" Sources Tests README.md Examples` vacío; `upload(UploadRequest(), data:)` devuelve `UploadRequest.Response` (test).
- [ ] `download(_:to:)` con `InMemoryTransport` secuencia `[500, 200]` y `RetryPolicy(maxAttempts: 2)` deja el fichero correcto tras 2 requests (test); un `PinningFailure` en download → `.untrustedServer` (test existente sigue verde).
- [ ] `APIError(code: .transport, underlying: URLError(.cannotConnectToHost)).category == .unreachable` y `errorDescription` en EN/ES (tests).
- [ ] `MockAPIService().execute(GetGames())` sin stub → `code == .unstubbed` (test).
- [ ] `grep -rn "CN-0\|X-0\|AF-0" Sources` vacío.
- [ ] `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` 0 warnings; `swift test --parallel` verde 3 veces; `swift format lint --strict --recursive Sources Tests` 0; `xcodebuild build -scheme CoreNetworking-Package -destination 'generic/platform=iOS Simulator'` OK; `Examples/IntegrationExample` `swift test` verde (adaptar si cambia `upload`).
