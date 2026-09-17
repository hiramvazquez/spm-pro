## Why

Los tres README prometen «Swift 6.2+ (swift-tools 6.2) — Xcode 26 o el toolchain
equivalente», pero el CI no comprueba esa promesa: `XCODE_VERSION: latest-stable` resuelve a
la 26.x **más nueva** que tenga la imagen, no al mínimo declarado. Medido el 2026-09-16 con
`gh api repos/actions/runner-images/…`: en `macos-15` eso es hoy Xcode 26.3 (Swift 6.2.4).
Nadie valida Xcode 26.0, que es lo que el contrato dice soportar; y el día que la imagen
incorpore una Xcode mayor, `latest-stable` saltará sola y el contrato se romperá sin que
ningún job se ponga rojo.

Al mismo tiempo, quien mantiene los paquetes desarrolla con Xcode 27 (Swift 6.4), y ese
desfase ya costó caro: el 2026-09-16, las versiones 1.4.0 y 1.3.0 se publicaron con el CI en
rojo y hicieron falta **tres rondas** de CI para cerrarlo, porque los diagnósticos de
`MemberImportVisibility` que emite Swift 6.2.4 no los emite 6.4 y no hay forma local de
verlos (ver `design.md` para las tres mediciones).

## What Changes

- **El CI fija la versión de Xcode en vez de heredarla.** `XCODE_VERSION` pasa de
  `latest-stable` a una versión explícita, para que la imagen no pueda mover el toolchain
  bajo los pies sin que nadie lo decida.
- **Se valida el mínimo declarado, no solo la 26.x más reciente.** Al menos un job compila
  con la Xcode 26 más antigua disponible en la imagen, que es lo que promete el contrato de
  los README, y ejecuta la suite de tests con la 26.x más baja en la que esa suite pueda
  correr (ver «Enmienda»).
- **Queda escrito que Xcode 27 NO entra en el CI todavía, y bajo qué condición entraría.**
  No es preferencia: medido el 2026-09-16, ninguna imagen alojada trae una Xcode 27 estable
  —`macos-15` llega a 26.3, `macos-26` a 26.6, y la única con 27 trae la beta 6
  (`27A5252f`), que ni siquiera es el build que se usa en local (`27A266a`)—. (Ese dato sigue
  siendo válido; lo que se corrigió tras la revisión fue otra afirmación sobre esas mismas
  imágenes: ver `design.md`, D2.)
- **Aviso temprano de Swift 6.4**, en un job que no bloquea: que una incompatibilidad con el
  toolchain de desarrollo se vea en el CI y no al publicar.
- **El desfase se documenta donde se toman decisiones**, no solo en `kit.conf`.

No hay rotura de API: **PATCH** para ambos paquetes si acaba generando release, y puede que
no genere ninguna — este cambio toca infraestructura y documentación, no código de librería.

## Capabilities

### New Capabilities
- `ci-toolchain`: qué toolchain valida el CI, qué promete el contrato publicado, y cómo se
  mantienen alineados.

### Modified Capabilities
<!-- Ninguna: openspec/specs/ está vacío, este es el primer cambio del repo. -->

## Fuera de alcance

- **Mover el CI a Xcode 27.** No se puede hoy y no se va a forzar con una imagen beta como
  toolchain principal.
- **Cambiar el mínimo soportado.** Sigue siendo Swift 6.2 / Xcode 26; esta propuesta lo
  comprueba, no lo mueve.
- **Tocar los manifiestos de los paquetes**, sus upcoming features o su código.
- **Los tests sensibles al entorno de CoreNetworking** (`TransferTests`,
  `CancellationTests`), que fallan con el runner cargado. Es un problema real y distinto.
- **Los `ci.yml` propios de `AppFoundation/` y `CoreNetworking/`** —los que viajan en el
  `subtree split`—, que siguen con un selector de «la más reciente» y sin job de mínimo.
  Añadido tras la revisión del 2026-09-16 (tarea 8.1): el monorepo es la fuente y sí tiene
  la puerta, pero quien clone un repo publicado tiene un CI que no comprueba lo que su
  README promete. Merece su propio cambio.

## Criterios de aceptación

- [ ] `.github/workflows/ci.yml` no contiene un selector de «la más reciente», y cada
      versión de Xcode que usa está escrita explícitamente.
- [ ] Existe un job que **compila** ambos paquetes con la Xcode 26 **más antigua** de la
      imagen, y su nombre dice que es el mínimo soportado.
- [ ] Existe un job que **ejecuta las suites de test** con la 26.x más baja en la que corren,
      y el workflow dice por qué esa versión y no el mínimo.
- [ ] Los README distinguen el mínimo para **consumir** del mínimo para **desarrollar**.
- [ ] Existe un job de Swift 6.4 marcado como no bloqueante
      (`continue-on-error: true`), y su nombre dice que es aviso temprano.
- [ ] `.github/workflows/ci.yml` lleva, junto a las variables de versión, un comentario con
      la fecha y el comando que sustentan la elección.
- [ ] `AGENTS.md` de cada paquete dice con qué toolchain valida el CI y que una verificación
      local con 6.4 no prueba compatibilidad con el mínimo.
- [ ] `/kit-verifica` en verde.

## Impact

- `.github/workflows/ci.yml` — `env.XCODE_VERSION`, la matriz de `test`, y dos jobs nuevos.
- `AppFoundation/AGENTS.md` y `CoreNetworking/AGENTS.md` — la nota sobre el toolchain.
- Sin efecto sobre consumidores: no cambia API, mínimos declarados ni artefactos publicados.
- Más minutos de CI: dos jobs adicionales sobre la matriz actual.

## Enmienda — 2026-09-16, tras la primera corrida del job del mínimo

El job del mínimo se escribió para compilar **y** testear con Xcode 26.0.1. La primera
corrida (run `35127837096`) demostró que eso no es alcanzable, y el hallazgo es más valioso
que el plan original:

- **CoreNetworking**: compila, pero la suite no corre. Cuatro tests usan *exit tests* de
  swift-testing (`NetworkingConfigurationTests` ×3, `PinningTests` ×1) y en ese toolchain la
  facilidad no está implementada: `Testing/ExitTest.swift:398: Fatal error: Unimplemented`.
- **AppFoundation**: ni siquiera compila las pruebas. `ViewModelOwnershipTests.swift:99` y
  `:127` usan `weak let`, que ese compilador rechaza con «'weak' must be a mutable
  variable». Es la contrapartida de `ImmutableWeakCaptures`, activada en la 1.4.0.

Ambos hallazgos tienen la misma forma y no la que se temía: **las librerías cumplen el
mínimo publicado; lo que no lo cumple son sus suites de test**. Quien consume los paquetes
desde Xcode 26.0 no está afectado.

Por eso el alcance cambia, y se dice en vez de estrecharlo en silencio: el job del mínimo
pasa a **compilar** en 26.0.1 —que es lo que el contrato promete a quien consume— y la
ejecución de las suites se hace en la versión más baja en la que corren, medida en CI. Los
README pasan a distinguir las dos cosas, porque hoy las presentan como una sola.

**Sigue fuera de alcance** cambiar el mínimo publicado para consumir, y tocar los cuatro
tests de exit tests o el `weak let`: son hallazgos reales, con su causa, y merecen su propio
cambio si alguien decide que la suite debe correr en 26.0.
