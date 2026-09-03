# PRD-X-05 — 1.0.1 de AppFoundation a partir de las fricciones de AppStarter

Origen: `AppStarter/docs/INFORME-INTEGRACION.md` y `docs/ISSUES.md` (2026-09-03), contrastados por el doble check. CoreNetworking no necesita cambios. Rompe API pública: no.

## Verificado en el doble check

| # | Fricción reportada | Veredicto tras contrastar | Acción |
|---|---|---|---|
| 2 | `swift package archlint` sin `--path` analiza `.build/checkouts` | **Bug del kit, confirmado**: `Config.swift` trae `**/.build/**` y `**/.swiftpm/**` como ignorados por defecto, pero un `ignore:` explícito los **reemplaza**, y el `.archlint.yml` que escribe `archinit` solo lista `Tests/**` y `**/Mocks/**`. | A1 |
| 4 | `defaultIsolation(MainActor)` + conformidad inline rompe el `init` de un `actor` | **Confirmado, causa precisada** con 9 variantes: no es `InferIsolatedConformances` (falla igual sin ella) ni el protocolo (con un `String` compila). Es `defaultIsolation(MainActor)` + conformidad `Sendable` inline + una **propiedad almacenada no-Sendable** (`UserDefaults`) asignada en el `init`. `nonisolated init` no está permitido en actores; la conformidad en `extension` compila. Las plantillas del generador no lo sufren (`@ModelActor`, valores `Sendable`). | A2 |
| 10 | `.onAppear` no siempre se dispara tras un push con `chrome: .custom` | **Plausible, no reproducido aquí**; `.task` es mejor práctica en cualquier caso (se cancela con la vista) y la plantilla `View.swift.txt` aún usa `.onAppear`. | A3 + investigación |
| 3 | `generate-feature` no reutiliza un Service/Store de otra feature | Limitación real del generador (documentada). | A4 |
| 1, 5, 6, 7, 9, 11 | Estructura «paquete local + app cáscara», `-skipPackagePluginValidation`, productos transitivos en `project.yml`, xcodegen y test targets de paquetes, variables de entorno en XCUITest, diálogo de guardar contraseña | Comportamientos de Xcode/xcodegen/simulador, no del kit. Van a documentación. | A5 |
| 8 | `.accessibilityIdentifier` en contenedor pisa a los hijos | Comportamiento de SwiftUI. | A5 |
| CI | El runner de GitHub arranca con un Xcode cuyo `swift-tools` < 6.2 | Real para cualquier consumidor. | A5 |

## Acciones (AppFoundation 1.0.1)

