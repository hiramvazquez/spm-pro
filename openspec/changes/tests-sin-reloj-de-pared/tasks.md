## 1. Grupo B — los cuatro «se cancela de verdad» (primero, puede destapar algo)

- [x] 1.1 Reproducir el fallo a voluntad: alargar la latencia del mock o estrechar el timeout
      hasta que llegue `URLError(-1001)` en vez de `.cancelled`. Verificación: el test falla
      con el mismo mensaje que el run `35070600701`, en local y sin carga artificial.
      **Hecho**: con `timeoutIntervalForResource = 0.3` y un «atasco» de 1 s antes de
      cancelar, sale `APIError(code: transport, method: GET, underlying: URLError(-1001))`,
      idéntico al de CI. Estrechar el `timeout` de la petición a 50 ms NO lo reproduce.
- [x] 1.2 Comprobar de dónde sale el timeout que gana la carrera (configuración del test,
      `NetworkingConfiguration` por defecto, o el del mock) y anotarlo aquí.
      **Respuesta**: `timeoutIntervalForResource`, **60 s**, que impone
      `NetworkingConfiguration.enforceSecurityFloor`. NO es `BaseRequest.timeout`, que es un
      timeout de INACTIVIDAD entre paquetes (`BaseRequest.swift:145`). Con tests de 130 s en
      un runner atascado, 60 s se superan.
- [x] 1.3 ~~Dar a esos cuatro tests un timeout holgado~~ **Reemplazada por la enmienda de D2**: en vez de ensanchar el margen se elimina la carrera: no es lo que prueban, es lo que no debe
      interferir. Verificación: con la latencia del mock alargada, el test ya no termina por
      timeout.
- [x] 1.4 Separar los dos rojos: antes de afirmar `.cancelled`, esperar la señal observable de
      transferencia en vuelo (`MockURLProtocol.waitForCancelledDelivery(...)` o la que
      corresponda) y fallar con «no pude poner la petición en vuelo» si no llega.
      **Hecho**: `expectCancelled(inFlight:)` espera a que el mock registre la petición
      (`recordedRequests`, que ya era público) y solo entonces cancela. Los dos mensajes son
      distintos: «no pude poner la petición en vuelo» vs «esperaba .cancelled».
- [x] 1.5 Sonda: amputar la cancelación en el transporte y comprobar que los cuatro se ponen
      rojos por el comportamiento, no por la premisa. Verificación: los cuatro fallan con el
      mensaje de comportamiento; restaurado, vuelven a verde.
      **Hecho, y la primera sonda estaba mal**: amputar `work.cancel()` en el mock NO los pone
      rojos, porque eso es la limpieza interna del mock y no el comportamiento bajo prueba —el
      contador de entregas canceladas registra que el URL loading system llamó a
      `stopLoading`, que es lo correcto—. La sonda buena está en `APIService.swift:439`, el
      mapeo `URLError(.cancelled)` → `.cancelled`: amputado, los cuatro fallan con
      `URLError(-999)` clasificado como `.transport`; restaurado, verde.
      Segunda sonda: subir la latencia del mock de 5 s a 60 s no cambia nada (0,11 s, verde),
      que es lo que demuestra que ya no dependen del reloj.
- [x] 1.6 Si al establecer bien la premisa aparece un defecto real de la librería —que la
      cancelación tarde de más en llegar al transporte—, **parar y renegociar por escrito**.
      **No aparece**: la librería mapea bien la cancelación y la propaga (vía Foundation,
      que es quien cancela la tarea de URLSession; no hay `withTaskCancellationHandler` en el
      transporte, ni hace falta). El defecto estaba en el test, no en el producto.

## 2. Grupo A — el backoff

- [x] 2.1 Comprobar si `ManualClock` permite distinguir «se canceló la espera» de «no hubo
      espera» (pregunta abierta de `design.md`). Verificación: la respuesta, con el
      **Sí puede.** `ManualClock.sleep` es cancelable —`withTaskCancellationHandler` que
      resume con `CancellationError`— y expone `waitUntilSleeping()`, que suspende hasta que
      el bucle registra el `sleep`. Eso ES la premisa observable: «el bucle llegó al
      backoff», sin suponer nada sobre cuánto tarda la máquina.
- [x] 2.2 Si la respuesta es sí: reescribir el test para ejercitar el backoff con
      `ManualClock`, avanzándolo a mano, y afirmar sobre la interrupción de la espera en vez
      de sobre su duración. **Hecho** con `InMemoryTransport` + `ManualClock`, el mismo
      patrón que `RetryBehaviorTests`. Quedan 3 `ContinuousClock`, todos en el techo de
      espera de `waitUntilInFlight`, con su porqué escrito al lado. De paso se fueron el
      actor `RetryInstantProbe`, la rama de espera fija y un valor de retorno sin uso; la
      suite del fichero baja de 0,110 s a 0,019 s.
- [x] 2.3 ~~Si la respuesta es no: replantear D1~~ **No aplica: la respuesta fue sí.**
- [x] 2.4 Sonda: un `RequestRetrier` que no interrumpa la espera debe poner el test rojo.
      **Hecho** con una sonda más directa: `ManualClock.sleep` resumiendo normalmente en vez
      de lanzar `CancellationError`. El test falla por las DOS afirmaciones —llega
      `httpStatus 500` en vez de `.cancelled`, y hay segundo request—; restaurado, verde.

## 3. Grupo C — el probe de 5 MB

- [x] 3.1 Mirar `URLSessionTransport` y responder la pregunta abierta: ¿se puede observar que
      no itera byte a byte sin tocar la librería? Verificación: la respuesta queda escrita
      **Sí se puede, léxicamente.** La regresión que el test vigila es `for try await` sobre
      `.bytes(...)` en el transporte, y hoy no hay ninguna ocurrencia en
      `Sources/CoreNetworking/`. Un chequeo léxico la cazaría sin reloj y sin tocar la
      librería. Límite honesto: caza ESA forma de lentitud, no «lento por otro motivo».
      Este paquete no tiene linter léxico propio (no usa `archlint`), así que habría que
      añadir el chequeo a `Scripts/` o como test que lee el fuente.
- [x] 3.2 **Decisión del owner** entre las tres opciones de `design.md` D3, con el dato de
      3.1 encima de la mesa. Cambia qué puede tumbar una publicación, así que no la toma
      **Elegida: el chequeo léxico** (2026-09-16), con el dato de 3.1 encima de la mesa:
      la regresión que el probe vigila es `for try await` sobre `.bytes(...)`, y eso se lee
      en el fuente sin reloj y sin tocar la librería.
- [x] 3.3 Aplicar la opción elegida. Si sale de la puerta bloqueante, el workflow dice por
      qué y qué job lo cubre. Verificación: lo que declare el CI coincide con lo que hace.

## 4. Cierre

- [x] 4.1 Veinte corridas consecutivas de `swift test --parallel` en CoreNetworking sin un
      solo rojo de estos tres grupos. Verificación: el comando y el resultado quedan escritos
      **20/20 verdes** con `swift test --parallel` en `CoreNetworking/`, 2026-09-16, sobre
      el árbol de este cambio. (Veinte verdes no prueban que no queden inestabilidades;
      acotan.)
- [ ] 4.2 Una corrida de CI completa en verde, incluido el simulador iOS, que es donde más
      caían. Verificación: el número de run queda escrito aquí.
- [x] 4.3 `/kit-verifica` en verde.
