# Auditoría técnica — AppFoundation + CoreNetworking

Fecha: 2026-09-01 · Toolchain: Swift 6.3.3 (swift-tools 6.2) · Objetivo: dejar ambos paquetes listos para producción en apps iOS nuevas.

## 0. Veredicto en una página

**Estado real.** Los dos paquetes están muy por encima de la media: Swift 6 estricto, Approachable Concurrency bien entendida, cero warnings, 236 tests verdes (74 + 162), compilan para macOS e iOS Simulator, decisiones documentadas con su racional, mocks fuera del binario de producción y mutation testing configurado. La base es sólida.

**Lo que impide llamarlos "PROD" hoy** son cuatro cosas concretas, todas verificadas en esta auditoría, no supuestas:

| # | Hallazgo | Severidad | Verificación |
|---|----------|-----------|--------------|
| CN-01 | Un fallo de SSL pinning llega a la app como `APIError.cancelled`, no como `certificateValidationFailed`. Ese caso **no lo produce ningún camino del código**. | Crítico | Script contra servidor real: cancelar el challenge → `URLError` -999. `grep` confirma cero productores del caso. |
| AF-01 | `BaseViewModel` **fuga** en fase `.error`: `phase → ScreenError.retry → work → self`. Con los ejemplos del README (`self.` fuerte en `work`) el VM no se libera nunca. | Crítico | Test temporal con `weak var`: el VM sigue vivo tras salir de scope. |
| CN-02 | El modelo de error (`enum APIError` cerrado + `.unknown` + `.custom` con forma de body fija + `TransportError` paralelo) es el que causa fricción a las apps que lo adoptan: pierde el body, pierde headers, no es extensible sin romper `switch` exhaustivos, y su `Equatable` miente. | Alto | Lectura + tests. Propuesta de rediseño en §4. |
| AF-02 | El fallback de error de `BaseViewModel` muestra `error.localizedDescription` de errores Swift que no son `LocalizedError`: en pantalla sale *"The operation couldn't be completed. (CoreNetworking.APIError error 9.)"*. | Alto | `BaseViewModel.swift:295`; `APIError` no conforma `LocalizedError`. |

Todo lo demás son mejoras de diseño (actor vs `@MainActor`, `AnyView`, barra de navegación custom, API deprecada) y limpieza. Se detallan por paquete con evidencia `archivo:línea`.

**Resumen por severidad**: 2 críticos · 9 altos · 18 medios · 16 bajos. Lo que está bien se lista explícitamente en §5 porque también es parte del veredicto.

---

## 1. Metodología

- Lectura completa de los 73 ficheros Swift (10.7k LOC) de ambos paquetes, tests incluidos.
- `swift build` + `swift test` en macOS (con `SWIFT_STRICT_WARNINGS=1` en AppFoundation) y `xcodebuild` para iOS Simulator en ambos: verde, 0 warnings.
- Verificaciones empíricas con el compilador y en runtime cuando un hallazgo dependía de un comportamiento de Foundation y no del código:
  - `JSONDecoder`, `JSONEncoder` y `URLSessionConfiguration` **sí** pasan como `Sendable` en este SDK (el README de CoreNetworking afirma lo contrario).
  - `Never` funciona como default de `associatedtype Body: Encodable & Sendable = Never`.
  - Cancelar un challenge de server-trust produce `URLError.cancelled` (-999), no `serverCertificateUntrusted` (-1202).
  - Test de fuga temporal en AppFoundation (añadido, ejecutado y borrado; el árbol de trabajo quedó limpio).
- Criterio: "mejores prácticas de Swift a día de hoy" = Swift 6.2 (`defaultIsolation`, `nonisolated(nonsending)`, typed throws, `Duration`/`Clock`, Observation, Swift Testing), APIs de Foundation modernas, y el contrato que un paquete público debe dar a quien lo consume (evolución sin roturas, errores extensibles, sin heurísticas de test en producción).

---

## 2. CoreNetworking

### 2.1 Tratamiento de errores (foco principal)

**CN-01 · Crítico · El pinning falla en silencio como "cancelación".**
`SessionDelegates.swift:33-39` responde `.cancelAuthenticationChallenge` cuando el pin no coincide. Foundation convierte eso en `URLError(.cancelled)`; `APIError.map(_:)` (`APIError.swift:85-90`) lo traduce a `.cancelled`. Consecuencias en cadena:
- `APIError.certificateValidationFailed` (`APIError.swift:61`) es un caso muerto: ninguna ruta lo crea (verificado con `grep` sobre Sources y Tests). Los tests de `TransportError` lo prueban "a mano" pero el pipeline jamás lo emite.
- Un MITM detectado por pinning se ve, desde la app, igual que un usuario cancelando. El idioma habitual `if case .cancelled = error { return }` se lo traga. `TransportError(from: .cancelled)` da `.unknown`.
- En AppFoundation, el `catch` genérico de `performLoad` no está cancelado (`Task.isCancelled == false`), así que **sí** llega a pantalla, pero como el mensaje basura de AF-02.

Corrección: el delegate tiene que **recordar** que él canceló, y el pipeline consultarlo al mapear `.cancelled`. Es lo que hace Alamofire (`serverTrustEvaluationFailed`). La forma limpia con URLSession async: un delegate **por tarea** (`session.data(for:delegate:)`) que implemente el challenge a nivel de task (`urlSession(_:task:didReceive:completionHandler:)`), guarde `pinningFailed = true` bajo lock, y `performOnce` haga `if urlError.code == .cancelled && taskDelegate.pinningFailed { throw .untrustedServer }`. Esto además elimina el delegate de sesión y el `deinit` con `finishTasksAndInvalidate` (`APIService.swift:62-66`) deja de ser necesario para evitar la fuga sesión↔delegate. Añadir un test de integración que registre un `URLProtocol` que genere un `URLError(.cancelled)` con el flag activo, o mejor, probar el mapeo con el delegate real inyectado.

