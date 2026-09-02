# PRD-AF-08 — Plugins: `GenerateFeature` (generador), `ArchitectureLint` (linter) y `archinit`

Ámbito: AppFoundation · Oleada 9 (tras AF-07) · Origen: `ARQUITECTURA-KIT-2026-09-02.md` §3-5 · Rompe API pública: no

## Entregables
1. **`archlint`** (`executableTarget`, sin dependencias externas): analizador léxico propio (tokens, `import`, declaraciones `class/struct/enum/actor/protocol X: A, B`, ignora comentarios y strings). Reglas de `ARQUITECTURA-KIT-2026-09-02.md` §1 (R1…R6), cada una con id `ArchLint.Rn`, mensaje que dice qué hacer, y test unitario con fixtures (fichero que viola / fichero que cumple). Configuración `.archlint.yml` (parser YAML mínimo propio o formato `key: value` plano; documentar): sufijos, imports permitidos por capa, reglas desactivadas, `ignore:` (globs), `strict:` (exige `LogicViewModel`). Salida `ruta:línea:col: error: [ArchLint.R1] …` y exit ≠ 0 si hay errores.
2. **`ArchitectureLint`** build-tool plugin (`.buildTool()`): pasa los `sourceFiles` del target a `archlint`; el build del consumidor falla con diagnósticos navegables en Xcode. **`ArchLintCommand`** command plugin (`swift package archlint [--path]`) para CI.
3. **`GenerateFeature`** command plugin (`swift package --allow-writing-to-package-directory generate-feature <Nombre> [--api] [--local] [--no-logic] [--no-tests] [--path Features] [--dry-run]`): genera la estructura de AF-07 desde plantillas de texto en `AppFoundation/Templates/` (`{{Feature}}`, `{{feature}}`, bloques condicionales `{{#api}}…{{/api}}`, `{{#local}}…{{/local}}`, sin librería externa). Todo lo generado compila y sus tests pasan. Imprime los pasos manuales (añadir `case` a `AppRoute`, registrar el `Module`). Incluye siempre el «Hola mundo» en la View con `ScreenContainer` y `send(.load)`.
4. **`archinit`** command plugin: crea `.archlint.yml`, `Features/`, copia `AGENTS.md` a la raíz del proyecto y añade `@AGENTS.md` a `CLAUDE.md` si existe (o lo crea), e instala `.claude/skills/feature.md` (skill que explica el generador y las reglas).
5. Docs: sección «Generador y linter» en README (uso desde SwiftPM y desde Xcode: Build Phases → Run Build Tool Plug-ins; clic derecho → comando), y en `AGENTS.md`.

## Verificación obligatoria
- Test de integración real: en un paquete SwiftPM temporal fuera del repo que depende de AppFoundation por `path:`, ejecutar `generate-feature Login --api`, `generate-feature Notes --local`, `generate-feature Catalog --api --local`, `generate-feature Counter`; `swift build` y `swift test` verdes en el temporal; después introducir una violación (un `import CoreNetworking` en `LoginViewModel.swift`) y comprobar que `swift build` con el plugin falla con `[ArchLint.R1]`; borrar el temporal. Documentar la transcripción en el informe.
- Los cuatro ejemplos de AF-07 pasan `swift package archlint` sin errores (son la referencia: si el linter los rechaza, el linter está mal o el ejemplo está mal — decidir y arreglar).
- `swift format lint --strict` 0; build estricto 0 warnings; tests de ambos paquetes verdes.

## Ficheros
`AppFoundation/Package.swift` (targets `archlint`, plugins), `AppFoundation/Sources/archlint/**`, `AppFoundation/Plugins/{ArchitectureLint,ArchLintCommand,GenerateFeature,ArchInit}/`, `AppFoundation/Templates/**`, `AppFoundation/Tests/ArchLintTests/**` (+ fixtures), `AppFoundation/AGENTS.md`, `AppFoundation/README.md` (sección nueva), `CHANGELOG.md`, `.github/workflows/ci.yml` (job que ejecuta el test de integración del generador).
