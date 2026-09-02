# PRD-APP-01 — AppStarter: app iOS real que consume AppFoundation + CoreNetworking 1.0.0

Repo: `hiramvazquez/AppStarter` (público, aparte del monorepo) · Directorio local: `/Users/hiram/Desktop/PROYECTOS/AppStarter` · Objetivo: probar los dos paquetes como los usará un integrador (proyecto Xcode, dependencias por URL + tag, plugins en Build Phases, `.xcstrings` compilado por Xcode, simulador) contra una **API real**, con varias pantallas y navegación; convertir en tests de UI lo que quedó como verificación manual; y dejar el resultado como plantilla de arranque de futuras apps.

## API: DummyJSON (https://dummyjson.com, sin registro)
- `POST /auth/login` `{username, password, expiresInMins}` → `{accessToken, refreshToken, id, username, email, firstName, lastName, image}`. Usuario de prueba: `emilys` / `emilyspass`.
- `POST /auth/refresh` `{refreshToken, expiresInMins}` → tokens nuevos; refresh inválido → 403.
- `GET /auth/me` (Bearer) → usuario; sin token/expirado → 401.
- `GET /products?limit=&skip=&select=` → `{products, total, skip, limit}`; `GET /products/{id}`; `GET /products/search?q=`.
- `expiresInMins: 1` en login permite probar el flujo 401 → refresh → reintento contra el servidor real.

## Pantallas y navegación (Coordinator de AppFoundation)
```
AppRoute: .login | .products | .productDetail(id) | .favorites | .profile | .search (modal, sheet)
Login ──(sesión)──▶ Products (lista paginada, pull-to-refresh, botón Buscar → sheet Search)
                     ├─ push ProductDetail(id) (favorito ⭐ → Store local)
                     ├─ push Favorites (SwiftData, solo local)
                     └─ push Profile (GET /auth/me con Bearer; logout; muestra el refresh cuando el token caduca)
```
Al expirar la sesión (refresh 403) → `SessionExpiring` → `setRoot(.login)` con banner.

## Arquitectura (la del kit, sin excepciones)
`Features/<Feature>/{View, ViewModel, Logic, Services/, Stores/}` generados con `swift package generate-feature` y luego completados a mano; `AppModule` como composition root (`DependencyModule`); `AppErrorPresenter: ErrorPresenting` sobre `DomainError`; `SessionStore` (Keychain o `UserDefaults` en el starter; documentar) inyectado en las Logic; `AuthService`, `ProductsService`, `ProfileService` sobre `APIServiceProtocol` + `EndpointService`; `FavoritesStore` con SwiftData (`@ModelActor`); `ArchitectureLint` activo en el target de la app **y** en el de tests; `archinit` ejecutado (`.archlint.yml`, `AGENTS.md`, `CLAUDE.md`, skill `/feature`).

## Proyecto
- `project.yml` de **xcodegen** (instalado): app iOS 17+, SwiftUI, `.xcodeproj` generado y **no** versionado (script `Scripts/bootstrap.sh` = `xcodegen generate`); dependencias `AppFoundation` y `CoreNetworking` por URL `from: "1.0.0"`; `swiftSettings` con `defaultIsolation(MainActor)` y los upcoming features; carpetas sincronizadas.
- Targets: `AppStarter` (app), `AppStarterTests` (unit: VM con spies de Logic, Logic con mocks de Service/Store, Services con `MockAPIService`/`InMemoryTransport`, más un test de integración opcional contra DummyJSON marcado `.disabled` por defecto y activable con `INTEGRATION=1`), `AppStarterUITests` (XCUITest).
- **XCUITests que sustituyen a la verificación manual**: (1) swipe-back desde el borde en `ProductDetail` con `chrome: .custom` vuelve a la lista; (2) VoiceOver: el botón atrás/cerrar de la barra custom expone `accessibilityLabel` «Back»/«Close» (comprobación de `XCUIElement.label`); (3) Dynamic Type: lanzar con `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` y comprobar que la barra custom y la lista siguen accesibles (elementos `isHittable`); (4) flujo completo: login → lista → detalle → favorito → favoritos → perfil → logout. Las pantallas usan `chrome: .native` salvo `ProductDetail`, que usa `.custom` a propósito para cubrir el caso.
- Red en UI tests: por defecto contra DummyJSON real (es el objetivo del PRD); con `-UITestOffline` la app usa `InMemoryTransport` con respuestas grabadas, para CI sin red o sin depender del servicio.
- CI (`.github/workflows/ci.yml`): `xcodegen generate` → `swift package archlint` sobre `Sources` → `xcodebuild test` unit + UI en iPhone 17 Pro (simulador detectado) con `-UITestOffline` → job aparte `integration` (manual `workflow_dispatch`) contra DummyJSON real.

## Entregables
1. Repo `AppStarter` con README (qué es, cómo arrancar en 5 minutos, cómo se generó cada feature, cómo añadir una), `AGENTS.md` (copiado por `archinit`), `project.yml`, `Scripts/bootstrap.sh`, CI.
2. Informe `docs/INFORME-INTEGRACION.md` en el repo: cada fricción encontrada al integrar los paquetes desde Xcode (plugins, permisos, `Bundle.module`, `.xcstrings`, linter, generador, DocC en Xcode), con propuesta de cambio para 1.0.1 de cada paquete.
3. Lista de issues a abrir en `AppFoundation`/`CoreNetworking` (título + descripción) por cada fricción que requiera cambio en los paquetes. No cambiar los paquetes desde este PRD.

## Criterios de aceptación
- [ ] `Scripts/bootstrap.sh && xcodebuild test -scheme AppStarter -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` verde (unit + UI offline).
- [ ] `xcodebuild test` con `INTEGRATION=1` (login real, productos reales, refresh real con `expiresInMins: 1`) verde al menos una vez, transcrito en el informe.
- [ ] `swift package archlint` en 0 sobre `Sources`; introducir una violación y comprobar que Xcode (build) falla con el plugin; revertir.
- [ ] Los 4 XCUITests de accesibilidad/gesto/Dynamic Type/flujo pasan en simulador.
- [ ] Cinco pantallas navegables (login, lista, detalle, favoritos, perfil) + sheet de búsqueda; logout global al caducar la sesión.
- [ ] Repo publicado con CI verde en el primer push (`archinit`, `generate-feature` documentados como se usaron de verdad).
