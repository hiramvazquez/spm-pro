# PRD-AF-02 — Inyección de dependencias `@MainActor`

Paquete: AppFoundation · Oleada 1 · Cubre: AF-09, AF-10, AF-11 · Rompe API pública: **sí** (`Container` es `@MainActor`; desaparece `.scoped`)

## Problema
`Container` es `@unchecked Sendable` con `NSLock` y un contrato («resuelve tipos MainActor solo desde MainActor») que
vive en un comentario. Todo lo que lo usa ya es `@MainActor`. Dos mecanismos de scope. `@Inject` es un service
locator con `autoclosure` que parece registrar instancias.

## Diseño
```swift
@MainActor
public final class Container {
    public static let shared = Container()
    public init(parent: Container? = nil)
    public func register<T>(_ type: T.Type = T.self, lifecycle: Lifecycle = .singleton, factory: @escaping @MainActor (Container) -> T)
    public func register<T>(instance: T, as type: T.Type = T.self)          // singleton ya construido
    public func resolve<T>(_ type: T.Type = T.self) -> T                     // trap si falta (documentado)
    public func tryResolve<T>(_ type: T.Type = T.self) -> T?
    public func canResolve<T>(_ type: T.Type) -> Bool
    public func reset()
    #if DEBUG  public func registeredTypes() -> [String]; public func validateRegistrations(_:) #endif
}
public enum Lifecycle: Sendable, Equatable { case singleton, transient }   // `.scoped` desaparece: usa Container(parent:) por flujo
```
- Claves por `ObjectIdentifier(type)`; sin lock; sin double-checked locking; la fábrica recibe el contenedor para
  resolver sus dependencias (elimina el «no correr bajo el lock»).
- `@Inject`: se mantiene **solo** para clases hoja; documentado como último recurso; `@MainActor`; sin cambios de
  semántica salvo la nueva firma del contenedor. Añadir al doc por qué en Views se usa `Environment`.
- `DependencyModule.register(in:)` sin cambios de firma.
- README «Dependency injection»: composition root + child container por flujo (ejemplo de checkout) + tabla
  «cuándo constructor / cuándo Environment / cuándo @Inject».

## Ficheros
Sources: `DependencyInjection/Container.swift` (reescritura), `Lifecycle.swift`, `Inject.swift`, `DependencyModule.swift` (docs).
Tests: `ContainerTests.swift` (adaptar; añadir «fábrica resuelve sus dependencias del mismo contenedor», «child por flujo sustituye a scoped»), `ContainerConcurrencyTests.swift` (**borrar**: no hay concurrencia que probar; el compilador lo garantiza), `IntegrationTests.swift` (`featureFlowScopeLifecycle` → child container).
README: «Dependency injection», «Recommended project flow §1».

## Criterios de aceptación
- [ ] `grep -rn "NSLock\|@unchecked\|createScope\|destroyScope\|scoped(" Sources Tests README.md` vacío.
- [ ] Resolver desde un contexto `nonisolated` no compila (test negativo documentado en el PRD final; no ejecutable).
- [ ] Ciclo de dependencias A→B→A en fábricas: trap con mensaje que nombra ambos tipos (test de la detección con un guard de reentrada, no del trap).
- [ ] Todo el flujo del README compila tal cual (copiar en un test `README examples compile`).
