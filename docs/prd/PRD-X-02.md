# PRD-X-02 — Cierre 1.0: coherencia de docs, verificación cruzada y release

Ámbito: repo · Oleada 4 (todo mergeado) · Cubre: AF-07 residual, coherencia de README/CHANGELOG · Rompe API pública: no

## Tareas
1. **Verificación cruzada de la auditoría**: recorrer el «Índice de hallazgos» de `AUDITORIA-2026-09-01.md` y, para
   cada ID, comprobar con `grep`/lectura que está resuelto o registrar por qué no. Producir `PRD/CIERRE.md` con la
   tabla ID → estado → commit/PR → evidencia (comando y salida).
2. **Ejemplo de integración de los dos paquetes** en `Examples/IntegrationExample/` (solo un `Package.swift` + un
   target ejecutable o de tests): un `AppErrorPresenter` que mapea `APIError.category` a `ScreenError`, un VM con
   `performLoad { vm in … }` sobre `MockAPIService`, y un `TokenRefreshRetrier` configurado. Se compila en CI.
   Es la prueba de que «lo genérico no causa problemas en la app que adopta el SPM».
3. **Docs**: pasada completa de ambos README contra la API real (compilar cada bloque de código en un test
   `READMEExamplesTests` o en el ejemplo anterior); eliminar referencias a APIs borradas; doc comments de
   `AppErrorConvertible`, `PhaseView`, `NavigationBarItem` verificados.
4. **Formato** (si X-01 no pudo aplicarlo antes de la oleada 1): `swift format --in-place` + lint verde.
   > **Nota de X-01 (2026-09-02):** el reformateo masivo **no** se aplicó en X-01 porque la oleada 1 corría en
   > paralelo con seis agentes tocando `Sources`/`Tests`, y un commit `style: formato automático` habría
   > generado conflictos en todos. X-01 dejó `.swift-format` en la raíz y el job `lint` de CI con
   > `continue-on-error: true` y sin `--strict`.
   >
   > Medición real en X-01 (swift-format 6.3.3, toolchain Swift 6.2): `swift format lint --strict --recursive
   > AppFoundation/Sources AppFoundation/Tests CoreNetworking/Sources CoreNetworking/Tests` da **0 avisos**, tanto
   > con `.swift-format` de la raíz como con la configuración por defecto (probado quitando el fichero). Es decir,
   > al cierre de X-01 el código ya cumple `.swift-format` tal cual está escrito; no hay una cifra de "≈247/≈521"
   > que reformatear — esa era una estimación sin ejecutar el comando y hay que descartarla.
   > **No** te fíes de que siga así: seis PRD (CN-03/04/05/06, AF-01…AF-04) tocan `Sources`/`Tests` después de
   > X-01, así que en X-02, con todo mergeado, hay que **volver a correr el lint** antes de decidir si hace falta
   > `swift format --in-place --recursive AppFoundation/Sources AppFoundation/Tests CoreNetworking/Sources
   > CoreNetworking/Tests` en un commit `style: formato automático`, o si ya está verde y solo falta endurecer CI:
   > añadir `--strict` al paso de lint en `.github/workflows/ci.yml` y quitar el `continue-on-error`. Aprovecha la
   > pasada de coherencia de README para añadir la referencia a `LICENSE` (MIT) en ambos README de paquete, que
   > X-01 no tocó por estar fuera de su lista de ficheros permitidos.
5. **Release**: `CHANGELOG.md` → `## [1.0.0] - <fecha>` con la lista de roturas de API (agregada de los resúmenes de
   cada PRD); tag `1.0.0` anotado en la raíz (los consumidores apuntan al repo con `path:` o URL + `from: "1.0.0"`).
   Comprobar que un paquete consumidor de prueba resuelve ambos productos por URL del repo.
6. **Verificación en dispositivo/simulador** (manual, documentada en `CIERRE.md`): swipe-back con `chrome: .native`
   y con `.custom`; VoiceOver en botón atrás; Dynamic Type XXL en la barra custom.

## Criterios de aceptación
- [ ] `PRD/CIERRE.md` con los 45 IDs y ninguno en estado «desconocido».
- [ ] `Examples/IntegrationExample` compila y sus tests pasan en CI.
- [ ] Ningún bloque de código de los README falla al compilar.
- [ ] Tag `1.0.0` creado; `git describe` lo muestra; CHANGELOG cerrado.
