# PRD-APP-02 — AppStarter en modo multi y escaparate completo de AppFoundation + CoreNetworking

Ámbito: repo `hiramvazquez/AppStarter` · Origen: propietario (2026-09-04): «migra todo a multi y que tenga ejemplo de todo, aunque haya que crear pantallas nuevas; así se ve el trabajo de la IA con el SPM» · Depende de: AppFoundation 1.2.0, CoreNetworking 1.0.0

## Objetivo

AppStarter pasa a ser (1) la prueba real de `archinit --multi` + `generate-feature` en modo multi
sobre una app existente, siguiendo la guía de migración del artículo `MultiModule`, y (2) un
**escaparate exhaustivo**: cada capacidad pública de los dos paquetes se usa en al menos una
pantalla o un test, y un índice en el README dice dónde. Siempre contra DummyJSON (real) con
modo offline por fixtures para los XCUITests. Todo generado con el kit donde el kit genera, y
completado a mano donde no.

## Fase 1 — Migración a tres niveles (sin funcionalidad nueva)

Estructura final (la que deja `archinit --multi`, aplicada a lo existente):

```
AppStarter/
├── App/                    cáscara (hoy AppStarter/): AppStarterApp, RootView, AppModule, AppRoute, OfflineFixtures
├── AppTests/  AppUITests/  (los actuales)
├── Packages/
│   ├── Platform/           Domain (modelos + protocolos compartidos: Product, UserProfile, Session,
│   │                       SessionStoring, ProductsServicing, FavoritesStoring, AnalyticsTracking,
│   │                       CameraCapturing…) · CameraKit · AnalyticsAdapters (consola; sin Firebase)
│   └── Features/           LoginFeature, ProductsFeature, ProductDetailFeature, FavoritesFeature,
│                           ProfileFeature, SearchFeature (targets; los actuales, movidos)
├── project.yml · Scripts/bootstrap.sh · .github/workflows/ci.yml (matriz por paquete + app)
└── .archlint.yml (modules:) · .swiftlint.yml · .swift-format · AGENTS.md · CLAUDE.md
```

Pasos (el orden del artículo): `Scripts/bootstrap-multi.sh AppStarter --capability Camera
--adapter Analytics` sobre el repo (idempotente: no pisa lo existente; comparar con el diff que
imprime), `Domain` con lo compartido, cada feature actual como target (uno por commit, con
`public` donde toque), el networking transversal (`NetworkingWiring`, `SessionStore`,
`RefreshActivityLog`, `AppSessionState`, `AppErrorPresenter`) a `Domain` o a la cáscara según
sea contrato o composición, R13 desde el primer commit, CI por paquete. `AppStarterKit/`
desaparece. Los 48 tests unitarios, 2 de integración y 4 XCUITests siguen en verde.

## Fase 2 — Escaparate: cada capacidad, en su sitio

Pantallas nuevas (todas con `generate-feature`, opción indicada) y dónde se enseña cada cosa.
Reglas: cada fila tiene un test; cada pantalla tiene `accessibilityIdentifier` en hojas; nada
de código muerto «para enseñar»: la capacidad se usa de verdad.

### CoreNetworking

| Capacidad | Dónde |
|---|---|
| `APIService` + `NetworkingConfiguration` (baseURL, timeouts, headers por defecto, decoder propio) | `Domain/Networking` (ya) + `Settings` muestra la configuración activa |
| `BaseRequest` GET/POST con query, body y `Empty` | Products (GET query), Login (POST body), `Products/add` (POST, ver Uploads) |
| `APIError`: categorías, `RequestSummary`/`ResponseSummary`, `decodeBody` de un error del servidor, `LocalizedError` | `Diagnostics` (nuevo, `--api`): lanza a propósito 404, 401, timeout, JSON inválido y host inalcanzable contra DummyJSON y muestra categoría, resumen y mapeo a `DomainError` |
| `RequestInterceptor` + `RequestContext` (`BearerTokenInterceptor`, `LoggingInterceptor`, uno propio que añade `X-Client` y cuenta peticiones) | `NetworkingWiring` (ya) + `Diagnostics` enseña el log del `LoggingInterceptor` y el contador |
| `RequestRetrier` + `RetryPolicy` (backoff, `RetryDecision`) | `Diagnostics`: un endpoint 5xx simulado por fixture con reintentos visibles y un caso real (timeout corto) |
| `TokenRefresher` + `TokenRefreshRetrier` (dedupe de refresh concurrente) | Profile (ya: `expiresInMins` y `RefreshActivityLog`) + test de dedupe con `ManualClock` |
| `EndpointService` | todos los `*Service` (ya) |
| `upload(_:data:progress:)` + `TransferProgress` | `Uploads` (nuevo, `--api`): `POST /products/add` con barra de progreso real (DummyJSON no persiste; se enseña el progreso y la respuesta) |
| `SSLPinningConfiguration` + `PinningValidationResult`/`PinningFailure` (≥2 pins, `NSPinnedDomains` documentado) | `Settings`: toggle «pinning estricto» que reconfigura el transporte con los pins de dummyjson.com; con un pin falso, la petición falla con `.untrustedServer` (nunca `.cancelled`) y `Diagnostics` lo muestra. Pins reales obtenidos con `openssl` y documentados en el README |
| `HTTPTransport` propio + `InMemoryTransport` | `App/OfflineFixtures` (ya) + fixtures nuevos para cada pantalla nueva |
| `ManualClock`, `MockAPIService` (stubs tipados, `Code.unstubbed`), `MockURLProtocol` (solo integración), `RecordingInterceptor` | tests: dedupe de refresh (`ManualClock`), tests de Logic (`MockAPIService`), un test de integración con `MockURLProtocol` sobre `URLSessionTransport` (latencia, cancelación), `RecordingInterceptor` en el test del interceptor propio |
| `TransportError` | `Diagnostics`: host inalcanzable → `.unreachable` |

