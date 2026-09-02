# Changelog

Todos los cambios notables de este repositorio se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el
versionado de cada paquete es independiente (`AppFoundation`, `CoreNetworking`).

## [Unreleased]

### AppFoundation

#### Changed
- **Rotura de API**: `Container` es ahora `@MainActor`. Se elimina el `NSLock` y el
  `@unchecked Sendable`: el compilador garantiza que las fábricas de tipos `@MainActor`
  se ejecutan en el main actor, en lugar de un contrato documentado en un comentario
  (AF-09).
- `register(_:lifecycle:factory:)` recibe ahora el `Container` en la fábrica, que puede
  usarse para resolver las dependencias de esa fábrica desde el mismo contenedor.
- `Lifecycle.scoped(key:)`, `Container.createScope`/`destroyScope` desaparecen: un
  `Container(parent:)` por flujo (checkout, sesión) sustituye al scope con clave de
  cadena (AF-10).
- `@Inject` documentado como último recurso para clases hoja; las vistas usan
  `Environment` (AF-11).

#### Removed
- `ContainerConcurrencyTests.swift`: no hay concurrencia que probar en un contenedor
  `@MainActor`, el compilador la garantiza.

#### Added
- Detección de ciclos de dependencias (A → B → A) en las fábricas: `preconditionFailure`
  con un mensaje que nombra todos los tipos implicados.
