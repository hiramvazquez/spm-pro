# Doble check — AppFoundation + CoreNetworking tras las oleadas 1-5

Fecha: 2026-09-02 · Base: `main` con los 13 PRD integrados (CN-01…06, AF-01…05, X-01, X-02) · Método: mismo que la auditoría del 2026-09-01 (lectura completa de Sources/Tests/Examples/README, build estricto, tests, verificación empírica de lo dudoso).

## 0. Veredicto

| | 2026-09-01 | Hoy | Objetivo |
|---|---|---|---|
| CoreNetworking | 7 / 10 | **9 / 10** | 10 con PRD-CN-07 + X-03 |
| AppFoundation | 6 / 10 | **9 / 10** | 10 con PRD-AF-06 + X-03 |

Los 43 hallazgos de la primera auditoría están resueltos (41 con test, 2 con fix aplicado y verificación manual pendiente en simulador: swipe-back y VoiceOver). Los dos críticos (pinning ≡ cancelled, fuga en `.error`) tienen test extremo a extremo. En esta relectura **no aparece ningún bug de corrección en CoreNetworking**; en AppFoundation apareció **uno** (corregido en `3463618`) y quedan pulidos de API y de documentación que son lo que separa el 9 del 10.

Verificado hoy en `main`: CoreNetworking 131 tests, AppFoundation 217, ejemplo 4; 0 warnings con `SWIFT_STRICT_WARNINGS=1`; `swift format lint --strict` en 0 en todo el repo (antes 803: X-02 lo midió sin `--strict`); iOS Simulator compila en ambos.

## 1. Corregido durante el doble check (ya en `main`)

| Commit | Qué |
|---|---|
| `5b4ff6d` | Flake real en la deduplicación de refresh: los tests forzaban el solape con `sleep(20 ms)`. Ahora `TokenRefresher.joinedInFlightCount` permite esperar al solape observado. 8/8 verdes. |
| `da1f5cd`, `e0ba9ce` | Lint estricto en 0: reglas ajustadas (`public extension`, `@_disfavoredOverload`, doc-comments en prosa) y formato aplicado. CI ya no rompe en el primer push. |
| `3463618` | **Bug**: `load()`/`activity()` (variantes estructuradas de AF-01) no ponían `phase = .loading` / `activity = .loading` antes de ejecutar el trabajo. Con `.task { await vm.load { … } }` la pantalla nunca mostraba el indicador. Test de regresión `StructuredLoadTests`. |

## 2. CoreNetworking — hallazgos del doble check

| ID | Sev. | Hallazgo | Dónde |
|---|---|---|---|
| DC-CN-1 | Medio | `upload(request:data:progress:) -> Response` infiere el tipo en el call-site y usa label `request:`; el resto de la API es `execute(_:) -> Request.Response`. Alinear: `upload(_:data:progress:) -> Request.Response`. | `APIServiceProtocol.swift:47` |
| DC-CN-2 | Medio | `download(_:to:)` duplica el pipeline (interceptores, `catch` de pinning, status) fuera de `performOnce` "para no tocar la región de CN-06", restricción que ya no existe. Unificar vía `performWithRetry` (cada intento reescribe el destino atómicamente, así que el retry es válido). | `APIService.swift:185-252` |
| DC-CN-3 | Bajo | `APIError.Category` sin `.unreachable`: `networkConnectionLost`, `cannotConnectToHost`, `dnsLookupFailed`, `cannotFindHost` caen en `.unknown` y la app no puede decir "no se pudo conectar". Añadir ahora (es `CaseIterable`/cerrado: hacerlo antes de 1.0). | `APIError.swift:215-245` |
| DC-CN-4 | Bajo | `MockAPIService` sin stub lanza `.invalidResponse`, que despista. TestSupport puede definir `APIError.Code.unstubbed` (el `Code` es abierto, para eso está). | `MockAPIService.swift:92-99` |
| DC-CN-5 | Bajo | Comentarios que citan PRDs como futuro: `APIService.upload` ("CN-04 lo cambia…"), `NetworkingConfiguration.defaultSessionConfiguration` ("NOTA (CN-03): hoy la construye APIService.init"), `Duration.timeInterval` ("ver CN-03 para migrarlo"). El código no debe hablar de PRDs. | varios |
| DC-CN-6 | Bajo | `NetworkingConfiguration.protocolClasses` convive con `sessionConfiguration`, que ya lo cubre. Deprecar el primero: una sola forma de hacerlo. | `NetworkingConfiguration.swift:42` |
| DC-CN-7 | Bajo | `Empty` sin `Equatable`; `RequestSummary.init(URLRequest)` cae a `.get` con un método desconocido. | `BaseRequest.swift:120`, `APIError.swift:95` |
| DC-CN-8 | Docs | README con 7 referencias históricas ("antes de CN-04…", "`TransportError` no existe: era…"). Para quien integra desde cero es ruido; la historia va al CHANGELOG. | `CoreNetworking/README.md` |

