# PRD-AF-01 — `BaseViewModel`: memoria, cancelación y presentación de errores

Paquete: AppFoundation · Oleada 1 · Cubre: AF-01 (crítico), AF-02, AF-03, AF-04, AF-05, AF-06, AF-07, AF-08 · Rompe API pública: **sí** (`performLoad`/`performActivity` reciben el VM como parámetro)

## Problema
1. Fuga verificada: `phase → ScreenError.retry → work → self`. Con `self.` fuerte en `work` (uso documentado) el VM
   en fase `.error` no se libera nunca.
2. `deinit` nunca cancela un load en vuelo porque `work` retiene `self`.
3. El fallback muestra `localizedDescription` de errores no-`LocalizedError` («… error 9»).
4. No hay un punto único donde la app mapee errores a copy.

## Diseño

### Closures que no capturan el VM
```swift
public protocol LoadableViewModel: BaseViewModel {}      // BaseViewModel conforma; los subtipos heredan Self correcto
public extension LoadableViewModel {
    @discardableResult
    func performLoad(style: ActivityStyle = .fullScreen,
                     errorTitle: LocalizedStringResource? = nil,
                     successTransition: LoadSuccessTransition = .setContent,
                     _ work: @escaping @MainActor (Self) async throws -> Void) -> Task<Void, Never>
    @discardableResult
    func performActivity(style: ActivityStyle = .overlay,
                         errorHandling: ActivityErrorHandling = .banner,
                         _ work: @escaping @MainActor (Self) async throws -> Void) -> Task<Void, Never>
    /// Variante ESTRUCTURADA: corre inline en el Task del llamador (p. ej. `.task { await vm.load { … } }`);
    /// la cancelación de la vista cancela el trabajo. No guarda Task.
    func load(style:…, _ work: @escaping @MainActor (Self) async throws -> Void) async
    func activity(style:…, _ work: @escaping @MainActor (Self) async throws -> Void) async
}
```
- Implementación interna en `BaseViewModel` (`_performLoad(_ work: @escaping @MainActor () async throws -> Void)`)
  con `Task { [weak self] in guard let self else { return } … }` y el retry guardado como
  `{ [weak self] in self?.performLoad(…, work) }` donde `work` ya **no** captura al VM. Sin ciclo.
- Las versiones antiguas (`work: () async throws -> Void`) se **eliminan** (no `deprecated`): dejarlas mantiene la
  fuga para quien no migre.
- `deinit` se mantiene (ahora sí cancela: nada retiene al VM).

### Cancelación
```swift
public protocol CancellationRecognizing: Sendable { func isCancellation(_ error: any Error) -> Bool }
// default: `error is CancellationError || (error as? URLError)?.code == .cancelled`; la app añade sus tipos.
```

### Presentación de errores
```swift
public protocol ErrorPresenting: Sendable {
    func screenError(for error: any Error, fallbackTitle: String, retry: Action?) -> ScreenError
}
public struct DefaultErrorPresenter: ErrorPresenting {
    // 1. AppErrorConvertible → su ScreenError (retry inyectado)
    // 2. LocalizedError con errorDescription no nil → título fallback + errorDescription
    // 3. resto → título fallback + L10n.genericErrorMessage ("Algo ha ido mal. Inténtalo de nuevo." / EN)
    //    y AppFoundationLogger.errors.error("unpresentable error: \(String(describing: error), privacy: .private)")
}
open class BaseViewModel {
    public static var errorPresenter: any ErrorPresenting = DefaultErrorPresenter()      // @MainActor static; configurable en el arranque de la app
    public static var cancellationRecognizer: any CancellationRecognizing = DefaultCancellationRecognizer()
    public init(errorPresenter: (any ErrorPresenting)? = nil)   // override por instancia
}
```
- `handleActivityError` y el `catch` de load usan el presenter. `WrappedError.screenError` usa `context` como título
  y el mensaje del `underlying` **solo** si es `LocalizedError`; si no, el genérico.
- `WrappedError`: `#fileID`, `now: () -> Date = Date.init` inyectable, quitar `debugDescription` muerto o conformar
  `CustomDebugStringConvertible`, quitar `Equatable` (o documentar que compara contexto+código solamente).
- README: sección «Errores» reescrita con `ErrorPresenting` y un ejemplo de presenter que entiende un error de red
  por categoría (sin depender de CoreNetworking: ejemplo con un enum de la app). Doc de `AppErrorConvertible`
  corregida (AF-07); `Background.swift` sin `@StateObject`.

## Ficheros
Sources: `Architecture/ViewModels/BaseViewModel.swift`, nuevo `Architecture/ViewModels/LoadableViewModel.swift`, nuevo `Architecture/AppError/ErrorPresenting.swift`, nuevo `Architecture/AppError/CancellationRecognizing.swift`, `Architecture/AppError/WrappedError.swift`, `Architecture/AppError/AppErrorConvertible.swift` (solo docs), `Utilities/L10n.swift` (+ `genericErrorMessage`), `Utilities/AppFoundationLogger.swift` (+ `errors`), `Resources/*/Localizable.strings` (nueva clave; si AF-03 ya migró a xcstrings, coordinar en el merge), `UI/Containers/Background.swift` (solo doc comment).
Tests: `BaseViewModelTests.swift`, `WrappedErrorTests.swift`, `IntegrationTests.swift` (adaptar closures), nuevo `BaseViewModelMemoryTests.swift`, nuevo `ErrorPresentingTests.swift`, `LocalizationTests.swift` (nueva clave).
README: «Errores», «BaseViewModel guidance», ejemplos de `performLoad`.

## Criterios de aceptación
- [ ] `BaseViewModelMemoryTests`: (a) VM en `.error` tras `performLoad { vm in … throw }` se libera al salir de scope (`weak var == nil`); (b) VM con load en vuelo se libera y el `Task` observa `Task.isCancelled == true` (usar un `ManualClock`/`AsyncStream` para no dormir); (c) VM en `.content` se libera.
- [ ] `performLoad { … }` sin parámetro de VM **no compila** (la API antigua no existe).
- [ ] Error `enum Foo: Error { case bar }` en load → `phase == .error(ScreenError(title: L10n.error, message: L10n.genericErrorMessage))`; la cadena «couldn't be completed» no aparece en ningún `ScreenError` (test).
- [ ] Presenter por instancia y estático: tests de precedencia (instancia > estático > default).
- [ ] `URLError(.cancelled)` en load no produce fase `.error` (test).
- [ ] Banner auto-dismiss con `Clock` inyectable; `grep -n "Task.sleep" Sources/AppFoundation/Architecture` vacío.
- [ ] README sin ningún ejemplo con `self.` dentro de `performLoad`/`performActivity`.
