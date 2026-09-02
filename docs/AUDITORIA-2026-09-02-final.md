# Doble check final y puntuación — AppFoundation + CoreNetworking 1.0.0

Fecha: 2026-09-02 · Base: `main` (`b7e4e21`), 173 commits, 20 PRD integrados (CN-01…07, AF-01…08, X-01…04) · Alcance acordado: seguridad avanzada fuera (SSL pinning básico y correcto dentro).

## 0. Puntuación

| | Inicio (09-01) | Doble check (09-02) | **Final** |
|---|---|---|---|
| CoreNetworking | 7 / 10 | 9 / 10 | **10 / 10** |
| AppFoundation | 6 / 10 | 9 / 10 | **10 / 10** (con una condición, ver §3) |
| Kit de arquitectura + plugins (nuevo) | — | — | **9 / 10** |

Criterio de 10 (definido el 09-01): cero defectos conocidos, API extensible sin roturas, concurrencia garantizada por el compilador, sin fugas demostrables, tests deterministas en paralelo, CI verde en macOS e iOS, documentación que compila, y un integrador que puede adoptar ambos paquetes sin tocar tipos de red desde los ViewModels. Todo eso está, verificado hoy sobre `main`:

| Verificación | Resultado |
|---|---|
| `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` | 0 warnings en ambos |
| `swift test --parallel` | AppFoundation 261 · CoreNetworking 138 |
| Ejemplos (`swift test`) | Counter 6 · Notes 13 · Login 12 · Catalog 15 · APIClient 4 |
| `swift format lint --strict` | 0 en Sources, Tests, Examples, Plugins, Snippets |
| `xcodebuild build` iOS Simulator | ambos schemes OK |
| `xcodebuild docbuild` (DerivedData limpia, iOS y macOS) | 0 warnings en los cuatro |
| `Scripts/check-doc-snippets.sh` | 29 bloques sincronizados con `Snippets/` |
| `git subtree split` por paquete | README, CHANGELOG, LICENSE, AGENTS, DocC, Snippets, Examples (+ Plugins/Templates) dentro |
| Generador y linter, probados por mí en un paquete consumidor temporal | `Login --api` y `Notes --local` compilan y pasan tests; violación R1 provocada → build falla con `[ArchLint.R1]`/`[ArchLint.R7]` en fichero:línea |
| Ramas `prd/*` sin mergear | ninguna |

## 1. Qué encontró el doble check final (y ya está corregido en `main`)

| Commit | Hallazgo |
|---|---|
| `f13faee` | El generador se negaba en un paquete recién creado (target de tests declarado pero sin ficheros: SwiftPM no lo lista). Es justo el primer uso. Ahora cae a `Tests/<Target>Tests/` y avisa. |
| `b89ffa5` | La instalación documentada apuntaba al monorepo (`spm-pro.git`), que no se puede consumir por URL (no hay `Package.swift` en la raíz). Ahora apunta al repo de cada paquete. `LICENSE` copiado dentro de cada SPM (el enlace `../LICENSE` no sobrevivía al split). Referencias a PRD en la doc que viaja, eliminadas. |
| `7ab883d` | El código generado y los plugins citaban `ARQUITECTURA-KIT-…md` y PRDs, documentos del monorepo que no existen en la app del integrador. |
| `7fb7c5a` | Parámetros sin documentar en dos `init` (warnings de DocC), un enlace DocC roto, 7 avisos de lint en snippets y en el ejemplo de CoreNetworking. |
| X-04 (`b7e4e21`) | `@Snippet` de DocC no se resolvía en el primer «Build Documentation» con DerivedData limpia (16 warnings) y sí en el segundo. Sustituidos por bloques en línea sincronizados con `Snippets/` por CI; `docbuild` limpio a la primera. |
| `65c1a27`, `f592a2c` | Formato residual que dos agentes reportaron como «lint 0» sin serlo. |

Patrón a recordar: tres agentes distintos reportaron «lint 0» o «docbuild sin warnings» sin haberlo medido en las condiciones exigidas. El CI ahora lo mide en frío (checkout limpio, DerivedData nueva, `--strict`), que es la única lectura fiable.

## 2. CoreNetworking — 10 / 10

Sin hallazgos abiertos. Lo que sostiene la nota: `struct APIError` extensible con `Code`, `category` (incluido `.unreachable`), `decodeBody` y `LocalizedError`; transporte inyectable con delegate por tarea (pinning ≡ `.untrustedServer`, nunca `.cancelled`, con test e2e); `upload(_:) -> Request.Response`, `data(for:)`, `download(_:to:)` por el pipeline con retry; `RequestRetrier` + `TokenRefresher` (deduplicación probada sin `sleep`); `Clock` inyectable; `InMemoryTransport`/`ManualClock`/`MockAPIService` tipado con `Code.unstubbed`; `EndpointService`; `NSPinnedDomains` documentado como opción por defecto y pinning programático con ≥ 2 pins; DocC con 12 artículos y 10 snippets compilados; `AGENTS.md`; ejemplo `APIClientApp`.

