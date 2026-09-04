# PRDs de remediación — spm-pro

Origen: `../AUDITORIA-2026-09-01.md` (IDs de hallazgo CN-xx / AF-xx referenciados en cada PRD).
Objetivo global: dejar AppFoundation y CoreNetworking en **10/10** dentro del alcance acordado
(seguridad avanzada fuera de alcance: se mantiene SSL pinning básico y correcto, nada más).

## Reglas comunes para todo agente (Definition of Done)

1. Trabaja en un **worktree propio** sobre una rama `prd/<ID>` creada desde `main` (o desde la rama que indique
   la dependencia). No toques ficheros fuera de la lista **Ficheros** de tu PRD; si es imprescindible, hazlo
   mínimo y decláralo en el resumen final.
2. Verde obligatorio antes de dar por terminado, ejecutado desde el directorio del paquete:
   ```bash
   SWIFT_STRICT_WARNINGS=1 swift build --build-tests     # 0 warnings (AppFoundation; CoreNetworking tras X-01)
   swift test                                            # todo verde
   xcodebuild build -scheme <AppFoundation | CoreNetworking-Package> -destination 'generic/platform=iOS Simulator'
   ```
3. Swift 6.2: sin `@unchecked Sendable` nuevo sin justificación en comentario; sin `nonisolated(unsafe)` nuevo;
   sin APIs deprecadas (`foregroundColor`, `edgesIgnoringSafeArea`, `cornerRadius`, `PreviewProvider`, `#file`).
4. Tests con **Swift Testing**, deterministas: nada de `Task.sleep` real cuando exista un `Clock` inyectable.
   Cada bug corregido lleva un test que falla antes y pasa después.
5. Documentación: actualiza la sección del README del paquete que corresponda a tu PRD y añade una entrada en
   `CHANGELOG.md` bajo `## [Unreleased]` (lo crea X-01; si aún no existe, créalo con ese formato).
6. Commits pequeños, en español, estilo del repo (`feat(corenetworking): …`, `fix(appfoundation): …`), con trailer:
   ```
   Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
   ```
7. Resumen final del agente: qué cambió, qué API pública se rompió (lista exacta), qué queda fuera, y la salida
   literal del último `swift test` (línea `Test run with N tests …`).

## Oleadas (paralelismo por propiedad de ficheros)

| Oleada | PRDs en paralelo | Dependencias |
|--------|------------------|--------------|
| 1 | CN-01, CN-02, AF-01, AF-02, AF-03, AF-04, X-01 | ninguna (ficheros disjuntos) |
| 2 | CN-03, CN-05 | CN-01 mergeado. Merge CN-03 primero; CN-05 se rebasa sobre él |
| 3 | CN-04, CN-06 | CN-03 y CN-05 mergeados. Merge CN-04 primero; CN-06 se rebasa |
| 4 | X-02 | todo lo anterior mergeado |
| 5 | AF-05 | X-02 mergeado |
| 6 | CN-07, AF-06 | AF-05 mergeado (paquetes distintos, sin solape) |
| 8 | AF-07 | oleada 6 mergeada |
| 9 | AF-08 | AF-07 mergeado |
| 10 | X-03 (v2) | AF-07 y AF-08 mergeados |
| 11 | X-04 | X-03 mergeado |
| 12 | APP-01 (repo AppStarter) | tags 1.0.0 publicados |
| 13 | X-05 (AppFoundation 1.0.1) | APP-01 terminado |
| 14 | AF-09 (calidad de código, AppFoundation 1.1.0) | calibrado en AppStarter primero |
| 15 | AF-10 (`archinit --multi`, AppFoundation 1.2.0) | AF-09 publicado |

Conflictos esperados y cómo evitarlos:
- `README.md` de cada paquete: cada PRD edita **solo su sección**; X-02 hace la pasada final de coherencia.
- `APIService.swift` es el fichero caliente de CoreNetworking: por eso CN-03/CN-05 y CN-04/CN-06 van en oleadas
  y con orden de merge explícito. Las regiones que toca cada uno están listadas en su PRD.
- `IntegrationTests.swift` (AppFoundation) puede tocarse desde AF-01 y AF-02: AF-02 tiene prioridad de merge;
  AF-01 se rebasa.