- **A1 · `archlint` nunca entra en `.build`/`.swiftpm`/`DerivedData`**: en `Config.swift`, separar una lista fija `alwaysIgnore` (`**/.build/**`, `**/.swiftpm/**`, `**/DerivedData/**`, `**/.git/**`) que se aplica siempre, independientemente del `ignore:` del usuario; `archinit` la menciona en el comentario del `.archlint.yml`. Test: un `ignore:` explícito de solo `Tests/**` sigue sin analizar `.build/checkouts`. `ArchitectureLint` (build-tool) ya recibe solo `sourceFiles` del target; comprobar que el command plugin sin `--path` da 0 en AppStarterKit.
- **A2 · Guía de actores con dependencias no-Sendable**: en `AGENTS.md` y `Architecture.md`: «Un `actor` que recibe por `init` un valor no-Sendable (`UserDefaults`, `FileManager`, un cliente de Keychain) y conforma inline a su `*Storing: Sendable` no compila bajo `defaultIsolation(MainActor)`; declara la conformidad en una `extension` (o inyecta un valor `Sendable`)». Añadir a `Examples/NotesApp` o `CatalogApp` un Store con `UserDefaults` que muestre el patrón, con test. Reportar aguas arriba con el repro mínimo (`docs/repros/actor-inline-conformance.md`).
- **A3 · La View es dueña de su ViewModel con `@State`**: en `Templates/View.swift.txt`, los cuatro ejemplos y los snippets de DocC, `@State private var viewModel: {{Name}}ViewModel` + `_viewModel = State(initialValue: viewModel)` en el `init`, en vez de `let viewModel`. Causa raíz confirmada en AppStarter (fricción 10 del informe, con trazas `os_log`): un ViewModel transitorio construido en el builder de destino de navegación se sustituye cuando SwiftUI reejecuta el builder durante el push; la instancia que recibió `.load` muere (`performLoad` captura `[weak self]`, sin error) y la que queda en pantalla nunca lo recibe. `.task` frente a `.onAppear` no era la causa: ambos se disparan por identidad de vista, no por instancia. Documentar la regla en `AGENTS.md` y `Architecture.md` («el composition root construye el ViewModel; la View lo retiene con `@State`»).
- **A4 · `generate-feature --no-service` / `--no-store`** (y `--service-from <Feature>` / `--store-from <Feature>` que inyecta el protocolo existente): la Logic generada recibe `any <Feature>Servicing` del feature indicado y no se genera un Service/Store nuevo; tests del motor de plantillas + `Scripts/verify-generator.sh` con un caso de reutilización.
- **A5 · Documentación de integración desde Xcode** (`GettingStarted.md` + README de AppFoundation, sección «Desde un proyecto Xcode»): patrón paquete local + app cáscara (con `project.yml` de ejemplo), `-skipPackagePluginValidation` en CI, declarar los paquetes transitivos en el target de la app, xcodegen y test targets de paquetes (`swift test` aparte), `.accessibilityIdentifier` solo en hojas, variables de entorno horneadas en el scheme para XCUITest, desactivar `.textContentType(.password)` bajo XCUITest, y en la sección CI: seleccionar un Xcode con `swift-tools` ≥ 6.2 en el runner (snippet del workflow de AppStarter).
- **A6 · Enlace desde ambos README a AppStarter** como app de referencia y plantilla de arranque.
- **A7 · Ninguna acción se pierde en silencio**: en `ScreenState.sender` (`ActionSender`) y en los `guard let self else { throw CancellationError() }` de `performLoad`/`performActivity`, emitir en `DEBUG` un `os_log` de nivel `error` («acción X descartada: el ViewModel ya no existe») con `assertionFailure` opcional. En AppStarter esa línea habría convertido horas de diagnóstico en un minuto. Valorar una regla R12 del linter que marque `let viewModel:` en un `*View.swift`.

## Criterios de aceptación
- [x] En AppStarterKit (clon limpio, dependencias resueltas), `swift package archlint` sin `--path` → 0 errores.
- [x] Ejemplo con Store sobre `UserDefaults` compila y su test pasa; repro documentado.
- [x] `grep -rn "onAppear" AppFoundation/Templates AppFoundation/Examples/*/Sources` vacío; verificación de A3 documentada (reproducido o no, con el procedimiento).
- [x] `generate-feature Detail --api --service-from Products` genera Logic que compila contra `ProductsServicing`; `Scripts/verify-generator.sh` lo cubre.
- [x] `GettingStarted.md` tiene la sección «Desde un proyecto Xcode»; READMEs enlazan a AppStarter.
- [x] Verificación completa del paquete (build estricto, tests, lint, iOS, docbuild limpio) y tag `1.0.1` tras CI verde.

## Ejecución (2026-09-03)

Tres agentes en paralelo (A: A1+A4+R12 · B: A3+A7 · C: A2+A5+A6 y prosa), integrados en `main` sin conflictos.
Evidencia sobre `main` integrado, medida por el orquestador:

| Comprobación | Resultado |
|---|---|
| `swift format lint --strict` (Sources, Tests, Examples, Plugins, Snippets) | limpio |
| `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` | Build complete |
| `swift test --parallel` | 274 tests, 35 suites, 0 fallos |
| Ejemplos (`swift test`) | Counter 6 · Notes 17 · Login 12 · Catalog 15, todos en verde |
| `Scripts/check-doc-snippets.sh` | 16 bloques OK |
| `Scripts/verify-generator.sh` (4 variantes + `Detail --api --service-from Products`) | Todo verde |
| `xcodebuild build` iOS Simulator | sin errores |
| `xcodebuild docbuild` iOS Simulator y macOS, DerivedData limpio | 0 warnings, SUCCEEDED en ambos |
| `archlint` (binario 1.0.1) sobre AppStarterKit sin `--path`, con `.build` presente | 0 errores, 0 avisos, 37 ficheros |
| `grep -rn onAppear Templates Examples/*/Sources` | vacío |
