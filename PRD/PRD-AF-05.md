# PRD-AF-05 — Contrato pantalla ↔ cáscara: `ScreenState`, `ActionHandling` y `ActionSender`

Paquete: AppFoundation · Oleada 5 (tras X-02) · Origen: decisión del propietario (2026-09-02) · Rompe API pública: **sí** (`ScreenContainer.init`)

## Problema
1. `ScreenContainer(viewModel: BaseViewModel)` acopla la cáscara a una clase concreta: cualquier pantalla que
   quiera la cáscara debe heredar de `BaseViewModel`, aunque solo se usan cuatro propiedades (`phase`, `activity`,
   `alert`, `banner`). El contrato pantalla↔cáscara no está escrito en ningún tipo.
2. Las vistas llaman métodos del view model directamente (`viewModel.load()`); no hay un único punto de entrada de
   acciones de usuario, que es lo que hace testeable el VM sin exponer sus métodos privados. Swift no tiene métodos
   abstractos, así que `BaseViewModel` no puede obligar a implementarlo; un protocolo con tipo asociado exigido por
   `ScreenContainer` sí, en compilación.

## Diseño

```swift
// Architecture/State/ScreenState.swift
/// Lo mínimo que una cáscara de pantalla necesita observar y cerrar. `BaseViewModel` conforma;
/// cualquier `@Observable` propio también puede.
@MainActor
public protocol ScreenState: AnyObject, Observable {
    var phase: ViewPhase { get }
    var activity: ActivityState { get }
    var alert: AlertState? { get set }
    var banner: BannerState? { get set }
}
extension BaseViewModel: ScreenState {}

// Architecture/Actions/ActionHandling.swift
/// Único punto de entrada de las acciones de usuario de una pantalla.
@MainActor
public protocol ActionHandling: AnyObject {
    associatedtype Action: Sendable
    func handle(_ action: Action)
}

/// Lo ÚNICO que la vista recibe para actuar sobre la pantalla: no ve los métodos del VM.
public struct ActionSender<Action: Sendable>: Sendable {
    public init(_ handler: @escaping @MainActor @Sendable (Action) -> Void)
    @MainActor public func callAsFunction(_ action: Action)        // send(.load)
    @MainActor public func send(_ action: Action)                  // alias explícito
}
public extension ActionHandling { var sender: ActionSender<Action> { get } }  // [weak self]

/// Un view model de pantalla = estado observable + acciones.
public typealias ScreenViewModel = ScreenState & ActionHandling
```

`ScreenContainer` y `PhaseView`:
```swift
public struct ScreenContainer<State: ScreenViewModel, Content: View>: View {
    public init(_ state: State,
                chrome: ScreenChrome = .native,
                @ViewBuilder content: @escaping (ActionSender<State.Action>) -> Content)
    // Se conserva el init con Bindings explícitos (sin objeto) y un init `stateOnly` para
    // pantallas puramente de lectura: `init(observing state: some ScreenState, chrome:, content: () -> Content)`.
}
// Modifier equivalente, idiomático SwiftUI (como .alert/.refreshable):
public extension View {
    func screen<State: ScreenState>(_ state: State, chrome: ScreenChrome = .native) -> some View
}
// EnvironmentValues: `@Environment(\.actionSender)` tipado vía `ActionSenderKey<Action>`; ScreenContainer
// lo inyecta para que subvistas profundas envíen acciones sin prop-drilling. Documentar el patrón
// `@Environment(ProfileViewModel.Sender.self)` alternativo si el tipado por Environment resulta incómodo.
```
- Los `init` de conveniencia de `ScreenContainer` (`title:`, `onBack:`, `searchText:`) se adaptan a `_ state:`.
- `ActionSender` captura el VM **débil**: la vista puede sobrevivir al VM sin retenerlo (coherente con AF-01).
- `BaseViewModel` NO cambia de API; solo gana la conformance a `ScreenState`. Ningún método nuevo obligatorio ahí:
  la obligación de `handle(_:)` la impone `ScreenContainer`/`ScreenViewModel`.
- Tests: `ActionSender` reenvía y no retiene (`weak var`), `ScreenContainer` compila con un `@Observable` propio que
  conforma `ScreenViewModel` sin heredar de `BaseViewModel` (test de compilación real), `.screen(_:)` produce las
  mismas decisiones de `ScreenPresentationLogic`, `handle(.load)` desde test sin exponer privados (ejemplo en
  `IntegrationTests`).
- README: sección nueva «Acciones: un solo punto de entrada» con el ejemplo completo (enum `Action`, `handle`,
  métodos privados, vista con `send(.load)`, test con `vm.handle(.load)`), y «Pantalla y cáscara: el contrato
  `ScreenState`» explicando por qué se pasa el VM (Observation) y por qué el tipo es un protocolo. Actualizar todos
  los ejemplos de `ScreenContainer(viewModel:)` → `ScreenContainer(vm) { send in … }`. `Examples/IntegrationExample`
  migra a `ActionHandling`.

## Ficheros
Sources: nuevos `Architecture/State/ScreenState.swift`, `Architecture/Actions/ActionHandling.swift` (junto a `Action.swift`), `UI/Containers/ScreenContainer.swift`, `UI/Containers/PhaseView.swift`, nuevo `UI/Containers/ScreenModifier.swift`, `Architecture/ViewModels/BaseViewModel.swift` (solo conformance/extension), `AppFoundation.swift` (doc de cabecera).
Tests: nuevo `ActionHandlingTests.swift`, `ScreenPresentationLogicTests.swift`/`ScreenChromeTests.swift` (adaptar), `IntegrationTests.swift`, `READMEExamplesTests.swift` (si existe tras X-02).
Docs: `AppFoundation/README.md`, `CHANGELOG.md` (`## [Unreleased]` → `### AppFoundation`), `Examples/IntegrationExample` (adaptar VM y tests).

## Criterios de aceptación
- [ ] `ScreenContainer(vm) { send in … }` **no compila** si `vm` no conforma `ActionHandling` (test negativo documentado en comentario) y **sí** compila con un `@Observable final class` propio que conforma `ScreenViewModel` sin heredar de `BaseViewModel` (test real).
- [ ] Dentro del closure de contenido no hay forma de invocar métodos del VM: el parámetro es `ActionSender<Action>` (revisión + README).
- [ ] `ActionSender` no retiene al VM (`weak var` test).
- [ ] `grep -rn "ScreenContainer(viewModel:" AppFoundation Examples` vacío.
- [ ] `SWIFT_STRICT_WARNINGS=1 swift build --build-tests` 0 warnings, `swift test --parallel` verde 3 veces, `xcodebuild build` iOS Simulator OK, `Examples/IntegrationExample` `swift test` verde.