**CN-02 · Alto · `APIError` como enum cerrado con payloads fijos.** Es el hallazgo que responde a "quiero algo más genérico que no cause problemas en las apps":
- `.custom(APIMessageError, ...)` (`APIError.swift:49, 73-82`) asume que el servidor devuelve `{ "message": "..." }`. Cualquier backend con otro sobre (`{ "error": { "code", "detail" } }`, RFC 9457 *problem+json*, errores de validación por campo) pierde el body: `.httpStatus(Int, retryAfter:)` no lleva `Data` ni headers. La app **no puede** decodificar el error del servidor con su propio DTO. Esto es lo primero que pide cualquier app real.
- `.unknown` (`APIError.swift:35`, producido en `APIService.swift:194, 230, 273`) descarta el error original. Un `NSError` de un `URLProtocol`, un POSIX error o un fallo de encoder que no sea `EncodingError` se pierden sin rastro.
- Enum público en un paquete fuente: añadir un caso rompe todos los `switch` exhaustivos de los consumidores. Con `throws(APIError)` el consumidor está incentivado a hacer `switch` exhaustivo. Cada caso nuevo es un breaking change.
- `Equatable` (`APIError.swift:207-236`) declara iguales dos `decodingError` distintos y dos `encodingError` distintos, e ignora `retryAfter`. Un `==` que "miente" en un tipo público invita a bugs en tests y en lógica de deduplicación. Lo mismo pasa en `RetryPolicy` (`RetryPolicy.swift:117-126`, ignora el closure) y en `WrappedError` (compara `localizedDescription`).
- `isRetryable` (`APIError.swift:129-141`) reintenta con `.notConnectedToInternet` (inútil: sin red no hay nada que reintentar en 0.5 s; el mecanismo correcto es `waitsForConnectivity`) y no incluye `.dnsLookupFailed` / `.cannotFindHost`, que sí son transitorios.

**CN-03 · Alto · `TransportError` es un segundo vocabulario de error para la misma capa.** `TransportError.swift:12-56`. Dos `Error` públicos para el mismo dominio confunden a quien adopta el paquete ("¿cuál capturo?"). Además:
- 401 y 403 colapsan en `.unauthorized` (`:51`); 403 es "autenticado pero prohibido", que la UI trata distinto (no hay que relanzar login).
- `.connectionInterrupted` se usa para "el pinning rechazó el certificado" (`:38-41`), y **no** para `.networkConnectionLost`, que es literalmente una conexión interrumpida. Nombre engañoso.
- Solo `.notConnectedToInternet` es `.offline` (`:33`); `.timedOut`, `.networkConnectionLost`, `.dnsLookupFailed` caen en `.unknown`.
- Identificadores en español (`mapearEstado`, `codigo`) en un API que por lo demás es inglés.
Debe ser una propiedad derivada del error único (`error.category`), no un `Error` aparte. Ver §4.

**CN-04 · Medio · Typed throws en API pública.** `APIServiceProtocol.swift:15-49`. SE-0413 recomienda typed throws para dominios de error cerrados y código genérico; para API de librería recomienda `throws` sin tipo salvo que el tipo de error sea evolutivo. Con un `enum` no lo es. Si `APIError` pasa a ser un `struct` con `Code` extensible (§4), mantener `throws(APIError)` es defendible y aporta ergonomía (no hay `as? APIError`). Con el enum actual es una trampa de compatibilidad. Nota práctica: la cancelación estructurada de Swift lanza `CancellationError`; con typed throws hay que envolverla, por eso existe `.cancelled`; hay que mantener `isCancellation` como propiedad y **no** confundirla con CN-01.

**CN-05 · Alto · Sin adaptador de reintento por autenticación (refresh token).** `RequestInterceptor.swift:29-50`. El interceptor solo puede mutar el request antes de enviar. No puede: (a) fallar (`willSend` no lanza; si no hay token, el request sale sin él y el servidor devuelve 401), ni (b) decidir "refresca el token y reintenta" tras un 401. Es el caso de uso número uno de interceptores en apps de producción. Añadir un contrato tipo `RequestRetrier` con `func retry(_ request: URLRequest, dueTo error: APIError, attempt: Int) async -> RetryDecision` (`.doNotRetry`, `.retry`, `.retryAfter(Duration)`), o ampliar el interceptor con `willSend(...) async throws(APIError)` + `shouldRetry(...)`. Diseñar el refresh con un `actor TokenRefresher` que deduplique refreshes concurrentes (N requests que reciben 401 a la vez → un único refresh).

**CN-06 · Medio · `didReceive(_ response: URLResponse, data:)` sin identidad de request.** `RequestInterceptor.swift:41`. El propio código lo reconoce (nota en `:134-141`: por eso se borró `PerformanceInterceptor`). Pasar `HTTPURLResponse` (no `URLResponse`, que obliga a cast) y el `URLRequest` (o un `RequestID`) resuelve métricas, tracing y correlación de logs. `didFail(_:error: Error)` (`:49`) debería tipar `APIError`.

### 2.2 Pipeline (`APIService`)

**CN-07 · Alto · `download` itera byte a byte.** `APIService.swift:107-125`: `for try await byte in bytes { data.append(byte) }` hace una llamada async por byte. Para una descarga de decenas de MB es CPU puro (órdenes de magnitud más lento que recibir chunks). Además la API se llama `download` pero devuelve `Data` en memoria: para ficheros grandes el API correcto es `session.download(for:)` a disco. Recomendación: dos APIs claras — `data(for:progress:)` usando `session.data(for:delegate:)` con un delegate por tarea que observe `task.progress` (mismo patrón que ya usa upload) y `download(for:destination:progress:)` a URL de fichero. La granularidad `data.count % 65536 == 0` (`:119`) solo funciona porque se añade de uno en uno; se rompe al pasar a chunks.

**CN-08 · Medio · Sin soporte para respuestas vacías (204 / HEAD).** `execute` siempre decodifica (`APIService.swift:76`); `JSONDecoder` con `Data()` lanza. `EmptyResponse` (`BaseResponse.swift:5`) no ayuda porque `{}` ≠ vacío. Añadir `execute(request:) async throws(APIError)` sin retorno, y tratar `Response == EmptyResponse` o `data.isEmpty` como éxito.

**CN-09 · Medio · Asimetría decoder/encoder.** Hay `makeDecoder` configurable (`NetworkingConfiguration.swift:59`) pero el body se codifica con `JSONEncoder()` a pelo (`APIService.swift:269`). Con `convertFromSnakeCase` en el decoder, el consumidor necesita `convertToSnakeCase` en el encoder y hoy no puede. Añadir `makeEncoder`. Corregir además el README: `JSONDecoder` **es** `Sendable` en el SDK actual (verificado con `swiftc -swift-version 6`); la fábrica sigue siendo un diseño válido (aislamiento por construcción) pero el racional escrito es falso.

