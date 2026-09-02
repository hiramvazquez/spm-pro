# PRD-AF-06 — Pulido de AppFoundation tras el doble check

Paquete: AppFoundation · Oleada 6 · Cubre: DC-AF-2…DC-AF-5 (`AUDITORIA-2026-09-02-doblecheck.md` §3) · Rompe API pública: **no** (solo añade)

## Cambios
1. **Tests sin polling**: `BaseViewModel` expone `public private(set) var inFlightLoad: Task<Void, Never>?` y `inFlightActivity` (`@ObservationIgnored`; se ponen a `nil` al terminar). Un test hace `vm.handle(.load); await vm.inFlightLoad?.value` en vez de `waitUntil`. Sustituir `waitUntil` en `AppFoundation/Tests` y en `Examples/IntegrationExample/Tests` por `await vm.inFlightLoad?.value` (borrar el helper si queda sin uso). Documentar en README «Deterministic tests».
2. **Inyección por instancia** de `clock` y `cancellationRecognizer` (`init(errorPresenter:cancellationRecognizer:clock:)` con defaults `nil` → estático). Precedencia instancia > estático, como `errorPresenter`. Los tests del paquete dejan de mutar los estáticos (`grep -rn "BaseViewModel\.\(clock\|errorPresenter\|cancellationRecognizer\) = " Tests` vacío salvo un único test `.serialized` que prueba explícitamente el default estático).
3. **`ScreenState` sin `@Observable`**: `BindingBackedState`/`ObservingScreenState` documentan por qué funcionan sin el macro (leen bindings / un `@Observable` durante `body`) y se marcan `@Observable` si el compilador lo permite sin efectos; si no, comentario. Test que verifica que un cambio en el VM envuelto re-renderiza (`ObservingScreenState` con `withObservationTracking`).
4. **Type-erasure restante**: `NavigationBarItemContent.view`, `NavigationBarTitle.custom`, `accessoryView`, `customContent` conservan `ErasedView` (decisión: la barra custom es opt-in); añadir doc en `ErasedView` con la lista de usos y el motivo. Sin cambios de API.
5. **Ejemplo con vista**: `Examples/IntegrationExample` gana `ProfileView` (SwiftUI, `#if canImport(SwiftUI)`): `ScreenContainer(vm) { send in … send(.load) … }` con `.task { await vm.load { … } }` **o** `handle(.load)` en `onAppear` (elegir uno y explicar cuándo cada cual), estilos por `Environment` y una `ProfilePreview` con `MockAPIService`. Debe compilar en macOS y iOS Simulator (`xcodebuild` no aplica al ejemplo; `swift build` en macOS sí).

## Ficheros
`Sources/AppFoundation/Architecture/ViewModels/{BaseViewModel,LoadableViewModel}.swift`, `Sources/AppFoundation/UI/Containers/ScreenContainer.swift`, `Sources/AppFoundation/UI/Styles/ErasedView.swift`, `Tests/AppFoundationTests/*` (adaptar), `Examples/IntegrationExample/**`, `AppFoundation/README.md` (secciones «Deterministic tests», «Pantalla y cáscara»), `CHANGELOG.md` (`## [Unreleased]` → `### AppFoundation`).

## Criterios de aceptación
- [ ] `grep -rn "waitUntil\|Task.sleep" AppFoundation/Tests Examples` vacío (salvo tests que prueben explícitamente un `Clock` real, si los hay: listarlos).
- [ ] `grep -rn "BaseViewModel\.\(clock\|errorPresenter\|cancellationRecognizer\) = " AppFoundation/Tests` → solo el test del default estático.
- [ ] `ProfileView` compila y su preview usa `MockAPIService`.
- [ ] `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` 0 warnings; `swift test --parallel` verde 3 veces; `swift format lint --strict --recursive AppFoundation Examples` 0; `xcodebuild build -scheme AppFoundation -destination 'generic/platform=iOS Simulator'` OK; ejemplo `swift test` verde.
