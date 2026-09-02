# PRD-X-03 (v2) — Documentación dentro de cada SPM y cierre definitivo de 1.0.0

Ámbito: ambos paquetes · Oleada 10 (tras AF-07 y AF-08) · Sustituye a la v1. Motivo del cambio: cada paquete se publica por `subtree split`, así que toda la documentación, ejemplos y changelog deben vivir **dentro del directorio del paquete**; nada en la raíz del monorepo viaja.

## Principios
- Documentar el estado actual: cero referencias a PRDs, auditorías o "antes de". La historia va al `CHANGELOG.md` del paquete.
- Cada pieza pública: para qué sirve, cuándo usarla y cuándo no, ejemplo completo, cómo se testea.
- Los ejemplos de la documentación **compilan**: `Snippets/` de SwiftPM (se compilan con el paquete) embebidos en DocC con `@Snippet(path:)`, más los `READMEExamplesTests` existentes para lo que quede en README.
- Español, directo, sin adjetivos.

## Entregables por paquete (dentro de `AppFoundation/` y `CoreNetworking/`)
1. `Sources/<Target>/Documentation.docc/` con: `<Target>.md` (landing), `GettingStarted.md` (una app en 20 minutos, paso a paso con resultado esperado), un artículo por pieza pública (orden de uso), `Architecture.md` (las 4 variantes; en CoreNetworking, su parte: Services), `Recipes.md` (paginación, pull-to-refresh, formulario, logout global al 401, descarga con progreso, rotación de pin, tests de VM/Logic/Service/Store), `Testing.md`, `FAQ.md` (`.xcstrings` y `.build` obsoleto; scheme `-Package`; `Retry-After`; por qué el VM no captura `self`; por qué no hay `TransportError`), `Generator.md`/`Lint.md` (AppFoundation). Verificar que `xcodebuild docbuild` (o `swift package generate-documentation` si el plugin DocC está disponible) construye sin warnings.
2. `Snippets/` con un snippet por artículo/pieza; `swift build` los compila.
3. `README.md` reescrito y corto: qué es, requisitos, instalación por URL + tag y por `path:`, «Empieza aquí» (enlace a DocC + los 6 pasos mínimos con código), enlaces a `AGENTS.md`, `Examples/`, `CHANGELOG.md`. Sin secciones históricas.
4. `CHANGELOG.md` **por paquete** (mover desde la raíz las entradas de cada uno; `[1.0.0] - 2026-09-02` con «Roturas de API» completa; `[Unreleased]` vacío). El de la raíz pasa a ser un índice que enlaza a los dos.
5. `Examples/` por paquete (AF-07 ya los deja en `AppFoundation/Examples/`; CoreNetworking tiene `Examples/APIClientApp` mínimo sin AppFoundation).
6. `AGENTS.md` revisado (coherente con DocC y generador).

## Cierre del monorepo
- `PRD/CIERRE.md`: filas DC-CN-1…8, DC-AF-1…7 y AF-07/AF-08 con estado; procedimiento de tag **en las ramas `subtree split`** (`cn-only`, `af-only`), comandos exactos del doble check §4; checklist final del propietario (último tag de AppFoundation en su remoto; verificación manual AF-12/AF-13; ejecutar `archinit` en la primera app).
- README raíz: índice de los paquetes, cómo publicar (subtree split + tag), cómo correr todo en local. Auditorías y PRD se quedan en la raíz (no viajan; son historia del monorepo). Mover a `docs/auditorias/` y `docs/prd/` con `git mv` y actualizar enlaces.
- CI: jobs de docs (`docbuild`) y de snippets.

## Criterios de aceptación
- [ ] `grep -rn "CN-0\|AF-0\|X-0\|auditor\|antes de\|ya no\|existía" AppFoundation/README.md CoreNetworking/README.md */Sources/*/Documentation.docc` vacío.
- [ ] Todo tipo público de ambos paquetes aparece en un artículo DocC con ejemplo (listar cobertura en el informe).
- [ ] `swift build` compila los `Snippets/`; docbuild sin warnings.
- [ ] Guía «20 minutos» de cada paquete reproducida en un paquete temporal fuera del repo, paso a paso, y borrada después.
- [ ] `git subtree split --prefix=AppFoundation` produce un árbol que contiene README, CHANGELOG, AGENTS.md, Documentation.docc, Snippets y Examples (comprobar con `git ls-tree -r --name-only <sha> | head`); ídem CoreNetworking.
- [ ] Verificación final completa (ambos paquetes, todos los ejemplos, lint, iOS) verde; `CIERRE.md` sin IDs desconocidos.