**CN-10 · Medio · `URLSessionConfiguration` no es configurable.** `APIService.swift:49-52` solo expone `protocolClasses`. Una app de producción necesita `waitsForConnectivity`, `timeoutIntervalForResource`, `httpShouldSetCookies = false` para APIs, `urlCache`/`requestCachePolicy`, `tlsMinimumSupportedProtocolVersion`, `multipathServiceType`, `httpAdditionalHeaders`. Aceptar una fábrica `@Sendable () -> URLSessionConfiguration` (o la configuración directamente: es `Sendable` en el SDK) y derivar `protocolClasses` de ahí.

**CN-11 · Medio · Retry sin `Clock` inyectable.** `APIService.swift:162` usa `Task.sleep` real; `RetryPolicy` trabaja en `TimeInterval`. `RetryBehaviorTests` prueban con delays de 10 ms y miden tiempo de pared (`retryAfterOverridesBackoff` asume `< 1.5 s`): flaky bajo carga de CI. AppFoundation ya inyecta `Clock` en `Debouncer`; hacer lo mismo aquí (`any Clock<Duration>`) y pasar `RetryPolicy` a `Duration`. `shouldRetry: (Error, Int)` (`RetryPolicy.swift:38`) debería tipar `APIError`.

**CN-12 · Bajo · `catch` residual a `.unknown`.** `APIService.swift:193-197, 229-231, 272-274`. Cubierto por CN-02: preservar el error original en `underlying`.

**CN-13 · Bajo · `Content-Type: application/json` en todos los requests.** `BaseRequest.swift:138` lo añade también a GET sin body; falta `Accept: application/json`. Poner `Content-Type` solo cuando hay body, en `buildURLRequest`.

**CN-14 · Bajo · `parseRetryAfter` crea un `DateFormatter` por llamada.** `APIError.swift:101-105`. En iOS 18+ existe `Date(_, strategy: .http)` (`Date.HTTPFormatStyle`, verificado que compila); con `#available` se elimina el formatter. Nit.

### 2.3 Modelo de request

**CN-15 · Medio · Boilerplate `typealias Parameters = EmptyParameters` en cada GET.** `BaseRequest.swift:82`. Con `associatedtype Parameters: Encodable & Sendable = Never` (verificado) desaparece; `RequestParameters` como protocolo marcador (`:20`) obliga a que los DTOs del consumidor conformen a un protocolo del paquete: fricción innecesaria, `Encodable & Sendable` basta.

**CN-16 · Medio · El request no declara su tipo de respuesta.** `execute<Request, Response: Decodable>` infiere `Response` del call-site (`let games: [Game] = ...`). El patrón actual es `associatedtype Response: Decodable` en el request: cada endpoint es un tipo completo, sin ambigüedades de inferencia, y el mock puede stubear por tipo de request en vez de `Any?` (ver CN-22).

**CN-17 · Bajo · Código muerto y API sin uso.** `BaseResponse`/`EmptyResponse` (`BaseResponse.swift`), `validated()`/`isValid`/`debugValidated()`/`RequestValidationError`/`requestDescription` (`BaseRequest.swift:163-271`), `NetworkingConfiguration.environment` (`:42`, "solo metadato", nadie lo lee). Ninguno se usa en Sources ni Tests. `RequestValidationError` además es un tercer tipo de error público fuera del dominio `APIError`. Borrar o integrar en `buildURLRequest`.

**CN-18 · Bajo · `HTTPMethod` con casos en mayúsculas.** `BaseRequest.swift:4-5`. La convención Swift (y `HTTPTypes` de Apple) es `.get` con `rawValue: "GET"`. Cambio de API menor pero visible en cada request del consumidor: hacerlo antes de 1.0.

### 2.4 SSL pinning

**CN-19 · Medio · ¿Es esta la mejor forma?** Para apps nuevas, Apple ofrece pinning declarativo desde iOS 14: `NSAppTransportSecurity → NSPinnedDomains → NSPinnedLeafIdentities / NSPinnedCAIdentities` con `SPKI-SHA256-BASE64` (el mismo formato que usa este paquete). Cero código, sin delegate, cubre toda `URLSession`, no puede tener el bug CN-01. Su límite: pins estáticos (sin rotación remota) y no cubre `WKWebView`. Recomendación: documentar `NSPinnedDomains` como opción por defecto y dejar el pinning programático como opt-in para quien necesite pins dinámicos. Si se mantiene el código:
- Exigir ≥ 2 pins (backup pin, RFC 7469) o al menos avisar: con un solo pin, rotar la clave del servidor deja la app inutilizable.
- `validateCertificateChain: Bool` (`SSLPinningConfiguration.swift:66`) es un flag peligroso en producción; si se conserva, gatearlo con `#if DEBUG` o nombrarlo `unsafeSkipChainValidation`.
- Añadir RSA-3072 a la tabla ASN.1 (`:142-160`); hoy un servidor con esa clave nunca valida (fail-closed correcto, pero sorprende).
- `pinnedHosts: Set<String>?` con `nil` = todos (`:61`): un enum `.allHosts | .hosts(Set)` es más legible que nil-como-comodín.

### 2.5 Logging

**CN-20 · Bajo · `didFail` loguea el error con `privacy: .public`.** `RequestInterceptor.swift:130`. `APIError.description` de `.custom` incluye el mensaje del servidor (puede llevar PII: "user john@x.com not found"). Marcar `.private` o loguear solo `code`/`status`. Subsystem `"CoreNetworking"` (`Logging.swift:6`) debería ser reverse-DNS y, mejor, configurable con el bundle id de la app.

### 2.6 Test support y `URLProtocol`

