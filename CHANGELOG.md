# Changelog

Todos los cambios notables de este repositorio se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el
versionado, [SemVer](https://semver.org/lang/es/). Los dos paquetes viajan en el
mismo repo y comparten tag, así que cada versión lleva una subsección por paquete.
Cada PRD añade sus entradas bajo `[Unreleased]` en la subsección de su paquete;
X-02 cierra la versión.

## [Unreleased]

### AppFoundation

<!-- PRD-AF-05 -->
#### Breaking

- `ScreenContainer.init(viewModel: BaseViewModel, ...)` se elimina. `ScreenContainer` pasa a
  `ScreenContainer<State: ScreenViewModel, Content: View>` (`ScreenViewModel` =
  `ScreenState & ActionHandling`, ambos protocolos nuevos): ya no depende de la clase
  concreta `BaseViewModel`, solo del contrato mínimo. El nuevo init designado es
  `ScreenContainer(_ state:chrome:backgroundColor:content:)`, con `content` recibiendo un
  `ActionSender<State.Action>` en vez de nada — la vista ya no puede llamar métodos del view
  model directamente, solo `send(.load)`. Los init de conveniencia (`title:`, `onBack:`,
  `searchText:`) migran del mismo modo (`viewModel:` → `_ state:`, `content` recibe el
  sender). Migrar `ScreenContainer(viewModel: vm) { ... }` a
  `ScreenContainer(vm) { send in ... }`, y hacer que `vm` conforme `ActionHandling` (un
  `enum Action`, `func handle(_ action: Action)`) para poder pasarlo (decisión del
  propietario, 2026-09-02).

#### Added

- `ScreenState` (`Architecture/State/ScreenState.swift`): el contrato mínimo que
  `ScreenContainer` observa (`phase`/`activity` de solo lectura, `alert`/`banner`
  `{ get set }`). `BaseViewModel` conforma (`extension BaseViewModel: ScreenState {}`) sin
  ganar ningún método nuevo — la obligación de `handle(_:)` la impone `ScreenContainer`, no
  `BaseViewModel`.
- `ActionHandling` (`Architecture/Actions/ActionHandling.swift`): protocolo con
  `associatedtype Action: Sendable` y `func handle(_ action: Action)` — el único punto de
  entrada de las acciones de usuario de una pantalla, testeable con `vm.handle(.load)` sin
  exponer métodos `private`.
- `ActionSender<Action>`: lo único que el closure de contenido de `ScreenContainer` recibe
  para actuar sobre la pantalla (`send(.load)`/`sender(.load)`); se construye vía
  `ActionHandling.sender`, capturando el view model **débilmente** (`[weak self]`) — un
  `ActionSender` retenido no mantiene vivo al view model.
- `ScreenViewModel` — `typealias ScreenViewModel = ScreenState & ActionHandling`.
- `ScreenContainer(observing:chrome:backgroundColor:content:)`: init para pantallas de solo
  lectura (`ScreenState` sin `ActionHandling`) — sin `ActionSender` en `content`.
- `.screen(_:chrome:)`: modifier equivalente a `ScreenContainer(observing:)` para envolver
  una vista existente con la cáscara de una pantalla de solo lectura.
- `PhaseView.init(observing:backgroundColor:content:)`: variante de `PhaseView` que observa
  un `some ScreenState` directamente, sin `Binding<ViewPhase>`.

PRD: [PRD-AF-05](PRD/PRD-AF-05.md).

<!-- PRD-AF-07 -->
#### Added

- `Logic` (`Architecture/Logic/Logic.swift`): `public protocol Logic: AnyObject {}`, el
  marcador que toda `XxxLogicProtocol` de una feature conforma — sin requisitos propios;
  documenta la arquitectura View → ViewModel → Logic → Services/Stores
  (`ARQUITECTURA-KIT-2026-09-02.md` §1-2) en el propio tipo.
- `LogicViewModel<L>` (`Architecture/ViewModels/LogicViewModel.swift`): `open class
  LogicViewModel<L>: BaseViewModel` con `public let logic: L` e `init(logic:errorPresenter:
  cancellationRecognizer:clock:)`. Hereda `phase`/`activity`/`performLoad`/`performActivity`
  de `BaseViewModel`; no conforma `ActionHandling` (cada subclase declara su propio
  `enum Action`).
- Nuevo producto **`AppFoundationTestSupport`** (target separado; nunca en el binario de
  producción, nunca dependencia del producto `AppFoundation`): `InMemoryStore<Key: Hashable
  & Sendable, Value: Sendable>` (actor genérico para dobles de `*Storing`), `ManualClock`
  (mismo contrato que el de `CoreNetworkingTestSupport`, duplicado — AppFoundation no
  depende de CoreNetworking), `SpyRecorder<Call: Sendable>` (grabador de llamadas thread-safe
  para spies generados/hechos a mano).
- `AGENTS.md` en la raíz del paquete: arquitectura, naming, las cuatro variantes y cómo
  testear cada capa, enlazado desde la nueva sección «Arquitectura» del README.
- `AppFoundation/Examples/`: cuatro paquetes SwiftPM autocontenidos, uno por variante —
  `CounterApp` (sin datos), `NotesApp` (solo local, SwiftData), `LoginApp` (solo API,
  sustituye a `Examples/IntegrationExample`), `CatalogApp` (API + local, cache-then-network).

PRD: [PRD-AF-07](PRD/PRD-AF-07.md).

### CoreNetworking

<!-- PRD-CN-07 -->

#### Breaking

- **`APIServiceProtocol.upload`** pasa a la misma forma que `execute`:
  `upload(_:data:progress:) -> Request.Response` (el tipo de respuesta ya no
  se anota en el call site, se infiere del propio request) más la sobrecarga
  `upload(_:data:as:progress:) -> Value`, igual que `execute(_:as:)`. Se
  elimina `upload(request:data:progress:) -> Response`. Migrar
  `service.upload(request: req, data: d)` a `service.upload(req, data: d)`.
- **`APIError.Category`** gana `.unreachable`
  (`networkConnectionLost`/`cannotConnectToHost`/`dnsLookupFailed`/
  `cannotFindHost`, antes indistinguibles de `.unknown`): un `switch`
  exhaustivo sobre `Category` en la app deja de compilar hasta añadir el caso
  — el propio doc del tipo pide comparar contra los casos conocidos y caer a
  `default`, nunca `switch` exhaustivo, precisamente por esto.
- `MockAPIService` (`CoreNetworkingTestSupport`) lanza `APIError(code:
  .unstubbed)` — no `.invalidResponse` — cuando un request no tiene stub
  registrado o el stub no coincide con el tipo pedido; `underlying` nombra el
  request y el tipo esperado. Un test que comparaba contra `.invalidResponse`
  para este caso debe comparar contra `.unstubbed` (extensión pública de
  `APIError.Code`, abierto para eso).

#### Changed

- **`download(_:to:)`** pasa por el mismo `performWithRetry` que
  `execute`/`upload`/`data` — interceptores, `retriers` y `retryPolicy`
  incluidos — en vez de una copia paralela del pipeline "de un único
  intento". Cada intento reescribe `destination` atómicamente, así que
  reintentar es válido: una descarga a medias reintenta desde cero, nunca
  reanuda. El mapeo de errores (pinning → `.untrustedServer`, status non-2xx
  → `.httpStatus` con limpieza de `destination`, cancelación → `.cancelled`)
  no cambia de comportamiento observable.
- `NetworkingConfiguration.protocolClasses` queda `@available(*,
  deprecated, message: "Configura protocolClasses en sessionConfiguration")`
  — sigue funcionando (se fusiona en la `URLSessionConfiguration` real), pero
  `sessionConfiguration` es ahora la única forma soportada de instalar un
  `URLProtocol` de mock, no dos caminos que hacían lo mismo.

#### Added

- `Empty` conforma `Equatable`.
- `APIError.Code.unstubbed` (`CoreNetworkingTestSupport`, `extension
  APIError.Code`): el código que lanza `MockAPIService` sin stub — ver
  Breaking arriba.
- `errorDescription` (EN/ES, `Localizable.xcstrings`) para `.unreachable`:
  "Could not connect to the server." / "No se pudo conectar con el
  servidor.".

#### Docs

- `RequestSummary.init(URLRequest)` documenta que un método fuera del
  `HTTPMethod` cerrado (p. ej. WebDAV) se guarda como `.get` igual que
  `httpMethod == nil` — limitación conocida, no un bug; `HTTPMethod` sigue
  cerrado a propósito (sin `case custom(String)`).
- Comentarios que citaban PRDs como referencia futura (`APIService.upload`,
  `NetworkingConfiguration.defaultSessionConfiguration`,
  `Duration.timeInterval`, `TaskDelegate`, `URLSessionTransport`,
  `InMemoryTransport`, `HTTPTransport`) reescritos en presente: el código no
  habla de los PRDs que lo dejaron así.

PRD: [PRD-CN-07](PRD/PRD-CN-07.md).

<!-- PRD-AF-06 -->
#### Added

- `BaseViewModel.inFlightLoad`/`inFlightActivity: Task<Void, Never>?` (`public
  private(set)`, `@ObservationIgnored`): el `Task` en vuelo de `performLoad`/`load(_:)` y
  `performActivity`/`activity(_:)` respectivamente, `nil` al terminar. Pensado para tests
  deterministas cuando la llamada pasa por `handle(_:)` (que devuelve `Void`, AF-05):
  `viewModel.handle(.load); await viewModel.inFlightLoad?.value` en vez de sondear
  `phase`/`hasError` en un bucle con `Task.sleep`. Sustituye al helper `waitUntil` de los
  ficheros de test (eliminado, sin más usos) en `AppFoundation/Tests` y en
  `Examples/IntegrationExample/Tests` (DC-AF-2).
- `BaseViewModel.init(errorPresenter:cancellationRecognizer:clock:)` gana `cancellationRecognizer:`
  y `clock:` (ambos `nil` por defecto — no rompe llamadas existentes). Misma precedencia que
  `errorPresenter`: instancia > `BaseViewModel.cancellationRecognizer`/`BaseViewModel.clock`
  (los `static var`, que siguen existiendo para configuración a nivel de app). Los tests del
  paquete ya no mutan esos estáticos salvo un único test `.serialized` que prueba
  explícitamente el valor por defecto (DC-AF-3).
- Documentación: `BindingBackedState`/`ObservingScreenState` (`ScreenContainer.swift`)
  documentan por qué observan correctamente sin que `@Observable` (con el que ahora se
  marcan, sin efecto: ninguna de sus propiedades es almacenada) haga ningún trabajo — la
  reactividad viene de `Binding`/`@State` o de reenviar la lectura al `Observable` envuelto
  (DC-AF-4). `ErasedView` documenta sus cuatro usos restantes, todos en la barra de
  navegación `.custom`, opt-in (DC-AF-5). Sin cambios de API en ninguno de los dos casos.
- `Examples/IntegrationExample` gana `ProfileView`/`ProfilePreview`
  (`Sources/IntegrationExample/ProfileView.swift`): la vista SwiftUI que integra
  `ScreenContainer` con `ProfileViewModel`, con una preview sobre `MockAPIService` y un
  estilo de error instalado por `Environment` — la pieza que un integrador copia primero
  (DC-AF-6).

PRD: [PRD-AF-06](PRD/PRD-AF-06.md).

<!-- PRD-AF-07 -->
#### Added

- `EndpointService` (`Sources/CoreNetworking/EndpointService.swift`): `public protocol
  EndpointService: Sendable { var api: any APIServiceProtocol { get } }` con `public
  extension EndpointService { func call<R: BaseRequest>(_ request: R) async
  throws(APIError) -> R.Response }`. Plantilla cómoda para un `Service` de un solo request
  — no un requisito: un `Service` que necesite más de un patrón de llamada sigue llamando
  `api.execute` directamente.
- `AGENTS.md` en la raíz del paquete: un Service por request, mapeo de errores con
  `category`/`decodeBody`, cómo testear con `MockAPIService`/`InMemoryTransport`.

PRD: [PRD-AF-07](PRD/PRD-AF-07.md).

## [1.0.0] - 2026-09-02

Primera versión estable. Cierra la auditoría técnica de 2026-09-01
(`AUDITORIA-2026-09-01.md`, 43 hallazgos, `PRD/CIERRE.md`) dentro del alcance acordado:
seguridad avanzada fuera de alcance, SSL pinning básico y correcto dentro.

### Roturas de API

Lista agregada de toda la API pública eliminada o renombrada desde `0.1.4`, por paquete
(el detalle de cada cambio, con su racional, está en la entrada del PRD correspondiente
más abajo).

#### AppFoundation

- `performLoad`/`performActivity` ya no aceptan `() async throws -> Void`; `work` es
  `@MainActor (Self) async throws -> Void` — migrar `performLoad { self.foo() }` a
  `performLoad { vm in vm.foo() }` (AF-01/PRD-AF-01).
- `WrappedError.init` gana `now: () -> Date` y usa `#fileID` en vez de `#file` como
  default de `file` (PRD-AF-01).
- `Container` pasa a `@MainActor` — se elimina el `NSLock` y el `@unchecked Sendable`
  (AF-09/PRD-AF-02).
- `register(_:lifecycle:factory:)` recibe ahora el `Container` en la fábrica.
- `Lifecycle.scoped(key:)`, `Container.createScope`/`destroyScope` desaparecen — usar
  `Container(parent:)` (AF-10/PRD-AF-02).
- `ContainerConcurrencyTests.swift` desaparece (sin objeto que probar en un `Container`
  `@MainActor`).
- `Debouncer`/`Throttler` pasan de `actor` a `@MainActor final class`, dejan de ser
  genéricos sobre `Clock` (`Debouncer<C>` → `Debouncer`) y `debounce(_:)` pasa a
  síncrono (AF-19/PRD-AF-03).
- `Debouncer.init(milliseconds:)` se elimina — usar `.milliseconds(n)`.
- `AppEnvironment` pasa de `struct` a `enum` namespace (AF-20/PRD-AF-03).
- `AppEnvironment.isTestOrPreview` se elimina (heurística de test en producción,
  AF-20/PRD-AF-03).
- `AppEnvironment.debugInfo` / `AppEnvironment.printDebugInfo()` se eliminan.
- `ScreenContainer`: el parámetro `navigation:` desaparece en favor de
  `chrome: ScreenChrome` (`.native` por defecto, `.custom(...)` opt-in;
  AF-12/AF-13/PRD-AF-04).
- `.loadingView { }`, `.errorView { }`, `.emptyView { }`, `.bannerView { }` de
  `ScreenContainer` se eliminan en favor de `LoadingViewStyle`/`ErrorViewStyle`/
  `EmptyViewStyle`/`BannerViewStyle` propagados por `Environment` (AF-15/PRD-AF-04).
- `.alertView(builder:)` se elimina.
- `NavigationBarItemContent.view`, `NavigationBarTitle.custom` y las propiedades
  `accessoryView`/`customContent` de `NavigationBarConfiguration` dejan de exponer
  `AnyView` en su firma pública.
- `NavigationBarTitle.largeText` se elimina.
- `BannerState.duration` cambia de `BannerState.Duration` (enum propio) a
  `Swift.Duration?` (AF-18/PRD-AF-04).
- `Coordinator.navigationHistory` pasa a `internal` (antes `public` solo en `DEBUG`,
  AF-14/PRD-AF-04).

#### CoreNetworking

- `APIError` pasa de `enum` cerrado a `struct` extensible con `Code`, `RequestSummary`,
  `ResponseSummary` y `underlying`; deja de ser `Equatable` (CN-02/PRD-CN-01).
- `TransportError` y `APIMessageError` desaparecen — `APIError.category` cubre la
  clasificación de alto nivel (CN-03/PRD-CN-01).
- `RetryPolicy.shouldRetry` pasa a `@Sendable (APIError, Int) -> Bool`; `RetryPolicy`
  deja de ser `Equatable` (PRD-CN-01).
- `RequestInterceptor.didFail(_:error:)` tipa `error: APIError` en vez de `Error`
  (PRD-CN-01) — sustituido más tarde por la firma de CN-06, ver abajo.
- `SSLPinningConfiguration`: `pinnedHosts: Set<String>?` → `hosts: Hosts` (`.all`/
  `.only`); `validateCertificateChain: Bool` → `chainValidation: ChainValidation`
  (`.system`/`.unsafeSkipForDevelopment`); el constructor exige ≥ 2 pines
  (CN-19/PRD-CN-02).
- `APIService.init` ya no crea su propia `URLSession`: el designado recibe
  `transport: any HTTPTransport` (el `convenience init(configuration:...)` de siempre
  se conserva) (CN-21/PRD-CN-03).
- `RetryPolicy.initialDelay`/`.maxDelay` pasan de `TimeInterval` a `Duration`
  (CN-11/PRD-CN-03).
- `CoreNetworkingTestSupport.MockAPIService.result: Any?` desaparece —
  `stub(_:returning:)`/`stub(_:throwing:)` por tipo de request (CN-22/PRD-CN-03).
- `BaseRequest` se rediseña alrededor de `associatedtype Body: Encodable & Sendable =
  Never` / `associatedtype Response: Decodable & Sendable = Empty`; `parameters` se
  renombra a `body`; `timeoutInterval: TimeInterval` pasa a `timeout: Duration`;
  `headers`/`queryItems` dejan de ser opcionales (CN-15/CN-16/PRD-CN-05).
- `HTTPMethod` cambia sus casos a minúscula (`.get`, `.post`, …) — `HTTPMethod.GET` ya
  no compila (CN-18/PRD-CN-05).
- `APIServiceProtocol.execute`: `execute<Request, Response: Decodable>(request:) ->
  Response` pasa a `execute<R: BaseRequest>(_:) -> R.Response`, con la sobrecarga
  `execute<R, Value>(_:as:)` añadida (CN-16/PRD-CN-05).
- `NetworkingConfiguration.environment` desaparece (CN-17/PRD-CN-05).
- `BaseResponse.swift` (`BaseResponse`, `EmptyResponse`), `RequestParameters`,
  `EmptyParameters`, `RequestValidationError`, `validated()`/`isValid`/
  `debugValidated()`/`requestDescription` se eliminan (CN-17/PRD-CN-05).
- `SessionDelegates.swift` (`PinningSessionDelegate`, `UploadProgressDelegate`)
  desaparece — el pinning decide por tarea con `TaskDelegate`
  (CN-01/CN-07/PRD-CN-04).
- `APIServiceProtocol.download(request:progress:) -> Data` se sustituye por
  `data(for:progress:) -> Data` (en memoria) y `download(_:to:progress:)` (a disco)
  (CN-07/PRD-CN-04).
- `RequestInterceptor` se reescribe alrededor de `RequestContext`: `willSend(_:context:)`
  pasa a `async throws(APIError)`; `didReceive` recibe `HTTPURLResponse` (no
  `URLResponse`) y `context`; `didFail` pasa a `didFail(_ error: APIError, context:)`
  (ya no recibe `request:` por separado) (CN-06/PRD-CN-06).
- `APIService.init` (designado y `convenience`) gana `retriers: [any RequestRetrier] =
  []` (CN-05/PRD-CN-06).

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

<!-- PRD-CN-04 -->

#### Breaking

- **Crítico (CN-01)** — cancelar el challenge de server-trust producía
  `URLError(.cancelled)`: un fallo de pinning llegaba a la app indistinguible
  de que el usuario hubiese cancelado, y `if case .cancelled = error { return
  }` se lo tragaba en silencio. La corrección cambia el punto de decisión:
  `PinningSessionDelegate` (delegate único, a nivel de SESIÓN) desaparece;
  `TaskDelegate` (nuevo, `Transport/TaskDelegate.swift`) decide el pinning
  POR TAREA — una instancia nueva por cada `execute`/`upload`/`data`/
  `download` — y recuerda si fue ella quien canceló el challenge.
  `URLSessionTransport` traduce ese `URLError(.cancelled)` a `PinningFailure`
  (interno del transporte, nunca visible fuera del paquete) cuando el flag
  está activo; `APIService` lo mapea a `APIError(code: .untrustedServer,
  category: .untrustedServer)`. Una cancelación real del `Task` sigue siendo
  `.cancelled` — nunca se confunde con la anterior.
- `SessionDelegates.swift` desaparece (`PinningSessionDelegate` y
  `UploadProgressDelegate`, esta última ya sin uso: el body de upload viajaba
  en `httpBody`, nunca por `session.upload(for:from:)`). `URLSessionTransport`
  crea su `URLSession` con `delegate: nil` — cada llamada pasa su propio
  `TaskDelegate` a `session.data(for:delegate:)` / `session.upload(for:from:
  delegate:)` / `session.download(for:delegate:)`.
- **`APIServiceProtocol`**: `download(request:progress:) -> Data` (CN-07: iteraba
  `AsyncBytes` byte a byte — una llamada async POR BYTE, órdenes de magnitud más
  lento que recibir por chunks, y el nombre prometía "descarga" pero devolvía
  todo en memoria) se sustituye por DOS métodos sin ambigüedad de nombre:
  - `data(for:progress:) -> Data` — mismo comportamiento que el `download`
    anterior (en memoria), implementado por chunks vía `session.data(for:)`,
    ya sin el bucle byte a byte.
  - `download(_:to:progress:)` — streaming directo a disco vía
    `session.download(for:)`; nunca mantiene el body completo en memoria.
    Comparte transporte, interceptores y mapeo de errores con el resto, pero
    es un único intento (sin retry: reintentar una descarga a disco a medias
    exigiría truncar/reanudar el fichero, fuera de alcance). Dado que el
    fichero de destino puede quedar con contenido a medio escribir de un
    intento fallido, `download(to:)` limpia `destination` en cualquier
    camino de error (status non-2xx, pinning, cancelación) antes de lanzar
    `APIError`.
  - `HTTPTransport` gana `download(_:to:destination:progress:)` con el mismo
    contrato. `URLSessionTransport.download` mueve el fichero temporal a
    `destination` inmediatamente después de que `session.download(for:)`
    regrese — verificado empíricamente que la API async de conveniencia NO
    invoca `URLSessionDownloadDelegate.didFinishDownloadingTo` en el SDK que
    este paquete usa, así que el movimiento no puede depender de ese
    callback (`TaskDelegate` lo implementa igualmente, por si alguna
    plataforma sí lo entrega).

#### Added

- `PinningFailure` (`Transport/TaskDelegate.swift`), `public`: la señal
  interna que distingue "pinning rechazó el certificado" de "el llamador
  canceló". `CoreNetworkingTestSupport.InMemoryTransport.Outcome
  .pinningFailure(host:)` la expone en tests sin necesitar un handshake TLS
  real.
- `PinningPipelineTests.swift`: el test de extremo a extremo que la auditoría
  señaló como hueco (CN-01) — un `PinningFailure` del transporte produce
  `APIError.code == .untrustedServer` / `category == .untrustedServer`; un
  `URLError(.cancelled)` sin el flag produce `.cancelled`. Cubre `execute`,
  `data(for:)` y `download(to:)`, y verifica directamente
  `URLSessionTransport.remapPinningCancellation`, la función pura que usan
  `send`/`download` en su `catch`.
- `PinningDelegateTests` migrada a `TaskDelegate`: las mismas 6 decisiones
  (ahora a nivel de tarea, con `URLSessionTask` en la firma del challenge) más
  un test nuevo — tras `.failed`, `pinningFailed == true`.
- `TransferTests`: `data(for:)` de 5 MB con límite de tiempo generoso (regresión
  contra el bucle byte a byte de CN-07); `download(to:)` verificado contra un
  servidor HTTP real en loopback (socket POSIX, no `URLProtocol` — un
  `URLProtocol` a medida no dispara la maquinaria de descarga a fichero real,
  verificado empíricamente) para probar que el fichero llega a `destination`
  sin temporales huérfanos y que sustituye un fichero existente.

PRD: [PRD-CN-04](PRD/PRD-CN-04.md).

<!-- PRD-CN-06 -->

#### Breaking

- `RequestInterceptor` se reescribe alrededor de `RequestContext` (`id`,
  `request`, `attempt` — 1-based —, `startedAt: ContinuousClock.Instant`):
  `willSend(_:context:)` pasa a `async throws(APIError)` (puede ABORTAR el
  request antes de que el transporte lo vea); `didReceive` recibe
  `HTTPURLResponse` (no `URLResponse`, sin castear) y `context`; `didFail`
  pasa a `didFail(_ error: APIError, context:)` (ya no recibe `request:`, va
  en `context.request`).
- `APIService.init` (ambos: el designado con `transport:` y el `convenience`
  con `sslPinning:`) gana `retriers: [any RequestRetrier] = []`.

#### Added

- `RequestRetrier` (`Retry/RequestRetrier.swift`): `func retry(_ error:
  APIError, context: RequestContext) async -> RetryDecision`
  (`.doNotRetry` / `.retry` / `.retryAfter(Duration)`), consultado ANTES que
  `RetryPolicy` en cada intento fallido — el primero que no responda
  `.doNotRetry` decide; `RetryDecision.retryAfter` manda sobre `RetryPolicy`
  Y sobre un `Retry-After` del servidor. `RetryPolicy.maxAttempts` acota
  ambos caminos (CN-05).
- `Auth/TokenRefresher.swift`: `TokenRefreshing` (protocolo) y `actor
  TokenRefresher` — deduplica refreshes concurrentes (N requests con 401 a
  la vez disparan UN único refresh; los demás esperan su resultado, tanto en
  éxito como en fallo). `BearerTokenInterceptor(tokenProvider:)` añade
  `Authorization: Bearer <token>` leyendo el token fresco en cada
  `willSend`. `TokenRefreshRetrier(refresher:)` refresca y reintenta un 401
  solo en el primer intento (`context.attempt == 1`); si el refresh falla,
  `.doNotRetry` — el 401 original llega al consumidor sin requests extra
  (CN-05).
- `CoreNetworkingTestSupport`: `RecordingInterceptor`, un
  `RequestInterceptor` público que graba `willSend`/`didReceive`/`didFail`
  (con su `RequestContext`) en orden, para probar interceptores y retriers
  propios sin un spy a medida; opcionalmente lanza un error fijo desde
  `willSend` para probar caminos de aborto.

#### Removed

- La nota histórica sobre `PerformanceInterceptor` en `RequestInterceptor.swift`
  desaparece: `context.id`/`context.attempt`/`context.startedAt` son
  exactamente la identidad de request que le faltaba para medir sin
  confundir requests concurrentes a la misma URL (CN-06).

PRD: [PRD-CN-06](PRD/PRD-CN-06.md).

<!-- PRD-CN-03 -->

#### Breaking

- `APIService.init` ya no crea su propia `URLSession`: recibe un `transport:
  any HTTPTransport` (el nuevo punto de inyección — `URLSessionTransport` en
  producción, `InMemoryTransport` en tests). El `init(configuration:,
  retryPolicy:, interceptors:, sslPinning:)` de siempre sigue existiendo como
  `convenience init` (azúcar sobre `URLSessionTransport`), así que la mayoría
  de consumidores no cambia una sola línea.
- `RetryPolicy.initialDelay` / `.maxDelay` pasan de `TimeInterval` a
  `Duration` (`.milliseconds(500)` / `.seconds(16)` por defecto);
  `baseDelay(for:)` / `jitteredDelay(for:)` devuelven `Duration`.
  `APIService` ya no reintenta con `Task.sleep` en el reloj real: duerme a
  través de un `any Clock<Duration>` inyectable (`init(clock:)`, por defecto
  `ContinuousClock()`).
- `CoreNetworkingTestSupport`: `MockAPIService.result: Any?` desaparece —
  `stub(_:returning:)` / `stub(_:throwing:)` registran el stub por TIPO de
  request, así que un `Response` que no matchea ya no cae silenciosamente en
  `.invalidResponse`. `MockNetworkExchange.response:` (single) sigue
  existiendo; `responses: [MockResponse]` es nuevo (secuencia consumida en
  orden, la última se repite).

#### Added

- `HTTPTransport` (`Transport/HTTPTransport.swift`): el protocolo `send(_:
  progress:) async throws -> (Data, HTTPURLResponse)` que reemplaza al
  registro estático de `URLProtocol` como punto de inyección bajo
  `APIService`. `URLSessionTransport` (`Transport/URLSessionTransport.swift`)
  es la implementación de producción: posee la `URLSession` y su `deinit`
  (movidos desde `APIService`), con `PinningSessionDelegate` como delegate de
  sesión — igual que antes, solo que ahora vive en el transporte, no en el
  servicio.
- `InMemoryTransport` (`CoreNetworkingTestSupport`): `HTTPTransport` en
  memoria, sin `URLSession` ni registro global — un `actor` por test, sin la
  disciplina de "un host por test" que exige `MockURLProtocol` bajo Swift
  Testing en paralelo. Soporta secuencias de respuestas (500 → 500 → 200),
  el hueco que hacía imposible probar "reintento que acaba bien" (CN-21).
- `ManualClock` (`CoreNetworkingTestSupport`): `Clock<Duration>` que solo
  avanza cuando el test llama a `advance(by:)`; `waitUntilSleeping()`
  suspende (sin sondear, sin dormir) hasta que el pipeline registra el
  siguiente `sleep`. `RetryBehaviorTests` ya no mide tiempo de pared ni
  contiene un solo `Task.sleep` real (CN-11).
- `MockURLProtocol` / `MockAPIHelper.setupMockSequence(...)`: soporte de
  secuencias también en el mock de integración, para los tests que
  deliberadamente siguen atravesando el URL loading system real.

PRD: [PRD-CN-03](PRD/PRD-CN-03.md).

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
  desactivadas, TLS 1.2 mínimo) como valor por defecto. El `convenience init`
  de `APIService` la usa para construir la `URLSessionConfiguration` que pasa
  a `URLSessionTransport` (CN-03), así que llega hasta la `URLSession` real.
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

<!-- PRD-CN-02 -->

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
