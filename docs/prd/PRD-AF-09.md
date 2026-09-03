# PRD-AF-09 — Calidad de código: SwiftLint curado, instalado por `archinit`

Ámbito: AppFoundation 1.1.0 · Origen: pregunta del propietario (2026-09-03) «¿un SPM que sea un linter general de Swift?» · Rompe API pública: no

## Decisión

No escribimos un linter general. `archlint` existe porque sus reglas (capas, nombres, `APIError`
fuera del ViewModel) no las conoce ninguna herramienta; su analizador es léxico a propósito y
basta para eso. Todo lo demás (`try!`, casts forzados, longitud de funciones y ficheros,
complejidad, capturas, opcionales implícitos) exige un parser real de Swift y años de depuración
de falsos positivos: eso es SwiftLint (SwiftSyntax, >200 reglas, severidad por regla, reglas
propias por regex, plugin de build para SwiftPM, versión de Swift detectada del toolchain).
Escribirlo de nuevo sería mantener un parser con cada versión de Swift para llegar peor.

Lo que sí es nuestro es el **criterio**: qué bloquea, qué avisa, con qué umbrales, y que se
instale en un paso. Dos capas complementarias:

| Capa | Herramienta | Valida | Quién la mantiene |
|---|---|---|---|
| Arquitectura | `archlint` / `ArchitectureLint` (AppFoundation) | DÓNDE está el código (R1-R12) | nosotros |
| Calidad | SwiftLint + `.swiftlint.yml` curado (AppFoundation lo instala) | CÓMO está escrito | SwiftLint; nosotros solo la configuración |
| Concurrencia y warnings | el compilador (`Swift 6`, `SWIFT_STRICT_WARNINGS=1`) | Sendable, aislamiento, data races | Apple |

Los ciclos de retención reales no los detecta ningún linter (análisis semántico entre ficheros);
las reglas cubren los patrones típicos (`weak_delegate`, `unowned_variable_capture`) y el resto
lo cazan los tests de fugas (`weak var` + `#expect(vm == nil)`, ver `Testing.md`).

## Entregables

1. **`Templates/swiftlint.yml`** — configuración curada, con comentario por regla explicando el
   porqué y la severidad. Umbrales calibrados contra AppStarter (código real generado por el kit
   y completado a mano) antes de fijarlos: ver «Calibración». Estructura:
   - `only_rules:` explícito (no `disabled_rules` sobre el default: así una versión nueva de
     SwiftLint no activa reglas sin que lo decidamos).
   - Bloquean (`severity: error`): `force_try`, `force_cast`, `force_unwrapping`,
     `implicitly_unwrapped_optional`, `unowned_variable_capture`, `weak_delegate`,
     `unhandled_throwing_task`, `self_in_property_initialization`, `private_swiftui_state`,
     `duplicate_imports`, `fatal_error_message`.
   - Avisan (`severity: warning`): `function_body_length`, `type_body_length`, `file_length`,
     `cyclomatic_complexity`, `line_length`, `large_tuple`, `function_parameter_count`,
     `nesting`, `todo`, `identifier_name`, `redundant_*`, `unused_*`.
   - `excluded:` `.build`, `.swiftpm`, `DerivedData`, `**/Mocks`, `Tests` solo para las reglas
     de longitud (usar `custom` por regla donde SwiftLint lo permite; si no, umbral más alto).
   - **Reglas propias** (`custom_rules`, regex) del equipo: `no_print_in_production`
     (`print(` fuera de tests → warning) y `os_log_public_interpolation` (`privacy: .public` →
     warning, exige justificación). La idea inicial `localized_text_literal` se descartó en la
     calibración: `Text("literal")` YA es `LocalizedStringKey`. Cada regla con test de que
     dispara y de que no.
   - `swiftlint_version:` mínimo, y nota: las reglas dependientes de versión de Swift las gestiona
     SwiftLint leyendo el toolchain; no reimplementamos detección.
2. **`archinit` copia `Templates/swiftlint.yml` como `.swiftlint.yml`** en la raíz del proyecto
   (si no existe; si existe, imprime el diff sugerido y no lo pisa), e imprime los dos pasos
   manuales: la dependencia `SwiftLintPlugins` y `.plugin(name: "SwiftLintBuildToolPlugin",
   package: "SwiftLintPlugins")` junto a `ArchitectureLint` en el target.
3. **`generate-feature`**: el código generado pasa el `.swiftlint.yml` curado sin avisos
   (`Scripts/verify-generator.sh` lo comprueba si `swiftlint` está en el PATH; si no, lo omite
   con aviso explícito). Los cuatro ejemplos también.
4. **Docs**: artículo `CodeQuality.md` en `Documentation.docc` (la tabla de tres capas, la
   configuración explicada, cómo subir o bajar un umbral, cómo añadir una regla regex, y por qué
   no hay linter propio), sección en `README.md`, bullet en `AGENTS.md` («Qué NO hacer» + Definition
   of Done con `swiftlint --strict`), `Lint.md` enlaza. `Templates/feature.skill.md` menciona el
   comando.
5. **CI de AppFoundation**: job `quality` que corre `swiftlint --strict` sobre `Examples/*/Sources`
   con la plantilla, para que la configuración curada nunca quede desalineada con el código que el
   kit genera.

## Calibración (hecha primero en AppStarter, antes de tocar AppFoundation)

Procedimiento, documentado con salidas reales en `AppStarter/docs/INFORME-CALIDAD.md`:
1. Línea base con las reglas por defecto de SwiftLint sobre `AppStarterKit/Sources` y `Tests`:
   conteo por regla.