**CN-21 · Medio · `URLProtocol` es la herramienta correcta para *integración*, no para *unidad*.** `MockURLProtocol.swift:83` usa un registro estático global; el README documenta una guerra real con Swift Testing en paralelo y la solución "un host por test". Eso es un síntoma: el servicio no tiene un punto de inyección por debajo de `URLSession`. Recomendación: introducir `protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`, que `APIService` reciba un transporte (default: `URLSessionTransport`), y que los tests unitarios inyecten uno en memoria (sin estado global, sin `nonisolated(unsafe)` en `:139`, paralelizable). Mantener `MockURLProtocol` para unos pocos tests de integración que necesiten atravesar el URL loading system de verdad (merge de headers, cookies, redirecciones, delegate de pinning). Cosas que hoy el mock **no** puede: secuencias de respuestas (500 → 200), que es exactamente lo que falta para probar "reintento que acaba bien"; y `recordedRequests` no expone el body (en `URLProtocol` viaja en `httpBodyStream`, gotcha conocido).

**CN-22 · Bajo · `MockAPIService.result: Any?`.** `MockAPIService.swift:24`. Un mismatch de tipo se convierte en `.invalidResponse`, que despista. Con `associatedtype Response` (CN-16) el stub puede ser tipado por request. Alternativa al `@unchecked Sendable` + lock: como todos los métodos ya son `async`, un `actor` sería natural; se mantiene la clase por ergonomía de `mock.result = x` síncrono, decisión válida si se documenta.

### 2.7 Tests (CoreNetworking)

Bien: matriz de retry (off-by-one, idempotencia, opt-in, Retry-After), cancelación real medida en tiempo, vectores openssl para SPKI, decisión de pinning en 3 estados, redacción de headers, mutation testing con findings anotados. Huecos:
- Ningún test de **mapeo extremo a extremo** del fallo de pinning (habría cazado CN-01).
- Ningún test de "reintento que termina en éxito" (limitación del mock, CN-21).
- Ningún test de 204/body vacío (CN-08), ni de interceptor que necesite abortar (CN-05).
- Tests de tiempo de pared en retry (CN-11).

---

## 3. AppFoundation

### 3.1 Memoria y ciclo de vida (`BaseViewModel`)

**AF-01 · Crítico · Fuga en fase `.error` (verificada).** `BaseViewModel.swift:204-213`: en el `catch`, se construye `retry = { [weak self] in self?.performLoad(..., work) }`. `retry` captura `work` **fuerte**; `work` captura `self` fuerte (así lo enseñan el README y toda la documentación: `self.repository.fetchProfile()`). Cadena: `self.phase → ScreenError.retry → work → self`. Resultado del test temporal:

```
✘ VM en fase .error con work que captura self fuerte: ¿se libera?
  Expectation failed: (weakVM → VM) == nil
```

Mientras la pantalla esté en error y se cierre (pop, dismiss), el VM, sus dependencias y todo lo que retenga viven para siempre. Es el estado más común tras un fallo de red.

**AF-03 · Alto · El contrato "deinit cancela lo que quede en vuelo" no se cumple con el uso documentado.** Mismo test, tercer caso: soltado el VM con un load en vuelo, `weakVM` sigue vivo hasta que `work` termina, porque `work` retiene `self` y el `Task` retiene `work`. `deinit` (`:60-66`) solo se ejecuta cuando ya no queda nada que cancelar. El request sigue en el aire y la pantalla ya no existe.

Corrección (cubre AF-01 y AF-03): el diseño de la API tiene que impedir que `work` retenga `self`, no pedir `[weak self]` en la documentación.
1. Pasar el view model como **parámetro** del closure, con `Self` a través de un protocolo (las clases no pueden usar `Self` covariante en parámetros, un protocol extension sí):
   ```swift
   public protocol LoadableViewModel: BaseViewModel {}
   extension LoadableViewModel {
       @discardableResult
       func performLoad(style: ActivityStyle = .fullScreen, ...,
                        _ work: @escaping @MainActor (Self) async throws -> Void) -> Task<Void, Never> {
           _performLoad(style: style, ...) { [weak self] in
               guard let self else { throw CancellationError() }
               try await work(self)
           }
       }
   }
   // uso: performLoad { vm in vm.items = try await vm.repository.fetch() }
   ```
   `work` ya no captura nada del VM; el ciclo desaparece y el retry puede guardarse sin fuga.
2. Ofrecer una variante **estructurada** `func load(...) async` que ejecute `work` inline, sin `Task` no estructurado, para usarla desde `.task { await vm.load() }`: SwiftUI cancela al desaparecer la vista, sin depender de `deinit`. La variante que devuelve `Task` queda para acciones de botón.
3. Añadir el test de fuga (`weak var`) a la suite: es barato y es el que faltaba.

**AF-04 · Medio · La cancelación se reconoce solo por `CancellationError`.** `BaseViewModel.swift:200`. Una capa de red cancela con `URLError.cancelled` / `APIError.cancelled`; hoy se salva por el `guard !Task.isCancelled` del `catch` genérico. Explicitar un `isCancellation(error)` extensible (protocolo o closure inyectable) que la app pueda ampliar con sus tipos.

**AF-05 · Bajo · `showBanner` duerme con reloj real.** `BaseViewModel.swift:150`. `bannerAutoDismissesAfterItsDuration` tarda 75-160 ms de reloj de pared; `Debouncer` ya inyecta `Clock`, `BaseViewModel` no. Inyectar `any Clock<Duration>` (default `ContinuousClock`).

### 3.2 Errores de cara al usuario (cruce con CoreNetworking)

**AF-02 · Alto · Fallback a `localizedDescription` produce texto basura.** `BaseViewModel.swift:295`. Para cualquier `Error` Swift que no sea `LocalizedError` (todos los enums de dominio, `APIError` incluido), `localizedDescription` es *"The operation couldn't be completed. (Módulo.Tipo error N.)"*. Eso es lo que ve el usuario cuando falla la red y el VM no ha mapeado el error. Reglas:
- El fallback para errores no convertibles debe ser un mensaje genérico **localizado** ("Algo ha ido mal. Inténtalo de nuevo.") y el detalle técnico va al logger, nunca a pantalla.
- `WrappedError.message` (`WrappedError.swift:91-93`) compone `"contexto: localizedDescription"` y `screenError` lo muestra tal cual: mismo problema con un prefijo.

