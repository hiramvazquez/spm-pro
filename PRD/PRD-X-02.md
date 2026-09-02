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
