## Context

Ver `proposal.md` — Why. Lo que sigue son las mediciones que sostienen las decisiones, hechas
el 2026-09-16 con `gh api repos/actions/runner-images/contents/…` sobre `actions/runner-images`.

**Qué Xcode ofrece cada imagen alojada:**

| Label | Xcode disponibles | Notas |
|---|---|---|
| `macos-15` (arm64) | 16.3 … **26.0.1, 26.1.1, 26.2, 26.3** | la única con 26.0.x |
| `macos-26` (arm64, = `macos-latest`) | **26.1.1 … 26.6** | ya no trae 26.0.x |
| `xcode-27` (arm64) | **27.0 beta 6** (`27A5252f`) | imagen en *preview*, no GA |

**Por qué no basta con «usar Xcode 27»:** el build de esa imagen (`27A5252f`) no es el que se
usa en local (`27A266a`, Xcode 27.0 estable), así que ni siquiera reproduce la máquina de
desarrollo. Y es preview, con el ciclo de vida que eso implica.

**Por qué no se puede resolver en local**, medido tres veces el 2026-09-16 sobre esta máquina
(macOS 27, Xcode 27.0 `27A266a`):

1. Swift 6.4 **no emite** los diagnósticos de `MemberImportVisibility` que sí emite 6.2.4.
   Comprobado reintroduciendo el fallo y compilando con `swift build`, `swift build
   --build-tests` y el target explícito: cero diagnósticos en los tres.
2. El toolchain 6.2.4 instalado con `swiftly` **no compila nada** aquí: un paquete de tres
   líneas falla con `unknown argument: '-target-arch-variant'`, porque el SDK de macOS 27
   pasa banderas que ese frontend no conoce.
3. El toolchain 6.3.3 da errores espurios por la misma mezcla (`extra argument 'encoding'`).

De ahí la conclusión que ordena todo el diseño: **el CI es el único juez de la compatibilidad
con el mínimo**, y por eso tiene que comprobar el mínimo de verdad.

## Goals / Non-Goals

**Goals**
- Que el contrato publicado («Swift 6.2+ / Xcode 26») esté respaldado por un job que lo
  ejercita.
- Que ninguna actualización de imagen mueva el toolchain validado sin decisión humana.
- Que una incompatibilidad con el toolchain de desarrollo se vea antes de publicar.

**Non-Goals**
- Reproducir el CI en la máquina de desarrollo. Está medido que hoy no es posible sin
  instalar Xcode 26 entero, y eso queda a criterio de quien mantiene, no de este diseño.
- Elegir por el proyecto si algún día sube el mínimo. Este diseño lo comprueba; moverlo es
  otro cambio.

## Decisions

### D1. Dos versiones fijas en vez de un selector

`XCODE_VERSION: latest-stable` se sustituye por dos variables explícitas: la del **mínimo
soportado** y la **corriente** con la que corre el grueso de la matriz.

*Por qué no una sola:* validar solo el mínimo dejaría sin cubrir la versión que la gente usa
de verdad; validar solo la corriente es exactamente el agujero de hoy.

*Alternativa descartada — `latest-stable` con una comprobación que avise si cambia:* añade una
pieza que hay que mantener para conservar un comportamiento que no queremos. Fijar la versión
es restar, no añadir.

### D2. El job del mínimo se queda en `macos-15`

El mínimo declarado es Xcode 26, y **26.0.1 solo existe en `macos-15`**. Si la matriz se
moviera a `macos-26`, el mínimo comprobable pasaría a ser 26.1.1 sin que nadie lo decidiera —
el mismo fallo que esta propuesta viene a cerrar, con otra cara.

*Consecuencia aceptada:* el día que `macos-15` se retire, el mínimo comprobable subirá. Esa
fecha no la controlamos, y por eso el comentario de la variable lleva fecha: cuando deje de
ser cierta, se vuelve a decidir.

### D3. El aviso temprano usa `xcode-27` y no bloquea

Un job con `continue-on-error: true` sobre la imagen `xcode-27`. Da señal del toolchain de
desarrollo sin que una imagen en preview pueda bloquear una publicación.

*Alternativa descartada — instalar toolchains en el runner con `swiftly`:* medido hoy que
mezclar un toolchain con el SDK de otra versión no compila. Sería trasladar al CI un problema
que ya sabemos que no funciona.

*Condición para promoverlo a bloqueante,* escrita en el propio workflow: cuando `xcode-27`
deje de estar en preview y su Xcode sea estable (seguimiento en
`actions/runner-images#14404`).

### D4. El desfase se escribe en los `AGENTS.md`

`kit.conf` ya declara el límite, pero lo lee quien va a verificar. La nota va también a los
`AGENTS.md` de cada paquete, que es lo que lee un agente antes de tocar código — que es
justo donde se tomaron las decisiones que hoy costaron tres rondas de CI.

## Risks / Trade-offs

- **Una versión fija envejece y hay que subirla a mano** → el comentario junto a la variable
  lleva la fecha y el comando que la produjo, así que al leerla se sabe si sigue vigente.
- **La imagen `xcode-27` puede cambiar o desaparecer sin aviso, por ser preview** → el job no
  bloquea; si la label deja de existir, ese job falla solo él y la corrida sigue.
- **Más minutos de CI** (dos jobs sobre la matriz actual) → se acepta: el coste de no tenerlo
  ya se pagó una vez, en tres rondas y dos versiones publicadas en rojo.
- **El job del mínimo puede destapar incompatibilidades reales y frenar trabajo** → es
  exactamente lo que se busca; lo contrario es enterarse al publicar.

## Migration Plan

1. Fijar las variables y añadir los dos jobs en una rama.
2. Correr el CI ahí y confirmar que el job del mínimo (Xcode 26.0.1) pasa con el código
   actual. **Si no pasa, el hallazgo es real y se trata antes de seguir**: significaría que
   lo publicado hoy no cumple el mínimo que promete.
3. Mergear. Sin rollback especial: revertir el commit devuelve el CI a su estado anterior.

## Open Questions

- ¿El job del mínimo debe correr la matriz entera (incluido `xcodebuild` en simulador) o solo
  build y tests de SwiftPM? Se puede decidir al implementar, viendo cuánto tarda; no cambia
  el contrato del spec.
- ¿La label `xcode-27` está disponible para esta cuenta? Se comprueba en el primer push de la
  rama: si no lo está, el job falla sin bloquear y se retira hasta que lo esté.
