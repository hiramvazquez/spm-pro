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
      *Corregido en la ronda 1 del juicio*: el mensaje era distinto, pero no era el único.
      `expectCancelledAndTornDown` seguía afirmando el desmontaje aunque la premisa hubiera
      fallado, así que salía un SEGUNDO rojo —«la transferencia siguió viva tras cancelar el
      Task»— acusando al sistema de algo que nunca se ejercitó, que es justo lo que el
      escenario de la spec prohíbe. Ahora `expectCancelled` devuelve si la premisa se
      estableció y el desmontaje solo se afirma si se estableció. Medido amputando el registro
      del mock: **un** rojo, el de la premisa.
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
      **Sí puede, pero no con `waitUntilSleeping()` a secas** —corregido en la ronda 1 del
      juicio, ver «Rondas de aceptación» al final—. `ManualClock.sleep` es cancelable
      —`withTaskCancellationHandler` que resume con `CancellationError`— y el reloj expone
      `waitUntilSleeping()`, que suspende hasta que el bucle registra el `sleep`. Con eso se
      distingue «se canceló la espera» (verde) de «la espera no se interrumpió» (rojo, sonda
      2.4).
      Lo que NO distingue es el tercer caso, que es el que importaba: **«no hubo espera»**.
      Si nadie llega a dormir, `waitUntilSleeping()` no vuelve nunca y el test **se cuelga en
      vez de fallar**. La señal que sí sirve es `pendingDeadlines`, que se puede consultar con
      un techo, y así se hizo: `waitUntilBackoffSleeping` espera a esa señal con un
      `ContinuousClock` de techo —10 s— y, si no llega, el test falla diciendo que no pudo
      establecer su premisa.
- [x] 2.2 Si la respuesta es sí: reescribir el test para ejercitar el backoff con
      `ManualClock`, avanzándolo a mano, y afirmar sobre la interrupción de la espera en vez
      de sobre su duración. **Hecho** con `InMemoryTransport` + `ManualClock`, el mismo
      patrón que `RetryBehaviorTests`. Quedan 6 `ContinuousClock`, todos en un techo de
      espera y con su porqué escrito al lado: 3 en `waitUntilInFlight` y —desde la ronda 1 del
      juicio— 3 en `waitUntilBackoffSleeping`, que es el techo que impide que el test se cuelgue
      cuando no hay espera. La anotación decía «3» y se quedó vieja al añadir el segundo techo;
      el criterio los admite porque ninguno decide el veredicto, solo acota la premisa. De paso se fueron el
      actor `RetryInstantProbe`, la rama de espera fija y un valor de retorno sin uso; la
      suite del fichero baja de 0,110 s a 0,019 s.
- [x] 2.3 ~~Si la respuesta es no: replantear D1~~ **No aplica: la respuesta fue sí.**
- [x] 2.4 Sonda: un `RequestRetrier` que no interrumpa la espera debe poner el test rojo.
      **Hecho**, y en las DOS formas que tiene «no se interrumpió» —la segunda la encontró el
      juez en la ronda 2, y era la que faltaba—:
      - *la espera resume normalmente*: `ManualClock.sleep` resumiendo sin lanzar
        `CancellationError`. Dos rojos: llega `httpStatus 500` en vez de `.cancelled`, y hay
        segundo request.
      - *la espera queda pendiente e ignora la cancelación*: el `sleep` del producto envuelto en
        un `Task.detached { try? … }`. Antes **colgaba el test para siempre** —el juez lo dejó
        3 min 28 s y lo mató a mano—. Ahora rojo en **~2 s** —hoy tres issues, con el fallo de
        premisa que añadió la revisión siguiente— (la cifra de
        6,9 s que se anotó antes incluía la compilación; el revisor midió 2,01 s).
      Restaurado en los dos casos, los cinco tests en verde en 0,031 s.
      **Y dos formas más**, que encontró el revisor del arreglo de la ronda 2 y que ese arreglo
      dejaba en **VERDE** —un falso verde, en el cambio que existe para quitar rojos falsos—: la
      espera blindada seguida de un `Task.checkCancellation()`, y la espera blindada con un
      `if Task.isCancelled { throw … }` al entrar al bucle de reintento. Ahora las cuatro dan
      rojo sin colgarse, y el producto sin tocar sale verde 100 de 100 veces.

## 3. Grupo C — el probe de 5 MB

