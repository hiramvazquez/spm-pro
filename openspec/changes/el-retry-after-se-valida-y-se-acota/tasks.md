## 1. El parser, con el trap visto antes de arreglarlo

- [x] 1.1 En `CoreNetworking/Tests/CoreNetworkingTests/APIErrorTests.swift`, añadir un test
      parametrizado de Swift Testing sobre `APIError.parseRetryAfter`, con la tabla de los
      criterios de aceptación:
      - `"7"` y `" 7 "` → `.seconds(7)`; `"0"` → `.zero`; `"86400"` → `.seconds(86400)`;
      - `"inf"`, `"-inf"`, `"nan"`, `"1e30"`, `"1e3"`, `"2.5"`, `"+5"`, `"-5"`, `""`,
        `"abc"` y `String(repeating: "9", count: 30)` → `nil`.

      Los tests de HTTP-date que ya existen (`retryAfterHTTPDate`) no se tocan.
      Verificación: el test existe con esos quince casos.
      **Hecho (2026-11-25):** `retryAfterDelaySeconds(value:expected:)`, quince casos, con la
      forma de la tabla que ya había en el fichero (`category clasifica correctamente`):
      tipo fijado con `as [(String, Duration?)]` y sin coma final, que `swift format lint
      --strict` exige.
- [x] 1.2 **La premisa.** Ejecutar solo ese test contra el `APIError.swift` sin tocar:
      `cd CoreNetworking && swift test --filter APIErrorTests`. Verificación: el proceso de
      test termina con `Fatal error` en uno de los casos `inf` o `1e30`. Se anota aquí la
      línea literal. Si termina en verde o en un fallo normal, el test no provoca lo que dice:
      se para y se anota, no se toca el parser.
      **Resultado (2026-11-25, Swift 6.4):** se cumple. `swift test --filter APIErrorTests`
      exit 1, sin línea `Test run with`: el proceso murió antes del resumen.
      `Swift/Integers.swift:3113: Fatal error: Double value cannot be converted to _Int128
      because it is outside the representable range`, justo después de arrancar los casos
      `"inf"` y `"-inf"` —se ejecutan en paralelo, así que el log no dice cuál de los dos—, y
      una segunda, `Swift/LegacyInt128.swift:790: Fatal error: Overflow in multiplication`, la
      de `"1e30"`. Cierra `swiftpm-testing-helper … exited with unexpected signal code 5`.
- [x] 1.3 `CoreNetworking/Sources/CoreNetworking/APIError.swift`, `parseRetryAfter`:
      - `delay-seconds`: solo dígitos ASCII, comprobados antes de `Int(_:)`, y `.seconds(Int)`;
      - HTTP-date: el intervalo, redondeado hacia arriba a un `Int` de segundos, o `nil` si no
        es finito o no cabe; cero si es negativo;
      - el doc-comment de `retryAfter` dice qué valores se aceptan y que el resto se ignora.

      Verificación: `cd CoreNetworking && swift test --filter APIErrorTests` en verde, con el
      test de la 1.1 y `retryAfterHTTPDate` pasando, y con la última línea anotada aquí.
      Además, `grep -n "TimeInterval(trimmed)" Sources/CoreNetworking/APIError.swift` no
      devuelve nada.
      **Resultado (2026-11-25):** `swift test --filter APIErrorTests` exit 0,
      `✔ Test run with 26 tests in 1 suite passed after 0.006 seconds.`, con los quince casos
      de la tabla y `retryAfterHTTPDate` en verde. `grep -c "TimeInterval(trimmed)"` da `0`.
      `swift format lint --strict` limpio sobre el fichero.

## 2. El techo del reintento