**AF-06 · Alto · No hay un punto único donde la app mapee errores a copy.** Hoy cada VM debe hacerlo, o conformar cada error de cada paquete a `AppErrorConvertible` (imposible para tipos de otro módulo sin retroactive conformance, que Swift 6 desaconseja con warning). Falta un **`ErrorPresenter`/`ErrorMapping`** inyectable en `BaseViewModel` (estático por defecto o por instancia vía `Container`): `func screenError(for error: any Error) -> ScreenError?`. La app registra uno que entiende `APIError.category` (§4), sus errores de dominio y el fallback. Esto es "lo genérico que no causa problemas": un solo adaptador por app, cero cambios en los paquetes cuando cambia el copy.

**AF-07 · Bajo · Documentación de errores desactualizada.** `AppErrorConvertible.swift:39-52` usa `load { }` (API eliminada) y hace `await` dentro de una función no-async. `Background.swift:18` usa `@StateObject`. `NavigationBarItem.swift:339, 375` referencian `NavigationBarStyle.dark`, que no existe.

**AF-08 · Bajo · `WrappedError` detalles.** `#file` (`:78`) → `#fileID` (no incrusta rutas absolutas en el binario). `timestamp = Date()` no inyectable. `debugDescription` sin conformar `CustomDebugStringConvertible` (nunca se usa). `Equatable` por `localizedDescription` (`:164-170`).

### 3.3 Inyección de dependencias

**AF-09 · Alto · `Container` con `NSLock` + `@unchecked Sendable` en un mundo `MainActor`.** `Container.swift:46, 75`. El propio comentario (`:31-39`) admite que las fábricas de tipos `@MainActor` "solo son seguras de ejecutar en el main actor" y que "el sistema de tipos no puede expresarlo": un contrato en un comentario en lugar de en el compilador. Todo lo que toca el contenedor **ya** es `@MainActor` (`DependencyModule`, `@Inject`, los VMs). La respuesta correcta a "¿cuándo usar un actor?" aquí es: **ninguno**. Hacer `Container` `@MainActor` elimina el lock, el double-checked locking (`:210-228`), el `@unchecked`, los tests de concurrencia y la clase de bug que el comentario describe; el compilador pasa a garantizar el contrato. El caso "resolver desde código `nonisolated`" se resuelve pasando la dependencia ya resuelta, que es constructor injection, la regla número uno del propio README. (Un `actor` sería la opción si hiciera falta resolución multi-hilo real, pero obligaría a `await` en `@Inject`, como bien se descarta en `:41-45`.)

**AF-10 · Medio · Dos mecanismos de scope.** `Lifecycle.scoped(key: String)` con `createScope`/`destroyScope` (`Container.swift:295-340`) y los **child containers** (`init(parent:)`) resuelven el mismo problema; el primero es stringly-typed, global y con `preconditionFailure` si olvidas `createScope` (`:148`). Un child container por flujo (checkout, sesión) es más seguro y ya existe. Eliminar `.scoped`.

**AF-11 · Medio · `@Inject` es un service locator.** `Inject.swift:43`. Oculta dependencias, traps en runtime si falta el registro, y como `final class` dentro de un `struct View` conserva estado entre copias de la vista sin ser `DynamicProperty`. El README ya lo relega a "bordes"; para vistas, el mecanismo nativo es `Environment` (`@Entry` en Xcode 16, retrocompatible por ser sintáctico). Recomendación: mantenerlo solo para objetos hoja no-View, o eliminarlo y dejar el contenedor como composition root. Nit: `register(_ factory: @autoclosure ...)` (`:104`) hace que `register(MyService(), lifecycle: .transient)` parezca registrar una instancia cuando registra una fábrica; un closure explícito es más honesto. `String(reflecting:)` como clave (`:107`) → `ObjectIdentifier(type)`.

### 3.4 Navegación

**AF-12 · Alto · Barra nativa oculta en toda pantalla → gesto de swipe-back probablemente roto.** `CoordinatorView.swift:79-85` y `ScreenContainer.swift:161-163` aplican `.toolbar(.hidden, for: .navigationBar)` a **todas** las rutas. En `NavigationStack`, ocultar la barra desactiva el `interactivePopGestureRecognizer`; no hay ningún workaround en el paquete (`grep` de `interactivePop`/`UINavigationController`: vacío). Hay que verificarlo en dispositivo, pero es el comportamiento documentado por la comunidad desde iOS 16. Si se confirma, es una regresión de UX básica en cada app que adopte el paquete. Cubierto también por AF-13.

**AF-13 · Alto · Reemplazar la barra de navegación nativa es una decisión que conviene revertir para apps nuevas.** `CustomNavigationBar.swift:5-19` lo justifica por "consistencia entre versiones e inmunidad a Liquid Glass (iOS 26)". El coste es alto y permanente: sin large titles, sin scroll-edge effects, sin `.searchable` (con su integración de teclado, tokens, sugerencias y scopes), sin `toolbar` semántico, sin comportamiento de back automático, sin Dynamic Type (altura fija 44, `:147-155`), botón atrás sin `accessibilityLabel` (VoiceOver lee "chevron left", `:115-120`), y AF-12. El HIG pide explícitamente respetar la barra del sistema, y en iOS 26 la app se verá "de otra época" en lugar de "consistente". Recomendación: `ScreenContainer` sobre la barra **nativa** (`navigationTitle`, `toolbar`, `searchable`) por defecto, y `CustomNavigationBar` como opt-in para el caso puntual (header con avatar). Si se mantiene la custom: `accessibilityLabel` en back/close, `ScaledMetric` para la altura, y el workaround del gesto.

**AF-14 · Bajo · `navigationHistory` es `public` solo en DEBUG.** `Coordinator.swift:134-138`. Una API cuya existencia depende de la configuración de build rompe al consumidor que la referencia en Release. Hacerla `internal` o siempre presente.

### 3.5 UI

**AF-15 · Medio · `AnyView` como mecanismo de personalización.** `ScreenContainer.swift:86-90, 425-454`, `PhaseView`, `NavigationBarItem.swift:60, 114, 270, 279`. `AnyView` borra identidad y penaliza diffing/animaciones. El patrón SwiftUI para "reemplaza cómo se ve el loading/error/empty" es un **style protocol** (`LoadingViewStyle`, como `ButtonStyle`) propagado por `Environment` con un modifier `.screenLoadingStyle(...)`. Composable, sin `AnyView`, y configurable una vez para toda la app.