## 3. AppFoundation — 10 / 10 con una condición

Sin hallazgos abiertos en código. La condición es la que no puedo cerrar desde aquí: la **verificación manual en simulador/dispositivo** de swipe-back con `chrome: .custom`, VoiceOver en atrás/cerrar y Dynamic Type XXL en la barra custom (procedimiento exacto en `docs/prd/CIERRE.md`). El código está y está cubierto por tests de lógica; el gesto y el lector de pantalla solo se comprueban con las manos. Hasta entonces, 9.5.

Lo que sostiene la nota: `performLoad { vm in … }` sin captura (fugas cubiertas por test), `load()/activity()` estructurados (bug corregido en el doble check anterior), `ErrorPresenting` + `DomainError`, `Container` `@MainActor` con detección de ciclos, `Debouncer`/`Throttler` `@MainActor`, `ScreenState` + `ActionHandling` + `ActionSender` débil, `ScreenChrome.native` por defecto con `PopGestureEnabler`, estilos por `Environment`, `inFlightLoad` para tests sin polling, `.xcstrings`, DocC con 14 artículos y 15 snippets, `AGENTS.md`, cuatro ejemplos de variante.

## 4. Kit de arquitectura + plugins — 9 / 10

Funciona de extremo a extremo (probado por mí, no solo por el agente): `generate-feature` en sus cuatro variantes produce código que compila y pasa tests desde el primer segundo; `ArchitectureLint` hace fallar el build con diagnósticos navegables; `archinit` deja `.archlint.yml`, `AGENTS.md`, `CLAUDE.md` y la skill. Lo que le falta para el 10, y por qué no se ha hecho ya:

- **`--module` no crea targets reales** (imprime el snippet para `Package.swift`). Editar el manifiesto del consumidor desde un plugin es frágil; conviene esperar a ver si de verdad se usa.
- **El linter es léxico** (sufijos de fichero, identificadores). Cubre R1-R11 con precisión suficiente para los ejemplos y los casos provocados, pero un `typealias` ingenioso lo esquiva. SwiftSyntax en una v2 si aparece la necesidad.
- **El generador no edita `AppRoute` ni el `.xcodeproj`**; imprime los dos pasos. Con carpetas sincronizadas de Xcode 16 el segundo desaparece.
- Falta uso real: la primera app que lo adopte dirá qué regla molesta y qué plantilla sobra.

## 5. Mejoras adoptadas sobre la arquitectura base (recordatorio)

M1 errores de dominio (`DomainError`) · M2 DTO → dominio en el Service · M3 navegación solo en el ViewModel · M4 composition root único (`XxxModule`) · M5 aislamiento por capa (Logic `nonisolated`, Store `actor`/`@ModelActor`, Service `struct Sendable`) · M6 `SessionStore` + logout global al 401 · M7 cache-then-network con `cached()`/`refresh()` · M8 `--module` opt-in · M9 previews y spies generados · M10 analítica como protocolo en la Logic. Todas aplicadas en los cuatro ejemplos, las plantillas y las reglas R7-R11.

## 6. Para el tag 1.0.0 (checklist del propietario)

1. Verificación manual AF-12/AF-13 en simulador (procedimiento en `docs/prd/CIERRE.md`).
2. Confirmar el último tag de AppFoundation en su remoto (no configurado en este clon).
3. Publicar: `git subtree split --prefix=CoreNetworking -b cn-only` → push → `git tag -a 1.0.0 cn-only` → push del tag; ídem `AppFoundation`/`af-only`. Nunca en `main`.
4. Un consumidor de prueba por URL + `from: "1.0.0"` con los tres productos (`AppFoundation`, `CoreNetworking`, `CoreNetworkingTestSupport`) y `AppFoundationTestSupport`.
5. `swift package archinit` + `generate-feature` en la primera app real; anotar fricciones para la 1.1.
6. Primer push a GitHub para ver el CI en verde de verdad (aquí no hay `act`).

## 7. Lo que cambió desde el 1 de septiembre, en una línea

43 hallazgos resueltos, 2 críticos con test extremo a extremo, 20 PRD ejecutados por agentes y verificados uno a uno, 5 bugs encontrados en los dobles checks que los agentes no vieron, API 1.0 estable y extensible, y una arquitectura que ya no depende de que alguien la recuerde: la genera un comando y la vigila el compilador.
