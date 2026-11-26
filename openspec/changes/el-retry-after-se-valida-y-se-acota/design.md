## Context

Ver `proposal.md` — Why. Lo que condiciona el cómo:

- `Duration.seconds(_: Double)` atrapa si el valor no cabe en su representación interna, un
  entero de attosegundos. `Duration.seconds(_: Int)` no atrapa con ningún `Int`: el mayor
  `Int64` en attosegundos sigue cabiendo. Medido el 2026-11-25 con Swift 6.4:
  `.seconds(Int.max)` da `9.223372036854776e+18 seconds`. También medido: `Int("+5")` es 5 e
  `Int("-5")` es −5, así que comprobar «solo dígitos» va antes de `Int(_:)`, no después.
- `performWithRetry` elige la espera en tres sitios:
  - `:326`, cuando un retrier devuelve `.retry`;
  - `:333`, por el camino de `RetryPolicy`;
  - `:349`, cuando falla `buildURLRequest`.

  En los tres la fórmula es `error.retryAfter ?? retryPolicy.jitteredDelay(...)`. En el
  tercero no hay respuesta, así que `retryAfter` siempre es `nil`.
- `RetryPolicy.maxDelay` acota hoy solo el backoff calculado (`baseDelay`); por defecto,
  16 s.
- Los tests del reintento usan `ManualClock` e `InMemoryTransport` y nunca duermen de verdad
  (`suite-determinista`).

## Goals / Non-Goals

**Goals:**

- Que ningún valor de `Retry-After` pueda terminar el proceso.
- Que ninguna petición espere entre dos intentos más de lo que su política permite.
- Que el cambio no toque ninguna firma pública.

**Non-Goals:**

- Ponerle techo a `RetryDecision.retryAfter(_:)`.
- Cambiar cómo se calcula el backoff.

## Decisions

### 1. El parser sigue RFC 9110 al pie de la letra

`delay-seconds` es `1*DIGIT`. El texto, sin espacios en los extremos como hoy, se acepta
solo si todos sus caracteres son dígitos ASCII, y se convierte con `Int(_:)`. Si no cabe en
un `Int`, la cabecera se ignora. El resultado se construye con `.seconds(Int)`, que no puede
atrapar.

Para la HTTP-date, el intervalo hasta la fecha se redondea **hacia arriba** a segundos
enteros: así nunca se reintenta antes de lo que pidió el servidor. Si el intervalo no es
finito o no cabe en un `Int`, la cabecera se ignora. Si es negativo, la espera es cero, como
hoy.

Alternativa descartada: **seguir con `TimeInterval` y rechazar solo lo no finito o
enorme.** Cierra el trap, pero sigue aceptando `2.5`, `1e3`, `+5` y `-5`, que el RFC no
permite y ningún servidor correcto manda. Para dejarlo seguro hacen falta más comprobaciones
que para dejarlo correcto.

### 2. El techo es `maxDelay`, y por encima no se reintenta

En `:326` y `:333`, si `error.retryAfter` supera `retryPolicy.maxDelay`, se lanza el error
en vez de dormir. Si no lo supera, se duerme ese valor exacto, como hoy. En `:349` no
cambia nada.

Alternativas descartadas:

- **Esperar `min(retryAfter, maxDelay)` y reintentar.** Reintenta antes de lo que pidió el
  servidor, que es justo lo que `Retry-After` pide no hacer. Ante un 429 lo normal es un
  segundo 429, así que gasta un intento y alarga el fallo.
- **Un techo propio, `RetryPolicy.maxRetryAfter`.** Añade API pública —sería MINOR— y una
  perilla más, cuando la auditoría que motiva este cambio pide quitar superficie.
  `maxDelay` ya dice «lo más que esta política espera entre dos intentos».
- **Una constante interna, por ejemplo 60 s.** No la ve ni la puede cambiar quien configura
  la política, y no hay un número que valga para todas las apps.

Por qué se devuelve el error y no se espera: la petición ya ha fallado. El error lleva
`retryAfter` con el valor que pidió el servidor, así que el `Logic` puede decirle al usuario
cuándo volver a intentarlo. Lo que no puede hacer es cancelar una espera de una hora que no
ve.

### 3. Un `.retry` de un retrier sigue la misma regla

En `:326`, un retrier que devuelve `.retry` delega la espera en el servidor o en el backoff.
Si el servidor pide más del techo, se aplica lo mismo: no se reintenta. Un retrier que
quiera reintentar de todos modos puede devolver `.retryAfter(_:)` con la espera que decida;
esa no lleva techo, porque la fija la app y no el servidor.

### 4. Primero se ve el trap

El test de la tabla del parser se ejecuta contra el `APIError.swift` de 1.3.1 antes de
tocarlo, filtrado a ese test. Tiene que terminar en `Fatal error`. Un test que dice cubrir
un crash y nunca lo ha provocado no prueba que lo cubra.

## Risks / Trade-offs

- **[Una app espera hoy, a propósito, más de 16 s por un `Retry-After`]** → pasa a recibir
  un error. Mitigación: subir `maxDelay` en su política, una línea. El CHANGELOG lo dice.
- **[`maxDelay` cambia de significado]** → deja de acotar solo el backoff y acota cualquier
  espera que venga del servidor. Es la razón por la que alguien podría leerlo como MINOR; lo
  decide quien publica.
- **[Un test que hoy no prueba lo que dice]** →
  `RetryBehaviorTests.retryAfterOverridesBackoff` se arregla porque este cambio lo obliga a
  cambiar su política. Se comprueba con una mutación (`proposal.md`, Impact).
- **[El CI usa otro Swift]** → la librería se compila allí con Xcode 26.0.1. Ver el límite en
  los criterios.
