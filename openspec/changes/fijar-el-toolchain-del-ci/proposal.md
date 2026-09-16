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
- **Se valida el mínimo declarado, no solo la 26.x más reciente.** Al menos un job compila y
  testea con la Xcode 26 más antigua disponible en la imagen, que es lo que promete el
  contrato de los README.
- **Queda escrito que Xcode 27 NO entra en el CI todavía, y bajo qué condición entraría.**
  No es preferencia: medido el 2026-09-16, ninguna imagen alojada trae una Xcode 27 estable
  —`macos-15` llega a 26.3, `macos-26` a 26.6, y la única con 27 trae la beta 6
  (`27A5252f`), que ni siquiera es el build que se usa en local (`27A266a`)—.
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

## Criterios de aceptación

- [ ] `.github/workflows/ci.yml` no contiene `latest-stable`; `XCODE_VERSION` nombra una
      versión concreta.
- [ ] Existe un job que compila y testea ambos paquetes con la Xcode 26 **más antigua** de la
      imagen, y su nombre dice que es el mínimo soportado.
- [ ] Existe un job de Swift 6.4 marcado como no bloqueante
      (`continue-on-error: true`), y su nombre dice que es aviso temprano.
- [ ] `.github/workflows/ci.yml` lleva, junto a `XCODE_VERSION`, un comentario con la fecha
      y el comando que sustentan la elección de versión.
- [ ] `AGENTS.md` de cada paquete dice con qué toolchain valida el CI y que una verificación
      local con 6.4 no prueba compatibilidad con el mínimo.
- [ ] `/kit-verifica` en verde.

## Impact

- `.github/workflows/ci.yml` — `env.XCODE_VERSION`, la matriz de `test`, y dos jobs nuevos.
- `AppFoundation/AGENTS.md` y `CoreNetworking/AGENTS.md` — la nota sobre el toolchain.
- Sin efecto sobre consumidores: no cambia API, mínimos declarados ni artefactos publicados.
- Más minutos de CI: dos jobs adicionales sobre la matriz actual.