- [x] 3.1 Mirar `URLSessionTransport` y responder la pregunta abierta: ¿se puede observar que
      no itera byte a byte sin tocar la librería? Verificación: la respuesta queda escrita
      **Sí se puede, léxicamente.** La regresión que el test vigila es `for try await` sobre
      `.bytes(...)` en el transporte, y hoy no hay ninguna ocurrencia en
      `Sources/CoreNetworking/`. Un chequeo léxico la cazaría sin reloj y sin tocar la
      librería. Límite honesto: caza ESA forma de lentitud, no «lento por otro motivo».
      Este paquete no tiene linter léxico propio (no usa `archlint`), así que habría que
      añadir el chequeo a `Scripts/` o como test que lee el fuente.
      *Límite de alcance, añadido en la ronda 2 con el dato del juez*: el guard escanea
      `Sources/CoreNetworking/Transport/`, y la regresión CN-07 vivía históricamente en
      `APIService.swift` (`session.bytes(for:)`). Hoy ese código está en `Transport/`, así que
      el alcance es correcto **hoy**; una reaparición fuera de ese directorio no la vería.
      Ensancharlo a todo `Sources/` es otra decisión y no entra aquí.
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
      *Corregido en la ronda 2*: esas veinte eran del árbol **anterior** a los arreglos de las
      dos rondas, así que ya no describían lo entregado. El juez las re-midió sobre `fc673df`
      —20/20— y además tres corridas con 30 procesos quemando CPU en 10 núcleos, que es el
      escenario «la máquina va cargada» de la spec: verdes, 0,095 s. Sobre el árbol final de la
      ronda 2 se han corrido de nuevo (ver «Rondas de aceptación»).
- [ ] 4.2 Una corrida de CI completa en verde, incluido el simulador iOS, que es donde más
      caían. Verificación: el número de run queda escrito aquí.
      **REABIERTA en la ronda 2, y el motivo es un error de hecho mío.** El run
      `35171916164` (2026-09-17T01:47Z, `workflow_dispatch` sobre esta rama) es **22 jobs en
      verde**, pero corrió sobre `eae8907`, que **ya no es el HEAD del cambio**: los arreglos de
      las dos rondas son `fc673df` y el siguiente. Yo escribí que `eae8907` era el HEAD, y lo
      era cuando lo escribí. El commit entregado no ha pasado por CI todavía.
      Lo que sí está medido mientras eso llega: el juez corrió a mano `xcodebuild test` en
      iPhone 18 Pro / iOS 27.0 sobre `fc673df` —**241 tests verdes en 1,173 s**—, que es la
      sustancia que esta tarea persigue; y la suite entera en local, verde, sobre el árbol final.
      Queda pendiente el número del run del HEAD entregado, que es lo que esta tarea pide.
      **Cerrada después de la ronda 2**: run `35298829414` (`workflow_dispatch` sobre esta rama),
      comprobado ANTES de mirarlo que corre sobre `381c0a4`, el HEAD que se entrega —el error de
      antes fue dar por bueno un run de otro commit—. **22 de 22 jobs en verde**, y dentro de
      `CoreNetworking`, `swift test (macOS)` y `xcodebuild test (iOS Simulator)` los dos en
      `success`: el simulador, que es donde más caían estos tests y lo que esta tarea pedía.
      **Reabierta otra vez, y por el mismo motivo que la primera**: después de ese run llegaron
      dos arreglos más (`dd91a14` y el siguiente), así que `381c0a4` ya no es el HEAD entregado.
      Se cierra con un run sobre el HEAD final, lanzado cuando la rama esté empujada.
      Y lo que esta tarea pedía de verdad —el simulador, que es donde más caían— comprobado
      paso a paso y no por el verde del job: dentro de `CoreNetworking`, `swift test (macOS)` y
      `xcodebuild test (iOS Simulator)` los dos en `success`. También verdes `Mínimo soportado`
      y `Tests en el mínimo ejecutable` de los dos paquetes, que son los que validan el
      toolchain que promete el README.
- [x] 4.3 `/kit-verifica` en verde.

## Rondas de aceptación

