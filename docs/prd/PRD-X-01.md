# PRD-X-01 — Proceso: CI, formato, licencia, changelog y gate estricto en CoreNetworking

Ámbito: repo · Oleada 1 · Cubre: §6 Fase 5 de la auditoría · Rompe API pública: no

## Entregables
1. **CI** `.github/workflows/ci.yml` (macOS runner, Xcode más reciente disponible):
   - matriz por paquete (`AppFoundation`, `CoreNetworking`);
   - `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` y `swift test --parallel`;
   - `xcodebuild test -scheme <AppFoundation | CoreNetworking-Package> -destination 'platform=iOS Simulator,name=iPhone 16'`
     (o el nombre disponible en el runner; detectarlo con `xcrun simctl list`);
   - job de formato: `swift format lint --strict --recursive Sources Tests` (usar el `swift-format` integrado en el toolchain 6.x).
2. **Formato**: `.swift-format` en la raíz (indent 4, líneas 120, `lineBreakBeforeEachArgument`, reglas ortográficas
   de Swift API Design Guidelines activadas). Ejecutar `swift format --in-place --recursive` **una sola vez** en un commit
   separado «style: formato automático» para que los diffs de los otros PRD no lo arrastren. Coordinar: este commit
   debe mergearse **antes** que el resto de la oleada 1 o, si no es posible, aplicarse al final en X-02.
3. **Gate estricto en CoreNetworking**: copiar el patrón de `AppFoundation/Package.swift` (`modoEstricto` por
   `SWIFT_STRICT_WARNINGS`) a `CoreNetworking/Package.swift`, con el mismo comentario de racional.
4. **`LICENSE`** (MIT, titular: Hiram Vazquez) en la raíz y referencia en ambos README.
5. **`CHANGELOG.md`** en la raíz (Keep a Changelog): `## [Unreleased]` con subsecciones por paquete; los demás PRD
   añaden sus entradas ahí.
6. **README raíz** (`README.md`): qué es el repo, los dos paquetes, requisitos, cómo consumirlos por URL + tag, cómo
   correr tests, enlace a `AUDITORIA-2026-09-01.md` y a `PRD/`.
7. `.gitignore` raíz: añadir `*.xcresult`, `.swiftpm/xcode/xcuserdata/`.

## Ficheros
Solo raíz y `.github/`, más `CoreNetworking/Package.swift` (3 líneas + comentario). No tocar Sources.

## Criterios de aceptación
- [ ] `act` o un push a rama muestra el workflow verde en ambos paquetes (adjuntar URL o log en el resumen).
- [ ] `SWIFT_STRICT_WARNINGS=1 swift build` en CoreNetworking: 0 warnings (si aparecen, listarlos en el resumen; **no** arreglar código de Sources aquí, eso es de los PRD CN).
- [ ] `swift format lint --strict` verde tras el commit de formato.
