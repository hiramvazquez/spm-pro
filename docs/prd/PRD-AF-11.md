# PRD-AF-11 — 1.2.1 de AppFoundation a partir de la migración real de AppStarter a multi

Ámbito: AppFoundation · Origen: `AppStarter/docs/INFORME-MULTI.md` (Fase 1 de PRD-APP-02, 2026-09-04) · Rompe API pública: no

| # | Fricción (con repro en el informe) | Veredicto | Acción |
|---|---|---|---|
| 1 | `archinit --multi` escribe fuera del paquete (`Packages/Platform`, `App/`, raíz) y el sandbox lo impide; `--allow-writing-to-package-directory` no lo cubre. Error crudo `NSCocoaErrorDomain 513` | **Bug de UX.** SwiftPM no tiene permiso «escribe en el repo padre»: `--disable-sandbox` es la única vía | A1 |
| 2 | `archinit --multi` deja `AppRoute` en `App/`, pero cualquier app con navegación entre features lo necesita en `Domain` (una feature no puede importar `App`); al moverlo, se pierde el marker `// archinit:routes` | **Error de diseño**, confirmado: el caso común es el que no cubre | A2 |
| 3 | R3 exige el `protocol XxxServicing` en el mismo fichero que el Service; en multi el protocolo compartido vive en otro módulo (`Networking`) → falso positivo, R3 desactivada en Features | **Limitación real** del análisis por fichero | A3 |
| 4 | `swift-format` (`multiElementCollectionTrailingCommas: false`, el que instala `archinit`) borra la coma colgante antes de los markers; la siguiente inserción de `generate-feature` deja código que no compila | **Bug**: el editor de manifiestos depende de que la línea anterior termine en coma | A4 |
| 5 | En modo multi, `--service-from`/`--store-from` genera tests que usan el mock de la otra feature, que no es visible desde el test target nuevo (cada feature tiene el suyo) | **Limitación conocida** (informe del agente B de AF-10) | A5 |
| 6 | `NetworkingModule`/target `Networking` (wiring del `APIService` autenticado, protocolos con `throws(APIError)`) no lo genera el kit: hubo que crearlo a mano | Falta en la plantilla multi para apps con API | A6 |

| 0 | **`@Observable` no se hereda**: `BaseViewModel` es `@Observable`, pero el macro solo instrumenta las propiedades declaradas EN esa clase. Los ViewModels generados (`Templates/ViewModel.swift.txt`, los ejemplos, las docs) NO llevan `@Observable`, así que sus propiedades propias (`items`, `results`…) no se observan: la vista solo se refresca cuando cambia `phase`/`activity` de la base, por coincidencia. Confirmado en AppStarter con un contador de renders (`INFORME-MULTI.md` §11) | **Bug del kit, grave y silencioso** | A0 |

| 8 | **`deinit` aislado sintetizado + shim de back-deploy**: en iOS 26.2 (CI, Xcode 26.3) dos `deinit` aislados anidados (ViewModel → `Coordinator`) abortan con double free en `swift_task_deinitOnExecutorMainActorBackDeploy`. Toda clase `@MainActor` sin `deinit` explícito lo sufre | **Bug grave** (posible crash en producción en iOS < runtime del toolchain) | A8 (publicada como 1.2.2) |

## Acciones (AppFoundation 1.2.1)

- **A8 · `deinit {}` explícito en toda clase `@MainActor`** (1.2.2 + 1.2.3): kit, plantilla, ejemplos,
  snippets, `AGENTS.md`; repro en `docs/repros/isolated-deinit-backdeploy.md`. 1.2.2 cubrió `Coordinator`
  y compañía y el abort se movió a `Throttler`; 1.2.3 añade su `deinit` y la **regla R16** (error:
  toda clase no `nonisolated` declara `deinit`). Confirmado en el CI de AppStarter (iOS 26.2): el job de
  la app pasa (`main` `7308a03`). Pendiente: reporte aguas arriba.

- **A0 · `@Observable` en cada ViewModel** (prioridad máxima): `Templates/ViewModel.swift.txt`, los cuatro ejemplos, los snippets y los artículos (`ScreenStateAndViewModels`, `Architecture`, `GettingStarted`, `Theming`) declaran `@Observable final class XxxViewModel: LogicViewModel<…>`; `AGENTS.md` lo dice en el bullet del ViewModel («`@Observable` no se hereda: cada ViewModel lo declara»). Regla **R15** de `archlint` (error): una `class` cuyo nombre termina en `ViewModel` y declara propiedades almacenadas debe llevar `@Observable`. Test de regresión en AppFoundation: una subclase sin el macro no notifica cambios de su propiedad (usando `withObservationTracking`), y la misma con el macro sí. Verificar que aplicar el macro en subclase e hija no duplica registradores ni rompe `phase` (el informe dice que funciona; medirlo en test).

