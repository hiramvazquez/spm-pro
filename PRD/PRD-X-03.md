# PRD-X-03 — Documentación de integración y cierre definitivo de 1.0.0

Ámbito: repo · Oleada 7 (tras CN-07 y AF-06) · Cubre: DC-CN-8, DC-AF-6, DC-AF-7 y el objetivo del propietario: «que al que lo integre le sea súper fácil integrar todo, con ejemplos de cómo usar cada cosa a detalle».

## Principios
- El README es una **guía de integración del estado actual**, no un diario: cero referencias a PRDs, auditorías o "antes de"; la historia vive en `CHANGELOG.md`.
- Cada pieza pública tiene: para qué sirve, cuándo usarla (y cuándo no), ejemplo completo que compila, y cómo se testea.
- Todo bloque de código de los README se pega literal en `READMEExamplesTests` (ya existen) y compila en CI.
- Español, tono directo, sin adjetivos.

## Estructura de cada README de paquete
1. **Qué es y qué no es** (5 líneas) + requisitos + instalación por URL y tag (`from: "1.0.0"`) y por `path:`.
2. **Empieza aquí: una app en 20 minutos** — guía lineal numerada: instalar → configurar → primera pantalla → primer request → primer error en pantalla → primer test. Cada paso con el código completo y el resultado esperado.
3. **Referencia por pieza** (una sección por tipo público, orden de uso):
   - CoreNetworking: `NetworkingConfiguration` (decoder/encoder/sesión), `BaseRequest`/`Empty`, `APIService` (`execute`, `upload`, `data`, `download`), `APIError` (`code`, `category`, `decodeBody`, `isCancellation`, `localizedDescription`), `RetryPolicy`, `RequestInterceptor` (+ `LoggingInterceptor`), `RequestRetrier` + `TokenRefresher` + `BearerTokenInterceptor` (flujo completo de auth con diagrama de secuencia en texto), `SSLPinningConfiguration` + `NSPinnedDomains`, `HTTPTransport`/`URLSessionTransport`, Testing (`InMemoryTransport`, `ManualClock`, `MockAPIService`, `RecordingInterceptor`, `MockURLProtocol` como integración).
   - AppFoundation: `BaseViewModel` + `LoadableViewModel` (`performLoad` vs `load`, `performActivity` vs `activity`, cuándo cada uno), `ActionHandling`/`ActionSender` (patrón `handle`, tests), `ScreenState` + `ScreenContainer` + `.screen` + `ScreenChrome` (nativo vs custom), estilos (`LoadingViewStyle` etc.), `ErrorPresenting` (+ presenter de ejemplo para `APIError.category` — en la sección «Integración con CoreNetworking»), `CancellationRecognizing`, `AlertState`/`BannerState`, `Coordinator`/`Router`/`CoordinatorView`/deep links, `Container`/`DependencyModule`/`@Inject`, `Debouncer`/`Throttler`, `AppEnvironment`, localización.
4. **Integración con el otro paquete** (sección espejo en ambos): presenter, VM con `APIServiceProtocol`, mocks en tests.
5. **Recetas**: paginación, pull-to-refresh, formulario con submit, logout al 401 global, descarga con progreso, pinning con rotación de clave, tests de un VM con `MockAPIService`, tests de un interceptor con `RecordingInterceptor`.
6. **FAQ / errores frecuentes**: `.xcstrings` y `.build` obsoleto; scheme `-Package` en CI; `Retry-After`; por qué no `TransportError`; por qué el VM no captura `self`.
7. **Referencia de API rota** → enlace al CHANGELOG.

## Ejemplo
`Examples/IntegrationExample` se convierte en la app de referencia: vista + VM + presenter + servicio + tests, con README propio que la recorre fichero a fichero.

## Cierre
- `CHANGELOG.md`: fusionar `[Unreleased]` (CN-07, AF-06, X-03) en `[1.0.0] - <fecha>`; la sección «Roturas de API» completa.
- `PRD/CIERRE.md`: añadir filas DC-CN-1…8 y DC-AF-1…7 con estado; corregir el procedimiento de tag: **en las ramas `subtree split` (`cn-only`, `af-only`), no en `main`**; checklist final para el propietario.
- README raíz: índice de los dos paquetes, enlaces a las guías, cómo publicar (subtree split + tag).
- `AUDITORIA-*.md` se mueven a `docs/auditorias/` con un índice; los PRD a `docs/prd/`. Actualizar enlaces.

## Criterios de aceptación
- [ ] `grep -rn "CN-0\|AF-0\|X-0\|auditor\|antes de\|ya no\|existía" AppFoundation/README.md CoreNetworking/README.md` vacío (salvo el enlace al CHANGELOG).
- [ ] Todo bloque Swift de ambos README está en `READMEExamplesTests` y compila (listar en el informe cuántos bloques).
- [ ] Guía «20 minutos» reproducida por el agente en un paquete temporal fuera del repo, paso a paso, y borrada después (describir el resultado).
- [ ] `Examples/IntegrationExample/README.md` existe y recorre cada fichero.
- [ ] Verificación final completa (ambos paquetes + ejemplo + lint + iOS) verde; `CIERRE.md` sin IDs desconocidos.