**AF-16 · Medio · API deprecada / de otra época.** `.edgesIgnoringSafeArea` (`ScreenContainer.swift:234, 239`) → `.ignoresSafeArea(.container, edges:)`. `.foregroundColor` (varios en `CustomNavigationBar.swift`, `PreviewHelpers.swift`) → `.foregroundStyle` (deprecado en iOS 17). `.cornerRadius` (`CustomNavigationBar.swift:330`) → `clipShape`. `PreviewProvider` (`CustomNavigationBar.swift:353`, `Background.swift:142`) → `#Preview`. No generan warning porque están "soft-deprecated", pero un paquete PRO no debería nacer con ellas.

**AF-17 · Bajo · Barra duplicada en el árbol.** `ScreenContainer.swift:231` y `:376/:384` renderizan `CustomNavigationBar` dos veces (contenido y overlay de estado), con el mismo binding de búsqueda: dos `TextField` enlazados, riesgo de foco/teclado raro al cambiar de fase.

**AF-18 · Bajo · Nombres.** `Background.swift` contiene `PhaseView`. `BannerState.Duration` sombrea `Swift.Duration` (`BannerState.swift:163`); usar `Swift.Duration?` (nil = indefinido). `NavigationBarTitle.largeText` es "future feature" en API pública (`NavigationBarItem.swift:111`).

### 3.6 Utilidades

**AF-19 · Medio · `Debouncer`/`Throttler` como `actor` es el caso de libro de "actor que no toca".** `Debouncer.swift:51`, `:207`. Un actor aísla estado mutable compartido entre dominios de concurrencia. El estado del debouncer solo lo toca quien lo llama (casi siempre `MainActor`). Consecuencias de haberlo hecho actor: cada uso desde un VM necesita `Task { await debouncer.debounce { ... } }` (lo enseña el propio doc, `:37-43`), la operación tiene que ser `@Sendable`, y tocar estado del VM desde ella exige otro salto al main actor. Con Swift 6.2 la forma idiomática es `@MainActor final class Debouncer` (o `nonisolated` con métodos async, que con `NonisolatedNonsendingByDefault` corren en el actor del llamador): sin saltos, sin `@Sendable`, misma testabilidad con `Clock`. Además, el genérico `Debouncer<C: Clock>` obliga a escribir `Debouncer<ContinuousClock>` en cada propiedad; `any Clock<Duration>` lo evita. Para búsqueda en SwiftUI, el patrón más simple sigue siendo `.task(id: query) { try await Task.sleep(...) }`, que cancela solo.

**AF-20 · Medio · `AppEnvironment.isTestOrPreview` es una heurística de test en código de producción.** `AppEnvironment.swift:34-39`. Detecta `XCTestCase` por nombre de clase (Swift Testing puro no lo garantiza) y una variable de entorno de previews. CoreNetworking presume, con razón, de "sin heurísticas de test"; AppFoundation debería seguir la misma regla. El resto del struct es un cajón de sastre (`physicalMemoryFormatted` con `String(format:)` cuando existe `.formatted(.byteCount(style: .memory))`, `debugInfo: [String: Any]`); `isTestFlight` vía recibo está bien anotado. Nit: struct sin estado → `enum` como namespace.

**AF-21 · Bajo · Localización.** El comentario de `L10n.swift:6` habla de `Localizable.xcstrings` pero los recursos son `.strings` en `en.lproj`/`es.lproj`. Migrar a String Catalog (Xcode 15+), que además detecta claves huérfanas. `@_disfavoredOverload` (`ViewPhase.swift:99` y otros) es un atributo con guion bajo, no API soportada; funciona y SwiftUI lo usa, pero conviene documentar el riesgo.

### 3.7 Tests (AppFoundation)

Bien: Swift Testing con argumentos, `Clock` manual en Debouncer, tests de lógica de presentación sin snapshots, l10n verificada en ambos idiomas, integración DI+VM+Router. Huecos: ningún test de fuga (AF-01/AF-03), ninguno del fallback de error con un error no-`LocalizedError` (AF-02), y los de concurrencia del `Container` desaparecen con AF-09.

---

## 4. Propuesta: un único modelo de error, extensible, que las apps puedan adoptar sin dolor

Objetivo: que una app pueda (1) obtener **todo** lo que dijo el servidor, (2) decodificar su propio sobre de error, (3) clasificar sin `switch` exhaustivo, (4) reconocer cancelación y pinning sin ambigüedad, y (5) que CoreNetworking pueda añadir casos sin romper a nadie.

```swift
public struct APIError: Error, Sendable {
    /// Extensible: añadir un código nuevo NO rompe a los consumidores.
    public struct Code: Hashable, Sendable, CustomStringConvertible {
        public static let invalidURL      = Code("invalidURL")
        public static let invalidResponse = Code("invalidResponse")
        public static let transport       = Code("transport")        // URLError en `underlying`
        public static let cancelled       = Code("cancelled")
        public static let untrustedServer = Code("untrustedServer")  // pinning: NUNCA se confunde con cancelled
        public static let httpStatus      = Code("httpStatus")       // `response` siempre presente
        public static let encoding        = Code("encoding")
        public static let decoding        = Code("decoding")
        public static let interceptor     = Code("interceptor")      // un interceptor abortó (token ausente…)
        public static let unexpected      = Code("unexpected")       // `underlying` siempre presente
    }

    public let code: Code
    public let request: RequestSummary?          // método + URL, sin headers sensibles
    public let response: ResponseSummary?        // statusCode, headers, body: Data — todo lo que dijo el servidor
    public let underlying: (any Error)?          // URLError / DecodingError / EncodingError / error del interceptor

    // Derivadas (lo que hoy está repartido entre APIError y TransportError)
    public var statusCode: Int? { response?.statusCode }
    public var retryAfter: Duration? { … }
    public var isRetryable: Bool { … }
    public var isCancellation: Bool { code == .cancelled }
    public var category: Category { … }          // .offline, .timeout, .unauthorized, .forbidden, .notFound,
                                                 // .rateLimited, .server, .client, .untrustedServer, .cancelled,
                                                 // .decoding, .unknown  ← sustituye a TransportError

    /// La app decodifica SU sobre de error con SU decoder.
    public func decodeBody<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T
}
extension APIError: LocalizedError {  // fallback técnico-neutral y localizable; nunca "error 9"
    public var errorDescription: String? { … }
}
```

