# El Retry-After se valida y se acota

## Why

CoreNetworking obedece la cabecera `Retry-After` de una respuesta sin validarla ni ponerle
techo. Con ciertos valores mata el proceso; con otros deja la petición esperando horas.

`APIError.parseRetryAfter` (`CoreNetworking/Sources/CoreNetworking/APIError.swift:307-317`)
pasa el texto de la cabecera a `TimeInterval` y de ahí a `Duration.seconds(_:)`. Esa
conversión atrapa cuando el valor no cabe. Medido el 2026-11-25 compilando la misma expresión
de las líneas 311-312, con Swift 6.4:

| `Retry-After` | Resultado |
|---|---|
| `2` | espera 2 s |
| `86400` | espera 24 h |
| `1e30` | `Fatal error: Overflow in multiplication` |
| `inf` | `Fatal error: Double value cannot be converted to _Int128 because it is outside the representable range` |
| `nan` | espera 0 s |

`performWithRetry` (`APIService.swift:326`, `:333` y `:349`) duerme lo que diga ese valor
antes de reintentar. Basta un 429 o un 5xx de un backend, una CDN o un portal cautivo con
una cabecera rara para tirar la app, o para dejar un `execute` colgado mientras el usuario
mira un indicador de carga.

Ninguno de esos valores es legal: RFC 9110 define `delay-seconds` como `1*DIGIT`, solo
dígitos. Que se acepten `1e30`, `inf`, `nan`, `2.5`, `+5` o `-5` es lo que abre la puerta al
fallo.

Lo encontró la auditoría del 2026-11-25 (`docs/AUDITORIA-2026-11-25.md`, defecto 1). Es el
único de sus hallazgos que puede tirar una app en producción.

## What Changes

- **`APIError.parseRetryAfter` solo acepta lo que permite RFC 9110.**
  - Para `delay-seconds`, acepta solo dígitos, como número entero de segundos; si el número
    no cabe, la cabecera se ignora.
  - Para una HTTP-date, el intervalo se redondea a segundos enteros y se ignora si no se
    puede representar.
  - Cualquier otra cosa devuelve `nil`, como hoy pasa con un texto que no es número ni
    fecha.
  - Ningún valor de la cabecera puede producir un trap.
- **El reintento nunca espera más que `retryPolicy.maxDelay` por un `Retry-After`.** Si el
  servidor pide más, no se reintenta y el error sale al que llamó: lleva `retryAfter`, así
  que el `Logic` puede decir «inténtalo en X». Vale para el camino de `RetryPolicy` y para un
  `RetryDecision.retry` de un retrier. Es la decisión central del cambio; ver `design.md`.
- **`RetryDecision.retryAfter(_:)` no cambia.** Es el retrier de la propia app quien decide,
  no el servidor.
- **La documentación lo dice:** el doc-comment de `APIError.retryAfter` y el de
  `RetryPolicy.maxDelay`, y los artículos `Retry.md` y `FAQ.md` de `Documentation.docc`.
- **Tests:** la tabla de valores del parser y los dos caminos del reintento —en el techo se
  espera; por encima no se reintenta—. `RetryBehaviorTests.retryAfterOverridesBackoff` se
  ajusta (ver Impact).
- Entrada en `CoreNetworking/CHANGELOG.md`.

### SemVer: PATCH, 1.3.2

No cambia ninguna firma pública: el código que compila contra 1.3.1 compila igual. Cambia
el comportamiento en tres casos, y los tres eran incorrectos:

1. Los valores que mataban el proceso ahora se ignoran y se usa el backoff.
2. Los valores no permitidos por RFC 9110 que hoy se aceptaban (`2.5`, `+5`, `-5`, `nan`)
   también se ignoran. Hoy significaban esperar 2,5 s, 5 s, 0 s y 0 s.
3. Un `Retry-After` mayor que `maxDelay` (16 s por defecto) deja de esperarse. Hoy se espera
   entero, sin límite.

Quien lea el tercer caso como cambio de contrato —`maxDelay` pasa de acotar el backoff a
acotar cualquier espera entre intentos— lo llevaría a MINOR, 1.4.0. Se propone PATCH porque
lo que deja de pasar es esperar sin límite; nadie puede depender de eso de forma razonable.
Lo decide quien publica.

## Capabilities

### New Capabilities

- `reintentos-de-red`: cuándo reintenta CoreNetworking una petición que falló y cuánto
  espera antes, incluido qué hace con el `Retry-After` del servidor.

### Modified Capabilities

Ninguna. `ci-toolchain` y `suite-determinista` no cambian; los tests nuevos cumplen la
segunda (reloj inyectado, sin dormir de verdad).

## Fuera de alcance

- **Los otros defectos de CoreNetworking que encontró la auditoría:**
  - el progreso de descarga que no emite fracciones;
  - el `+` sin codificar en la query;
  - el backoff tras refrescar el token, y `.noRetry` apagando el refresco;
  - los defaults del transporte a pelo;
  - `waitsForConnectivity`.

  Cada uno es su cambio.
- **`RetryDecision.retryAfter(_:)`**, que sigue sin techo (ver What Changes).
- **Publicar.** El `git subtree split`, el tag `1.3.2` en `cn-only` y el push al repositorio
  de CoreNetworking son un paso aparte, que decide el owner.