- [x] 2.1 En `CoreNetworking/Tests/CoreNetworkingTests/RetryBehaviorTests.swift`, añadir, con
      `InMemoryTransport` y `RetryPolicy()` por defecto:
      - **Un 503 con `Retry-After: 86400`.** Exige que `execute` lanza un `APIError` con
        `statusCode == 503` y `retryAfter == .seconds(86400)`, que
        `transport.recorded.count == 1` y que no se pidió ningún `sleep`.
      - **Un 503 con `Retry-After: 16` y después un 200**, con `ManualClock` como los tests
        que ya hay. Exige que el `sleep` pedido es exactamente `.seconds(16)` y que la petición
        termina bien.

      **El primero no puede colgarse contra el código de hoy**, que dormiría 86400 s en un
      reloj que nadie avanza. Por eso no sirve esperar `task.value` con `ManualClock`. Tampoco
      sirve `clock.waitUntilSleeping()`: no admite cancelación (`ManualClock.swift:127-140`) y
      se colgaría con el código nuevo, que no duerme. Ni `.timeLimit`, por lo que explica
      `CancellationTests.swift:289-292`. Tiene que decidir con una señal que llegue en los dos
      casos. Una forma: un reloj de test privado del fichero cuyo `sleep` anota la espera
      pedida y lanza en vez de suspender; con el código de hoy el test sale rojo diciendo qué
      espera se pidió. La premisa —que el transporte llegó a responder el 503— se comprueba
      aparte y con su propio mensaje (`suite-determinista`).
      Verificación: los dos tests existen.
      **Hecho (2026-11-25):** `retryAfterAboveMaxDelayIsNotWaited` y
      `retryAfterAtMaxDelayIsWaited`. Los dos usan `RecordingClock`, un reloj con `now`
      congelado cuyo `sleep` anota la espera pedida y vuelve en el acto. Se eligió así, y no un
      reloj que lanza, porque de este modo el de 16 s también termina la petición —que es lo
      que pide la tarea— y nada puede colgarse. Dos diferencias con el texto de la tarea, las
      dos de forma: el segundo test usa también `RecordingClock` en vez de `ManualClock`; y el
      reloj no es privado del fichero sino `internal`, a nivel de fichero, porque `RetrierTests`
      lo necesita y copiarlo duplicaría el código. La premisa va con `#require` y su propio
      mensaje; el maxDelay por defecto, también.
- [x] 2.2 En `CoreNetworking/Tests/CoreNetworkingTests/RetrierTests.swift`, añadir:
      - **Un retrier que devuelve `.retry`, ante un 503 con `Retry-After: 86400`.** Exige lo
        mismo que el primer test de la 2.1, con la misma forma de no colgarse.
      - **Un retrier que devuelve `.retryAfter(.seconds(3600))`, con `maxDelay` de 16 s.**
        Exige que el `sleep` pedido es `.seconds(3600)`.

      Verificación: los dos tests existen.
      **Hecho (2026-11-25):** `retryDecisionWithRetryAfterAboveMaxDelayIsNotWaited` y
      `retryAfterDecisionIsNotCappedByMaxDelay`, los dos con `RecordingClock`.
- [x] 2.3 Contra el `APIService.swift` sin tocar, `cd CoreNetworking && swift test --filter
      "RetryBehaviorTests|RetrierTests"`. Verificación:
      - los dos tests de 86400 —el de la 2.1 y el de la 2.2— **fallan**, sin colgarse, con un
        mensaje que dice que se pidió una espera de 86400 s;
      - el de `Retry-After: 16` y el de `.retryAfter(3600)` pasan, porque eso ya funciona.

      Se anota aquí qué falló y con qué mensaje. Si alguno se cuelga, la 2.1 no está bien
      hecha: se para y se corrige el test, no el producto.
      **Resultado (2026-11-25):** se cumple, sin colgarse: exit 1 en 4 s,
      `✘ Test run with 23 tests in 2 suites failed after 0.009 seconds with 4 issues.` Los dos
      tests de 86400 fallan cada uno en dos exigencias —`waits.isEmpty`
      (`RetryBehaviorTests.swift:340`, `RetrierTests.swift:680`) y `requests == 1` (`:341`,
      `:681`)— con los mensajes `se pidió esperar [86400.0 seconds, 86400.0 seconds] en vez de
      devolver el error` y `se reintentó: 3 peticiones`. Su `statusCode` y su `retryAfter` no
      dan incidencia. Pasan `Retry-After igual a maxDelay…` y `RetryDecision.retryAfter no tiene
      el techo…`, como estaba previsto, y el resto de los dos ficheros.
