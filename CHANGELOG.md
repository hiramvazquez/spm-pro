# Changelog

Todos los cambios notables de este repositorio se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), y este proyecto
se adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html) una vez publique su
primera versión 1.0.

## [Unreleased]

### AppFoundation

#### Breaking

- `ScreenContainer` cambia su modelo de personalización de navegación: el parámetro
  `navigation:` desaparece en favor de `chrome: ScreenChrome`, con `.native` como valor por
  defecto (la barra nativa deja de ocultarse en cada ruta) y `.custom(NavigationBarConfiguration, placement:)`
  como opt-in explícito para la barra personalizada (PRD-AF-04, AF-12, AF-13).
- Los modifiers `.loadingView { }`, `.errorView { }`, `.emptyView { }` y `.bannerView { }` de
  `ScreenContainer` se eliminan en favor de los protocolos `LoadingViewStyle`,
  `ErrorViewStyle`, `EmptyViewStyle` y `BannerViewStyle`, propagados por `Environment`
  (`.loadingViewStyle(_:)`, `.errorViewStyle(_:)`, `.emptyViewStyle(_:)`,
  `.bannerViewStyle(_:)`) — sin `AnyView` en el call site (AF-15).
- `.alertView(builder:)` se elimina: las alertas siempre usan la presentación nativa.
- `NavigationBarItemContent.view`, `NavigationBarTitle.custom` y las propiedades
  `accessoryView`/`customContent` de `NavigationBarConfiguration` dejan de exponer
  `AnyView` en su firma pública; usan `ErasedView`, el único punto de type-erasure interno
  del paquete (documentado en `UI/Styles/ErasedView.swift`).
- `NavigationBarTitle.largeText` se elimina (no era una feature implementada).
- `BannerState.duration` cambia de `BannerState.Duration` (enum propio) a `Swift.Duration?`
  (`nil` = indefinido), y ya no sombrea el tipo del sistema.
- `Coordinator.navigationHistory` pasa a `internal` (antes era `public` solo en builds
  `DEBUG`, una API cuya existencia dependía de la configuración de build).

#### Added

- `ScreenChrome`: `.native` (la barra del sistema nunca se oculta; la pantalla la controla
  con `navigationTitle`/`toolbar`/`searchable`) y `.custom(NavigationBarConfiguration, placement:)`.
- `PopGestureEnabler` (`UI/Platform`, solo `iOS`): reinstala el gesto interactivo de
  swipe-back que `UINavigationController` desactiva al ocultar la barra nativa;
  `ScreenContainer` lo instala automáticamente cuando `chrome` es `.custom`.
- `LoadingViewStyle` / `ErrorViewStyle` / `EmptyViewStyle` / `BannerViewStyle` y sus
  implementaciones por defecto (`DefaultLoadingViewStyle`, etc.), con el mismo patrón que
  `ButtonStyle`/`ProgressViewStyle` de SwiftUI.
- `ScreenChromeTests.swift`: cobertura de la lógica pura de qué chrome oculta la barra
  nativa.
- Accesibilidad: los botones atrás/cerrar de `CustomNavigationBar` llevan
  `accessibilityLabel` localizado (`L10n.back`/`L10n.close`) y el trait `.isButton`;
  `NavigationSearchBar` expone `accessibilityLabel` y desactiva
  `textInputAutocapitalization` en iOS.

#### Fixed

- La barra nativa ya no se oculta en todas las rutas (`CoordinatorView`/`ScreenContainer`),
  lo que restaura el gesto de swipe-back para cualquier pantalla en `chrome: .native`
  (AF-12).
- `CustomNavigationBar` ya no se instancia dos veces en el árbol (contenido + overlay de
  estado): el chrome se instala una única vez alrededor de todo el screen (AF-17).
- Altura de `CustomNavigationBar` con `@ScaledMetric` en vez de un valor fijo de 44pt;
  iconos con fuentes semánticas (`.headline`/`.subheadline`) en vez de tamaños fijos
  (Dynamic Type, AF-16).
- APIs deprecadas o de otra época: `.edgesIgnoringSafeArea` → `.ignoresSafeArea(.container, edges:)`,
  `.foregroundColor` → `.foregroundStyle`, `.cornerRadius(_:)` → `.clipShape(.rect(cornerRadius:))`,
  `PreviewProvider` → `#Preview` (AF-16).
- `Background.swift` se renombra a `PhaseView.swift` para que el fichero coincida con el
  tipo que contiene (AF-18).
