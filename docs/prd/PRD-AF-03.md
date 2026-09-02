# PRD-AF-03 — Utilidades: `Debouncer`/`Throttler`, `AppEnvironment`, String Catalog

Paquete: AppFoundation · Oleada 1 · Cubre: AF-19, AF-20, AF-21 · Rompe API pública: **sí** (`Debouncer` deja de ser actor y genérico)

## Diseño
### Debouncer / Throttler
```swift
@MainActor public final class Debouncer {
    public init(delay: Duration, edge: DebouncerEdge = .trailing, clock: any Clock<Duration> = ContinuousClock())
    public func debounce(_ operation: @escaping @MainActor () async -> Void)    // sin @Sendable, sin saltos
    public func cancel(); public func reset(); public func executeImmediately(_:) async
    deinit { /* cancela tasks */ }
}
@MainActor public final class Throttler { … mismo criterio … }
```
- Justificación en el doc comment: el estado solo lo toca el llamador; un actor añadía `Task { await … }` y `@Sendable`
  sin aportar aislamiento útil. Referencia a la auditoría AF-19.
- Doc: recomendar `.task(id:)` de SwiftUI para búsqueda; `Debouncer` para código no-View.

### AppEnvironment
- `enum AppEnvironment` (namespace). Eliminar `isTestOrPreview` y `printDebugInfo`/`debugInfo`. Mantener
  `isDebug`, `isRelease`, `isSimulator`, `isDevice`, `isTestFlight` (anotación actual), `isProduction`, metadatos de
  bundle, locale/timezone. `physicalMemoryFormatted` → `physicalMemory.formatted(.byteCount(style: .memory))`.
- `deviceModel` y compañía: mantener `@MainActor` (UIDevice).

### Localización
- Migrar `Resources/{en,es}.lproj/Localizable.strings` a `Resources/Localizable.xcstrings` (mismas claves y valores;
  usar el formato JSON del String Catalog a mano si no hay Xcode disponible; `swift build` lo compila).
- `L10n` doc actualizado; `LocalizationTests` leen del catálogo.
- Documentar `@_disfavoredOverload` en un comentario único (en `ScreenError`) y referenciarlo desde los demás usos.

## Ficheros
Sources: `Utilities/Debouncer.swift`, `Architecture/Environment/AppEnvironment.swift`, `Utilities/L10n.swift`, `Resources/**`, `Package.swift` (solo si el `.process("Resources")` necesita cambio; no debería).
Tests: `DebouncerTests.swift` (adaptar: sin `await` en `debounce`, `ManualClock` se conserva), `AppEnvironmentTests.swift`, `LocalizationTests.swift`.
README: «Utilities», «Notes».

## Criterios de aceptación
- [ ] `grep -rn "actor Debouncer\|actor Throttler\|isTestOrPreview\|XCTestCase\|String(format:" Sources` vacío.
- [ ] Un VM `@MainActor` puede hacer `debouncer.debounce { self.query = … }` sin `Task` ni `await` (test compila y ejecuta con `ManualClock`).
- [ ] `find Sources -name "*.strings"` vacío; `Localizable.xcstrings` con EN y ES; `LocalizationTests` verdes.
- [ ] Tests de Debouncer/Throttler siguen sin sleeps reales.