- `throws(APIError)` puede mantenerse: con un `struct` + `Code` la evolución es aditiva y el consumidor hace `switch error.code { case .httpStatus: … default: … }` sin miedo. `Equatable` sale de `APIError` (se compara `code`/`statusCode`, no el error); si los tests lo necesitan, un helper en `CoreNetworkingTestSupport`.
- `TransportError` desaparece como tipo; `category` cubre su función sin un segundo `Error` y sin descartar información.
- Pinning: el delegate por tarea marca el fallo y el pipeline emite `.untrustedServer` (CN-01).
- Interceptores: `willSend` puede lanzar (`.interceptor` con `underlying`), y existe `RequestRetrier` para 401 → refresh → reintento (CN-05).

Puente con AppFoundation (una sola pieza por app):

```swift
public protocol ErrorPresenting: Sendable {
    func screenError(for error: any Error, retry: Action?) -> ScreenError
}
// BaseViewModel.errorPresenter (inyectable; default: AppErrorConvertible → LocalizedError → genérico localizado)
struct AppErrorPresenter: ErrorPresenting {
    func screenError(for error: any Error, retry: Action?) -> ScreenError {
        if let api = error as? APIError {
            switch api.category {
            case .offline:       return ScreenError(title: "Sin conexión", message: "…", retry: retry)
            case .unauthorized:  return ScreenError(title: "Sesión caducada", message: "…")
            case .untrustedServer: return ScreenError(title: "Conexión no segura", message: "…")
            default: if let body = try? api.decodeBody(ServerProblem.self) { return … }
            }
        }
        return DefaultErrorPresenter().screenError(for: error, retry: retry)
    }
}
```

Con esto, un VM nunca toca `APIError`, el copy vive en un sitio, y cambiar de backend o de sobre de error es un cambio local.

---

## 5. Lo que está bien (y conviene no tocar)

- **Swift 6.2 en serio**: `defaultIsolation(MainActor)`, `InferIsolatedConformances`, `NonisolatedNonsendingByDefault`, modo de lenguaje 6, `nonisolated` explícito en tipos de valor. Es exactamente el modelo que Apple está empujando para apps.
- **Manifiesto de AppFoundation** (`Package.swift:9-25`): la explicación de por qué `-warnings-as-errors` no debe viajar al consumidor (choca con `-suppress-warnings` en Xcode) y el gate por variable de entorno es un ejemplo de madurez que rara vez se ve. CoreNetworking debería adoptar el mismo gate.
- **Mocks fuera del binario**: producto `CoreNetworkingTestSupport` separado; nota del scheme `-Package` en README.
- **Pipeline único** para execute/upload/download con interceptores, retry y mapeo compartidos; `deinit` que invalida la sesión (correcto mientras exista delegate de sesión).
- **Retry**: `maxAttempts` como total, gate de idempotencia por método con opt-in, equal jitter, `Retry-After` (segundos y HTTP-date) por encima del backoff, cancelación durante el backoff mapeada. Tests que cuentan requests reales.
- **Pinning**: decisión pura de 3 estados con autoclosures (testable sin red), SPKI real con cabecera ASN.1 (formato TrustKit), nunca `useCredential` a ciegas, logs sin pins ni claves, fixture de certificado embebido y subclase de `URLProtectionSpace` para probar el delegate.
- **Redacción de headers no configurable**: sobre-redactar es la decisión segura.
- **`Coordinator`**: `@Observable`, una capa modal documentada y testada, bindings vivos, dismissal interactivo que limpia estado, deep links tipados y desacoplados del grafo de rutas.
- **`ScreenPresentationLogic`** extraído para probar la matriz fase/actividad sin snapshots; banners anunciados a VoiceOver; alertas nativas por defecto.
- **`Debouncer` con `Clock` inyectable** y tests sin sleeps (el problema es la elección de actor, no la implementación).
- **i18n**: todos los defaults en EN+ES, `LocalizedStringResource` en la API con la técnica de `@_disfavoredOverload` para que los literales localicen y los `String` de runtime no.
- **Higiene de repo**: `.build`/`xcuserdata`/reportes de mutación ignorados; commits que explican el porqué.

---

## 6. Plan por fases

**Fase 1 — Bloqueantes (antes de que otra app lo consuma)**
1. CN-01 pinning → delegate por tarea + `untrustedServer` + test e2e.
2. AF-01/AF-03 fuga → `performLoad { vm in … }` + variante estructurada + test de fuga en suite.
3. AF-02 fallback de error → mensaje genérico localizado; detalle al logger.

**Fase 2 — Modelo de error (rompe API; hacerlo antes de 1.0 y de una vez)**
4. `APIError` struct + `Code` + `response`/`underlying` + `category` (§4); eliminar `TransportError`, `.unknown`, `Equatable`.
5. `ErrorPresenting` en AppFoundation; `APIError: LocalizedError`.
6. Interceptores: `willSend` que lanza, `didReceive` con request + `HTTPURLResponse`, `RequestRetrier` para refresh de token.

**Fase 3 — Concurrencia y herramientas (la parte "cuándo usar un actor")**
7. `Container` → `@MainActor` (AF-09); eliminar `.scoped` (AF-10).
8. `Debouncer`/`Throttler` → `@MainActor` con `any Clock<Duration>` (AF-19).
9. `Clock` inyectable en retry y banners (CN-11, AF-05); `RetryPolicy` en `Duration`.
10. `HTTPTransport` inyectable; `MockURLProtocol` queda para integración (CN-21).

**Fase 4 — Superficie de API y UI**
11. `associatedtype Body = Never` y `associatedtype Response` en el request; `HTTPMethod.get`; borrar código muerto (CN-15/16/17/18).
12. `download` con delegate/`download(for:)`, 204, `makeEncoder`, `URLSessionConfiguration` (CN-07/08/09/10).
13. Barra nativa por defecto + custom opt-in; a11y; gesto de back (AF-12/13). Style protocols en vez de `AnyView` (AF-15). APIs deprecadas (AF-16).
14. `NSPinnedDomains` documentado como opción por defecto; ≥ 2 pins (CN-19).

