# Cierre 1.0.0 — spm-pro

Verificación cruzada de la auditoría (oleadas 1-3, PRD-X-02), el doble check (oleadas 4-6,
DC-CN-1…8/DC-AF-1…7), el kit de arquitectura (AF-07/AF-08) y el cierre de documentación
(X-03). Un único fichero: es el punto de referencia para decidir si `1.0.0` está lista
para el tag.

## Índice

- [PRD-X-02 — verificación cruzada de la auditoría](#prd-x-02--cierre-10-verificación-cruzada-de-la-auditoría) (43 hallazgos `CN-01`…`AF-21`)
- [Doble check — DC-CN-1…8, DC-AF-1…7](#doble-check--dc-cn-18-dc-af-17)
- [AF-07 / AF-08 — kit de arquitectura y plugins](#af-07--af-08--kit-de-arquitectura-y-plugins)
- [X-03 — documentación dentro de cada SPM y cierre 1.0.0](#x-03--documentación-dentro-de-cada-spm-y-cierre-100)
- [Procedimiento de tag en las ramas `subtree split`](#procedimiento-de-tag-en-las-ramas-subtree-split)
- [Checklist final del propietario](#checklist-final-del-propietario)

---

# PRD-X-02 — Cierre 1.0: verificación cruzada de la auditoría

Verificación ejecutada el 2026-09-02 sobre `main` con las oleadas 1-3 ya mergeadas (commit
base `148a191`), en el worktree de la rama `prd/X-02`.

## Nota sobre el número de IDs

El PRD y el README raíz citan «45 hallazgos». El recuento real del «Anexo — Índice de
hallazgos» de `AUDITORIA-2026-09-01.md` es **43**: `CN-01`…`CN-22` (22 IDs) +
`AF-01`…`AF-21` (21 IDs).

```bash
grep -oE '^\| (CN|AF)-[0-9]+' ../AUDITORIA-2026-09-01.md | sort -u | wc -l
#   43
```

Se verifican los 43 IDs reales; el README raíz se corrige en esta misma rama (ver commit
`docs: corrige a 43 el recuento de hallazgos de la auditoría`).

## Resumen

| Estado | Nº IDs | IDs |
|---|---|---|
| Resuelto | 41 | todos salvo AF-12, AF-13 |
| Verificación manual pendiente (el fix de código está aplicado y verificado por test; falta el paso a mano en simulador/dispositivo) | 2 | AF-12, AF-13 |
| Parcial | 0 | — |
| Desconocido | 0 | — |

No queda ningún ID en estado «desconocido». Ninguno quedó «parcial»: donde la auditoría
proponía una mejora de diseño (p. ej. CN-14, un "nit"), el PRD correspondiente la aplicó
por completo (con `#available` para el camino nuevo y `DateFormatter` solo como *fallback*
documentado por debajo del mínimo de despliegue).

---

## CoreNetworking

| ID | Estado | Evidencia | PRD / commit |
|----|--------|-----------|---------------|
| CN-01 | Resuelto | `grep -n "untrustedServer" CoreNetworking/Sources/CoreNetworking/APIService.swift` → `APIError(code: .untrustedServer, ...)` en las dos rutas de error de pinning (`APIService.swift:194,380`). `TaskDelegate.swift:16` define `PinningFailure`; `URLSessionTransport.swift:115-128` traduce el `URLError(.cancelled)` a `PinningFailure` solo si el propio delegate de tarea marcó `pinningFailed`. `PinningPipelineTests.swift` cubre `execute`/`data(for:)`/`download(to:)` end-to-end (el hueco que señalaba la auditoría). | [PRD-CN-04](PRD-CN-04.md), merge `97561e7` |
| CN-02 | Resuelto | `sed -n '1,70p' CoreNetworking/Sources/CoreNetworking/APIError.swift` → `public struct APIError: Error, Sendable` con `Code` (`Hashable`, conjunto abierto), `request`, `response`, `underlying`. `APIError` ya no es `Equatable` (política de evolución documentada). | [PRD-CN-01](PRD-CN-01.md), merge `60e222e` |
| CN-03 | Resuelto | `grep -rn "TransportError" CoreNetworking AppFoundation README.md` → solo menciones históricas ("`TransportError` no existe", tests que documentan "a diferencia del TransportError borrado"). El tipo no existe en `Sources`. `category` (`APIError.swift:237-251`) sustituye su función, con `.unauthorized`/`.forbidden` ya distintos. | [PRD-CN-01](PRD-CN-01.md), merge `60e222e` |
| CN-04 | Resuelto | `grep -n "throws(APIError)" CoreNetworking/Sources/CoreNetworking/APIServiceProtocol.swift` → typed throws en las 5 firmas públicas (`execute` ×2, `upload`, `data`, `download`), defendible ahora que `APIError` es un struct extensible. | [PRD-CN-01](PRD-CN-01.md), merge `60e222e` |
| CN-05 | Resuelto | `RequestInterceptor.swift`: `willSend(...) async throws(APIError)` puede abortar. `Retry/RequestRetrier.swift`: `protocol RequestRetrier { func retry(_:context:) async -> RetryDecision }`. `Auth/TokenRefresher.swift`: `actor TokenRefresher` deduplica refresh; `TokenRefreshRetrier` reintenta 401 solo en `attempt == 1`. | [PRD-CN-06](PRD-CN-06.md), merge `3dc87ef` |
| CN-06 | Resuelto | `RequestInterceptor.swift:10` — `RequestContext` (`id`, `request`, `attempt`, `startedAt`) fluye por `willSend`→`didReceive`/`didFail`; `didReceive(_ response: HTTPURLResponse, ...)` sin cast; `didFail(_ error: APIError, context:)` ya tipa `APIError`. | [PRD-CN-06](PRD-CN-06.md), merge `3dc87ef` |
| CN-07 | Resuelto | `grep -n "func data(for\|func download\|for try await byte"` → sin bucle byte a byte; `URLSessionTransport.swift:74` implementa `download` a disco vía `session.download(for:)`; `APIService.swift:167` expone `download<Request>(_:to:progress:)`. `TransferTests.swift` prueba 5 MB con límite de tiempo y `download(to:)` contra un servidor loopback real. | [PRD-CN-04](PRD-CN-04.md), merge `97561e7` |
| CN-08 | Resuelto | `BaseRequest.swift:120` — `public struct Empty: Decodable, Sendable`; `APIService.swift:432` decodifica `Response == Empty` sin mirar el body (204/HEAD/DELETE). | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-09 | Resuelto | `NetworkingConfiguration.swift:66` — `public let makeEncoder: @Sendable () -> JSONEncoder`; `APIService.swift:521` lo usa para codificar el body. README corrige el racional de `Sendable` (línea ~100: "no porque `JSONDecoder`/`JSONEncoder` no sean `Sendable` (lo SON...)"). | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-10 | Resuelto | `NetworkingConfiguration.swift:83` — `public let sessionConfiguration: @Sendable () -> URLSessionConfiguration`; `:92` activa `waitsForConnectivity`. | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-11 | Resuelto | `APIService.swift:33,62` — `private let clock: any Clock<Duration>`, `init(clock: any Clock<Duration> = ContinuousClock())`. `ManualClock` (`CoreNetworkingTestSupport`) permite a `RetryBehaviorTests` avanzar el reloj a mano sin `Task.sleep` real. | [PRD-CN-03](PRD-CN-03.md), merge `f4e9c9d` |
| CN-12 | Resuelto | `grep -n "\.unknown" CoreNetworking/Sources/CoreNetworking/APIService.swift` → sin resultados; `Code` ya no tiene `.unknown` (sustituido por `.unexpected`, que siempre lleva `underlying`). | [PRD-CN-01](PRD-CN-01.md), merge `60e222e` |
| CN-13 | Resuelto | `APIService.swift:502-508` — `Accept: application/json` siempre; `Content-Type` solo `if body != nil`. | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-14 | Resuelto | `APIError.swift:293-306` — `parseHTTPDate` usa `Date(_:strategy: .http)` bajo `#available(iOS 26, macOS 26, *)` (documentado: la conformidad a `ParseStrategy` no llegó hasta ese SDK) y cae a `DateFormatter` solo por debajo de ese mínimo — ya no se crea un formatter en cada llamada en el camino moderno. | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-15 | Resuelto | `BaseRequest.swift:67` — `associatedtype Body: Encodable & Sendable = Never`; sin `typealias Parameters`/`EmptyParameters` en el paquete (`grep -rn "EmptyParameters\|typealias Parameters" CoreNetworking` → vacío). | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-16 | Resuelto | `BaseRequest.swift:72` — `associatedtype Response: Decodable & Sendable = Empty`; `APIServiceProtocol.execute<Request: BaseRequest>(_:) -> Request.Response` fija el tipo por el propio request. | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-17 | Resuelto | `grep -rn "BaseResponse\|EmptyResponse\|func validated\|debugValidated\|RequestValidationError\|\.environment\b" CoreNetworking/Sources/CoreNetworking/*.swift` → sin resultados; código muerto eliminado. | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-18 | Resuelto | `BaseRequest.swift:5-13` — `enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", ... }`, todo en minúscula. `HTTPMethod.GET` no compila (verificado: no aparece en Sources/Tests/README). | [PRD-CN-05](PRD-CN-05.md), merge `668a1b3` |
| CN-19 | Resuelto | `SSLPinningConfiguration.swift:73` `enum Hosts` (`.all`/`.only`), `:82` `enum ChainValidation` (`.system`/`.unsafeSkipForDevelopment`, gateado a `DEBUG` en `:190`), `precondition` de ≥2 pines (`:146`), RSA-3072 añadido a la tabla ASN.1 (`:261`). README añade la sección «Pinning declarativo (recomendado): `NSPinnedDomains`» (`CoreNetworking/README.md:397-441`). | [PRD-CN-02](PRD-CN-02.md), merge `cad6d14` |
| CN-20 | Resuelto | `RequestInterceptor.swift:203` — el log de `didFail` solo interpola `code`/`status`/tiempo con `privacy: .public`; el body/mensaje del servidor no aparece en ese log. `Logging.swift:10` — `subsystem` deriva de `Bundle.main.bundleIdentifier` de la app consumidora, con fallback fijo. | [PRD-CN-01](PRD-CN-01.md), merge `60e222e` |
| CN-21 | Resuelto | `Transport/HTTPTransport.swift:11` — `protocol HTTPTransport: Sendable`. `CoreNetworkingTestSupport/InMemoryTransport.swift:36-71` — `Exchange.responses: [Outcome]` (secuencias 500→500→200), sin registro estático global. `MockURLProtocol` se conserva para integración (README «Testing»). | [PRD-CN-03](PRD-CN-03.md), merge `f4e9c9d` |
| CN-22 | Resuelto | `MockAPIService.swift:10` — comentario explícito "This replaces a single untyped `result: Any?`"; `:36,42` — `stub<Request: BaseRequest, Value>(_:returning:)` / `stub<Request>(_:throwing:)`, tipados por request. | [PRD-CN-03](PRD-CN-03.md), merge `f4e9c9d` |

## AppFoundation

| ID | Estado | Evidencia | PRD / commit |
|----|--------|-----------|---------------|
| AF-01 | Resuelto | `LoadableViewModel.swift:28,50` — `protocol LoadableViewModel: BaseViewModel {}`, `performLoad(...)` recibe `work: @MainActor (Self) async throws -> Void`, el VM se pasa como parámetro. `BaseViewModelMemoryTests.swift:16` — `@Test func viewModelInErrorPhaseIsDeallocated()`, verde: el ciclo `self → phase → retry → work → self` ya no existe. | [PRD-AF-01](PRD-AF-01.md), merge `516fd43` |
| AF-02 | Resuelto | `BaseViewModel.swift:86` — `public static var errorPresenter: any ErrorPresenting = DefaultErrorPresenter()`; el fallback genérico usa `L10n.genericErrorMessage`, nunca `error.localizedDescription` de un `Error` ajeno. `ErrorPresentingTests.swift:65-71` — `foreignErrorUsesFallbackTitleAndGenericMessage` afirma explícitamente `!result.message.contains("couldn't be completed")`. | [PRD-AF-01](PRD-AF-01.md), merge `516fd43` |
| AF-03 | Resuelto | `BaseViewModelMemoryTests.swift:38` — `@Test func viewModelWithInFlightLoadIsDeallocatedAndCancelsWork()`, verde: al no capturar `self`, soltar la última referencia externa libera el VM y su `deinit` cancela el `Task` en vuelo. | [PRD-AF-01](PRD-AF-01.md), merge `516fd43` |
| AF-04 | Resuelto | `CancellationRecognizing.swift:12` — `protocol CancellationRecognizing: Sendable`; `BaseViewModel.swift:96` — `public static var cancellationRecognizer: any CancellationRecognizing = DefaultCancellationRecognizer()`, consultado junto a `Task.isCancelled` en los dos `catch` genéricos (`:265,301`). | [PRD-AF-01](PRD-AF-01.md), merge `516fd43` |
| AF-05 | Resuelto | `BaseViewModel.swift:100` — `public static var clock: any Clock<Duration> = ContinuousClock()`; `:203` — `try? await clock.sleep(for: duration)` en el auto-dismiss del banner. | [PRD-AF-01](PRD-AF-01.md), merge `516fd43` |
| AF-06 | Resuelto | `ErrorPresenting.swift` — `public protocol ErrorPresenting: Sendable { func screenError(for:fallbackTitle:retry:) -> ScreenError }`, inyectable en `BaseViewModel` (estático y por instancia, con precedencia instancia > estático > default, cubierta por `ErrorPresenterPrecedenceTests`). | [PRD-AF-01](PRD-AF-01.md), merge `516fd43` |
| AF-07 | Resuelto | `AppErrorConvertible.swift` — el doc-comment usa `performLoad { vm in ... }` (API actual), sin `await` suelto en contexto no-async. `find AppFoundation -iname "Background.swift"` → vacío (renombrado a `PhaseView.swift`, AF-18). `grep -rn "@StateObject" AppFoundation/Sources` → vacío. `grep -rn "NavigationBarStyle" AppFoundation/Sources` → solo el tipo real (`.default`/`.solid`/`.transparent`/`.blur`); no aparece `.dark`. | [PRD-AF-01](PRD-AF-01.md) (doc del propio AppErrorConvertible) + [PRD-AF-04](PRD-AF-04.md) (renombrado de `Background.swift`), merges `516fd43` / `5c1064d` |
| AF-08 | Resuelto | `WrappedError.swift:84,86` — `file: String = #fileID`, `now: () -> Date = Date.init` (inyectable); `:161` `extension WrappedError: Equatable` documentada como aproximación por `context`+`code`+`localizedDescription`; `:171` `extension WrappedError: CustomDebugStringConvertible`. | [PRD-AF-01](PRD-AF-01.md), merge `516fd43` |
| AF-09 | Resuelto | `Container.swift:59-60` — `@MainActor public final class Container`; `grep -n "NSLock\|@unchecked"` sobre el fichero → sin resultados. | [PRD-AF-02](PRD-AF-02.md), merge `92c5175` |
| AF-10 | Resuelto | `grep -rn "\.scoped\|createScope\|destroyScope" AppFoundation/Sources` → sin resultados; `Lifecycle` ya no tiene caso `.scoped` (`Container(parent:)` es el único mecanismo de scope, documentado en README §«One child container per flow»). | [PRD-AF-02](PRD-AF-02.md), merge `92c5175` |
| AF-11 | Resuelto | `Container.swift:79,82` — claves `[ObjectIdentifier: Registration]`/`[ObjectIdentifier: Any]` (ya no `String(reflecting:)` como clave primaria, aunque se conserva para mensajes de ciclo legibles en `:167,243`). `register(_:lifecycle:factory:)` usa un closure explícito, no `@autoclosure` (`Container.swift:118-124`); `register(instance:as:)` (`:127-140`) es la "honest spelling" para una instancia ya construida. README documenta `@Inject` como último recurso para clases hoja, con `Environment` para vistas. | [PRD-AF-02](PRD-AF-02.md), merge `92c5175` |
| AF-12 | **Verificación manual pendiente** (fix de código verificado; falta el paso interactivo) | `ScreenContainer.swift:28-34` — `enum ScreenChrome { case native; case custom(...) }`; `chromeWrappedBody` (`:198-206`) NO oculta la barra nativa para `.native` — `ScreenChromeTests.swift:13` (`nativeChromeNeverHidesTheNavigationBar`) y `:19` (`customChromeAlwaysHidesTheNavigationBar`) verifican la lógica pura. `PopGestureEnabler.swift:20` reinstala el gesto interactivo cuando `chrome` es `.custom` (`ScreenContainer.swift:231`). Lo que NO puede cubrir un test de lógica pura es el gesto físico de swipe-back en UIKit — procedimiento abajo. | [PRD-AF-04](PRD-AF-04.md), merge `5c1064d` |
| AF-13 | **Verificación manual pendiente** (fix de código verificado; falta el paso interactivo) | Barra nativa es el default (`ScreenChrome.native`, arriba). `CustomNavigationBar.swift:53,57` — `@ScaledMetric private var barHeight` (Dynamic Type en vez de 44pt fijo); `:138,282,347,366` — `.accessibilityLabel` en back/close/búsqueda. Lo que NO puede cubrir un test unitario es que VoiceOver lea efectivamente esa etiqueta o que la altura escale visualmente con Dynamic Type XXL — procedimiento abajo. | [PRD-AF-04](PRD-AF-04.md), merge `5c1064d` |
| AF-14 | Resuelto | `Coordinator.swift:132-140` — `navigationHistory` ya no es `public`; es `private(set) var` (sin modificador de acceso = `internal`), con un comentario que cita AF-14 explícitamente, siempre presente (dentro de `#if DEBUG` para su implementación, pero su ausencia de API pública ya no depende de la configuración de build). | [PRD-AF-04](PRD-AF-04.md), merge `5c1064d` |
| AF-15 | Resuelto | `grep -rn "AnyView" AppFoundation/Sources` → solo `UI/Styles/ErasedView.swift` (comentario: "The ONE place in this package where `AnyView` is used"), ningún otro fichero. `LoadingViewStyle`/`ErrorViewStyle`/`EmptyViewStyle`/`BannerViewStyle` en `UI/Styles/`, propagados por `Environment` (`.errorViewStyle(_:)` etc., documentado en README). | [PRD-AF-04](PRD-AF-04.md), merge `5c1064d` |
| AF-16 | Resuelto | `grep -rn "edgesIgnoringSafeArea\|foregroundColor(\|cornerRadius(\|PreviewProvider" AppFoundation/Sources` → sin resultados. | [PRD-AF-04](PRD-AF-04.md), merge `5c1064d` |
| AF-17 | Resuelto | `ScreenContainer.swift:214,223` — las dos apariciones de `CustomNavigationBar(...)` están en ramas mutuamente excluyentes de `switch placement { case .stack: ...; case .overlay: ... }`, no en el árbol dos veces simultáneas (a diferencia del hallazgo original, que las duplicaba en contenido + overlay de estado). | [PRD-AF-04](PRD-AF-04.md), merge `5c1064d` |
| AF-18 | Resuelto | `find AppFoundation/Sources -iname "*Background*"` → vacío (`PhaseView.swift` es el nombre actual). `BannerState.swift:49` — `public let duration: Swift.Duration?` (ya no `BannerState.Duration`). `grep -n "largeText" AppFoundation/Sources/AppFoundation/UI/NavigationBar/NavigationBarItem.swift` → sin resultados. | [PRD-AF-04](PRD-AF-04.md), merge `5c1064d` |
| AF-19 | Resuelto | `Debouncer.swift:101,250` — `public final class Debouncer` / `public final class Throttler` (no `actor`), `:102,261` — `clock: any Clock<Duration>` (no genérico `Debouncer<C: Clock>`). `grep -n "Debouncer<" AppFoundation` → sin resultados. | [PRD-AF-03](PRD-AF-03.md), merge `f7a47bd` |
| AF-20 | Resuelto | `grep -rn "isTestOrPreview\|debugInfo\|printDebugInfo" AppFoundation/Sources AppFoundation/README.md` → sin resultados. `AppEnvironment.swift:174` — `physicalMemory.formatted(.byteCount(style: .memory))` sustituye a `String(format:)`. (`AppEnvironment` es `enum`, ver README «Notes».) | [PRD-AF-03](PRD-AF-03.md), merge `f7a47bd` |
| AF-21 | Resuelto | `find AppFoundation -iname "*.xcstrings" -o -iname "*.lproj"` → solo `Resources/Localizable.xcstrings`, sin `.lproj`. `@_disfavoredOverload`: `ViewPhase.swift:96-99` documenta la técnica una vez (comentario completo, "the same technique SwiftUI's `Text` uses"); `BannerState.swift:71`, `AlertState.swift:89` y `BaseViewModel.swift:149` referencian ese doc con "(see `ScreenError`)"/"Runtime-string variant of..." en vez de repetir la explicación completa. | [PRD-AF-03](PRD-AF-03.md) (String Catalog) + [PRD-AF-01](PRD-AF-01.md)/[PRD-AF-04](PRD-AF-04.md) (unificación de comentario), merges `f7a47bd` / `516fd43` / `5c1064d` |
| PRD-AF-05 *(post-1.0.0, no es uno de los 43 hallazgos — decisión del propietario, 2026-09-02)* | Resuelto | `grep -rn "ScreenContainer(viewModel:" AppFoundation Examples` → vacío. `ScreenContainer.swift` — `public struct ScreenContainer<State: ScreenViewModel, Content: View>`; `Architecture/State/ScreenState.swift` — `protocol ScreenState: AnyObject, Observable { var phase: ViewPhase { get }; var activity: ActivityState { get }; var alert: AlertState? { get set }; var banner: BannerState? { get set } }`, `extension BaseViewModel: ScreenState {}` (sin métodos nuevos obligatorios). `Architecture/Actions/ActionHandling.swift` — `protocol ActionHandling: AnyObject { associatedtype Action: Sendable; func handle(_ action: Action) }`, `ActionSender<Action>` (`sender(.load)`/`.send(.load)`, capturado con `[weak self]` vía `ActionHandling.sender`). `ActionHandlingTests.swift` prueba `ScreenContainer` compilando contra un `@Observable final class` propio que conforma `ScreenViewModel` sin heredar de `BaseViewModel`, y que `ActionSender` no retiene su view model. `Examples/IntegrationExample` migrado (`ProfileViewModel: BaseViewModel, ActionHandling`, `load()` ahora `private`). | [PRD-AF-05](PRD-AF-05.md) |

---

## AF-12 / AF-13 — procedimiento de verificación manual en simulador

El fix de código está aplicado y cubierto por test de lógica pura (`ScreenChromeTests`), pero
dos comportamientos solo se pueden observar con una interacción física en UIKit/VoiceOver —
no hay API pública para "preguntarle" al sistema si el gesto está armado o si VoiceOver
pronunció una cadena concreta. Procedimiento exacto para quien tenga acceso a Xcode/simulador:

### AF-12 — swipe-back con `chrome: .native` y con `.custom`

1. `xcrun simctl list devices available` → elegir un simulador de iOS 17+ arrancado
   (`xcrun simctl boot "<nombre>"` si hace falta).
2. Crear una app SwiftUI mínima que dependa de `AppFoundation` por `path:` (o usar
   `Examples/IntegrationExample` como base) con dos rutas en un `NavigationStack`
   envueltas en `CoordinatorView`.
3. Pantalla A → `ScreenContainer(chrome: .native)` (el default) → pantalla B.
   - Abrir con `xcodebuild build -scheme <esquema> -destination 'platform=iOS
     Simulator,name=<simulador>'` e instalar/lanzar (`xcrun simctl install` +
     `xcrun simctl launch`, o botón Run en Xcode).
   - Navegar A → B. Desde el borde izquierdo de B, deslizar hacia la derecha sin soltar:
     la vista debe seguir el dedo y volver a A si se suelta antes de superado el 50%, o
     completar el pop si se suelta después. Repetir con `.custom(...)`: debe comportarse
     igual gracias a `PopGestureEnabler`.
4. Criterio de aceptación: el gesto responde en ambos casos (`.native` porque nunca oculta
   la barra real; `.custom` porque `PopGestureEnabler` reinstala
   `interactivePopGestureRecognizer.delegate`). Si `.custom` no responde, el simulador no
   sirve de evidencia por software: haría falta inspeccionar
   `UINavigationController.interactivePopGestureRecognizer.isEnabled` con el debugger de
   vistas de Xcode en el momento del gesto.

### AF-13 — VoiceOver en el botón atrás y Dynamic Type XXL en la barra custom

1. En el simulador: *Settings ▸ Accessibility ▸ VoiceOver* → activar (o
   `xcrun simctl spawn <simulador> defaults write com.apple.Accessibility
   VoiceOverTouchEnabledByDefault -bool true` seguido de un reinicio del simulador, según
   versión de Xcode).
2. Navegar a una pantalla con `chrome: .custom(...)`. Con VoiceOver activo, tocar (no pulsar)
   el botón atrás: debe anunciar el texto de `L10n.back` ("Back"/"Atrás" según idioma del
   simulador) y el trait "Button" — nunca "chevron left" ni un nombre de símbolo SF Symbols.
3. Para Dynamic Type: *Settings ▸ Accessibility ▸ Display & Text Size ▸ Larger Text* →
   activar y arrastrar al máximo (AX5/XXL). Volver a la pantalla con `chrome: .custom`: la
   altura de la barra (`@ScaledMetric barHeight`, relativa a `.headline`) debe crecer
   visualmente en vez de recortar el contenido a 44pt fijos.
4. Criterio de aceptación: el anuncio de VoiceOver coincide con `L10n.back`/`L10n.close`
   (ver `CustomNavigationBar.swift:138,282`) y la barra crece con el tamaño de texto sin
   solapar el contenido.

---

## Ejemplo de integración

`Examples/IntegrationExample/` (paquete SwiftPM independiente, `.package(path: "../../AppFoundation")` +
`.package(path: "../../CoreNetworking")`) demuestra que ambos paquetes se adoptan juntos sin fricción:
`AppErrorPresenter: ErrorPresenting` mapea `APIError.category` a `ScreenError` y decodifica un sobre de
error propio con `decodeBody`; `ProfileViewModel: BaseViewModel` usa `performLoad { vm in ... }` sobre
`MockAPIService`/`InMemoryTransport`; `APIService` se configura con `BearerTokenInterceptor` +
`TokenRefreshRetrier`. Ver `Examples/IntegrationExample/README.md` (si existe) o el propio
`Package.swift`/`Tests` para el detalle. Compila y pasa con `swift test` desde ese directorio, y corre
como job independiente en `.github/workflows/ci.yml`.

---

## Release 1.0.0 — checklist para el propietario (histórico, PRD-X-02)

> Este procedimiento etiquetaba `main` directamente. Ya no es el correcto: cada paquete se
> publica por `git subtree split`, y SwiftPM exige `Package.swift` en la raíz del repo
> consumido — el tag va en la rama split (`cn-only`/`af-only`), nunca en `main`. Ver
> [Procedimiento de tag en las ramas `subtree split`](#procedimiento-de-tag-en-las-ramas-subtree-split)
> y el [Checklist final del propietario](#checklist-final-del-propietario) al final de este
> fichero para el procedimiento vigente. Se conserva esta sección tal cual la dejó X-02, sin
> reescribirla, porque documenta el estado de esa rama en su momento.

`CHANGELOG.md` ya cierra `## [1.0.0] - 2026-09-02` en esta rama (con la sección «Roturas de
API» agregada por paquete) y deja un `## [Unreleased]` vacío arriba. **No se ha creado el
tag** — queda a criterio del propietario tras revisar el PR de `prd/X-02`. Pasos, en orden,
una vez el PR esté mergeado a `main`:

```bash
git checkout main
git pull
git tag -a 1.0.0 -m "1.0.0 — primera versión estable: modelo de error unificado y
extensible, BaseViewModel sin fugas, DI @MainActor, chrome de navegación nativo por
defecto, SSL pinning con backup pin obligatorio, CI y formato en modo estricto."
git push origin 1.0.0
git describe   # debe imprimir "1.0.0"
```

Checklist antes de empujar el tag:

- [ ] El PR de `prd/X-02` está mergeado a `main` (no se etiqueta una rama de trabajo).
- [ ] `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` (0 warnings) y `swift test --parallel`
      verdes en ambos paquetes, ejecutados sobre `main` ya mergeado (no solo en el worktree).
- [ ] `xcodebuild build -destination 'generic/platform=iOS Simulator'` verde para los schemes
      `AppFoundation` y `CoreNetworking-Package`.
- [ ] La verificación manual de AF-12/AF-13 (arriba) se ha hecho al menos una vez en
      simulador/dispositivo real, o se documenta explícitamente por qué no fue posible.
- [ ] Un consumidor de prueba resuelve `AppFoundation`, `CoreNetworking` y
      `CoreNetworkingTestSupport` apuntando al repo por URL + `from: "1.0.0"` (no solo por
      `path:` local) — el tag tiene que existir y estar empujado antes de poder probar esto,
      así que es el único paso que va DESPUÉS de `git push origin 1.0.0`.
- [ ] Ninguna rama `prd/*` sin mergear queda huérfana (`git branch --no-merged main`).

---

## Verificación final ejecutada en esta rama (2026-09-02)

Entorno: Xcode 26.6, `xcrun simctl` con `iPhone 17` (iOS 26.5), simulador con idioma
`AppleLanguages = (es-ES, en-MX)`.

| Comprobación | AppFoundation | CoreNetworking |
|---|---|---|
| `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` | 0 warnings | 0 warnings |
| `swift test --parallel` × 3 | verde, 207 tests las 3 veces | verde, 131 tests las 3 veces |
| `xcodebuild build -destination 'generic/platform=iOS Simulator'` | `BUILD SUCCEEDED` (scheme `AppFoundation`) | `BUILD SUCCEEDED` (scheme `CoreNetworking-Package`) |
| `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17'` | `TEST SUCCEEDED`, 207 tests (requerido por PRD-X-02) | `TEST SUCCEEDED`, 130 tests (verificación extra, no exigida por el PRD para este paquete) |
| `swift format lint --strict --recursive` (Sources+Tests de ambos + `Examples`) | 0 avisos | 0 avisos |

### Hallazgos nuevos, descubiertos por esta verificación (no estaban en los 43 de la auditoría)

**1. `APIErrorTests.localizedDescriptionEnglish()` fallaba bajo `xcodebuild test` con el
simulador en español — corregido en esta rama.** `errorDescription(locale:)` pasa un
`Locale` explícito a `String(localized:bundle:locale:)`, pero ese override no es fiable
frente a un `.lproj` compilado por Xcode cuando el idioma del simulador ya coincide con
otra localización del catálogo: pedir `"en"` en un simulador `es-ES` devolvía la frase en
español. Es un comportamiento de Foundation/String Catalogs (ya documentado indirectamente
por `AppFoundation/Tests/AppFoundationTests/LocalizationTests.swift`, que evita la misma
trampa cargando el `.lproj` por *path* en vez de confiar en `locale:`), no un bug de
`APIError`: la propiedad pública `errorDescription` siempre usa `.current`, así que en
producción nunca pide una localización distinta de la del dispositivo. Corregido con el
mismo mecanismo que ya usa AppFoundation (commit `55a3254`).

**2. `RetrierTests.concurrentRequestsDedupRefresh()` era intermitente bajo `xcodebuild
test` — CORREGIDO en el doble check posterior a X-02.** Causa: el test forzaba el solape de
los diez `401` con un `Task.sleep(20 ms)` dentro del refresh; bajo carga, alguna request
recibía su `401` después de que el refresh terminara y disparaba (correctamente) un segundo
refresh. Ahora `TokenRefresher` expone `joinedInFlightCount` y los dos tests de
deduplicación (`RetrierTests`, `TokenRefresherTests`) esperan a que las otras nueve
llamadas se hayan enganchado al refresh en vuelo antes de dejarlo terminar: el solape es
un hecho observado, no una carrera contra el scheduler. Sin `sleep`; 8/8 corridas
consecutivas verdes en ~4 ms.

---

# Doble check — DC-CN-1…8, DC-AF-1…7

Verificado sobre `main` en la rama `prd/X-03`, con PRD-CN-07 y PRD-AF-06 ya mergeados.

## CoreNetworking

| ID | Estado | Evidencia |
|----|--------|-----------|
| DC-CN-1 | Resuelto | `grep -n "func upload" CoreNetworking/Sources/CoreNetworking/APIServiceProtocol.swift` → `upload<Request: BaseRequest>(_:data:progress:) -> Request.Response` y la sobrecarga `upload(_:data:as:progress:) -> Value`, misma forma que `execute`. `upload(request:data:progress:) -> Response` no existe. |
| DC-CN-2 | Resuelto | `grep -n "func download" CoreNetworking/Sources/CoreNetworking/APIService.swift` → `download<Request: BaseRequest>(_:to:progress:)` pasa por `performWithRetry`; cada intento reescribe `destination` atómicamente. |
| DC-CN-3 | Resuelto | `APIError.swift` — `Category` incluye `.unreachable` (`networkConnectionLost`/`cannotConnectToHost`/`dnsLookupFailed`/`cannotFindHost`), distinto de `.offline`. |
| DC-CN-4 | Resuelto | `MockAPIService.swift` — un request sin stub lanza `APIError(code: .unstubbed, underlying: UnstubbedRequest(...))`, no `.invalidResponse`. `APIError.Code.unstubbed` vive en `CoreNetworkingTestSupport`. |
| DC-CN-5 | Resuelto | `grep -rn "CN-0[0-9]\|PRD-CN" CoreNetworking/Sources/CoreNetworking/*.swift` → vacío. Los comentarios que citaban PRDs como futuro están reescritos en presente. |
| DC-CN-6 | Resuelto | `NetworkingConfiguration.swift:47` — `protocolClasses` con `@available(*, deprecated, message: "Configura protocolClasses en sessionConfiguration")`; el almacenamiento real (`legacyProtocolClasses`) sigue funcionando para compatibilidad. |
| DC-CN-7 | Resuelto | `BaseRequest.swift:120` — `public struct Empty: Decodable, Sendable, Equatable`. `RequestSummary.init(URLRequest)` documenta el fallback a `.get` para un método fuera del `HTTPMethod` cerrado. |
| DC-CN-8 | Resuelto | `grep -c "antes de CN\|antes de PRD\|CN-0[0-9]" CoreNetworking/README.md` → `0`. El README se reescribió por completo en X-03: corto, sin historia, con enlace a `Documentation.docc/` para la referencia completa. |

## AppFoundation

| ID | Estado | Evidencia |
|----|--------|-----------|
| DC-AF-1 | Resuelto (ya en `main` antes de esta rama) | `LoadableViewModel.swift:116,129` — `setLoading(style)`/`startActivity(style)` se llaman ANTES de ejecutar `work`, en las variantes estructuradas `load`/`activity`. |
| DC-AF-2 | Resuelto | `BaseViewModel.swift:79,83` — `inFlightLoad`/`inFlightActivity: Task<Void, Never>?` (`public private(set)`, `@ObservationIgnored`). `Examples/*/Tests` y `AppFoundation/Tests` usan `await viewModel.inFlightLoad?.value` en vez de sondear `phase` en un bucle. |
| DC-AF-3 | Resuelto | `BaseViewModel.swift:100,103` — `instanceCancellationRecognizer`/`instanceClock` (`@ObservationIgnored private let`), inyectados por `init`, con precedencia sobre `Self.cancellationRecognizer`/`Self.clock` (`:406,412`). Los tests del paquete solo mutan el estático en un único test `.serialized` que prueba explícitamente el valor por defecto. |
| DC-AF-4 | Resuelto | `ScreenContainer.swift:432-447` — el comentario «Why this observes correctly without `@Observable` doing any work (DC-AF-4)» documenta por qué `BindingBackedState`/`ObservingScreenState` observan bien sin que `@Observable` instrumente nada (ninguna propiedad es almacenada). |
| DC-AF-5 | Resuelto (documentado, sin cambio de API) | `grep -rn "ErasedView(" AppFoundation/Sources/AppFoundation` → 7 apariciones, todas dentro de `NavigationBarItem.swift`/`*ViewStyle.swift`, piezas opt-in de la barra `.custom` — con `.native` por defecto (el caso común) no entran en juego. |
| DC-AF-6 | Resuelto | `AppFoundation/Examples/LoginApp/Sources/LoginApp/Features/Login/LoginView.swift` — la vista SwiftUI que integra `ScreenContainer` con `LoginViewModel`, con preview sobre `MockAPIService`; reemplaza al `Examples/IntegrationExample` original (sin vista) señalado por el hallazgo. |
| DC-AF-7 | Resuelto | `wc -l AppFoundation/README.md` → `93` (antes, 996). Guía de integración lineal y referencia por pieza con ejemplo completo movidas a `Sources/AppFoundation/Documentation.docc/` (X-03); el README queda corto, sin racional de auditoría ni notas de diseño. |

---

# AF-07 / AF-08 — kit de arquitectura y plugins

| ID | Estado | Evidencia |
|----|--------|-----------|
| AF-07 | Resuelto | `Logic` (`Architecture/Logic/Logic.swift`), `LogicViewModel<L>` (`Architecture/ViewModels/LogicViewModel.swift`), `DomainError` (`Architecture/AppError/DomainError.swift`), producto `AppFoundationTestSupport` (`InMemoryStore`/`ManualClock`/`SpyRecorder`), `EndpointService` en CoreNetworking. Cuatro ejemplos en `AppFoundation/Examples/` (`CounterApp`, `NotesApp`, `LoginApp`, `CatalogApp`), uno por variante, cada uno con tests por capa (VM/Logic/Service o Store) y mocks/spies. `AGENTS.md` en ambos paquetes. |
| AF-08 | Resuelto | `Sources/archlint` (analizador léxico, reglas R1-R11, `Tests/ArchLintTests` con fixtures `Good`/`Bad` por regla); plugins `ArchitectureLint` (build-tool), `ArchLintCommand`/`GenerateFeature`/`ArchInit` (command) en `AppFoundation/Package.swift`; plantillas en `AppFoundation/Templates/*.txt`; `Scripts/verify-generator.sh` (verificación de integración real en un paquete temporal, usado por el job `generator` de CI). |


---

# X-03 — documentación dentro de cada SPM y cierre 1.0.0

Ejecutado en la rama `prd/X-03`, sobre `main` con AF-07 y AF-08 ya mergeados.

## Entregables

| Entregable | Estado | Evidencia |
|---|---|---|
| `Documentation.docc` en cada target principal | Resuelto | `AppFoundation/Sources/AppFoundation/Documentation.docc/` (landing + 13 artículos: `GettingStarted`, `ScreenStateAndViewModels`, `ErrorHandling`, `Navigation`, `DependencyInjection`, `UserInterface`, `Utilities`, `Architecture`, `Recipes`, `Testing`, `Generator`, `Lint`, `FAQ`). `CoreNetworking/Sources/CoreNetworking/Documentation.docc/` (landing + 12 artículos: `GettingStarted`, `Requests`, `ErrorHandling`, `Retry`, `Pinning`, `Interceptors`, `Authentication`, `Transport`, `Architecture`, `Recipes`, `Testing`, `FAQ`). |
| `xcodebuild docbuild` sin warnings de enlaces rotos | Resuelto | `xcodebuild docbuild -scheme AppFoundation -destination 'generic/platform=iOS Simulator'` → `BUILD DOCUMENTATION SUCCEEDED`; diagnóstico del compilador (`AppFoundation-diagnostics.json`): 4 warnings, los 4 preexistentes ("Parameter missing documentation" en `WrappedError.swift`), ninguno de enlace roto ni de topic de DocC. `xcodebuild docbuild -scheme CoreNetworking-Package -destination 'generic/platform=iOS Simulator'` → `BUILD DOCUMENTATION SUCCEEDED`; `CoreNetworking-diagnostics.json`: 6 warnings, los 6 preexistentes ("Parameter missing documentation" en `HTTPTransport.swift`/`APIService.swift`), cero relacionados con `Documentation.docc` o `@Snippet`. |
| `Snippets/` compilados por SwiftPM | Resuelto | `AppFoundation/Snippets/` (14 ficheros), `CoreNetworking/Snippets/` (10 ficheros). `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` en ambos paquetes compila todos los snippets junto con Sources/Tests — 0 warnings (`swift build --build-tests` incluye los productos ejecutables de `Snippets/` automáticamente; no hace falta un paso separado). |
| README corto sin historia | Resuelto | `wc -l AppFoundation/README.md CoreNetworking/README.md` → 93 y ~90 líneas (antes 996 y 774). `grep -rn "CN-0\|AF-0\|X-0\|auditor\|antes de\|ya no\|existía" AppFoundation/README.md CoreNetworking/README.md AppFoundation/Sources/AppFoundation/Documentation.docc CoreNetworking/Sources/CoreNetworking/Documentation.docc` → vacío. |
| `CHANGELOG.md` por paquete | Resuelto | `AppFoundation/CHANGELOG.md`, `CoreNetworking/CHANGELOG.md`, ambos con `## [1.0.0] - 2026-09-02` (Roturas de API agregada) y `## [Unreleased]` vacío. `CHANGELOG.md` de la raíz es un índice de dos líneas que enlaza a ambos. |
| `Examples/` por paquete | Resuelto | `AppFoundation/Examples/{CounterApp,NotesApp,LoginApp,CatalogApp}` (AF-07). `CoreNetworking/Examples/APIClientApp` — consumidor mínimo sin AppFoundation, `swift test` 4/4 en verde. |
| `AGENTS.md` revisado | Resuelto | Ambos enlazan a `Documentation.docc/` y (CoreNetworking) a `Examples/APIClientApp`; contenido ya coherente con el generador/linter desde AF-08, sin cambios de fondo necesarios. |

## Cobertura de API pública

Inventario de tipos públicos de nivel superior (`struct`/`class`/`enum`/`protocol`/`actor`/
`typealias`), sin contar miembros anidados: AppFoundation 57 (producto `AppFoundation`) + 4
(`AppFoundationTestSupport`); CoreNetworking 39 (producto `CoreNetworking`) + 12
(`CoreNetworkingTestSupport`). Enlaces de símbolo curados en las secciones «Topics» de
`Documentation.docc`: 48 en AppFoundation, 33 en CoreNetworking — cubren todos los tipos
principales (view models, contrato pantalla↔cáscara, errores, navegación, DI, UI,
utilidades, requests, errores de red, retry, pinning, interceptores, autenticación,
transporte), cada uno con al menos un ejemplo de código que compila (`@Snippet` o bloque
probado en `Examples/`/`READMEExamplesTests`). Los tipos no curados explícitamente en
`Topics` — variantes anidadas de `NavigationBarItem`/`AlertState`/`BannerState`, los pares
`*Configuration`/`*ViewStyle`, cada `Category`/`Code` de `APIError`, los productos de
`TestSupport` (documentados por nombre en <doc:Testing> de cada paquete, sin artículo
DocC propio porque viven en un módulo distinto del que documenta el catálogo) — siguen
apareciendo en el artículo que cubre su pieza y en la página de referencia que DocC genera
de su propio doc-comment (varios de esos doc-comments ya traían su propio bloque
`## Example`, verificado en la lectura previa del código fuente).

## Guía «20 minutos» reproducida fuera del repo

Reproducida en un paquete SwiftPM nuevo por `mktemp -d`, copiando los bloques de
`GettingStarted.md` tal cual, paso a paso, para cada paquete; borrado al terminar.

- **AppFoundation**: tres fallos reales, corregidos en la guía — (1) el `Package.swift`
  del paso 1 no traía `defaultIsolation(MainActor.self)` ni los `upcoming features` que
  usa el propio paquete, así que un test normal no podía llamar a un tipo
  MainActor-isolated (`BaseViewModel`/`Container`) sin `@MainActor` explícito; (2) los
  pasos 2, 4 y 5 mezclaban declaraciones con la demostración de uso (una llamada/`await`
  suelto), que no compila fuera del único fichero "main" de un target de biblioteca —
  aclarado qué línea va en qué fichero y que la demostración de uso va al paso de test.
  Tras el arreglo: `swift build` compila, `swift test` corre 2 tests en verde.
- **CoreNetworking**: mismo problema de declaración-vs-uso en los pasos 2/4/5, corregido
  igual; y un fallo de compilación real en el paso 6:
  `mock.stub(GetGames.self, returning: .init(games: ["chess"]))` no compila —
  `stub<Request: BaseRequest, Value>(_:returning:)` no liga `Value` a `Request.Response`,
  así que `.init(...)` no puede inferir el tipo por contexto. Corregido a
  `GetGames.Response(games: ["chess"])`, también en `CoreNetworking/README.md`. Tras el
  arreglo: `swift build` compila, `swift test` corre 1 test en verde.

## `git subtree split` — comprobación de publicación

```
$ git subtree split --prefix=AppFoundation -b tmp-af-split
$ git subtree split --prefix=CoreNetworking -b tmp-cn-split
$ git ls-tree -r --name-only tmp-af-split | grep -E "README|CHANGELOG|AGENTS|docc|Snippets|Examples" | head
$ git ls-tree -r --name-only tmp-cn-split | grep -E "README|CHANGELOG|AGENTS|docc|Snippets|Examples" | head
$ git branch -D tmp-af-split tmp-cn-split
```

Ejecutado en la rama `prd/X-03` (commit `cac98dd` para `tmp-af-split`, `8424645` para
`tmp-cn-split`, ambos borrados tras la comprobación). Raíz de `tmp-af-split`: `AGENTS.md`,
`CHANGELOG.md`, `Examples/`, `Package.swift`, `Plugins/`, `README.md`, `Snippets/`,
`Sources/`, `Templates/`, `Tests/` — sin ningún resto de `PRD/`, `AUDITORIA-*`,
`ARQUITECTURA-KIT-*` ni ficheros de la raíz del monorepo. Raíz de `tmp-cn-split`:
`AGENTS.md`, `CHANGELOG.md`, `Examples/`, `Package.swift`, `README.md`, `Snippets/`,
`Sources/`, `Tests/` (más `.gitignore`/`.swiftpm`/`.swift-mutation-testing.yml`, ficheros
de configuración propios del paquete). El grep confirma en ambos: `Documentation.docc/`
completo (todos los artículos), `Snippets/` completo, `Examples/` completo con sus
`README.md`/`Package.swift`/`Sources`/`Tests`, y `AGENTS.md`/`CHANGELOG.md`/`README.md` en
la raíz — el árbol que SwiftPM resolvería al consumir cada paquete por URL trae todo lo
necesario.

---

# Procedimiento de tag en las ramas `subtree split`

SwiftPM resuelve un paquete remoto por URL exigiendo `Package.swift` en la **raíz** del
repositorio consumido — spm-pro tiene dos paquetes en subdirectorios, así que ninguno de
los dos se puede etiquetar ni consumir directamente desde `main`. Cada paquete se publica
por [`git subtree split`](https://git-scm.com/docs/git-subtree): un split reescribe el
historial de un subdirectorio como si siempre hubiera sido la raíz de su propio repo, sin
tocar `main`.

```bash
# CoreNetworking
git subtree split --prefix=CoreNetworking -b cn-only
git push <remoto-corenetworking> cn-only:main
git tag -a 1.0.0 cn-only -m "CoreNetworking 1.0.0"
git push <remoto-corenetworking> 1.0.0

# AppFoundation
git subtree split --prefix=AppFoundation -b af-only
git push <remoto-appfoundation> af-only:main
git tag -a 1.0.0 af-only -m "AppFoundation 1.0.0"
git push <remoto-appfoundation> 1.0.0
```

Notas:

- El split se repite en cada release: no se reutiliza la rama `cn-only`/`af-only` local
  entre versiones, se recalcula desde `main` (`git branch -D cn-only` antes de rehacer el
  split, o `-f` en `subtree split`).
- El tag se crea sobre el commit que el split produjo para esa versión — nunca sobre
  `main`, donde `Package.swift` no está en la raíz.
- `git subtree split` puede tardar varios minutos en un historial grande: recorre cada
  commit que tocó el prefijo.
- Verificación de que el árbol publicado trae todo lo necesario (README, CHANGELOG,
  AGENTS.md, `Documentation.docc`, `Snippets`, `Examples`) antes de empujar:
  ```bash
  git ls-tree -r --name-only cn-only | grep -E "README|CHANGELOG|AGENTS|docc|Snippets|Examples"
  ```
- Doble check §4 (comandos exactos, ya verificados en esta rama): el único tag existente
  del monorepo (`0.1.4`) vive en `cn-only`; `af-only` es el split de AppFoundation. Con las
  roturas de API acumuladas desde entonces, la versión que corresponde a ambos paquetes es
  **1.0.0**.

---

# Checklist final del propietario

- [ ] El PR de `prd/X-03` (y de cualquier PRD pendiente por delante en la tabla de oleadas)
      está mergeado a `main`.
- [ ] `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` (0 warnings) y `swift test
      --parallel` × 3 verdes en ambos paquetes, ejecutados sobre `main` ya mergeado.
- [ ] Los cinco ejemplos (`AppFoundation/Examples/{CounterApp,NotesApp,LoginApp,CatalogApp}`,
      `CoreNetworking/Examples/APIClientApp`) compilan y pasan `swift test`.
- [ ] `swift format lint --strict --recursive` en 0 sobre ambos paquetes (`Sources`,
      `Tests`, `Examples`, `Plugins`).
- [ ] `xcodebuild build -destination 'generic/platform=iOS Simulator'` verde para los
      schemes `AppFoundation` y `CoreNetworking-Package`.
- [ ] `xcodebuild docbuild` verde para ambos schemes, sin warnings de enlaces rotos.
- [ ] La verificación manual de AF-12/AF-13 (swipe-back con `chrome: .native`/`.custom`,
      VoiceOver en el botón atrás, Dynamic Type XXL en la barra `.custom` — procedimiento
      arriba) se ha hecho al menos una vez en simulador/dispositivo real desde que se tocó
      por última vez `ScreenContainer`/`CustomNavigationBar`.
- [ ] `git subtree split --prefix=CoreNetworking -b cn-only` y
      `--prefix=AppFoundation -b af-only`; `git ls-tree -r --name-only` sobre cada rama
      confirma README/CHANGELOG/AGENTS.md/`Documentation.docc`/`Snippets`/`Examples`
      presentes.
- [ ] Tag `1.0.0` creado y empujado en **cada** rama split (`cn-only`, `af-only`) — nunca
      en `main` — siguiendo el procedimiento de arriba.
- [ ] Último tag de AppFoundation confirmado en su remoto (el remoto de AppFoundation no
      está configurado en este entorno de desarrollo; confirmarlo antes de asumir que
      `0.1.4`/versiones previas quedaron publicadas).
- [ ] Un consumidor de prueba resuelve `AppFoundation`, `CoreNetworking` y
      `CoreNetworkingTestSupport` apuntando a sus repos por URL + `from: "1.0.0"` (no solo
      por `path:` local) — paso posterior a empujar ambos tags.
- [ ] `swift package archinit` ejecutado sobre la primera app real que adopte el kit de
      arquitectura, para confirmar que `.archlint.yml`/`Features/`/`AGENTS.md`/
      `.claude/skills/feature.md` se generan correctamente fuera de este monorepo.
- [ ] Ninguna rama `prd/*` sin mergear queda huérfana (`git branch --no-merged main`).

## Doble check final (2026-09-02, tras X-04)

Informe completo y puntuación: `docs/AUDITORIA-2026-09-02-final.md`. Estado de `main` (`b7e4e21`): AppFoundation 261 tests, CoreNetworking 138, ejemplos 50, lint estricto 0, iOS OK, `docbuild` limpio en DerivedData nueva (iOS y macOS), 29 bloques de DocC sincronizados con `Snippets/`, ninguna rama `prd/*` sin mergear. Correcciones aplicadas en este doble check: generador en paquete recién creado (`f13faee`), instalación por repo de cada paquete y `LICENSE` dentro del SPM (`b89ffa5`), código generado sin referencias al monorepo (`7ab883d`), parámetros documentados y lint residual (`7fb7c5a`), X-04. Puntuación final: CoreNetworking 10/10; AppFoundation 10/10 condicionado a la verificación manual AF-12/AF-13; kit + plugins 9/10.