- [x] 2.4 `CoreNetworking/Sources/CoreNetworking/APIService.swift`, `performWithRetry`: en las
      ramas de `:326` y `:333`, si `error.retryAfter` supera `retryPolicy.maxDelay`, lanzar
      `error` sin dormir. `:349` no se toca. Actualizar el doc-comment del método («Retry
      rules») con la regla nueva.
      Verificación: `git diff` de ese fichero solo toca `performWithRetry` y su doc-comment.
      **Hecho (2026-11-25):** `8 insertions(+)` en tres trozos —una viñeta nueva en «Retry
      rules» y la comprobación en las dos ramas—, los tres dentro de `performWithRetry` y su
      doc-comment. La rama de `buildURLRequest` (ahora `:357`) queda igual. La comprobación es
      la misma línea en las dos ramas en vez de una función auxiliar: así lo pedía la
      verificación de esta tarea, y son dos líneas.
- [x] 2.5 `RetryBehaviorTests.retryAfterOverridesBackoff`: su política pasa a
      `initialDelay: .seconds(3600), maxDelay: .seconds(7200)`, que es lo que su comentario
      dice que tiene. Verificación: pasa. Y, mutando `:333` para que use siempre
      `jitteredDelay`, se pone rojo, cosa que hoy no hace. Se anota la mutación y se restaura
      el fichero (mismo sha256).
      **Resultado (2026-11-25):** pasa con la política nueva, que se construye en el propio
      test con `APIService(...)` en vez del helper `service(...)`; un comentario dice por qué.
      Medido en las dos direcciones, con la mutación «el camino de la política usa siempre
      `jitteredDelay`»:
      - con el test ajustado y el código nuevo, sale rojo:
        `RetryBehaviorTests.swift:168:9: Expectation failed: requestedDelay <= .seconds(1)`;
      - con el test y el código de 1.3.1 —los tres ficheros sacados de `HEAD`—, la misma
        mutación sale **verde**: `✔ Test run with 1 test in 1 suite passed`. Confirma por
        medición lo que `proposal.md` decía por lectura: el test no distinguía el
        `Retry-After` del backoff.

      Los tres ficheros se restauraron con el mismo sha256. Un tropiezo al medir: la primera
      vez solo se volvieron a `HEAD` dos de los tres ficheros y `RetrierTests.swift` no
      compilaba sin `RecordingClock`; se repitió con los tres.
- [x] 2.6 `cd CoreNetworking && swift test --filter "RetryBehaviorTests|RetrierTests|APIErrorTests"`.
      Verificación: todo verde, incluidos los dos tests de 86400 que en la 2.3 fallaban. Se
      anota la última línea.
      **Resultado (2026-11-25):** exit 0,
      `✔ Test run with 49 tests in 3 suites passed after 0.007 seconds.`, con los dos tests de
      86400 en verde.

## 3. Documentación y CHANGELOG

- [x] 3.1 Doc-comment de `RetryPolicy.maxDelay` (`RetryPolicy.swift:53`): acota también la
      espera que pide el servidor; por encima no se reintenta. `Documentation.docc/Retry.md`
      (líneas 32-33) y `FAQ.md` (líneas 17-19): qué valores de `Retry-After` se aceptan y qué
      pasa por encima de `maxDelay`. Verificación: `cd CoreNetworking &&
      Scripts/check-doc-snippets.sh` en verde, y los dos artículos dicen las dos cosas.
      **Hecho (2026-11-25):** el doc de la propiedad `maxDelay` (`RetryPolicy.swift:33`) y el
      de su parámetro (`:53`); `Retry.md` y `FAQ.md` dicen qué valores se aceptan y qué pasa
      por encima de `maxDelay`, y `Retry.md` añade que `.retryAfter(_:)` no tiene ese techo.
      `check-doc-snippets.sh`: exit 0, `CoreNetworking: 13 bloques de snippet verificados`.
      Ninguno de los textos editados está dentro de un bloque de snippet.
- [x] 3.2 `CoreNetworking/CHANGELOG.md`: entrada `## [1.3.2] - sin publicar`, en la sección
      «Corregido», con los tres comportamientos que cambian (los que lista `proposal.md` en
      SemVer) y una línea para quien espera hoy más de 16 s a propósito: que suba `maxDelay`.
      Verificación: la entrada existe y nombra los tres.
      **Hecho (2026-11-25):** entrada `## [1.3.2] - sin publicar` › `### Corregido`, con los
      tres comportamientos numerados, «No cambia ninguna firma pública» y la línea para quien
      espera más de 16 s a propósito. La fecha y la decisión entre PATCH y MINOR son de quien
      publique.