2. Configuración curada propuesta; conteo por regla de nuevo. Cada aviso restante se clasifica
   como (a) código a mejorar → se corrige en AppStarter, (b) umbral demasiado estricto para código
   razonable → se ajusta y se anota el motivo, (c) falso positivo → `disabled` o `excluded` con
   justificación.
3. Resultado: `swiftlint --strict` en 0 sobre AppStarter, integrado en su `Package.swift`
   (plugin) y en su CI. Esa configuración final es la que pasa a `Templates/swiftlint.yml`.

## Verificación obligatoria
- AppStarter: `swift build` (el plugin corre en el build), `swiftlint --strict` 0, `swift test`
  48/48, `xcodebuild test` verde, CI verde.
- AppFoundation: `Scripts/verify-generator.sh` incluye SwiftLint; los cuatro ejemplos pasan
  `swiftlint --strict` con la plantilla; lint de formato, build estricto, tests, DocC limpio.
- Prueba negativa documentada: un `try!` en un ViewModel de AppStarter hace fallar `swift build`
  con `error: Force Try Violation` navegable en Xcode; se revierte.

## Fuera de alcance
- Reglas de analizador (`swiftlint analyze`, requieren log del compilador): se documentan como
  opcionales para CI, no se instalan por defecto.
- Formato: sigue siendo `swift-format` (`.swift-format` ya existe); SwiftLint no formatea aquí.

## Ficheros
`AppFoundation/Templates/swiftlint.yml`, `AppFoundation/Plugins/ArchInit/plugin.swift`,
`AppFoundation/Scripts/verify-generator.sh`, `AppFoundation/Sources/AppFoundation/Documentation.docc/CodeQuality.md`,
`AppFoundation/{README,AGENTS,CHANGELOG}.md`, `AppFoundation/.github/workflows/ci.yml`;
AppStarter: `AppStarterKit/{Package.swift,.swiftlint.yml}`, `.github/workflows/ci.yml`,
`docs/INFORME-CALIDAD.md`, `README.md`.

## Calibración ejecutada en AppStarter (2026-09-03)

Informe completo con salidas reales: `AppStarter/docs/INFORME-CALIDAD.md` (commit en `main` de
`hiramvazquez/AppStarter`). Resumen:

| Paso | Resultado |
|---|---|
| Línea base, reglas por defecto | 53 avisos; 29 son `identifier_name` sobre `c`/`vm`, los idioms del kit |
| Configuración curada, primera pasada | 63 avisos: 32 `async_without_await` (falso positivo estructural: el `async` viene del protocolo), 4 `closure_body_length` (bodies de SwiftUI), 4 de la regla propia de `Text` (premisa falsa), 16 `line_length`, 3 ternarios con Void, 3 `aspectRatio`, 1 `function_parameter_count` |
| Descartadas con motivo en el `.yml` | `async_without_await`, `closure_body_length`, `localized_text_literal` |
| Código corregido | ternarios → `if/else`; `.scaledToFit()`; 18 ficheros formateados con el `.swift-format` del kit; un nombre de test acortado |
| Excepción justificada | `makeAuthenticatedAPIService` (7 dependencias, composition root): `swiftlint:disable:next` con el motivo |
| Resultado | `swiftlint --strict` 0 · `archlint` 0/0 · `swift build` con ambos plugins · `swift test` 48/48 |
| Prueba negativa | `try!` en `ProfileViewModel` → `error: Force Try Violation (force_try)` y build fallido; revertido |

Conclusión para el kit: la configuración de `AppStarterKit/.swiftlint.yml` pasa a
`Templates/swiftlint.yml` sin cambios; los umbrales de tamaño/complejidad no se tensaron con este
código y quedan en los valores propuestos.

## Ejecución en AppFoundation (2026-09-03, versión 1.1.0)

| Entregable | Estado | Evidencia |
|---|---|---|
| `Templates/swiftlint.yml` | Hecho | = `.swiftlint.yml` de AppStarterKit + `excluded` en dos formas (relativa y glob) y `empty_count` como aviso |
| `archinit` copia `.swiftlint.yml` e imprime los pasos manuales | Hecho | `Plugins/ArchInit/plugin.swift` |
| Generador y ejemplos pasan `swiftlint --strict` | Hecho | `verify-generator.sh` lo comprueba (cazó el ternario con `Void` de `Templates/ViewModel.swift.txt`, corregido); 4 ejemplos y `Snippets` limpios; job `quality` en CI |
| Docs | Hecho | `CodeQuality.md` (+ índice DocC y `Lint.md`), README, `AGENTS.md` (Qué NO hacer, Definition of Done), `feature.skill.md` |
| Extra | Hecho | `SpyRecorder.isEmpty`; ejemplos y snippets corregidos (`isEmpty`, `#require`/`guard let`, `Data(_.utf8)`, sin `print`) |

Aprendido al ejecutarlo: los `excluded` del `.yml` son relativos al fichero de configuración,
no al directorio lintado; con `--config` desde otro sitio hay que lintar `Sources`/`Tests`
explícitos. Y `try #require(UserDefaults(suiteName:))` no puede pasarse a un `actor` bajo
región-isolation (el valor sale del macro «posiblemente compartido»): `guard let` sí.

Verificación sobre `main`: lint estricto limpio · build estricto · 274 tests · 4 ejemplos ·
snippets sincronizados · `verify-generator.sh` con SwiftLint en verde · build iOS · docbuild
iOS y macOS sin warnings. Publicación: `main` de AppFoundation `ddef77d`, tag `1.1.0` tras CI.