- **Ronda 1 — DEVUELTO** (juez, 2026-09-17). Motivo, y era grave: el test del backoff esperaba
  con `await clock.waitUntilSleeping()` **sin techo, sin mensaje de premisa y sin `.timeLimit`**.
  El juez amputó el `clock.sleep` del producto (`APIService.swift:369`) y el proceso siguió vivo
  **32 minutos** sin una línea de salida, parado en `swift_task_asyncMainDrainQueue`; lo mató él.
  En CI no lo mata nadie: `.github/workflows/ci.yml` no fija `timeout-minutes`, así que serían
  las seis horas por defecto del job y sin decir por qué.

  Por qué no era una pega de estilo, con sus tres razones:
  1. **La versión anterior sí fallaba limpio ahí.** Este cambio borró el
     `#require(await probe.decidedAt, "el bucle no llegó a decidir el reintento…")`, que es
     literalmente el riesgo que `design.md` puso por escrito: «que al quitar el reloj el test
     deje de detectar lo que detectaba».
  2. **La pregunta abierta de D1 era esta misma**, y la tarea 2.1 la cerró con un «sí puede»
     que la entrega no sostenía. Corregida arriba.
  3. **El paquete ya tenía el idiom y su razón escrita**, en el mismo target:
     `TaskDelegateTests.swift:451-456` pone `.timeLimit` precisamente porque «este test se
     COLGARÍA en vez de fallar — en CI eso se come el timeout del job entero y no dice por qué».

  Arreglado reusando lo que el fichero ya tenía, sin maquinaria nueva:
  `waitUntilBackoffSleeping` sondea `ManualClock.pendingDeadlines` con un techo de
  `ContinuousClock`, igual que `waitUntilInFlight` hace con `recordedRequests`, y si no llega la
  señal el test falla con «el bucle no llegó a dormir el backoff».
  **Medido en los dos sentidos**: con el `clock.sleep` amputado, el test falla en **10,005 s**
  con ese mensaje —antes, 32 minutos colgado—; restaurado, los cinco del fichero en verde en
  0,018 s. Y la suite entera, 244 tests, verde en tres corridas seguidas.

  El segundo hallazgo de esa ronda —el doble rojo del grupo B— está corregido y anotado en la
  tarea 1.4.

- **Ronda 2 — DEVUELTO** (juez, 2026-09-17). Y con razón otra vez: el arreglo de la ronda 1 puso
  techo a la **premisa** —que alguien llegue a dormir— y dejó sin techo el **veredicto**. El juez
  amputó la otra forma de «la espera no se interrumpe» —blindar el `sleep` del producto frente a
  la cancelación— y el test se colgó igual: 3 min 28 s, matado a mano. Con `ManualClock` una
  espera pendiente que nadie interrumpe ni avanza es infinita; con el reloj real, un backoff de
  5 s se resolvía solo. Esa instancia no la introdujo la ronda 1: venía de `0dfc08f`, una línea
  más abajo.

  **Y su arreglo propuesto no funciona, medido.** El juez sugería «una línea: el trait
  `.timeLimit`». Lo puse, repetí su amputación, y el test **seguía colgado pasados 600 s**: en
  Swift Testing el límite es cooperativo y no interrumpe un `await` que ignora la cancelación.
  Queda escrito en el código, junto al guard que sí funciona, para que nadie lo vuelva a intentar.

  Lo que cierra el caso es que el test **desbloquee el reloj que él mismo controla**: tras
  cancelar, si el durmiente sigue en `pendingDeadlines` pasado un techo de 2 s, la cancelación no
  llegó a la espera, y `clock.advance(by:)` la desbloquea para que el test pueda JUZGAR en vez de
  colgarse. El segundo request que eso provoca es justo el rojo que la tarea 2.4 promete.
  **Medido**: 2 rojos en ~2 s con esa amputación (anoté 6,9 s: incluía la compilación); 2 rojos en 0,008 s con la otra; los cinco
  tests en verde sin amputar y la suite entera —244 tests— verde.

  De paso, un hallazgo suyo de información: el esqueleto del bucle de sondeo estaba escrito tres
  veces. Las dos copias de este fichero pasan ahora por `esperaSenal`; la tercera vive en otro
  target (`MockURLProtocol.waitForCancelledDelivery`) y no se toca aquí.

  Veinte corridas de `swift test --parallel` sobre el árbol final de esta ronda: **20/20
  verdes**, que es el criterio de la tarea 4.1 re-medido sobre lo que de verdad se entrega.

  Sus dos errores de hecho en mi texto, corregidos arriba: las 20 corridas de la 4.1 eran del
  árbol anterior a los arreglos, y la 4.2 afirmaba que el run era del HEAD entregado cuando ya no
  lo era — esa tarea queda **reabierta**.

