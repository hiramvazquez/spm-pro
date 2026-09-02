# PRD-AF-07 — Kit de arquitectura: `Logic`, `LogicViewModel`, `EndpointService`, test support y ejemplos por variante

Ámbito: AppFoundation (+ una pieza en CoreNetworking) · Oleada 8 · Origen: `ARQUITECTURA-KIT-2026-09-02.md` §1-2, §7 · Rompe API pública: no (solo añade)

## Decisiones fijadas por el propietario
- Capas: View → ViewModel → Logic → Services (API) / Stores (local). Un `Logic` por ViewModel. Inyección 100 % por `init` y por **protocolo** (`any XxxLogicProtocol`, `any XxxServicing`, `any XxxStoring`); mocks/spies por protocolo en tests.
- El ViewModel no conoce services, stores ni red: solo su `Logic`.
- Naming: `XxxLogic` / `XxxLogicProtocol`; `XxxService` / `XxxServicing` (API); `XxxStore` / `XxxStoring` (local). Un Service = una llamada a API con su `BaseRequest`.
- Cuatro variantes de app deben quedar ejemplificadas: solo API, solo local, API + local, sin datos.

## Entregables
0. **Mejoras M1-M7 de `ARQUITECTURA-KIT-2026-09-02.md` §8** aplicadas en el kit y en los cuatro ejemplos: `DomainError` en AppFoundation; errores de dominio por feature mapeados en la Logic; DTO→dominio en los Services; Logic sin `Router`; `XxxModule` como composition root y VMs construidos fuera de las capas; aislamiento por capa (Logic `nonisolated`, Store `actor`/`@ModelActor`, Service `struct Sendable`); `SessionStore` + logout global al 401 en `LoginApp`; cache-then-network con `cached()`/`refresh()` en `CatalogApp`.
1. **AppFoundation**
   - `Architecture/Logic/Logic.swift`: `public protocol Logic: AnyObject {}` (marcador; doc: por qué existe: lint, generador, intención).
   - `Architecture/ViewModels/LogicViewModel.swift`: `open class LogicViewModel<L>: BaseViewModel { public let logic: L; public init(logic: L, errorPresenter:cancellationRecognizer:clock:) }`. Conforma `ScreenState`/`LoadableViewModel` por herencia; **no** conforma `ActionHandling` (lo hace cada subclase con su `Action`).
   - Nuevo producto **`AppFoundationTestSupport`** (target separado, como en CoreNetworking): `InMemoryStore<Key: Hashable, Value>` (actor) para tests de Logic con Stores, `ManualClock` (mover/duplicar el de tests, público) y `SpyRecorder` mínimo para spies generados. Nada de esto viaja en el binario de producción.
   - `AGENTS.md` en la raíz del paquete: arquitectura en ≤ 80 líneas (capas, reglas, naming, las 4 variantes, cómo testear cada capa, qué NO hacer). Enlazado desde el README.
2. **CoreNetworking**
   - `EndpointService.swift`: `public protocol EndpointService: Sendable { var api: any APIServiceProtocol { get } }` con `public extension EndpointService { func call<R: BaseRequest>(_ request: R) async throws(APIError) -> R.Response }`. Es una plantilla cómoda, no un requisito. Doc + test.
   - `AGENTS.md` propio: un Service por request, mapeo de errores con `category`/`decodeBody`, tests con `MockAPIService`/`InMemoryTransport`.
3. **Ejemplos** (cada uno un paquete SwiftPM autocontenido y con tests verdes, dentro de `AppFoundation/Examples/`; los que usan API dependen de CoreNetworking por `path: "../../../CoreNetworking"` **solo** en este monorepo, con un comentario en `Package.swift` mostrando la línea `url:`/`from: "1.0.0"` equivalente para el uso real):
   - `Examples/CounterApp` (sin datos): `CounterView`, `CounterViewModel: LogicViewModel<any CounterLogicProtocol>`, `CounterLogic`. Tests de VM (spy) y de Logic.
   - `Examples/NotesApp` (solo local): SwiftData `@Model Note`, `NotesStore: NotesStoring` (SwiftData) + `InMemoryNotesStore` (tests), `NotesLogic`, `NotesViewModel`, `NotesView` con lista y `send(.add(text))`. Tests con `InMemoryStore`.
   - `Examples/LoginApp` (solo API): reemplaza al actual `Examples/IntegrationExample` del monorepo (mover con `git mv` a `AppFoundation/Examples/LoginApp`): `LoginRequest: BaseRequest`, `LoginService: LoginServicing, EndpointService`, `LoginLogic(loginService:)`, `LoginViewModel`, `LoginView`, `AppErrorPresenter`, `LoginModule: DependencyModule`. Tests: VM con `LoginLogicMock`, Logic con `LoginServiceMock`, Service con `MockAPIService` **y** con `InMemoryTransport` (401 → refresh → 200).
   - `Examples/CatalogApp` (API + local): `CatalogService` + `CatalogStore` (SwiftData) + `CatalogLogic` con política *cache-then-network* (devuelve lo local, refresca de red, persiste); tests de la política con mocks de ambos.
   - Cada ejemplo: `README.md` que recorre los ficheros y explica la variante; estructura de carpetas idéntica (`Features/<Feature>/{View,ViewModel,Logic,Services,Stores,Tests}`); registro en DI en `AppModule`.
4. CI: job por ejemplo (`swift test` en cada `Examples/*`). Actualizar `.github/workflows/ci.yml` y quitar el job del `Examples/IntegrationExample` raíz.

## Ficheros
`AppFoundation/Package.swift` (nuevo target/producto `AppFoundationTestSupport`), `AppFoundation/Sources/AppFoundation/Architecture/{Logic,ViewModels}/`, nuevo `AppFoundation/Sources/AppFoundationTestSupport/`, `AppFoundation/AGENTS.md`, `AppFoundation/Examples/**`, `CoreNetworking/Sources/CoreNetworking/EndpointService.swift`, `CoreNetworking/AGENTS.md`, tests nuevos en ambos paquetes, `README.md` de ambos (solo añadir una sección «Arquitectura» corta que enlace a `AGENTS.md`; el rediseño es de X-03), `CHANGELOG.md` (`[Unreleased]`), `.github/workflows/ci.yml`, `git mv Examples/IntegrationExample AppFoundation/Examples/LoginApp`.

## Criterios de aceptación
- [ ] Los cuatro ejemplos compilan y sus tests pasan (`swift test` en cada uno); ninguno tiene `Task.sleep`/polling en tests (usar `inFlightLoad`).
- [ ] En los cuatro: `grep -rn "APIService\|BaseRequest\|URLSession\|SwiftData" */Features/*/ViewModel*.swift` vacío; `grep -rn "import SwiftUI" */Features/*/*Logic.swift` vacío; todo `init` de VM/Logic recibe solo `any …Protocol`/`…Servicing`/`…Storing`.
- [ ] `LogicViewModel` y `Logic` con tests en AppFoundation; `EndpointService` con test en CoreNetworking.
- [ ] `AppFoundationTestSupport` no aparece como dependencia del producto `AppFoundation`.
- [ ] `AGENTS.md` en ambos paquetes; la sección «Arquitectura» del README enlaza a él.
- [ ] Verificación: `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` 0 warnings y `swift test --parallel` verde 3 veces en ambos paquetes; `swift format lint --strict --recursive AppFoundation CoreNetworking` 0; `xcodebuild build` iOS Simulator en ambos; CI actualizado y YAML válido.
