## Why

La suite de CoreNetworking produce rojos recurrentes en puertas bloqueantes, siempre con
cero errores de compilación. El 2026-09-16, en las corridas de CI de esa jornada, tres
grupos de tests distintos fallaron en al menos cuatro ocasiones —el recuento exacto no es
reproducible desde la API, porque relanzar un job sobrescribe su conclusión— y en todos los
casos el veredicto fue el mismo: *eso es que el runner iba cargado*. Un rojo que se explica
así cada vez enseña a ignorar los rojos, y ese es el coste real, no los minutos.

Además contradice el propio diseño del paquete. `APIService` acepta un `Clock` inyectado
—`init(clock:)`, hallazgo CN-11 de la auditoría— y su documentación dice literalmente «no
real wall-clock waits in tests». Hay un `ManualClock` en `CoreNetworkingTestSupport` y
**siete ficheros de test lo usan**. `CancellationTests.swift` es el que se salta ese diseño
y mide con `ContinuousClock.now`.

Y agrupar los tres bajo la etiqueta «tests inestables» esconde lo que de verdad pasa: **solo
uno de los tres es un problema de tiempo**.

## What Changes

- **El test del backoff deja de medir con el reloj de pared.** `CancellationTests` mide
  `ContinuousClock.now` y exige que la ventana de backoff dure menos de 3 s. El mecanismo
  para no necesitarlo ya existe y lo usan otros siete ficheros.
- **Los cuatro tests de «se cancela de verdad» dejan de depender de la suerte.** Hoy asumen
  que la petición sigue en vuelo cuando llega la cancelación. Medido en el run `35070600701`:
  bajo carga llega `APIError(code: transport, underlying: URLError(-1001))`, es decir, la
  petición **terminó por timeout antes** de que la cancelación aterrizara. El test afirma
  sobre una premisa que no estableció, así que su rojo no significa lo que su nombre dice.
  (Al implementar se midió cuál es ese timeout: `timeoutIntervalForResource`, 60 s, no el de
  la petición. Ver `design.md` D2, enmendado.)
- **El probe de rendimiento de 5 MB se nombra como lo que es.** `data(for:) de 5 MB no es
  lenta` no comprueba corrección sino que no ha vuelto el bucle byte a byte, y lo hace con un
  presupuesto de reloj (200 ms en macOS, 20 s en simulador; medido 55 s y 130 s en runners
  cargados). Hay que decidir si una medición de rendimiento pertenece a una puerta
  bloqueante, y expresarla contra el mecanismo si se puede.

Sin rotura de API. Toca `Tests/` y, si el tercer punto lo exige, la configuración del CI.
**PATCH** si acaba generando release.

## Capabilities

### New Capabilities
- `suite-determinista`: qué puede y qué no puede usar la suite de tests para decidir si algo
  pasa, de forma que un rojo signifique siempre lo mismo.

### Modified Capabilities
<!-- Ninguna. `ci-toolchain` no cambia: esto no toca qué toolchain valida. -->

## Fuera de alcance

- **Subir los presupuestos de tiempo.** Es lo cómodo y es esconder el problema: un número
  más grande solo mueve la frontera a un runner más cargado.
- **Marcar tests como «flaky» para que se salten o se reintenten.** Un test que se reintenta
  hasta pasar no afirma nada.
- **La librería**, salvo que alguno de los hallazgos demuestre un defecto en ella. Si eso
  pasa, se renegocia por escrito antes de tocarla.
- **Los exit tests y el `weak let`** que impiden correr la suite en Xcode 26.0/26.1 (ver el
  cambio archivado `2026-09-16-fijar-el-toolchain-del-ci`).
- **Los `ci.yml` propios de cada paquete** (tarea 8.1 de ese mismo cambio).

## Criterios de aceptación

- [ ] `grep -c "ContinuousClock" CoreNetworking/Tests/CoreNetworkingTests/CancellationTests.swift`
      devuelve `0`, o cada uso restante lleva escrito al lado por qué el reloj inyectado no
      sirve ahí.
- [ ] Los cuatro tests de cancelación fallan si la cancelación NO interrumpe la operación, y
      **no** fallan porque la petición terminó antes por timeout. Se demuestra con una sonda:
      amputar la cancelación los pone rojos; alargar artificialmente la latencia del mock no.
- [ ] El probe de 5 MB, o bien no vive en una puerta bloqueante, o bien no decide con el
      reloj. La opción elegida queda escrita con su razón.
- [ ] Veinte corridas consecutivas de `swift test --parallel` en local, sin un solo rojo de
      estos tres grupos. El número y el comando quedan escritos en las tareas.
- [ ] `/kit-verifica` en verde.

## Impact

- `CoreNetworking/Tests/CoreNetworkingTests/CancellationTests.swift` — los cinco tests.
- `CoreNetworking/Tests/CoreNetworkingTests/TransferTests.swift` — el probe de 5 MB.
- Posiblemente `CoreNetworking/Sources/CoreNetworkingTestSupport/MockURLProtocol.swift`, si
  garantizar el estado «en vuelo» exige una señal que el mock todavía no expone.
- Posiblemente `.github/workflows/ci.yml`, si el probe de rendimiento sale de la puerta.
- Sin efecto sobre quien consume los paquetes.
