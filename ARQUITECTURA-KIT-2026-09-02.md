# Kit de arquitectura: View → ViewModel → Logic → Services/Stores

Análisis de opciones (2026-09-02) para que cualquier app que adopte los SPM siga la arquitectura del propietario, y para que un agente no pueda salirse de ella.

## 1. La arquitectura, escrita una vez

```
Features/Login/
├── LoginView.swift            SwiftUI. Solo conoce el ViewModel a través de ScreenContainer(vm) { send in … }.
├── LoginViewModel.swift       BaseViewModel + ActionHandling. Orquesta: recibe acciones, llama a Logic, actualiza estado.
│                              init(logic: any LoginLogicProtocol). NO conoce services, stores ni red.
├── LoginLogic.swift           protocol LoginLogicProtocol + final class LoginLogic. Toda la lógica de negocio.
│                              init(loginService: any LoginServicing, sessionStore: any SessionStoring). Sin SwiftUI.
├── Services/
│   └── LoginService.swift     protocol LoginServicing + struct LoginService(api: any APIServiceProtocol).
│                              Aquí vive el BaseRequest y la llamada a execute. Una llamada a API = un Service.
├── Stores/
│   └── SessionStore.swift     protocol SessionStoring + implementación local (SwiftData/UserDefaults/Keychain/memoria).
│                              Persistencia local = un Store. Misma forma que un Service, distinto origen.
└── Tests/
    ├── LoginViewModelTests.swift   VM con LoginLogicMock (spy): handle(.login) → logic.login llamado, phase == .content.
    ├── LoginLogicTests.swift       Logic con LoginServiceMock + SessionStoreMock.
    ├── LoginServiceTests.swift     Service con MockAPIService / InMemoryTransport.
    └── Mocks/                      Un mock/spy por protocolo, generados.
```

Reglas (las que el linter comprueba):
1. **ViewModel** no importa CoreNetworking ni referencia `APIService`, `URLSession`, `*Service`, `*Store`; solo `*LogicProtocol` por `init`. Conforma `ActionHandling`.
2. **Logic** no importa SwiftUI/UIKit, no referencia `*ViewModel`; declara `*LogicProtocol` y una implementación; sus dependencias entran por `init` como protocolos.
3. **Service** declara `*Servicing` + implementación; solo él toca `APIServiceProtocol`/`BaseRequest`. **Store** declara `*Storing` + implementación; solo él toca SwiftData/CoreData/UserDefaults/Keychain/FileManager.
4. **View** no referencia `*Logic`, `*Service`, `*Store` ni `APIService`; recibe el VM y usa `ActionSender`.
5. Cada `XxxViewModel.swift` tiene su `XxxLogic.swift` (desactivable por pantalla en la config).
6. Ninguna clase concreta de Service/Store/Logic aparece en un `init` de otra capa: siempre `any XxxProtocol`.

Cuatro variantes de app, mismas reglas:

| Variante | Logic depende de | Ejemplo generado |
|---|---|---|
| Solo API | `*Servicing` | `LoginLogic(loginService:)` |
| Solo local | `*Storing` | `NotesLogic(notesStore:)` con SwiftData |
| API + local | ambos | `CatalogLogic(catalogService:catalogStore:)` con política cache-then-network |
| Sin datos | nada (o un `Clock`, un `Calculator`…) | `CounterLogic()` puro |

## 2. Cómo hacer que la arquitectura sea el camino fácil (en el SPM)

**AppFoundation** aporta las formas, no la app:

```swift
/// Marcador: toda Logic conforma. Sin requisitos: documenta intención y permite al linter y al generador reconocerla.
public protocol Logic: AnyObject {}      // o Sendable según la app; se decide en AF-07

/// Base opcional para VMs con Logic inyectada. `logic` es `let`: no se sustituye después de construir.
open class LogicViewModel<L>: BaseViewModel {
    public let logic: L
    public init(logic: L, errorPresenter: (any ErrorPresenting)? = nil) { … }
}
```
`LogicViewModel` no obliga (se puede heredar de `BaseViewModel` a pelo) pero convierte "VM con Logic" en una línea, y el linter puede exigirlo (regla 5 en modo estricto).

**CoreNetworking** aporta la forma de un Service:

