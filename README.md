# spm-pro

Dos paquetes Swift para arrancar apps SwiftUI con la misma base: uno para la
arquitectura de pantalla y otro para la capa de red. Swift 6.2 en serio
(`defaultIsolation(MainActor)`, modo de lenguaje 6, warnings como errores en
desarrollo) y sin dependencias externas.

| Paquete | Qué resuelve | README |
|---------|--------------|--------|
| **AppFoundation** | Estado de pantalla (`BaseViewModel`, `ViewPhase`, `ActivityState`), navegación (`Coordinator`, `Router`, deep links), inyección de dependencias (`Container`, `@Inject`), shell de UI (`ScreenContainer`) y utilidades (`Debouncer`, `Throttler`, `AppEnvironment`). | [AppFoundation/README.md](AppFoundation/README.md) |
| **CoreNetworking** | Cliente sobre `URLSession` con typed throws (`APIError`), retry seguro con backoff, SSL pinning (SPKI), interceptores y un producto separado de mocks (`CoreNetworkingTestSupport`). | [CoreNetworking/README.md](CoreNetworking/README.md) |

Son independientes: se pueden adoptar por separado. Juntos, `AppFoundation` presenta
los errores que `CoreNetworking` tipa.

## Requisitos

- Swift 6.2+ (swift-tools 6.2) — Xcode 26 o el toolchain equivalente.
- iOS 17+ / macOS 14+.

## Instalación

Por URL y tag (los dos paquetes comparten repo y tag; ver [CHANGELOG.md](CHANGELOG.md)):

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/hiram0816/spm-pro.git", from: "0.1.4")
],
targets: [
    .target(
        name: "MiApp",
        dependencies: [
            .product(name: "AppFoundation", package: "spm-pro"),
            .product(name: "CoreNetworking", package: "spm-pro")
        ]
    ),
    .testTarget(
        name: "MiAppTests",
        dependencies: [
            "MiApp",
            .product(name: "CoreNetworkingTestSupport", package: "spm-pro")
        ]
    )
]
```

En Xcode: *File ▸ Add Package Dependencies…*, pega la URL del repo y elige los
productos que necesites. Para desarrollo local, `.package(path: "../spm-pro")`.

Los manifiestos no imponen `-warnings-as-errors` a quien los consume: el gate
estricto solo se activa con la variable de entorno `SWIFT_STRICT_WARNINGS`
(ver el comentario en cada `Package.swift`).

## Desarrollo y tests

Desde el directorio de cada paquete:

```bash
SWIFT_STRICT_WARNINGS=1 swift build --build-tests   # nivel 0: 0 warnings
swift test --parallel                                # Swift Testing, macOS
xcodebuild test -scheme AppFoundation \
  -destination "platform=iOS Simulator,name=iPhone 17"
xcodebuild test -scheme CoreNetworking-Package \
  -destination "platform=iOS Simulator,name=iPhone 17"
```

Con dos productos, SPM no genera un scheme `CoreNetworking` con acción de test: el
agregado se llama `CoreNetworking-Package`. Si el nombre del simulador no existe en
tu máquina, `xcrun simctl list devices available` te da los que hay.

Formato: `swift format` del toolchain con la configuración de [`.swift-format`](.swift-format):

```bash
swift format lint --recursive AppFoundation/Sources AppFoundation/Tests \
                              CoreNetworking/Sources CoreNetworking/Tests
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) ejecuta exactamente eso
para cada paquete en un runner macOS, detectando el simulador disponible.

## Estado y hoja de ruta

- [`AUDITORIA-2026-09-01.md`](AUDITORIA-2026-09-01.md): auditoría técnica de ambos
  paquetes con 45 hallazgos (IDs `CN-xx` / `AF-xx`).
- [`PRD/`](PRD/README.md): los PRD de remediación, agrupados en oleadas, con la
  Definition of Done común y el orden de merge.
- [`CHANGELOG.md`](CHANGELOG.md): cambios por versión y por paquete.

## Licencia

MIT — ver [LICENSE](LICENSE). © 2026 Hiram Vazquez.