**Fase 5 — Proceso**
15. CI (GitHub Actions: `swift test` macOS + `xcodebuild test` iOS Simulator, ambos paquetes), `swift-format` o SwiftLint con reglas acordadas, `LICENSE`, `CHANGELOG`, tags semánticos (hoy solo `0.1.4`), gate `SWIFT_STRICT_WARNINGS` también en CoreNetworking, String Catalogs, corregir docs (AF-07, README de CoreNetworking sobre `Sendable`).

---

## Anexo — Índice de hallazgos

| ID | Sev. | Título | Evidencia |
|----|------|--------|-----------|
| CN-01 | Crítico | Fallo de pinning ≡ `.cancelled` | `SessionDelegates.swift:33-39`, `APIError.swift:85-90` |
| CN-02 | Alto | `APIError` enum cerrado, pierde body/headers/underlying, `Equatable` engañoso | `APIError.swift:33-236` |
| CN-03 | Alto | `TransportError` duplica vocabulario; 401=403; `.connectionInterrupted` mal nombrado | `TransportError.swift` |
| CN-04 | Medio | Typed throws con enum no evolutivo | `APIServiceProtocol.swift:15-49` |
| CN-05 | Alto | Sin `RequestRetrier` / refresh token; `willSend` no puede fallar | `RequestInterceptor.swift:29-50` |
| CN-06 | Medio | `didReceive` sin identidad de request; `didFail(error: Error)` | `RequestInterceptor.swift:41-49` |
| CN-07 | Alto | `download` byte a byte y en memoria | `APIService.swift:107-125` |
| CN-08 | Medio | Sin 204 / body vacío | `APIService.swift:76`, `BaseResponse.swift` |
| CN-09 | Medio | Sin `makeEncoder`; racional `Sendable` incorrecto | `APIService.swift:269`, `NetworkingConfiguration.swift:55-58` |
| CN-10 | Medio | `URLSessionConfiguration` no configurable | `APIService.swift:49-52` |
| CN-11 | Medio | Retry sin `Clock`; tests de tiempo de pared | `APIService.swift:162`, `RetryBehaviorTests.swift:115-134` |
| CN-12 | Bajo | `catch` residual a `.unknown` | `APIService.swift:194, 230, 273` |
| CN-13 | Bajo | `Content-Type` en GET; sin `Accept` | `BaseRequest.swift:138` |
| CN-14 | Bajo | `DateFormatter` por llamada | `APIError.swift:101-105` |
| CN-15 | Medio | `typealias Parameters = EmptyParameters` obligatorio | `BaseRequest.swift:82` |
| CN-16 | Medio | Request sin `associatedtype Response` | `APIServiceProtocol.swift:15` |
| CN-17 | Bajo | Código muerto (`BaseResponse`, `validated()`, `environment`) | `BaseRequest.swift:163-271`, `NetworkingConfiguration.swift:42` |
| CN-18 | Bajo | `HTTPMethod.GET` vs `.get` | `BaseRequest.swift:4-5` |
| CN-19 | Medio | Alternativa `NSPinnedDomains`; 1 pin; flag de cadena; RSA-3072 | `SSLPinningConfiguration.swift:61-66, 142-160` |
| CN-20 | Bajo | Log público con mensaje del servidor; subsystem | `RequestInterceptor.swift:130`, `Logging.swift:6` |
| CN-21 | Medio | `URLProtocol` global para unidad; sin secuencias | `MockURLProtocol.swift:83, 139` |
| CN-22 | Bajo | `MockAPIService.result: Any?` | `MockAPIService.swift:24` |
| AF-01 | Crítico | Fuga en fase `.error` | `BaseViewModel.swift:204-213` |
| AF-02 | Alto | Fallback `localizedDescription` basura | `BaseViewModel.swift:295`, `WrappedError.swift:91` |
| AF-03 | Alto | `deinit` no cancela con uso documentado | `BaseViewModel.swift:60-66, 193` |
| AF-04 | Medio | Cancelación solo por `CancellationError` | `BaseViewModel.swift:200` |
| AF-05 | Bajo | Banner con reloj real | `BaseViewModel.swift:150` |
| AF-06 | Alto | Sin `ErrorPresenting` inyectable | `BaseViewModel.swift:286-296` |
| AF-07 | Bajo | Docs desactualizadas | `AppErrorConvertible.swift:39-52`, `Background.swift:18`, `NavigationBarItem.swift:339` |
| AF-08 | Bajo | `WrappedError`: `#file`, `Date()`, `Equatable` | `WrappedError.swift:78-87, 164-170` |
| AF-09 | Alto | `Container` lock + `@unchecked` en mundo `MainActor` | `Container.swift:31-46, 75, 198-268` |
| AF-10 | Medio | Scopes por string vs child containers | `Container.swift:144-160, 295-340` |
| AF-11 | Medio | `@Inject` service locator; autoclosure; clave por string | `Inject.swift:43`, `Container.swift:104-107` |
| AF-12 | Alto | Barra oculta → swipe-back (verificar en dispositivo) | `CoordinatorView.swift:79-85`, `ScreenContainer.swift:161-163` |
| AF-13 | Alto | Barra custom vs nativa; a11y; Dynamic Type | `CustomNavigationBar.swift:5-19, 115-120, 147-155` |
| AF-14 | Bajo | API `public` solo en DEBUG | `Coordinator.swift:134-138` |
| AF-15 | Medio | `AnyView` como personalización | `ScreenContainer.swift:86-90, 425-454` |
| AF-16 | Medio | APIs deprecadas (`edgesIgnoringSafeArea`, `foregroundColor`, `cornerRadius`, `PreviewProvider`) | varios |
| AF-17 | Bajo | Barra duplicada en árbol | `ScreenContainer.swift:231, 376, 384` |
| AF-18 | Bajo | Nombres (`Background.swift`, `BannerState.Duration`, `.largeText`) | varios |
| AF-19 | Medio | `Debouncer`/`Throttler` como actor | `Debouncer.swift:51, 207` |
| AF-20 | Medio | Heurística de test en producción; cajón de sastre | `AppEnvironment.swift:34-39` |
| AF-21 | Bajo | `.strings` vs String Catalog; `@_disfavoredOverload` | `L10n.swift:6`, `ViewPhase.swift:99` |
