# Changelog

Todos los cambios notables de este repositorio se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el
versionado, [SemVer](https://semver.org/lang/es/). Los dos paquetes viajan en el
mismo repo y comparten tag, así que cada versión lleva una subsección por paquete.
Cada PRD añade sus entradas bajo `[Unreleased]` en la subsección de su paquete;
X-02 cierra la versión.

## [Unreleased]

### AppFoundation

<!-- PRD-AF-02 -->
#### Changed
- **Rotura de API**: `Container` es ahora `@MainActor`. Se elimina el `NSLock` y el
  `@unchecked Sendable`: el compilador garantiza que las fábricas de tipos `@MainActor`
  se ejecutan en el main actor, en lugar de un contrato documentado en un comentario
  (AF-09).
- `register(_:lifecycle:factory:)` recibe ahora el `Container` en la fábrica, que puede
  usarse para resolver las dependencias de esa fábrica desde el mismo contenedor.
- `Lifecycle.scoped(key:)`, `Container.createScope`/`destroyScope` desaparecen: un
  `Container(parent:)` por flujo (checkout, sesión) sustituye al scope con clave de
  cadena (AF-10).
- `@Inject` documentado como último recurso para clases hoja; las vistas usan
  `Environment` (AF-11).

#### Removed
- `ContainerConcurrencyTests.swift`: no hay concurrencia que probar en un contenedor
  `@MainActor`, el compilador la garantiza.

#### Added
- Detección de ciclos de dependencias (A → B → A) en las fábricas: `preconditionFailure`
  con un mensaje que nombra todos los tipos implicados.

PRD: [PRD-AF-02](PRD/PRD-AF-02.md).

<!-- PRD-AF-03 -->
#### Changed

- **Breaking:** `Debouncer` and `Throttler` are now `@MainActor final class` instead
  of `actor`, and no longer generic over `Clock` (`Debouncer<C>` → `Debouncer`). The
  clock is `any Clock<Duration>`. `debounce(_:)` is synchronous and its operation is
  no longer `@Sendable`; `deinit` cancels any in-flight work (AF-19).
- **Breaking:** `AppEnvironment` is now an `enum` namespace instead of a `struct`.
  `physicalMemoryFormatted` uses `.formatted(.byteCount(style: .memory))` instead of
  `String(format:)` (AF-20).
- Default strings moved from `Resources/{en,es}.lproj/Localizable.strings` to a
  single `Resources/Localizable.xcstrings` String Catalog with the same keys and
  values (AF-21).

#### Removed

- **Breaking:** `Debouncer.init(milliseconds:)` — use `.milliseconds(n)` instead.
- **Breaking:** `AppEnvironment.isTestOrPreview` — detecting the test runner or
  Xcode Previews by heuristic in production code is unsupported; inject the
  behaviour you want in tests instead (AF-20).
- **Breaking:** `AppEnvironment.debugInfo` / `AppEnvironment.printDebugInfo()`.

PRD: [PRD-AF-03](PRD/PRD-AF-03.md).

<!-- PRD-AF-04 -->
#### Breaking

- `ScreenContainer` cambia su modelo de personalización de navegación: el parámetro
  `navigation:` desaparece en favor de `chrome: ScreenChrome`, con `.native` como valor por
  defecto (la barra nativa deja de ocultarse en cada ruta) y `.custom(NavigationBarConfiguration, placement:)`
  como opt-in explícito para la barra personalizada (PRD-AF-04, AF-12, AF-13).
- Los modifiers `.loadingView { }`, `.errorView { }`, `.emptyView { }` y `.bannerView { }` de
  `ScreenContainer` se eliminan en favor de los protocolos `LoadingViewStyle`,
  `ErrorViewStyle`, `EmptyViewStyle` y `BannerViewStyle`, propagados por `Environment`
  (`.loadingViewStyle(_:)`, `.errorViewStyle(_:)`, `.emptyViewStyle(_:)`,
  `.bannerViewStyle(_:)`) — sin `AnyView` en el call site (AF-15).
- `.alertView(builder:)` se elimina: las alertas siempre usan la presentación nativa.
- `NavigationBarItemContent.view`, `NavigationBarTitle.custom` y las propiedades
  `accessoryView`/`customContent` de `NavigationBarConfiguration` dejan de exponer
  `AnyView` en su firma pública; usan `ErasedView`, el único punto de type-erasure interno
  del paquete (documentado en `UI/Styles/ErasedView.swift`).
- `NavigationBarTitle.largeText` se elimina (no era una feature implementada).
- `BannerState.duration` cambia de `BannerState.Duration` (enum propio) a `Swift.Duration?`
  (`nil` = indefinido), y ya no sombrea el tipo del sistema.
- `Coordinator.navigationHistory` pasa a `internal` (antes era `public` solo en builds
  `DEBUG`, una API cuya existencia dependía de la configuración de build).

#### Added

- `ScreenChrome`: `.native` (la barra del sistema nunca se oculta; la pantalla la controla
  con `navigationTitle`/`toolbar`/`searchable`) y `.custom(NavigationBarConfiguration, placement:)`.
- `PopGestureEnabler` (`UI/Platform`, solo `iOS`): reinstala el gesto interactivo de
  swipe-back que `UINavigationController` desactiva al ocultar la barra nativa;
  `ScreenContainer` lo instala automáticamente cuando `chrome` es `.custom`.
- `LoadingViewStyle` / `ErrorViewStyle` / `EmptyViewStyle` / `BannerViewStyle` y sus
  implementaciones por defecto (`DefaultLoadingViewStyle`, etc.), con el mismo patrón que
  `ButtonStyle`/`ProgressViewStyle` de SwiftUI.
- `ScreenChromeTests.swift`: cobertura de la lógica pura de qué chrome oculta la barra
  nativa.
- Accesibilidad: los botones atrás/cerrar de `CustomNavigationBar` llevan
  `accessibilityLabel` localizado (`L10n.back`/`L10n.close`) y el trait `.isButton`;
  `NavigationSearchBar` expone `accessibilityLabel` y desactiva
  `textInputAutocapitalization` en iOS.

#### Fixed

- La barra nativa ya no se oculta en todas las rutas (`CoordinatorView`/`ScreenContainer`),
  lo que restaura el gesto de swipe-back para cualquier pantalla en `chrome: .native`
  (AF-12).
- `CustomNavigationBar` ya no se instancia dos veces en el árbol (contenido + overlay de
  estado): el chrome se instala una única vez alrededor de todo el screen (AF-17).
- Altura de `CustomNavigationBar` con `@ScaledMetric` en vez de un valor fijo de 44pt;
  iconos con fuentes semánticas (`.headline`/`.subheadline`) en vez de tamaños fijos
  (Dynamic Type, AF-16).
- APIs deprecadas o de otra época: `.edgesIgnoringSafeArea` → `.ignoresSafeArea(.container, edges:)`,
  `.foregroundColor` → `.foregroundStyle`, `.cornerRadius(_:)` → `.clipShape(.rect(cornerRadius:))`,
  `PreviewProvider` → `#Preview` (AF-16).
- `Background.swift` se renombra a `PhaseView.swift` para que el fichero coincida con el
  tipo que contiene (AF-18).

PRD: [PRD-AF-04](PRD/PRD-AF-04.md).

<!-- PRD-AF-01 -->
#### Added

- `LoadableViewModel`, adopted by `BaseViewModel`: `performLoad`/`performActivity` (and
  the structured `load`/`activity` variants) now hand the view model to `work` as a
  parameter instead of relying on closure capture — the API shape that closes the
  `.error`-phase retention cycle (AF-01) and makes `deinit` actually cancel in-flight
  work (AF-03).
- `ErrorPresenting` / `DefaultErrorPresenter`: a single, app-configurable place to map
  errors to `ScreenError` copy (`BaseViewModel.errorPresenter`, overridable per instance
  via `BaseViewModel(errorPresenter:)`). Foreign errors that aren't `AppErrorConvertible`
  or `LocalizedError` now fall back to a generic, localized message instead of
  `error.localizedDescription` (AF-02).
- `CancellationRecognizing` / `DefaultCancellationRecognizer`: extensible cancellation
  detection beyond typed `CancellationError` (default also recognizes
  `URLError(.cancelled)`), configurable via `BaseViewModel.cancellationRecognizer` (AF-04).
- `L10n.genericErrorMessage` (EN + ES) — the fallback copy `DefaultErrorPresenter` shows
  for errors it can't otherwise present.
- `AppFoundationLogger.errors` — logs the technical detail of unpresentable errors
  (`.private`), never shown on screen.
- `BaseViewModel.clock` (injectable `any Clock<Duration>`, defaults to
  `ContinuousClock()`): the banner auto-dismiss timer no longer sleeps for real in tests.

#### Changed

- **Breaking:** `performLoad`/`performActivity` no longer accept a
  `() async throws -> Void` closure; `work` is now
  `@MainActor (Self) async throws -> Void`, receiving the view model as `vm`. Existing
  call sites must migrate from `performLoad { self.foo() }` to
  `performLoad { vm in vm.foo() }`.
- **Breaking:** `WrappedError.init` gains an injectable `now: () -> Date` parameter and
  uses `#fileID` instead of `#file` for its default `file` argument.
- `WrappedError` now conforms to `CustomDebugStringConvertible` (was a plain
  `debugDescription` property); its `Equatable` conformance is documented as comparing
  `context` + `code` + `underlying.localizedDescription` only, not a structural
  comparison of `underlying`.

#### Fixed

- **Critical:** a `BaseViewModel` in the `.error` phase never deallocated when `work`
  captured `self` (the documented pattern): `phase → ScreenError.retry → work → self`
  formed a permanent reference cycle. Closed by the `LoadableViewModel` API shape.
- `deinit` now actually cancels an in-flight `performLoad`/`performActivity`: since
  `work` no longer captures the view model, dropping the last external reference lets
  the view model deallocate, and its `deinit` cancels the owned `Task`.

PRD: [PRD-AF-01](PRD/PRD-AF-01.md).

### CoreNetworking

<!-- PRD-CN-05 -->

#### Breaking

- `BaseRequest` se rediseña alrededor de `associatedtype Body: Encodable & Sendable = Never`
  y `associatedtype Response: Decodable & Sendable = Empty`: un endpoint es un
  tipo completo, sin `typealias Parameters = EmptyParameters` de relleno en
  cada GET y sin ambigüedad en el call site sobre qué devuelve `execute`.
  `parameters` se renombra a `body`; `timeoutInterval: TimeInterval` pasa a
  `timeout: Duration`; `headers` y `queryItems` dejan de ser opcionales
  (`[:]`/`[]` por defecto).
- `HTTPMethod` cambia sus casos a minúscula (`.get`, `.post`, `.put`, `.patch`,
  `.delete`, `.head`, `.options`) — `HTTPMethod.GET` ya no compila.
- `APIServiceProtocol.execute`: la firma principal pasa de
  `execute<Request, Response: Decodable>(request:) -> Response` (con
  `Response` inferido en el call site) a `execute<R: BaseRequest>(_:) -> R.Response`,
  con el tipo de respuesta fijado por el propio request. Se añade la
  sobrecarga `execute<R, Value: Decodable & Sendable>(_:as:) -> Value` para el
  caso puntual en que hace falta decodificar algo distinto de `R.Response`.
  `upload`/`download` no cambian de firma.
- `NetworkingConfiguration.environment` desaparece (era metadato sin lectores).

#### Fixed

- `execute` ya soporta respuestas vacías: `Response == Empty` decodifica a
  `Empty()` sin mirar el body (204, HEAD, DELETE); un `Response` declarado que
  no sea `Empty` con body vacío (p. ej. 204 inesperado, o 200 sin contenido)
  lanza `.decoding` con `response.body.isEmpty` en vez de que `JSONDecoder`
  falle con un mensaje opaco.
- `Content-Type: application/json` ya solo se envía cuando el request declara
  `body` (antes viajaba también en GET sin cuerpo); `Accept: application/json`
  se envía siempre, sobrescribible por `headers`.
- El body del request se codifica con `NetworkingConfiguration.makeEncoder`
  (nuevo) en vez de un `JSONEncoder()` recién instanciado: con `makeDecoder`
  usando `convertFromSnakeCase` ya se podía configurar el encoder simétrico.
- `buildURLRequest` usa `URL.appending(path:)` en vez de
  `appendingPathComponent`.

#### Added

- `Empty`: el `Decodable` que `BaseRequest.Response` usa por defecto y que
  `execute` produce para 204/205/body vacío.
- `NetworkingConfiguration.makeEncoder: @Sendable () -> JSONEncoder` (misma
  razón de ser que `makeDecoder`: clase mutable, no ausencia de `Sendable`).
- `NetworkingConfiguration.sessionConfiguration: @Sendable () -> URLSessionConfiguration`,
  con `defaultSessionConfiguration()` (`waitsForConnectivity`, cookies
  desactivadas, TLS 1.2 mínimo) como valor por defecto. `APIService.init` la
  usa con el cambio mínimo — CN-03 reubicará esa construcción en
  `URLSessionTransport`.
- `RequestBuildingTests.swift`: cobertura de `Empty`/204, `Accept`/`Content-Type`,
  `makeEncoder` y la fábrica de `sessionConfiguration` llegando a la
  `URLSession` real.

#### Removed

- `BaseResponse.swift` (`BaseResponse`, `EmptyResponse`), `RequestParameters`,
  `EmptyParameters`, `RequestValidationError` y `validated()`/`isValid`/
  `debugValidated()`/`requestDescription` en `BaseRequest`: código sin uso en
  Sources ni Tests.
- README: el racional de `makeDecoder` ya no afirma que `JSONDecoder` no es
  `Sendable` (lo ES en el SDK actual); la fábrica se documenta como
  aislamiento por construcción frente a una instancia mutable compartida.

PRD: [PRD-CN-05](PRD/PRD-CN-05.md).

#### Changed

- **Rompe API pública** — `SSLPinningConfiguration`: `pinnedHosts: Set<String>?`
  se reemplaza por `hosts: Hosts` (`.all` / `.only(Set<String>)`), y
  `validateCertificateChain: Bool` por `chainValidation: ChainValidation`
  (`.system` / `.unsafeSkipForDevelopment`, esta última con efecto solo en
  builds `DEBUG`). El constructor ahora exige, con `precondition`, al menos
  dos pines válidos (RFC 7469 §2.5: pin de respaldo) — con un solo pin, rotar
  la clave del servidor deja la app instalada sin poder conectar. Añadido
  `SSLPinningConfiguration.validatePins(_:)` para validar pines de origen
  remoto sin arriesgarse a un crash.
- Tabla ASN.1 de SPKI: añadido RSA-3072 (antes solo RSA-2048/4096 y EC
  P-256/P-384).
- README: nueva sección «Pinning declarativo (recomendado)» documentando
  `NSPinnedDomains` (`NSPinnedLeafIdentities` / `NSPinnedCAIdentities`,
  `SPKI-SHA256-BASE64`) como opción por defecto desde iOS 14, y cuándo el
  pinning programático de este paquete sigue siendo necesario.

PRD: [PRD-CN-02](PRD/PRD-CN-02.md).

<!-- PRD-CN-01 -->

#### Breaking

- `APIError` pasa de ser un `enum` cerrado a un `struct` extensible con
  `Code` (conjunto abierto), `RequestSummary`, `ResponseSummary` y
  `underlying`. Añadir un `Code` nuevo ya no rompe a los consumidores.
  `TransportError` y `APIMessageError` desaparecen: `APIError.category`
  cubre la clasificación de alto nivel que daba `TransportError`, y
  `decodeBody<T>(_:using:)` permite decodificar cualquier sobre de error del
  servidor con el tipo y el `JSONDecoder` del consumidor.
- `APIError` deja de ser `Equatable` (un `==` que ignorase `underlying`
  mentiría). `CoreNetworkingTestSupport` añade `APIError.stub(code:...)`
  para tests.
- `RetryPolicy.shouldRetry` pasa a `@Sendable (APIError, Int) -> Bool`;
  `RetryPolicy` deja de ser `Equatable` (el predicado es un closure).
- `RequestInterceptor.didFail(_:error:)` tipa `error: APIError` en vez de
  `Error`.

#### Fixed

- Ningún `catch` del pipeline pierde ya el error original: un `NSError`
  arbitrario del transporte llega como `code == .unexpected` con
  `underlying` intacto; un fallo de decodificación conserva el body de la
  respuesta para diagnóstico.
- 401 y 403 ya no colapsan en la misma categoría (`.unauthorized` vs.
  `.forbidden`).
- `isRetryable` ya no reintenta `notConnectedToInternet` (sin red no hay
  nada que reintentar en medio segundo) y sí reintenta `dnsLookupFailed` /
  `cannotFindHost`, que son transitorios.

#### Added

- `APIError.errorDescription` (`LocalizedError`): frase neutra y
  localizable (inglés/español, string catalog del paquete) por `category`,
  nunca un código pelado.

PRD: [PRD-CN-01](PRD/PRD-CN-01.md).

## [0.1.4]

Estado previo a la auditoría técnica de 2026-09-01 (`AUDITORIA-2026-09-01.md`).
Los cambios anteriores a este punto se documentan solo en el historial de git.