```swift
/// Un Service de API: un request, una llamada, un mapeo. `EndpointService` es la plantilla del generador,
/// no un requisito del linter (un Service puede necesitar dos requests).
public protocol EndpointService: Sendable { associatedtype Request: BaseRequest; var api: any APIServiceProtocol { get } }
public extension EndpointService { func call(_ request: Request) async throws(APIError) -> Request.Response { try await api.execute(request) } }
```

**Persistencia local**: AppFoundation no incluye una capa de datos (fuera de alcance de un SPM de base); aporta el **contrato** y el ejemplo: `protocol Storing`-style por feature, un `InMemoryStore` genérico en `AppFoundationTestSupport` (nuevo producto, análogo a `CoreNetworkingTestSupport`) para tests, y en el ejemplo un `SwiftDataNotesStore` real.

## 3. Generador: `swift package generate-feature`

Un **command plugin** de SwiftPM dentro de AppFoundation (`Plugins/GenerateFeature`). Se invoca desde el proyecto que consume el paquete:

```bash
swift package --allow-writing-to-package-directory generate-feature Login --api            # Service
swift package … generate-feature Notes --local                                            # Store (SwiftData)
swift package … generate-feature Catalog --api --local                                    # ambos
swift package … generate-feature Counter                                                  # solo Logic
opciones: --route AppRoute.login  --no-logic  --tests/--no-tests  --path Features  --dry-run
```
En Xcode: clic derecho sobre el proyecto → el plugin aparece en el menú (Xcode 14+); pide permiso de escritura una vez.

Qué genera (todo compila desde el primer segundo y sus tests pasan):
- `LoginView` con `ScreenContainer(viewModel) { send in … }` y un «Hola mundo» que ya llama a `send(.load)`.
- `LoginViewModel: LogicViewModel<any LoginLogicProtocol>, ActionHandling` con `enum Action { case load }`.
- `LoginLogic` + `LoginLogicProtocol`; `LoginService` + `LoginServicing` + `LoginRequest: BaseRequest` (con `--api`); `LoginStore` + `LoginStoring` (con `--local`, SwiftData `@Model` mínimo).
- Registro en DI: `LoginModule: DependencyModule` con las tres capas registradas por protocolo.
- Tests + mocks/spies por protocolo (`LoginLogicMock` con `var loginCalls = 0`, `LoginServiceMock` con `result`/`error`).
- Plantillas en `AppFoundation/Templates/*.swift.stencil` (texto plano, sin dependencia de Stencil: sustitución `{{Feature}}`), legibles también por un agente que prefiera copiar a mano.

Límites honestos: el plugin escribe ficheros, **no** edita el `.xcodeproj` (los proyectos con carpetas sincronizadas de Xcode 16 los recogen solos; los antiguos requieren arrastrar la carpeta) ni añade el `case` al `enum AppRoute` (lo imprime como paso siguiente). Un `swift package archinit` inicial crea `.archlint.yml`, `Features/`, `AGENTS.md` y el snippet de `CLAUDE.md`.

## 4. Obligar: `ArchitectureLint`, build-tool plugin que viaja en el SPM

Un **build-tool plugin** (`Plugins/ArchitectureLint` + `executableTarget archlint`) que el consumidor añade a su target:

```swift
// Package.swift del consumidor, o Xcode: Build Phases → Run Build Tool Plug-ins → ArchitectureLint
.target(name: "MiApp", dependencies: [...], plugins: [.plugin(name: "ArchitectureLint", package: "AppFoundation")])
```
Recibe los `sourceFiles` del target, aplica las reglas de §1 y emite diagnósticos con formato `ruta:línea:col: error: [ArchLint.R1] …` → **el build falla**. Configuración por `.archlint.yml` en la raíz del target (sufijos `ViewModel/Logic/Service/Store`, imports permitidos por capa, reglas desactivadas, carpetas ignoradas, `strict: true` para exigir `LogicViewModel`). El mismo ejecutable se expone como command plugin (`swift package archlint`) para CI sin integrar el build.

Implementación: análisis léxico propio (identificadores, `import`, `class/struct/protocol … : …`, ignorando comentarios y strings), sin SwiftSyntax en la v1: cero dependencias y compila en segundos. SwiftSyntax queda como v2 si las reglas necesitan semántica (p. ej. "el `init` de un ViewModel solo acepta protocolos").