## Lanzamiento (un agente por PRD, worktree aislado)

```bash
git worktree add ../spm-pro-CN-01 -b prd/CN-01 main
# … el agente recibe: "Ejecuta docs/prd/PRD-CN-01.md. Lee primero docs/prd/README.md y docs/AUDITORIA-2026-09-01.md."
```

Orden de merge dentro de una oleada: el que aparece primero en la tabla. Tras cada merge a `main`, la siguiente
oleada parte de `main` actualizado.

## Índice

| ID | Título | Hallazgos | Paquete |
|----|--------|-----------|---------|
| [CN-01](PRD-CN-01.md) | Modelo de error unificado y extensible | CN-02, CN-03, CN-04, CN-12, CN-20 | CoreNetworking |
| [CN-02](PRD-CN-02.md) | Pinning: configuración segura y `NSPinnedDomains` | CN-19 | CoreNetworking |
| [CN-03](PRD-CN-03.md) | `HTTPTransport` inyectable, `Clock` en retry, mocks con secuencias | CN-11, CN-21, CN-22 | CoreNetworking |
| [CN-04](PRD-CN-04.md) | Delegate por tarea: pinning extremo a extremo, progreso, `download` a disco | CN-01, CN-07 | CoreNetworking |
| [CN-05](PRD-CN-05.md) | Superficie de request/response y configuración de sesión | CN-08, CN-09, CN-10, CN-13, CN-14, CN-15, CN-16, CN-17, CN-18 | CoreNetworking |
| [CN-06](PRD-CN-06.md) | Interceptores v2, `RequestRetrier` y refresh de token | CN-05, CN-06 | CoreNetworking |
| [AF-01](PRD-AF-01.md) | `BaseViewModel`: memoria, cancelación y presentación de errores | AF-01…AF-08 | AppFoundation |
| [AF-02](PRD-AF-02.md) | Inyección de dependencias `@MainActor` | AF-09, AF-10, AF-11 | AppFoundation |
| [AF-03](PRD-AF-03.md) | Utilidades: `Debouncer`/`Throttler`, `AppEnvironment`, String Catalog | AF-19, AF-20, AF-21 | AppFoundation |
| [AF-04](PRD-AF-04.md) | Navegación y UI: barra nativa por defecto, estilos sin `AnyView`, a11y | AF-12…AF-18 | AppFoundation |
| [X-01](PRD-X-01.md) | Proceso: CI, formato, licencia, changelog, gate estricto en CoreNetworking | — | ambos |
| [X-02](PRD-X-02.md) | Cierre 1.0: coherencia de docs, verificación cruzada, release | AF-07 y docs | ambos |
| [AF-05](PRD-AF-05.md) | Contrato pantalla ↔ cáscara: `ScreenState`, `ActionHandling`, `ActionSender` | decisión del propietario | AppFoundation |
| [CN-07](PRD-CN-07.md) | Pulido tras el doble check | DC-CN-1…7 | CoreNetworking |
| [AF-06](PRD-AF-06.md) | Pulido tras el doble check | DC-AF-2…5 | AppFoundation |
| [AF-07](PRD-AF-07.md) | Kit de arquitectura: `Logic`, `LogicViewModel`, `EndpointService`, test support, 4 ejemplos | [`../ARQUITECTURA-KIT-2026-09-02.md`](../ARQUITECTURA-KIT-2026-09-02.md) | ambos |
| [AF-08](PRD-AF-08.md) | Plugins: generador `generate-feature`, linter `ArchitectureLint`, `archinit` | ídem | AppFoundation |
| [X-03](PRD-X-03.md) | (v2) Documentación dentro de cada SPM (DocC + Snippets) y cierre 1.0.0 | DC-CN-8, DC-AF-6/7 | ambos |
| [X-04](PRD-X-04.md) | Snippets DocC en línea verificados por CI | doble check final | ambos |
| [APP-01](PRD-APP-01.md) | AppStarter: app real sobre DummyJSON con los paquetes 1.0.0 | — | repo AppStarter |
| [X-05](PRD-X-05.md) | AppFoundation 1.0.1 a partir de las fricciones de AppStarter | INFORME-INTEGRACION | AppFoundation |