## 4. Cierre

- [x] 4.1 `git status` y `git diff --stat`. Verificación: el cambio toca solo los ficheros
      que lista `proposal.md` en Impact y este directorio. Los doce borrados de `.claude/` que
      ya había en el árbol siguen sin stagear: se stagea por nombre de fichero, nunca con
      `git add -A`.
      **Resultado (2026-11-25):** nueve ficheros modificados, exactamente los nueve que
      lista Impact (`comm` entre las dos listas: nada sobra ni falta), más este directorio. Sin
      contar los borrados de `.claude/`: `+269 −8` en `CoreNetworking/` (`git diff --numstat`). Los doce
      borrados de `.claude/` siguen sin stagear.
- [x] 4.2 Stagear por nombre, `/kit-verifica` y `/kit-revisa`. Verificación: firma verde con
      `CoreNetworking · build + tests` y `snippets · los dos paquetes` entre sus pasos, y el
      revisor sin hallazgos que bloqueen. Se anotan aquí el `verificado:` de la firma y el
      veredicto.
      **Resultado (2026-11-25, kit 2.4.1):** primera firma verde (`2026-11-26T05:05:52Z`), y
      `/kit-revisa` en la ronda 1 de un presupuesto de 2: **AMBER**, sin nada roto. Su
      hallazgo: cuatro textos seguían prometiendo que `.retry` siempre reintenta, o decían
      «nunca más que `maxDelay`» sin la excepción de `.retryAfter(_:)`:
      - `RequestRetrier.swift:12-13` y `:30`;
      - `Retry.md:61`;
      - `FAQ.md:22`.

      Causa única: la lista de Impact no los nombraba. Se corrigió el acuerdo por escrito
      (`proposal.md`, Impact) y luego esos textos. Por la misma causa se añadió una frase a
      `Authentication.md` y otra al CHANGELOG: si el 401 que dispara `TokenRefreshRetrier`
      trae un `Retry-After` por encima del techo, el token se renueva y la petición no se
      reintenta.

      De sus opcionales se adoptaron tres, solo en tests:
      - `retryAfterHTTPDateRoundsUp`, con `now` fijo;
      - un `Retry-After: 86400` en `retryAfterDecisionIsNotCappedByMaxDelay`;
      - la premisa antes de afirmar en los dos tests de 86400.

      Comprobados con mutación: con el redondeo hacia abajo sale rojo
      `APIErrorTests.swift:291`; con el techo subido por encima del `switch` sale rojo
      `RetrierTests.swift:687`. Los ficheros se restauraron idénticos. No se adoptaron el log
      al cortar ni el refactor de `retryAfter` en una variable: son código de producción y
      habrían pedido otra ronda.

      Como el arreglo es prosa y tests, el punto se marcó sin segunda ronda. Firma final:
      `verificado: 2026-11-26T05:19:21Z`, `diff: de3b0bd2…`, `resultado: verde`, los siete
      pasos en ✅, con `CoreNetworking · build + tests` y `snippets · los dos paquetes` entre
      ellos. La suite de los tres ficheros: `✔ Test run with 50 tests in 3 suites passed`.

## Workflow follow-up

- El commit pasa por la puerta del kit. El push a `origin` (spm-pro) lo decide el owner: se
  para y se pregunta.
- Tras el push, el CI del monorepo es la única prueba con Xcode 26.0.1 y 26.2 (`LIMITES` de
  `kit.conf`). Si algo falla ahí, se anota y se decide; no se improvisa sobre el cambio.
- Publicar 1.3.2 —`git subtree split --prefix=CoreNetworking -b cn-only`, el tag `1.3.2` en
  `cn-only` y el push al remoto `cn`—, poner la fecha en el CHANGELOG y decidir PATCH o MINOR
  son del owner, con el procedimiento del README raíz y `docs/prd/CIERRE.md`.
- Después de publicar, AppStarter pasa a 1.3.2 en su propio cambio.
- Archivar, con `/kit-revisa` pasado: el delta crea `openspec/specs/reintentos-de-red/spec.md`.
