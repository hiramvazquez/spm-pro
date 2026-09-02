# PRD-AF-04 — Navegación y UI: barra nativa por defecto, estilos sin `AnyView`, accesibilidad

Paquete: AppFoundation · Oleada 1 · Cubre: AF-12, AF-13, AF-14, AF-15, AF-16, AF-17, AF-18 · Rompe API pública: **sí** (`ScreenContainer` cambia su modelo de personalización; `navigation:` pasa a opt-in)

## Problema
La barra nativa se oculta en todas las rutas (swipe-back en riesgo, sin large titles/`searchable`, botón atrás sin
etiqueta de accesibilidad, altura fija sin Dynamic Type); personalización vía `AnyView`; APIs deprecadas; barra
duplicada en el árbol.

## Diseño
### Chrome nativo por defecto
- `CoordinatorView` deja de aplicar `.toolbar(.hidden, for: .navigationBar)`. Cada pantalla decide.
- `ScreenContainer(viewModel:)` **no** oculta la barra. Nueva API:
  ```swift
  public enum ScreenChrome { case native            // usa navigationTitle/toolbar/searchable del llamador
                             case custom(NavigationBarConfiguration, placement: NavigationPlacement = .stack) }
  ScreenContainer(viewModel:, chrome: .native, content:)                 // default
  ```
  Con `.custom` se oculta la barra nativa **y** se instala el workaround del gesto: `UIViewController`
  representable mínimo que, en `viewDidAppear`, pone `navigationController?.interactivePopGestureRecognizer?.delegate = nil`
  y `isEnabled = true` (iOS solamente; comentario explicando por qué). Verificar en simulador con un test de UI manual
  descrito en el resumen (no automatizable aquí).
- Los `init` de conveniencia `title:`/`onBack:`/`searchText:` se conservan pero construyen `.custom(...)`; sus docs
  dicen «prefiere `.native` + `navigationTitle`/`toolbar`/`searchable`».

### Estilos en vez de `AnyView`
```swift
public protocol LoadingViewStyle { associatedtype Body: View; @ViewBuilder func makeBody(configuration: LoadingConfiguration) -> Body }
public protocol ErrorViewStyle   { … ErrorConfiguration(error: ScreenError) … }
public protocol EmptyViewStyle   { … }
public protocol BannerViewStyle  { … BannerConfiguration(banner:, dismiss:) … }
extension View {
    func loadingViewStyle(_:) / errorViewStyle(_:) / emptyViewStyle(_:) / bannerViewStyle(_:)   // Environment
}
```
- `ScreenContainer` y `PhaseView` leen los estilos del `Environment`; los modifiers `.loadingView { }` etc. se eliminan.
  `alertView(builder:)` se elimina: las alertas son nativas (si hace falta custom, es un `AlertViewStyle` futuro, no `AnyView`).
- `NavigationBarItemContent.view(AnyView)`, `NavigationBarTitle.custom(AnyView)`, `accessoryView: AnyView?`,
  `customContent: AnyView?` → genéricos con `some View` almacenados vía un pequeño type-erasure interno **solo**
  donde SwiftUI lo exige (documentado), o eliminados si `.native` cubre el caso.

### Accesibilidad y Dynamic Type (barra custom)
- `.back`/`.close` con `accessibilityLabel(L10n.back / L10n.close)` y `accessibilityAddTraits(.isButton)`.
- Altura con `@ScaledMetric(relativeTo: .headline)`; iconos con `.font(.headline)` en vez de tamaños fijos.
- `NavigationSearchBar`: `accessibilityLabel`, `.textInputAutocapitalization(.never)`.

### Limpieza
- `.edgesIgnoringSafeArea` → `.ignoresSafeArea(.container, edges:)`; `.foregroundColor` → `.foregroundStyle`;
  `.cornerRadius` → `.clipShape(.rect(cornerRadius:))`; `PreviewProvider` → `#Preview`.
- `Background.swift` → `PhaseView.swift`. `BannerState.Duration` → `duration: Swift.Duration?` (nil = indefinido).
  `NavigationBarTitle.largeText` se elimina. `Coordinator.navigationHistory` → `internal`.
- La barra se renderiza **una** vez: el overlay de estado no vuelve a instanciar `CustomNavigationBar`.

## Ficheros
Sources: `Navigation/Views/CoordinatorView.swift`, `Navigation/Core/Coordinator.swift` (solo `navigationHistory`), `UI/Containers/ScreenContainer.swift`, `UI/Containers/Background.swift` (→ `PhaseView.swift`), nuevo `UI/Styles/*.swift`, nuevo `UI/Platform/PopGestureEnabler.swift`, `UI/NavigationBar/CustomNavigationBar.swift`, `UI/NavigationBar/NavigationBarItem.swift`, `UI/Containers/Previews/*`, `Architecture/State/BannerState.swift`, `Utilities/L10n.swift` (+ `back`, `close`), `Resources/*` (2 claves; coordinar con AF-03 en el merge).
Tests: `ScreenPresentationLogicTests.swift`, `ViewPhaseTests.swift`, `BaseViewModelTests.swift` (solo `BannerState.Duration`), nuevo `ScreenChromeTests.swift` (lógica pura: qué chrome oculta la barra), `LocalizationTests.swift`.
README: «Render with ScreenContainer», «UI».

## Criterios de aceptación
- [ ] `grep -rn "AnyView\|edgesIgnoringSafeArea\|foregroundColor\|\.cornerRadius(\|PreviewProvider\|largeText" Sources` vacío (salvo el type-erasure interno documentado, si existe, en un único fichero).
- [ ] Con `chrome: .native`, `grep` de `.toolbar(.hidden` no aparece en la ruta de render (test de `ScreenChrome` lógica + revisión).
- [ ] Botón atrás custom tiene `accessibilityLabel` localizado (test de la vista con `ViewInspector` **no** se añade; verificar por revisión y en previews).
- [ ] Previews compilan (`swift build` incluye `#Preview` en DEBUG).
- [ ] README muestra primero el flujo `.native` con `navigationTitle` y `toolbar`, y la barra custom como opt-in.