Esto es lo único que **obliga**: un agente puede ignorar un README, no un error de build. Combinado con el generador (camino fácil) y `AGENTS.md` (contexto), cubre las tres capas.

## 5. Para los agentes

- `AGENTS.md` en cada paquete: la arquitectura de §1 en 60 líneas, los comandos del generador y del linter, y «qué NO hacer». Claude Code y Cursor lo leen si está en el árbol del proyecto; el `archinit` lo copia a la raíz de la app y añade a `CLAUDE.md` una línea `@AGENTS.md`.
- Skill de Claude Code (`.claude/skills/feature.md`, instalada por `archinit`): `/feature Login --api` ejecuta el generador y recuerda las reglas.

## 6. Documentación dentro de cada SPM

- `Sources/<Target>/Documentation.docc/` con artículos: `GettingStarted` (20 minutos), uno por pieza, `Architecture` (§1 con las 4 variantes), `Recipes`, `Testing`. Xcode los muestra en «Build Documentation».
- `Snippets/` en la raíz del paquete: SwiftPM los **compila** y DocC los embebe con `@Snippet(path:)`; los ejemplos de la documentación no pueden quedarse obsoletos.
- `README.md` corto (qué es, instalación, enlace a DocC/GettingStarted), `CHANGELOG.md` y `AGENTS.md` por paquete; `Examples/` por paquete, autocontenido. El ejemplo cruzado vive en `AppFoundation/Examples/AppWithAPI` dependiendo de CoreNetworking por URL + tag (y `path:` solo en CI del monorepo mediante `swift package edit`/override).

## 7. Plan

| PRD | Contenido | Depende de |
|---|---|---|
| AF-07 | Kit: `Logic`, `LogicViewModel`, `AppFoundationTestSupport` con `InMemoryStore`, `EndpointService` en CoreNetworking, cuatro ejemplos de variante (`Examples/`), `AGENTS.md` | — |
| AF-08 | Plugins: `GenerateFeature` (command), `ArchitectureLint` (build-tool + command), `archinit`, plantillas, tests de los plugins | AF-07 (formas) |
| X-03 v2 | Docs dentro de cada SPM: DocC + Snippets + README/CHANGELOG por paquete; cierre 1.0.0 | AF-07, AF-08 |

## 8. Mejoras adoptadas sobre la arquitectura base (2026-09-02, con el visto bueno de abrir mejoras)

Cada una cierra un hueco concreto que la arquitectura View → ViewModel → Logic → Services/Stores deja abierto. Todas se aplican en los ejemplos (AF-07), en las plantillas y en el linter (AF-08) y en la documentación (X-03).

