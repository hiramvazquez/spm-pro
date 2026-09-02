# PRD-CN-04 — Delegate por tarea: pinning extremo a extremo, progreso y `download` a disco

Paquete: CoreNetworking · Oleada 3 (tras CN-03 y CN-05) · Cubre: CN-01 (crítico), CN-07 · Rompe API pública: **sí** (`download` → dos APIs)

## Problema
1. Cancelar el challenge de server-trust produce `URLError(.cancelled)` (verificado: −999), así que un fallo de
   pinning llega como cancelación. `certificateValidationFailed` nunca se emite.
2. `download` itera `AsyncBytes` byte a byte y devuelve `Data` en memoria.

## Diseño (todo dentro de `URLSessionTransport`)

```swift
/// Un delegate por tarea. Implementa SOLO los callbacks de URLSessionTaskDelegate/DataDelegate que necesita.
final class TaskDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    // @unchecked justificado: estado bajo OSAllocatedUnfairLock; URLSession llama desde su cola serial.
    private let pinning: SSLPinningConfiguration?
    private let progress: TransferProgress?
    private let state = OSAllocatedUnfairLock(initialState: State())   // pinningFailed: Bool, bytesReceived/expected
    func urlSession(_:task:didReceive challenge:completionHandler:)     // decide con pinning.validate; si .failed → state.pinningFailed = true; completionHandler(.cancelAuthenticationChallenge, nil)
    func urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)   // progress.onUpload
    func urlSession(_:dataTask:didReceive data:)                          // progress.onDownload por chunk (expectedContentLength de la respuesta)
    func urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)
    var pinningFailed: Bool
}
```
- El delegate de **sesión** desaparece (`PinningSessionDelegate` se borra); la sesión se crea con `delegate: nil`.
  Todos los métodos `URLSession` async reciben `delegate: TaskDelegate` por tarea.
- Mapeo: tras `catch let e as URLError where e.code == .cancelled`, si `delegate.pinningFailed` → lanzar
  `PinningFailure(host:)` (error interno del transporte) que `APIService` convierte en
  `APIError(code: .untrustedServer, request:)`. Con `Task.isCancelled == true` y sin pinningFailed → `.cancelled`.
- `HTTPTransport` gana `func download(_ request: URLRequest, to destination: URL, progress:) async throws -> HTTPURLResponse`
  (usa `session.download(for:delegate:)`, mueve el fichero temporal a `destination` **antes** de volver, porque el
  temporal se borra al salir del callback).
- `APIServiceProtocol`:
  - `execute` y `upload` sin cambios de firma (ya en CN-05).
  - `func data<Request: BaseRequest>(for request: Request, progress:) async throws(APIError) -> Data` sustituye al
    `download` actual (mismo comportamiento, implementación por chunks, progreso real por `didReceive data`).
  - `func download<Request: BaseRequest>(_ request: Request, to destination: URL, progress:) async throws(APIError)`.
- `upload` usa `session.upload(for:from:delegate:)` (el body **no** viaja en `httpBody`).

## Ficheros
Sources: `Transport/URLSessionTransport.swift` (+ nuevo `Transport/TaskDelegate.swift`), `SessionDelegates.swift` (borrar), `HTTPTransport.swift` (nueva firma), `APIService.swift` (métodos `data`/`download`/`upload` y el mapeo de `PinningFailure`), `APIServiceProtocol.swift`.
TestSupport: `InMemoryTransport.swift` (soporte de `download(to:)` y de simular `PinningFailure`), `MockAPIService.swift`.
Tests: `PinningDelegateTests.swift` (migrar a `TaskDelegate`; conservar el fixture de certificado y `EspacioConTrust`), `TransferTests.swift` (reescribir: chunks, `download(to:)`, progreso), `CancellationTests.swift`, nuevo `PinningPipelineTests.swift`.
README: «Upload / Download», «SSL Pinning» (párrafo «qué recibe la app cuando falla el pinning»).

## Criterios de aceptación
- [ ] Test e2e con `URLProtocol` de integración: un transporte cuyo `TaskDelegate` tiene `pinningFailed == true` y lanza `URLError(.cancelled)` produce `APIError.code == .untrustedServer` y `category == .untrustedServer`. Un `URLError(.cancelled)` **sin** el flag produce `.cancelled`.
- [ ] `PinningDelegateTests` cubre las 6 decisiones existentes sobre `TaskDelegate` (misma matriz) y además «tras `.failed`, `pinningFailed == true`».
- [ ] `data(for:)` de 5 MB con `MockURLProtocol` devuelve los bytes en < 0,2 s en debug (test con límite generoso, solo para cazar la regresión byte a byte) y el progreso es monótono y termina en 1.0.
- [ ] `download(to:)` deja el fichero en `destination` y no queda temporal huérfano.
- [ ] `grep -rn "PinningSessionDelegate\|UploadProgressDelegate\|certificateValidationFailed\|for try await byte" Sources` vacío.
- [ ] `URLSessionTransport` mantiene `deinit { session.finishTasksAndInvalidate() }` con comentario de por qué (aunque ya no haya delegate de sesión, el retain de la sesión sobre su cola sigue existiendo) o justifica su eliminación.