- **A1 · Sandbox explícito**: `Scripts/bootstrap-multi.sh` pasa `--disable-sandbox` siempre (con el porqué en el script); `archinit --multi` detecta `NSCocoaErrorDomain 513`/`EPERM` al escribir fuera del paquete y falla con un mensaje que dice exactamente qué flag añadir; la guía (`MultiModule.md`) muestra el comando completo con el flag.
- **A2 · `AppRoute` en `Domain` por defecto**: `archinit --multi` genera `Packages/Platform/Sources/Domain/AppRoute.swift` (con el marker `// archinit:routes`) y `App/RootView.swift` lo importa de `Domain`; `generate-feature` busca el marker primero en `Domain` y después en `App/` (compatibilidad con repos ya generados). Flag `--routes-in-app` para el caso raro contrario. `verify-multi.sh` lo cubre: una feature navega a otra por `AppRoute` y R13 sigue en 0.
- **A3 · R3 consciente de módulos**: R3 acepta el `protocol XxxServicing`/`XxxStoring` declarado en otro fichero del mismo target o en cualquier módulo que el fichero importa (misma resolución cross-módulo que R13: el command plugin ve el paquete entero; el build-tool plugin, solo su target, así que ahí se degrada a «mismo target» y lo dice en el mensaje). AppStarter vuelve a activar R3.
- **A4 · Inserción robusta**: `ManifestEditor.insertBeforeMarker`/`insertBetweenMarkers` garantizan la coma: si la línea anterior no vacía no termina en `,` (ni es el marker de inicio ni un `[`/`(`), se la añaden antes de insertar. Test con el fixture «tras swift-format». Además, `.swift-format` que instala `archinit` no cambia (es el criterio del kit); la robustez va en el editor.
- **A5 · Mocks compartidos en multi**: cuando `--service-from`/`--store-from` se usa en modo multi, el generador escribe el mock reutilizado en un target `PlatformTestSupport` (lo crea en `Packages/Platform` si no existe, con su producto) y lo añade como dependencia del test target nuevo; documentado en `Generator.md`. Alternativa mínima si no cabe: generar el mock duplicado en el test target nuevo con un comentario.
- **A6 · Target `Networking` en la plantilla multi** (`--api` en `archinit --multi`, o siempre que la app consuma CoreNetworking): `Packages/Platform/Sources/Networking` con `NetworkingModule` (configuración, transporte, `APIService` autenticado con `BearerTokenInterceptor` + `TokenRefreshRetrier`, `SessionStoring` en Domain) tomado del wiring real de AppStarter, más su entrada en `modules:` (`Networking` puede importar CoreNetworking y Domain; prohibidos features, Kits y Adapters). `generate-feature --api` en multi depende de `Networking` para el `APIServiceProtocol`.
- **A7 · `PlatformTestSupport` de serie**: `archinit --multi` crea el target (vacío, con `InMemoryAnalytics` si hay `--adapter` y los spies de los protocolos de Domain) para que A5 tenga dónde escribir.

## Criterios de aceptación
- [ ] `verify-multi.sh` cubre: arranque sin `--disable-sandbox` a mano (el script lo pone), `AppRoute` en Domain con navegación cruzada, `Networking` generado y una feature `--api` que lo usa, `--service-from` en multi con tests en verde, y una inserción tras `swift format format -i` que compila.
- [ ] AppStarter (rama `multi`) actualizado a 1.2.1: R3 activada, `AppRoute` donde lo deja el kit, sin workarounds propios.
- [ ] Verificación completa del paquete y tag `1.2.1` tras CI verde.

## Ejecución

- **A8 publicada como 1.2.2/1.2.3** (2026-09-04): ver arriba.
- **A0 publicada como 1.2.1** (2026-09-04, `main` de AppFoundation `1482cb9`): `@Observable` en
  plantilla, ejemplos, snippets, artículos, README y `AGENTS.md`; regla R15 (error) con fixture y
  tests; `ObservationInheritanceTests` mide el fallo y la corrección con `withObservationTracking`.
  Verificación completa en verde (336 tests, generador, `verify-multi`, DocC sin warnings).
- **A1–A7 pendientes** → siguiente versión (1.3.0), junto con lo que salga de las Fases 2 y 3 de
  PRD-APP-02.