| # | Mejora | Por qué | Dónde se hace cumplir |
|---|---|---|---|
| M1 | **Errores de dominio entre capas.** Un Service lanza `APIError`; la Logic lo traduce a un error de dominio del feature (`LoginError.invalidCredentials`, `.offline`, `.unknown(underlying:)`) que conforma `DomainError` (= `Error & AppErrorConvertible & Sendable`, nuevo en AppFoundation, con `isRetryable`). El ViewModel y el presenter nunca ven `APIError`. | Sin esto, el copy de error acaba dependiendo de la red en la capa de UI, y una app sin API tiene un camino distinto. Con `DomainError`, `ErrorPresenting` funciona igual para las cuatro variantes. | Lint R7: `*ViewModel.swift`/`*View.swift` no referencian `APIError`; `*Logic.swift` sí puede (`import CoreNetworking` permitido solo en Logic y Services). |
| M2 | **Modelos por capa.** DTOs (`Decodable`, `BaseRequest.Response`) viven en el Service y se mapean a modelos de dominio (structs `Sendable`/`Equatable`) antes de salir; la Logic trabaja y devuelve dominio; el ViewModel expone estado de vista. | Un cambio en el JSON no debe tocar ni Logic ni View. | Lint R8: `*ViewModel.swift`/`*View.swift`/`*Logic.swift` no referencian tipos `*Request`, `*Response`, `*DTO`. |
| M3 | **Navegación solo desde el ViewModel.** La Logic no conoce `Router`/`Coordinator`; devuelve resultados y el ViewModel decide a dónde ir. | Navegación es orquestación, no negocio; y así la Logic se testea sin SwiftUI ni rutas. | Lint R9: `*Logic.swift`/`*Service.swift`/`*Store.swift` no referencian `Router`, `Coordinator`, `DeepLink`. |
| M4 | **Composition root único.** Cada feature tiene su `XxxModule: DependencyModule` que registra Store, Service, Logic por protocolo; los ViewModels se construyen en el `CoordinatorView` (o en una `XxxFactory`) resolviendo del contenedor. Ninguna capa llama a `Container.shared` por su cuenta; `@Inject` queda para casos hoja documentados. | Es lo que hace la inyección 100 % por `init` real y no "por `init` salvo cuando molesta". | Lint R10: `Container.shared`/`.resolve(`/`@Inject` prohibidos en `*ViewModel/*Logic/*Service/*Store.swift`. |
| M5 | **Aislamiento por capa, explícito.** ViewModel: `@MainActor` (ya). Logic: `nonisolated`, métodos `async`; con `NonisolatedNonsendingByDefault` corren en el actor del llamador, así que trabajo CPU-pesado va con `@concurrent`. Service: `struct Sendable`. Store: `actor` (o `@ModelActor` con SwiftData). | Es la respuesta a "cuándo usar un actor" aplicada a la arquitectura: el único estado compartido real está en los Stores. | Plantillas del generador; `AGENTS.md`; lint R11 (aviso, no error): `*Logic.swift` con `@MainActor` en su tipo. |
| M6 | **Estado transversal como Store.** Sesión/usuario actual, feature flags, preferencias: `SessionStore: SessionStoring` inyectado en las Logic que lo necesiten. Nada de singletons globales. Logout global al 401: `TokenRefreshRetrier` falla → `SessionStore.invalidate()` a través de un `SessionExpiring` protocolo que la app implementa; el `CoordinatorView` observa la sesión y hace `setRoot(.login)`. | Es el caso que todas las apps con login acaban necesitando y suele resolverse con un `NotificationCenter` global. | Ejemplo `LoginApp`; receta en docs. |
| M7 | **Contrato de cache-then-network fijado.** `CatalogLogic`: devuelve lo local si existe, lanza la red, persiste y re-emite; los errores de red con caché válida son un banner, sin caché son fase de error. El ViewModel lo recibe como `AsyncStream<[Item]>` o dos llamadas explícitas; se elige **dos llamadas** (`cached()` + `refresh()`) por simplicidad y testabilidad. | Evita que cada app invente su política. | Ejemplo `CatalogApp`; plantilla `--api --local`. |
| M8 | **Feature como módulo (opt-in).** `generate-feature Login --api --module` crea dos targets locales: `LoginCore` (Logic, Services, Stores, dominio; depende de CoreNetworking) y `LoginUI` (View, ViewModel; depende de AppFoundation y `LoginCore`). La dirección de dependencias queda impuesta por el compilador (`LoginCore` no puede ver el ViewModel) y `internal` esconde el resto. Por defecto, carpetas. | Es el único mecanismo que hace cumplir la dirección de dependencias sin linter; se ofrece a quien tenga apps grandes. | Generador; lint sigue aplicando dentro de cada target. |
| M9 | **Previews y spies generados.** Cada View generada tiene `#Preview` con `XxxLogicMock`; cada protocolo generado tiene su mock con contadores de llamadas y argumentos grabados; los tests generados cubren VM (spy de Logic), Logic (mocks de Service/Store) y Service (`MockAPIService`). | Testeable al 100 % desde el minuto cero, sin escribir un mock a mano. | Generador. |
| M10 | **Observabilidad de negocio.** `Analytics`/`EventTracking` como protocolo inyectado en la Logic (eventos de negocio), nunca en la View ni en el ViewModel. | Cuando llega el requisito de analítica, no se cuela en la capa de UI. | Plantilla opcional `--analytics`; receta. |

Lo que se mantiene tal cual porque ya es correcto: un `Logic` por feature/pantalla con protocolo, Services por llamada, Stores para lo local, DI por `init` y por protocolo, `Action` única en el ViewModel, `ScreenContainer` como cáscara.
