# spm-pro

Dos paquetes Swift para arrancar apps SwiftUI con la misma base: uno para la
arquitectura de pantalla y otro para la capa de red. Swift 6.2 en serio
(`defaultIsolation(MainActor)`, modo de lenguaje 6, warnings como errores en
desarrollo) y sin dependencias externas. Cada paquete se publica de forma
independiente — ver [«Cómo se publica»](#cómo-se-publica) — así que toda su
documentación, ejemplos y changelog viven dentro de su propio directorio.

| Paquete | Qué resuelve | Documentación |
|---------|--------------|--------|
| **AppFoundation** | Estado de pantalla (`BaseViewModel`, `ViewPhase`, `ActivityState`), navegación (`Coordinator`, `Router`, deep links), inyección de dependencias (`Container`, `@Inject`), shell de UI (`ScreenContainer`), utilidades (`Debouncer`, `Throttler`, `AppEnvironment`), y el kit de arquitectura View → ViewModel → Logic → Services/Stores con generador (`generate-feature`) y linter (`ArchitectureLint`). | [`AppFoundation/README.md`](AppFoundation/README.md) · [DocC](AppFoundation/Sources/AppFoundation/Documentation.docc) |
| **CoreNetworking** | Cliente sobre `URLSession` con typed throws (`APIError`), retry seguro con backoff, SSL pinning (SPKI), interceptores, autenticación con refresh de token, y un producto separado de mocks (`CoreNetworkingTestSupport`). | [`CoreNetworking/README.md`](CoreNetworking/README.md) · [DocC](CoreNetworking/Sources/CoreNetworking/Documentation.docc) |

Son independientes: se pueden adoptar por separado. Juntos, `AppFoundation` presenta
los errores que `CoreNetworking` tipa — ver `AppFoundation/Examples/LoginApp` para el
ejemplo completo de los dos compuestos.

## Requisitos

- Swift 6.2+ (swift-tools 6.2) — Xcode 26 o el toolchain equivalente.
- iOS 17+ / macOS 14+.

## Instalación

Cada paquete se instala por separado, apuntando a su propio repositorio publicado (ver
«Cómo se publica»):

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/hiram0816/AppFoundation.git", from: "1.0.0"),
    .package(url: "https://github.com/hiram0816/CoreNetworking.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MiApp",
        dependencies: [
            .product(name: "AppFoundation", package: "AppFoundation"),
            .product(name: "CoreNetworking", package: "CoreNetworking")
        ]
    )
]
```

En Xcode: *File ▸ Add Package Dependencies…*, pega la URL de cada repo y elige los
productos que necesites.

## Cómo correr todo en local

Este repositorio (`spm-pro`) es el monorepo de desarrollo: los dos paquetes viven en
subdirectorios con su propio `Package.swift`, y todo se ejecuta desde el directorio de
cada paquete.

```bash
cd AppFoundation    # o CoreNetworking
SWIFT_STRICT_WARNINGS=1 swift build --build-tests   # nivel 0: 0 warnings
swift test --parallel                                # Swift Testing, macOS
xcodebuild test -scheme AppFoundation \
  -destination "platform=iOS Simulator,name=iPhone 17"
xcodebuild test -scheme CoreNetworking-Package \
  -destination "platform=iOS Simulator,name=iPhone 17"
```

Con dos productos, SPM no genera un scheme `CoreNetworking` con acción de test: el
agregado se llama `CoreNetworking-Package`. Si el nombre del simulador no existe en tu
máquina, `xcrun simctl list devices available` te da los que hay.

Los cinco ejemplos (`AppFoundation/Examples/{CounterApp,NotesApp,LoginApp,CatalogApp}`,
`CoreNetworking/Examples/APIClientApp`) son paquetes SwiftPM autocontenidos: `cd` a cada
uno y `swift test`.

Formato: `swift format` del toolchain con la configuración de [`.swift-format`](.swift-format):

```bash
swift format lint --strict --recursive AppFoundation/Sources AppFoundation/Tests \
                              AppFoundation/Examples AppFoundation/Plugins \
                              CoreNetworking/Sources CoreNetworking/Tests \
                              CoreNetworking/Examples
```

Documentación: Xcode, **Product ▸ Build Documentation** con el scheme del paquete, o
desde línea de comandos:

```bash
xcodebuild docbuild -scheme AppFoundation -destination 'generic/platform=iOS Simulator'
xcodebuild docbuild -scheme CoreNetworking-Package -destination 'generic/platform=iOS Simulator'
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) ejecuta lint, tests
(macOS + iOS Simulator) por paquete, los cinco ejemplos, la generación de documentación,
la compilación de `Snippets/` y la verificación del generador/linter.

## Cómo se publica

SwiftPM resuelve un paquete remoto por URL exigiendo `Package.swift` en la raíz del
repositorio — este monorepo tiene dos paquetes en subdirectorios, así que ninguno se
consume directamente desde aquí. Cada uno se publica por
[`git subtree split`](https://git-scm.com/docs/git-subtree), que reescribe el historial
de su subdirectorio como si siempre hubiera sido la raíz de su propio repositorio:

```bash
# CoreNetworking
git subtree split --prefix=CoreNetworking -b cn-only
git push <remoto-corenetworking> cn-only:main
git tag -a 1.0.0 cn-only -m "CoreNetworking 1.0.0"
git push <remoto-corenetworking> 1.0.0

# AppFoundation
git subtree split --prefix=AppFoundation -b af-only
git push <remoto-appfoundation> af-only:main
git tag -a 1.0.0 af-only -m "AppFoundation 1.0.0"
git push <remoto-appfoundation> 1.0.0
```

El tag se crea siempre en la rama split (`cn-only`/`af-only`), nunca en `main`: es la
única rama con `Package.swift` en la raíz. Antes de empujar, `git ls-tree -r --name-only
cn-only | grep -E "README|CHANGELOG|AGENTS|docc|Snippets|Examples"` confirma que el árbol
publicado trae README, CHANGELOG, AGENTS.md, `Documentation.docc`, `Snippets` y
`Examples`. Ver [`docs/prd/CIERRE.md`](docs/prd/CIERRE.md) para el checklist completo
antes de un tag.

## Estado y hoja de ruta

Este monorepo conserva su historia técnica en `docs/`: la auditoría inicial y su doble
check, el análisis que llevó al kit de arquitectura, y los PRD de remediación (agrupados
en oleadas, con la verificación cruzada de cada hallazgo).

- [`docs/AUDITORIA-2026-09-01.md`](docs/AUDITORIA-2026-09-01.md) /
  [`docs/AUDITORIA-2026-09-02-doblecheck.md`](docs/AUDITORIA-2026-09-02-doblecheck.md)
- [`docs/ARQUITECTURA-KIT-2026-09-02.md`](docs/ARQUITECTURA-KIT-2026-09-02.md)
- [`docs/prd/`](docs/prd/README.md) — PRD por oleada, con la Definition of Done común.
- [`docs/prd/CIERRE.md`](docs/prd/CIERRE.md) — estado de cada hallazgo, el kit de
  arquitectura, y el procedimiento de publicación/tag.
- [`CHANGELOG.md`](CHANGELOG.md) — índice; el detalle está en el `CHANGELOG.md` de cada
  paquete.

## Licencia

MIT — ver [LICENSE](LICENSE). © 2026 Hiram Vazquez.