Bien (y verificado): `struct APIError` completo con `decodeBody`; transporte por tarea con pinning e2e; `upload(for:from:)` y progreso por chunks; `download` a disco con limpieza en non-2xx; `RequestRetrier` + `TokenRefresher` (actor justificado); `InMemoryTransport`/`ManualClock`; privacidad de logs; `Empty`/204; `waitsForConnectivity` y cookies fuera por defecto.

## 3. AppFoundation — hallazgos del doble check

| ID | Sev. | Hallazgo | Dónde |
|---|---|---|---|
| DC-AF-1 | Alto → corregido | `load()`/`activity()` sin `.loading` (ver §1). | `LoadableViewModel.swift` |
| DC-AF-2 | Medio | Tests deterministas sin polling: `handle(_:)` devuelve `Void`, así que el ejemplo y los tests de consumidores hacen `waitUntil { vm.phase == .content }` con `Task.sleep(10 ms)` en bucle. Exponer `inFlightLoad`/`inFlightActivity: Task<Void, Never>?` (solo lectura) en `BaseViewModel` para `await vm.inFlightLoad?.value`. | `BaseViewModel.swift:67-70`, `Examples/…/TestSupport.swift` |
| DC-AF-3 | Medio | `BaseViewModel.errorPresenter` / `cancellationRecognizer` / `clock` son `static var` mutables. Los tests los mutan (`ErrorPresentingTests` con `.serialized`), pero `.serialized` solo ordena dentro de la suite: otra suite en paralelo puede ver un presenter de mock. Riesgo de flake. Añadir inyección por instancia de `clock` y `cancellationRecognizer` (como ya tiene `errorPresenter`) y que los tests usen solo instancia; los estáticos quedan para la app. | `BaseViewModel.swift:86-100` |
| DC-AF-4 | Bajo | `BindingBackedState` y `ObservingScreenState` conforman `Observable` sin `@Observable`: funciona porque leen bindings/un `@Observable` envuelto durante `body`, pero es un contrato implícito. Documentarlo en el tipo o marcar `@Observable` donde aplique. | `ScreenContainer.swift:346-400` |
| DC-AF-5 | Bajo | `ErasedView` es `AnyView` con otro nombre en un único fichero (aceptable, documentado); `NavigationBarItemContent.view`, `NavigationBarTitle.custom`, `accessoryView`, `customContent` siguen borrando tipo. Con `.native` por defecto el impacto es bajo. | `UI/Styles/ErasedView.swift` |
| DC-AF-6 | Docs | El ejemplo de integración no tiene vista SwiftUI (`ScreenContainer(vm) { send in … }`): la pieza que un integrador copia primero. | `Examples/IntegrationExample` |
| DC-AF-7 | Docs | README de 806 líneas mezcla guía, racional de auditoría y notas de diseño. Falta una guía de integración lineal ("app nueva en 20 minutos") y una referencia por pieza con ejemplo completo. | `AppFoundation/README.md` |

Bien (y verificado): `performLoad { vm in … }` sin captura y con tests de fuga; `ErrorPresenting` con precedencia instancia > estático > default y fallback localizado; `Container` `@MainActor` con detección de ciclos; `Debouncer`/`Throttler` `@MainActor` con `ClockStopwatch` sobre `any Clock<Duration>`; `ScreenChrome.native` por defecto con `PopGestureEnabler` y a11y en la barra custom; `ScreenState` + `ActionHandling` + `ActionSender` débil; style protocols por `Environment`; `.xcstrings`.

## 4. Tags y publicación

El único tag del monorepo (`0.1.4`) vive en `cn-only`, el `subtree split` de CoreNetworking; `af-only` es el de AppFoundation. Los tags se crean **en las ramas split** (SwiftPM exige `Package.swift` en la raíz del repo consumido), nunca en `main`. Con las roturas de API de las oleadas 1-5, la versión que corresponde a ambos es **1.0.0**. Procedimiento por paquete:

```bash
git subtree split --prefix=CoreNetworking -b cn-only
git push <remoto-corenetworking> cn-only:main
git tag -a 1.0.0 cn-only -m "CoreNetworking 1.0.0" && git push <remoto-corenetworking> 1.0.0
# ídem AppFoundation / af-only
```

Falta confirmar el último tag de AppFoundation en su remoto (no configurado aquí).

## 5. Qué falta para el 10 (oleada 6)

- **PRD-CN-07** — pulido de CoreNetworking: DC-CN-1…7.
- **PRD-AF-06** — pulido de AppFoundation: DC-AF-2…5.
- **PRD-X-03** — documentación de integración en ambos paquetes: guía lineal, referencia por pieza con ejemplo completo y test que compila cada bloque, ejemplo con vista SwiftUI, sin historia en el README (va al CHANGELOG), y `CIERRE.md` cerrado con el procedimiento de tags correcto.

CN-07 y AF-06 corren en paralelo (paquetes distintos); X-03 después, sobre la API final.