### AppFoundation

| Capacidad | Dónde |
|---|---|
| `performLoad` (`.fullScreen`), `performActivity` (`.overlay`/`.inline`), `successTransition: .preserveCurrentPhase`, `load()`/`activity()` estructurados | Products (ya), Favorites (ya), `Uploads` usa `activity()` estructurado con `.inline` |
| `ErrorPresenting` propio + `DomainError` + `isRetryable` + reintento desde el error | `AppErrorPresenter` (ya) + `Diagnostics` |
| `CancellationRecognizing` + `inFlightLoad` (salir de la pantalla cancela) | test de ViewModel (ya) + `Diagnostics` con un endpoint lento y botón «cancelar» |
| `AlertState` (primario/secundario/destructivo) | Favorites: «Vaciar favoritos» con alerta destructiva; Profile: logout con confirmación |
| `BannerState` (success/info/warning/error, `duration`) | `Uploads` (success), Products refresh fallido (warning, ya), `Settings` (info) |
| `ViewPhase.empty` + `EmptyViewStyle`; `.error` + `ErrorViewStyle`; `.loading` + `LoadingViewStyle`; `BannerViewStyle` | **`Theming`**: `App/Theme/` con `BrandLoadingStyle`, `BrandErrorStyle`, `BrandEmptyStyle`, `BrandBannerStyle` instalados en `RootView`, y `Settings` con un toggle «tema del kit / tema de marca» que los quita y los pone (así se ve la diferencia) |
| `ScreenChrome.native` / `.custom(_, placement: .stack)` / `.custom(_, placement: .overlay)` + `NavigationBarStyle` presets (`.solid`, `.transparent`, `.blur`) + `NavigationBarItem` + `SearchBarConfiguration` | ProductDetail (custom stack, ya), `Gallery` (nuevo, `--api --module`: imagen grande con barra `.transparent` en `.overlay`), Search con `SearchBarConfiguration` en la barra custom (`.blur`) |
| `PopGestureEnabler` (swipe-back con barra custom) | SwipeBackTests (ya) + Gallery |
| `Coordinator`/`Router`/`CoordinatorView` (push, pop, popToRoot, sheet) + `DeepLink` | `App/`: URL scheme `appstarter://product/3` y `appstarter://search?q=phone` parseados con `DeepLink` y encaminados; test unitario + XCUITest que abre la app con la URL |
| `Container`: módulos, `lifecycle` singleton/transient, `Container(parent:)` (contenedor hijo por sesión que se destruye al cerrar sesión) | `AppModule` (ya) + sesión: al hacer login se crea `Container(parent:)` con `SessionStoring` y los módulos autenticados; al salir se descarta (test que demuestra que los singletons de sesión no sobreviven al logout) |
| `Debouncer` / `Throttler` | Search (debounce del texto, ya o añadir) + `Gallery` (throttle del scroll para prefetch) |
| `Logic`/`LogicViewModel` + generador `--api`, `--local`, `--api --local`, sin datos, `--module`, `--service-from`/`--store-from`, `--no-service` | Login (`--api`), Favorites (`--local`), ProductDetail (`--api --local` + `--service-from Products --store-from Favorites`), `Settings` (sin datos, `--local` para persistir el tema con `UserDefaults` vía Store), `Gallery` (`--api --module`), `Diagnostics` (`--api --no-service`: reutiliza el `APIServiceProtocol` directamente desde un Service propio mínimo) |
| `AppFoundationTestSupport`: `InMemoryStore`, `ManualClock`, `SpyRecorder` (+ `isEmpty`) | tests de Stores y ViewModels |
| `L10n` + `.xcstrings` (es/en) + `ResourceBundle` | toda cadena visible; `Settings` cambia el idioma en runtime para verlo (o test de que existen ambas) |
| `AppFoundationDiagnostics` (`droppedActionHandler`, `assertOnDroppedAction`) | `App/`: en DEBUG, `assertOnDroppedAction = true` y test de que un ViewModel liberado registra el descarte |
| `ObservingScreenState`, `BindingBackedState`, `PhaseView`, `ScreenModifier` | `Gallery`: una sub-vista con `PhaseView` y estado por `BindingBackedState` (un caso donde no hay ViewModel) |
| `AppEnvironment` | `Settings` muestra el entorno (debug/release, versión, build) |
| Capacidad (`CameraKit`) y adapter (`AnalyticsAdapters`) por protocolo de `Domain` | `Uploads` adjunta una foto via `any CameraCapturing` (simulador: `SimulatedCamera` devuelve una imagen de asset); `AnalyticsTracking` registra eventos de navegación y `Settings` muestra los últimos N (adapter de consola + `InMemoryAnalytics` en tests) |
| Linter R1–R14 + SwiftLint + Definition of Done | CI; el README enseña una violación de cada tipo (R1 capa, R13 módulo, `try!`) fallando en `swift build`, como transcripción |

