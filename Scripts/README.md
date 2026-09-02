# Scripts

Scripts de repositorio, invocados desde `.github/workflows/ci.yml` y (opcionalmente) a
mano en local. Ninguno tiene dependencias fuera de lo que trae macOS/Xcode: `bash`, `awk`,
`python3`.

## `check-doc-snippets.sh`

Los artículos de `Documentation.docc/` de cada paquete muestran ejemplos de código en
bloques ` ```swift ` en línea, cada uno precedido de un comentario HTML
`<!-- snippet: <name> --> ` que lo asocia con un fichero de `Snippets/`. El bloque en línea
es lo que ve quien pulsa "Build Documentation" la primera vez (`@Snippet(path:)` no se
resuelve en el primer `xcodebuild docbuild` sobre DerivedData limpio — ver PRD-X-04);
`Snippets/` sigue existiendo porque es lo único que garantiza que el ejemplo compila de
verdad, vía `swift build`.

Este script compara cada bloque marcado con el contenido "visible" del snippet
correspondiente (la región entre `// snippet.show`/`// snippet.hide` si el fichero los
tiene; si no, el fichero entero menos la cabecera de comentarios) y falla si divergen.

```bash
Scripts/check-doc-snippets.sh          # comprueba; sale 1 si algo diverge
Scripts/check-doc-snippets.sh --fix    # regenera in situ los bloques que divergen
```

CI: job `docs` de `.github/workflows/ci.yml`, antes de `xcodebuild docbuild` — así un
snippet editado sin actualizar su artículo (o al revés) rompe el build, no solo el code
review.

## `verify-generator.sh`

Reproduce, en un paquete SwiftPM temporal fuera del repo, la verificación real del
generador (`generate-feature`) y el linter (`ArchitectureLint`/`archlint`) de
PRD-AF-08: las cuatro variantes de `generate-feature` compilan y pasan sus tests, el
plugin de build pasa limpio, una violación de R1 hace fallar el build con
`[ArchLint.R1]`, y `swift package archlint` pasa limpio sobre los cuatro ejemplos del kit
de arquitectura (son la referencia).

```bash
Scripts/verify-generator.sh
```

CI: job `generator` de `.github/workflows/ci.yml`.