- **Revisión del arreglo de la ronda 2 — RED** (revisor, 2026-09-17). Obligatoria: el requisito
  «No se archiva sobre el arreglo de un juicio que no ha visto ningún revisor» impide archivar
  sobre un arreglo que cambia lo que el código hace, y el de la ronda 2 no lo había visto nadie
  —ni siquiera el juez, porque no era el que él propuso—.

  **Y encontró un falso verde que ese arreglo había abierto.** La rama que desbloquea el reloj
  no registraba ningún fallo: el comentario decía «la espera NO se interrumpió» y el test lo
  sabía y no lo decía, y luego solo miraba el código de error y el número de requests. Un
  producto que no interrumpe la espera pero mira la cancelación DESPUÉS sale bien en esas dos
  cosas, así que salía en verde — reproducido de dos formas, las dos en ~2 s. Antes de ese
  arreglo esas variantes colgaban el test; con él, **pasaban**. Es decir: arreglar el cuelgue
  había convertido un fallo ruidoso en uno silencioso.

  Arreglado con una línea: la rama registra el fallo —«la cancelación no llegó a la espera del
  backoff»— antes de avanzar el reloj, y el `advance` queda solo para que el test termine.
  **Medido**: las cuatro formas de «no se interrumpió» dan rojo sin colgarse —3, 1, 1 y 2
  issues—, las fuentes quedan intactas, y el producto sin tocar sale verde **100 de 100**;
  suite entera en verde tres veces.

  El falso rojo que yo temía **no es alcanzable**, y lo midió él: `onCancel` corre de forma
  síncrona dentro de `task.cancel()`, así que la lista queda vacía en cuanto `cancel()` vuelve
  —2000 de 2000 sin carga, 300 de 300 con carga media ~75—. El techo de 2 s no se gasta nunca
  en el camino correcto y no decide nada por reloj.

  **Y se retiró el `.timeLimit`**, que yo había dejado con un comentario encima que prometía
  «acotar el veredicto». Medido por él: con terminal imprime el fallo a los 60 s y el proceso
  **sigue vivo**; sin terminal —como en CI— no escribe ni un byte. Daba confianza y no
  terminaba nada. El porqué de que no esté queda escrito junto al guard.

- **Revisión del arreglo del RED — AMBER, no bloquea** (revisor, 2026-09-17). Sin falso verde
  realista y sin falso rojo, confirmado sobre `dd91a14`: `onCancel` corre síncrono dentro de
  `task.cancel()`, 2000 de 2000 sin carga y 3 × 2000 con la CPU ocupada. Probó dos variantes más
  de las cuatro mías —un `withTaskCancellationShield` alrededor del `sleep` da rojo—.

  Lo que deja es el **mapa de lo que el test no ve**, y queda escrito en el código junto al
  guard: solo escapa lo que espera FUERA del reloj inyectado. Si esa espera es finita, sale
  verde (un segundo reloj dentro del producto: teórico, el test observa el reloj inyectado por
  diseño). Si es infinita, se cuelga (un producto que traga la cancelación y vuelve a dormir
  hasta el deadline: la cancelación sí llega a la primera espera, así que el guard no dispara).

  Sobre ese cuelgue: quitar el `.timeLimit` pierde una señal pequeña —en una terminal local
  imprimiría el nombre del test a los 60 s—, y en CI no se pierde nada, porque con la salida a un
  pipe no escribe un byte. **No se devuelve el trait**: sería un cambio de código y otra pasada
  obligatoria para ganar una línea en una terminal local. Se declara como límite, que es lo que
  es. El comentario que decía «no sirve aquí» a secas se precisó: no aporta nada en los casos que
  el guard cubre.

  Fuera de alcance, y anotado para quien lo retome: `TaskDelegateTests.swift:451-456` sigue
  prometiendo que `.timeLimit` convierte un cuelgue en «un fallo con nombre en segundos», que es
  la misma creencia que este cambio ha corregido; y `ManualClock.swift:72-88` tiene una carrera
  preexistente —una cancelación entre `checkCancellation()` y la instalación del handler deja al
  durmiente dentro para siempre— que aquí es inalcanzable porque se cancela con el durmiente ya
  visible.