### Fase 3 — Tests de UI y documentación

- XCUITests offline nuevos: Diagnostics (categorías visibles), Uploads (progreso y banner),
  Gallery (barra overlay, swipe-back), Settings (cambio de tema y pinning), deep link.
- `docs/INFORME-MULTI.md`: la migración paso a paso con lo que costó, y fricciones nuevas del
  kit (→ issues para 1.2.1). `docs/ESCAPARATE.md` (o el README): la tabla de arriba con enlaces
  a fichero y línea reales, generada o mantenida a mano pero verificada por un script
  (`Scripts/check-showcase.sh`: cada símbolo de la tabla aparece en el código).
- Snapshot tests por estado (`swift-snapshot-testing`) de `Diagnostics`, `Uploads` y `Gallery`
  en loading/empty/error/content con el tema del kit y el de marca. Referencias aprobadas en el PR.
- README: índice del escaparate, cómo correr todo, y la sección «lo que hizo la IA» honesta.

## Criterios de aceptación
- [x] `swift test` en Platform y Features (8 + 125), `archlint` 0 en ambos (R13 y R15), `swiftlint --strict` 0, `xcodebuild test` (11 unit + 24 snapshots + 10 XCUITests offline) verde dos veces seguidas en local; `INTEGRATION=1` 2/2 contra DummyJSON real. CI: ver «Ejecución».
- [x] `Scripts/check-showcase.sh`: 50 citas verificadas, 0 fallos. Cinco capacidades marcadas «no cubiertas» con motivo en el README (`MockURLProtocol`, `RecordingInterceptor`, `InMemoryStore`, `L10n`/`.xcstrings`, `AppFoundationDiagnostics`).
- [x] Ninguna feature importa otra feature ni `CameraKit`/`AnalyticsAdapters` (R13, probada en negativo).
- [x] `docs/INFORME-MULTI.md` (migración, fricciones del kit → PRD-AF-11, verificación con Xcode) y README con «Lo que hizo la IA».

## Fuera de alcance
Firebase real (el adapter de consola enseña el patrón); publicación en TestFlight; snapshot tests de todas las pantallas antiguas.

## Ejecución (2026-09-04, `main` de AppStarter `3b4d3d8`)

Tres fases con agentes (Sonnet) sobre la rama `multi`, integradas por el orquestador; ~55 commits.

- **Fase 1** (migración): 11 commits. `AppRoute` a `Domain`, target `Networking` en Platform (el kit no
  lo genera), R3 desactivada en Features por falso positivo cross-módulo. Fricciones → PRD-AF-11.
- **Fase 2** (escaparate): Diagnostics (7 experimentos reales), Uploads (progreso, foto por `CameraKit`),
  Gallery (`--module`, barra `.transparent` en `.overlay`, `Throttler`, `PhaseView`), Settings (tema de
  marca conmutable, pinning con pins reales, `AppEnvironment`, analytics), alertas destructivas, sesión
  con `Container(parent:)`, deep links, `SearchBarConfiguration` + `Debouncer`. Bugs reales encontrados
  contra DummyJSON y corregidos: cookie que hacía pasar el 401, `waitsForConnectivity`, semáforo
  bloqueante, `APIServiceProtocol` autorregistrado, **`@Observable` no heredado** (→ AppFoundation 1.2.1).
- **Fase 3** (tests y docs): 3 XCUITests nuevos, 24 snapshot tests (`swift-snapshot-testing`),
  `check-showcase.sh`, CI por paquete, README. El agente no pudo ejecutar `xcodebuild` (Xcode.app tenía el
  proyecto abierto y retenía el lock); el orquestador lo ejecutó desde un clon en otra ruta y corrigió lo
  que la primera ejecución real destapó (tabla en `INFORME-MULTI.md`): `Process` en iOS, stubs `struct`
  para `Logic: AnyObject`, productos sin enlazar en `AppTests`, PNG de snapshots como recursos, el toggle de
  tema recreando la pila, el `TabView` paginado frente al swipe-back, `XCUIApplication.open` relanzando la
  app (→ deep links pendientes hasta login), `UserDefaults` persistente entre lanzamientos.
- **Resultado**: `xcodebuild test` completo en verde dos veces seguidas; AppFoundation 1.2.1.
