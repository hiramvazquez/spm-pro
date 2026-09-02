# PRD-X-04 — DocC fiable en el primer «Build Documentation»: snippets en línea verificados por CI

Ámbito: ambos paquetes · Oleada 11 · Origen: doble check final (2026-09-02)

## Problema (verificado)
`@Snippet(path:)` en los artículos DocC no se resuelve en el **primer** `xcodebuild docbuild` sobre DerivedData limpio (16 warnings «Snippet named … couldn't be found» en AppFoundation; 1 en CoreNetworking en otra corrida) y sí en el segundo: la extracción de símbolos de los `Snippets/` termina después de compilar la documentación. Para quien integra el paquete y pulsa «Build Documentation» una vez, los artículos salen sin código.

## Solución
1. Cada `@Snippet(path: "<Pkg>/Snippets/<name>")` se sustituye por un bloque ```` ```swift ```` con el contenido visible del snippet (la región entre `// snippet.show`/`// snippet.hide` si existe; si no, el fichero entero sin la cabecera de comentarios). Los `Snippets/` **se conservan** y siguen compilando con `swift build` (es lo que impide que la documentación se pudra).
2. `Scripts/check-doc-snippets.sh` (o un ejecutable Swift en `Scripts/`): para cada bloque marcado en el artículo con un comentario HTML `<!-- snippet: <name> -->` justo antes del bloque, compara el bloque con el contenido visible del snippet y falla si difieren. Job `docs` de CI lo ejecuta antes de `docbuild`. Un `make sync-doc-snippets`/script `--fix` regenera los bloques desde los snippets.
3. `xcodebuild docbuild` con DerivedData limpio (`-derivedDataPath $(mktemp -d)`) para ambos schemes, destino iOS Simulator y macOS: 0 warnings (ni de snippets ni de parámetros sin documentar). Transcribir.
4. Artículo `FAQ`: nota breve sobre por qué los ejemplos están en línea y también en `Snippets/`.

## Ficheros
`*/Sources/*/Documentation.docc/*.md`, `Scripts/check-doc-snippets.sh` (+ `Scripts/README.md` si no existe), `.github/workflows/ci.yml`, `*/AGENTS.md` (una línea: «los ejemplos de DocC están sincronizados con `Snippets/` por CI»), `CHANGELOG.md` de cada paquete (`[Unreleased]`).

## Criterios de aceptación
- [ ] `grep -rn "@Snippet" */Sources/*/Documentation.docc` vacío.
- [ ] `Scripts/check-doc-snippets.sh` en verde; provocar una divergencia y comprobar que falla; revertir.
- [ ] `docbuild` limpio (DerivedData nuevo) 0 warnings en ambos paquetes y ambos destinos.
- [ ] `swift build` sigue compilando los `Snippets/`; `swift test --parallel` verde en ambos; lint estricto 0.
