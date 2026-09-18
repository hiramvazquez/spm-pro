## Context

Ver `proposal.md` — Why. Lo que sigue es lo medido el 2026-09-16, fichero y línea, porque los
tres grupos se parecen por fuera y no se arreglan igual.

**Grupo A — el backoff.** `CancellationTests.swift:190-200`: toma `ContinuousClock.now` antes
y después, y exige `backoffWindow < .seconds(3)`. Ya se estrechó una vez (la 1.2.3 lo pasó de
cronometrar la operación entera a cronometrar solo la ventana de backoff), así que el margen
de seguir estrechando está agotado: lo que queda es no usar el reloj real.

**Grupo B — «se cancela de verdad» (cuatro tests).** `CancellationTests.swift:91` afirma
`apiError?.code == .cancelled`. En el run `35070600701` llegó
`APIError(code: transport, underlying: URLError(-1001))` en dos de ellos. `-1001` es
`NSURLErrorTimedOut`: **la petición terminó por timeout antes de que la cancelación llegara**.
No es una clasificación errónea del error —el sistema hizo lo correcto con lo que pasó—, es
que el test no llegó a ejercitar lo que dice ejercitar.

**Grupo C — el probe de 5 MB.** `TransferTests.swift:370-377`: presupuesto de 200 ms en macOS
y 20 s en simulador, con el mensaje «¿volvió el bucle byte a byte?». Medido bajo carga: 55 s y
130 s. Su intención es detectar una regresión de rendimiento concreta, no comprobar
corrección.

**Lo que ya existe y no hay que construir:** `APIService.init(clock:)` (CN-11),
`ManualClock` en `CoreNetworkingTestSupport`, y `MockURLProtocol.cancelledDeliveries(...)` /
`waitForCancelledDelivery(...)`, añadidos en la 1.2.3 precisamente como señal observable de
que el URL loading system desmontó una transferencia en vuelo. Siete ficheros de test usan ya
`ManualClock`.

## Goals / Non-Goals

**Goals**
- Que un rojo de estos tres grupos signifique siempre lo mismo.
- Que la causa de cada uno se trate según lo que es, no según lo que parece.

**Non-Goals**
- Eliminar toda medición de tiempo del repositorio. El grupo C mide rendimiento a propósito;
  lo que se decide es dónde vive, no si existe.
- Cambiar la librería. Si algún hallazgo lo exige, se renegocia por escrito.

## Decisions

### D1. Grupo A: el reloj inyectado, no un presupuesto mayor

El backoff se ejercita con `ManualClock`, avanzándolo a mano. El test deja de preguntar
«¿tardó poco?» y pasa a preguntar «¿se interrumpió la espera?», que es lo que de verdad
quiere saber.

*Alternativa descartada — subir el presupuesto a 10 s:* mueve la frontera a un runner más
cargado y deja el test afirmando sobre la máquina, no sobre el código. Además el paquete ya
declara «no real wall-clock waits in tests»: subir el número consolidaría la excepción.

*Riesgo a comprobar al implementar:* la cancelación durante un `clock.sleep` puede
comportarse distinto con `ManualClock` que con `ContinuousClock`. Si resulta que con reloj
manual el test ya no puede distinguir «canceló la espera» de «nunca esperó», hay que decirlo
y replantear, no forzarlo.

### D2. Grupo B: establecer el estado «en vuelo» y separar los dos rojos

Dos cambios sobre los cuatro tests:

1. **Que no haya carrera, en vez de darle más margen.** *Enmendado el 2026-09-16, al
   implementar la tarea 1.2.* La versión original de esta decisión decía «dar un timeout
   holgado», y se apoyaba en creer que el timeout que vence era el de la petición. Es falso:
   `BaseRequest.timeout` es un timeout de INACTIVIDAD entre paquetes
   (`BaseRequest.swift:145`), y estrecharlo a 50 ms no reproduce el fallo —medido—. El que
   vence es `timeoutIntervalForResource`, **60 s**, que impone
   `NetworkingConfiguration.enforceSecurityFloor`. Y con esperas de 130 s por test en un
   runner atascado, 60 s se superan.

   Ensanchar ese margen seguiría siendo una carrera, solo que con más cuerda — justo lo que
   el proposal declara fuera de alcance. La carrera se elimina: el test deja de dormir
   100 ms de reloj de pared y **espera la señal observable de que la petición está en
   vuelo** antes de cancelar. `MockURLProtocol.startLoading` registra la petición en
   `recordedRequests`, que es público, así que la señal ya existe y no hay que tocar el mock.
2. **Que el fallo distinga premisa de comportamiento.** Si esa señal no llega en un plazo
   razonable, el test falla con «no pude poner la petición en vuelo», no con «esperaba
   .cancelled».

*Alternativa descartada — deducir la premisa del propio error:* tratar `URLError(-1001)` como
«esto fue un timeout, reintenta el test» es un reintento disfrazado, y un test que se
reintenta hasta pasar no afirma nada.

### D3. Grupo C: decidir dónde vive antes de tocarlo

Tres opciones reales, y la decisión es del owner porque cambia qué puede tumbar una
publicación:

| opción | qué gana | qué cuesta |
|---|---|---|
| Sacarlo de la puerta a un job propio, informativo | la puerta deja de tener ruido | una regresión de rendimiento deja de bloquear |
| Dejarlo donde está con presupuesto medido por corrida (calibrado contra una operación de referencia en la misma máquina) | sigue bloqueando y deja de depender de la máquina | hay que construir y mantener la calibración |
| Expresarlo contra el mecanismo (que el transporte no itere byte a byte) en vez de contra el tiempo | deja de ser una medición | puede que no haya forma de observarlo sin tocar la librería |

La tercera es la mejor si resulta viable; hay que mirar el transporte antes de prometerla.

## Risks / Trade-offs

- **Que al quitar el reloj el test deje de detectar lo que detectaba** → cada grupo lleva su
  sonda: se amputa el comportamiento y se comprueba que el test se pone rojo. Sin esa sonda,
  el arreglo no está hecho.
- **Que el grupo B esconda un defecto real de la librería** —que la cancelación tarde más de
  lo debido en llegar al transporte— → al establecer bien la premisa se verá; si aparece, es
  un hallazgo y se renegocia, no se ajusta el test.
- **Veinte corridas verdes no prueban ausencia de inestabilidad**, solo la acotan → se dice
  así en el criterio, con el número y el comando.

## Migration Plan

Un grupo por vez, en este orden, porque el B puede destapar algo que cambie el resto: B → A →
C. Cada uno con su sonda antes de darlo por hecho. Sin despliegue: son tests.

## Open Questions

- ¿El transporte permite observar que no itera byte a byte, sin tocar la librería? Decide
  entre las tres opciones de D3 y se responde mirando `URLSessionTransport`.
- ¿`ManualClock` permite distinguir «se canceló la espera» de «no hubo espera»? Se responde
  al implementar D1, y si la respuesta es no, D1 se replantea por escrito.