- **AppStarter.** Pasar a 1.3.2 es un cambio en ese repo, después de publicar.
- **AppFoundation**, entero.
- **Lo que ya cubre `RetryBehaviorTests.retryAfterOverridesBackoff`**, más allá del ajuste
  que obliga este cambio (ver Impact).

## Criterios de aceptación

- [ ] `APIErrorTests` tiene una tabla que fija `parseRetryAfter`:
  - `"7"` y `" 7 "` → 7 s; `"0"` → 0 s; `"86400"` → 86400 s;
  - `"inf"`, `"-inf"`, `"nan"`, `"1e30"`, `"1e3"`, `"2.5"`, `"+5"`, `"-5"`, `""`, `"abc"` y
    un número de 30 dígitos → `nil`.

  Los tests de HTTP-date que ya existen siguen pasando sin cambiar sus expectativas.
- [ ] Ese test, ejecutado contra el `APIError.swift` de 1.3.1, termina el proceso de test con
  un trap (`Fatal error`). Se anota la línea en `tasks.md`.
- [ ] Hay un test que, con `RetryPolicy` por defecto (`maxDelay` 16 s) y un 503 con
  `Retry-After: 86400`, exige a la vez:
  - que `execute` lanza un `APIError` cuyo `retryAfter` es 86400 s;
  - que el transporte registra **una** petición;
  - que no se pidió ningún `sleep`.

  Contra el código de 1.3.1, ese test sale rojo sin colgarse.
- [ ] Hay un test que, con `Retry-After` igual a `maxDelay`, exige que se reintenta y que el
  `sleep` pedido es exactamente `maxDelay`.
- [ ] Hay un test que hace lo mismo que el de 86400 pasando por un retrier que devuelve
  `.retry`, y otro que fija que `.retryAfter(_:)` de un retrier por encima de `maxDelay` sí
  se espera.
- [ ] `RetryBehaviorTests.retryAfterOverridesBackoff` sigue existiendo y, con su política
  ajustada, se pone rojo si el reintento usa el backoff en vez del `Retry-After`. Se
  comprueba mutando el código.
- [ ] Los doc-comments y los artículos `Retry.md` y `FAQ.md` dicen qué valores se aceptan y
  que por encima de `maxDelay` no se reintenta.
  `Scripts/check-doc-snippets.sh` en verde.
- [ ] `CoreNetworking/CHANGELOG.md` tiene la entrada del cambio, con los tres comportamientos
  que cambian.
- [ ] `/kit-verifica` en verde y `/kit-revisa` sin hallazgos que bloqueen.

**Límite, dicho antes de empezar:** la firma local es de Swift 6.4. El CI compila la librería
con Xcode 26.0.1 y ejecuta las suites con 26.2. Que el cambio compile y pase allí solo lo
prueba el CI, y eso va después del push, que decide el owner.

## Impact

- `CoreNetworking/Sources/CoreNetworking/APIError.swift`: `parseRetryAfter` y el
  doc-comment de `retryAfter`.
- `CoreNetworking/Sources/CoreNetworking/APIService.swift`: `performWithRetry`, en los dos
  sitios donde se elige `error.retryAfter` (`:326` y `:333`). El tercero (`:349`) es el
  error de `buildURLRequest`, que nunca lleva respuesta ni, por tanto, `Retry-After`; se deja
  como está.
- `CoreNetworking/Sources/CoreNetworking/RetryPolicy.swift`: solo el doc-comment de
  `maxDelay`.
- `CoreNetworking/Sources/CoreNetworking/Documentation.docc/Retry.md` y `FAQ.md`.
- `CoreNetworking/Tests/CoreNetworkingTests/APIErrorTests.swift`,
  `RetryBehaviorTests.swift` y `RetrierTests.swift`.
- `CoreNetworking/CHANGELOG.md`.
- **Corrección (2026-11-25, tras `/kit-revisa`; la lista de arriba se deja como se acordó).**
  Faltaban dos ficheros de documentación que el cambio deja diciendo algo falso:
  - el doc-comment de `RetryDecision.retry` y el de `RequestRetrier`
    (`CoreNetworking/Sources/CoreNetworking/Retry/RequestRetrier.swift:12-13` y `:30`), que
    prometen que `.retry` siempre vuelve a enviar la petición;
  - `Documentation.docc/Authentication.md`, que no dice qué pasa cuando el 401 que refresca
    el token trae un `Retry-After` por encima de `maxDelay`: el token se renueva, pero el
    `.retry` no se reintenta.

  `Retry.md` y `FAQ.md`, que ya estaban en la lista, tenían cada uno una frase del mismo
  tipo. Solo cambia prosa; ningún comportamiento.
- **`RetryBehaviorTests.retryAfterOverridesBackoff` hoy no distingue lo que dice.** Su helper
  fija `maxDelay` en 10 ms, así que el backoff «enorme» de 3600 s queda en 10 ms, que también
  cumple `<= 1 s`. Leído en `RetryPolicy.baseDelay`, no medido. Con este cambio, además, ese
  `Retry-After: 1` supera el techo y el test dejaría de reintentar. Su política pasa a
  `initialDelay` 3600 s y `maxDelay` 7200 s, como ya tienen los tests equivalentes de
  `RetrierTests`.
- Para quien consume la librería: con la política por defecto, un `Retry-After` de más de
  16 s se convierte en un error inmediato en vez de una espera. El error lleva el valor que
  pidió el servidor.
