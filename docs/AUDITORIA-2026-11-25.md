# Auditoría de AppFoundation 1.4.2 y CoreNetworking 1.3.1

2026-11-25 · para decidir qué quitar, simplificar, mejorar y agregar en los dos paquetes base.

## Cómo se hizo y cuánto vale

- **Qué se auditó.** El monorepo `spm-pro` en `3a03cf6`. Sus `Sources/` son idénticos a los que
  resuelve AppStarter (`diff -rq`: solo `.DS_Store`), así que lo dicho vale para lo publicado.
- **Cómo.** Cuatro lecturas independientes y de solo lectura —librería de AppFoundation, sus
  herramientas y ejemplos, CoreNetworking, y los proyectos que consumen los paquetes—. Las cuatro
  leyeron antes las tres auditorías de septiembre (`docs/AUDITORIA-2026-09-*.md`) para no
  repetirlas; lo que ya estaba señalado va marcado.
- **Línea de base, medida aparte.** Compilación en frío con tests: CoreNetworking 11 s,
  AppFoundation 23 s; **0 warnings, 0 dependencias externas** en los dos. Tests: CoreNetworking
  `244 tests in 33 suites passed`; AppFoundation `365 tests in 50 suites passed` más 130 en los
  otros tres targets de test.
- **Etiquetas.** `medido`: salió de ejecutar algo, con el comando o la sonda citados. `leído`: se
  ve en el código. `hipótesis`: una cadena de lecturas sin medición.
- **Comprobado una segunda vez**, por quien firma, antes de ponerlo arriba: que nadie en el kit
  lee `isRetryable`; que la expresión de `Retry-After` revienta con `inf` y `1e30`; qué códigos
  HTTP caen en `.client`; que la documentación de `load(_:)` propone `performLoad` para «a
  submit»; que AppStarter enlaza `CoreNetworkingTestSupport` en el target de la app; que R3 está
  apagada en `Packages/Features`; y que `archinit` genera `"*Kit"`.
- **El límite más importante.** «Sin uso» está medido contra **un** consumidor al día,
  AppStarter, que además es escaparate. Ver «Deriva entre proyectos».

## Juicio en cinco líneas

1. **Los dos están sanos.** Compilan limpios, pasan sus tests y no arrastran nada de terceros.
   Lo que sale es de diseño y de superficie, no de roturas.
2. **AppFoundation: le sobra superficie y le falta núcleo.** El contrato de errores y
   cancelación está a medio cablear, y cada app lo termina a mano.
3. **Lo que el kit enseña va por detrás de lo que el kit exige.** Dos de los cuatro ejemplos de
   referencia dejan al usuario sin el control que necesita, con un test que lo da por bueno.
4. **CoreNetworking: el código es proporcionado; tiene defectos de corrección que su suite no
   ve.** De 3.423 líneas, 1.553 son código y 1.608 comentario.
5. **«La base de cada proyecto» es hoy la base de uno.** Solo AppStarter está en la versión
   actual.

## 1. Defectos de corrección

Lo primero, porque no depende de ninguna decisión de diseño.

| # | Paquete | Qué pasa | Evidencia | Confianza | Esf. | ¿Rompe API? |
|---|---|---|---|---|---|---|
| 1 | CN | `Retry-After` se obedece sin validar ni acotar. Con `inf` o `1e30` el proceso muere (`Fatal error`); con `86400` la llamada espera 24 h | `APIError.swift:311-312`; `APIService.swift:326,333,349` | medido (la expresión, dos veces; el camino hasta ella, leído) | S | no |
| 2 | AF | Una cancelación reconocida con la `Task` viva sale por un `return` que no deshace el estado: la pantalla se queda en `.loading` o con el indicador puesto para siempre | `BaseViewModel.swift:401,451`. Los tests del kit solo afirman `!hasError` | leído; el coste, medido: 11 bloques en 8 de 11 ViewModels de AppStarter | S | no |
| 3 | AF | El kit enseña a enviar formularios con `performLoad`, y un error no reintentable a pantalla completa no tiene salida. `.empty` tampoco | `Examples/LoginApp/…/LoginViewModel.swift:45` y su test `:42-53`; `Examples/NotesApp/…/NotesViewModel.swift:38` (lista vacía → desaparece el campo «New note»: no se puede crear la primera nota); `LoadableViewModel.swift:59-62` («a submit») frente a `:170` y `Recipes.md:143` | leído; en AppStarter, medido en simulador | S–M | no |
| 4 | CN | El progreso de `data(for:)` y `download(_:to:)` nunca emite fracciones: solo `1.0` al final | `Transport/TaskDelegate.swift:244-302` no se ejecuta con las API async. Sonda en loopback, 2 MB en 8 trozos: 0 callbacks de datos. Los tests solo afirman `last == 1.0` | medido en macOS 27.0.1; no en iOS | S–M | no |
| 5 | CN | El suelo de seguridad y `sessionConfiguration` solo se aplican por el `convenience init`. Por el otro camino —el que pide la arquitectura para poder inyectar el transporte— van cookies compartidas y 7 días de timeout de recurso | `APIService.swift:100-113` frente a `Transport/URLSessionTransport.swift:35,44`. AppStarter en producción entra por el camino sin suelo (`NetworkingModule.swift:61,70`) y ya lo pagó una vez en Diagnostics | leído | S | no (cambia comportamiento) |
| 6 | CN | Un `+` en un valor de query sale sin codificar | `APIService.swift:553-555`; sonda: `ana+test@x.com` sale tal cual; 0 `%2B` en los tests | medido (la URL) | S | no |
| 7 | CN | Tras refrescar el token, el reintento espera el backoff (250–500 ms). Y `.noRetry` apaga el refresco en silencio | `Auth/TokenRefresher.swift:124-127`; `APIService.swift:318,326`; `RetryPolicy.swift:58,85-89` | leído | S | no |
| 8 | AF | `generate-feature --no-logic` genera código que el linter del propio kit rechaza (R15 y R16), y ningún script lo ejercita | `Plugins/GenerateFeature/NoLogicTemplates.swift:25,62-63` | medido (plantilla renderizada y pasada por `archlint`) | S | no |
| 9 | AF | `archinit --multi` escribe `"*Kit"` en `forbiddenImports`, que casa con `UIKit`, `MapKit` y `StoreKit`. Y `"*Feature"` no casa con `XxxFeatureUI`/`Core` | `ArchInitSupport.swift:163`; `Glob.swift:48` | medido (3 falsos positivos de 4) · ya en sept., abierto | S | no |
| 10 | AF | Cada feature `--api` registra su propio `APIServiceProtocol`; el último gana y pisa al autenticado | `Templates/Module.swift.txt:73-74` | leído · ya en sept., abierto | S | no |
| 11 | CN | Con los defaults, sin red no llega `.offline`: se espera hasta 60 s por intento y llega `.timeout`, reintentable | `NetworkingConfiguration.swift:108,143`; `RetryPolicy.swift:57` | **hipótesis** | S | no (cambia comportamiento) |

Del 3 hay una decisión de producto dentro, que es tuya: que `ScreenError` pueda llevar un
`dismiss` que restaure la fase anterior, y que el estilo por defecto pinte «OK». Sin eso, un
error no reintentable a pantalla completa sigue siendo un callejón aunque los ejemplos se
corrijan.

## 2. Cerrar el contrato de errores y cancelación

Es el cambio que más código quita **en las apps**, y son tres piezas pequeñas en el kit:

- `DefaultErrorPresenter` consulta `isRetryable`. Hoy nadie en el kit lo lee (`grep`: 2
  declaraciones, 0 lecturas), y adjunta `retry` a todo.
- `DomainError` gana `isCancellation` (por defecto `false`) y `DefaultCancellationRecognizer`
  lo consulta.
- `_runLoad` y `_runActivity` deciden por generación: si la carga sigue siendo la vigente,
  restauran el estado; si fue sustituida, no tocan.

Lo que desaparece en AppStarter, medido:

| Hoy | Tamaño |
|---|---|
| `App/AppErrorPresenter.swift` (copia del de `Examples/LoginApp`) | 33 líneas |
| `App/AppCancellationRecognizer.swift` (enumera 7 errores, obliga a `App/` a importar las features) | 56 líneas |
| `RecognizerDePrueba` | 20 líneas, usado en 8 ficheros de test |
| Bloques `catch XError.cancelled { if !Task.isCancelled { … } }` | 11, en 8 de 11 ViewModels (97 líneas) |
| Mutaciones de `BaseViewModel.cancellationRecognizer` en tests | 14, en 8 ficheros |
| Cláusulas 3 y 4 del requisito de cancelación de `plataforma` | una norma escrita para no olvidarlo |

Once de los 26 cambios de `openspec/changes` de AppStarter existen por estos huecos.

**Van con el punto 3 de arriba.** Si el presenter por defecto deja de adjuntar `retry` a los
errores no reintentables y no hay otra salida, aparecen más pantallas sin salida, no menos.

## 3. Quitar

**AppFoundation**

| Qué | Por qué | Tamaño |
|---|---|---|
| `load(_:)` y `activity(_:)` | La «API recomendada por defecto» tiene 0 llamadas (frente a 19 de `performLoad`/`performActivity`), obliga a la vista a saltarse `ActionSender`, y la doc reconoce que ya no aporta cancelación | `LoadableViewModel.swift:63-98` |
| `WrappedError` | 0 usos; ya causó un fallo de seguridad (1.2.6) y una norma en AppStarter para un tipo que AppStarter no usa | fichero de 276 líneas |
| `@Inject` | 0 usos, y R10 lo prohíbe en cuatro capas | 78 líneas |
| `AppEnvironment` | 20 de 22 miembros sin uso; `isTestFlight` usa API deprecada y es la causa de una excepción en `Package.swift:43` | 203 líneas |
| `public enum AppFoundation {}` | Sin miembros, y tapa el nombre del módulo: impide desambiguar `Action` | `AppFoundation.swift:18` |
| `LifecycleContractProbeApp` fuera de `Sources/` | Rompió el build del paquete dos veces y mide macOS, no iOS | `Package.swift:135-140` |
| `--no-logic` | Ver defecto 8; además contradice «un Logic por ViewModel» | 119 líneas |
| Flags del generador sin ejercitar | 15 flags, los scripts prueban 5; `--analytics` solo añade un comentario y `--route` solo imprime un recordatorio | `plugin.swift:43-61` |
| La cláusula de R3 «el protocolo va en el mismo fichero» | Es de forma; en modo multi obliga a apagar R3 entera, y con ella la parte que importa | `Rules.swift:207-236` · ya en sept. |
| Diagnóstico doble | R1 y R7 por el mismo `import`; R3 y R8 por el mismo `BaseRequest` | `Rules.swift:81,441,198,462` |
| La recomendación de `SwiftLintBuildToolPlugin` | El consumidor real usa la CLI | `README.md:135-141` |

**CoreNetworking**

| Qué | Por qué |
|---|---|
| `upload(_:data:as:)`, `data(for:)`, `download(_:to:)` | 0 llamadas en consumidores y ejemplos; `upload` ni en la suite propia |
| `RetryPolicy.aggressive`/`.conservative`, `authenticationPolicy`, `RedirectPolicy` | 0 usos; nadie configura redirecciones |
| `MockAPIHelper` (71 líneas) | No aparece en ningún sitio |
| `MockURLProtocol` (287 líneas) | Solo lo usa su propia suite; AppStarter usa `InMemoryTransport` y `MockAPIService` |
| `EndpointService.call(_:)` | Es `api.execute(_:)` con otro nombre: 10 líneas de código y 56 de comentario; obliga a exponer `api` y `UploadsService` tiene que saltárselo. Decisión documentada con la que el auditor discrepa |
| Los tres callbacks de descarga muertos y sus 15 tests | Ver defecto 4 |

En conjunto, medido por símbolos: 745 públicos entre los dos paquetes; **26 de 105 tipos de nivel
superior no los nombra ningún consumidor** (840 líneas de declaración), y 150 de 545 miembros no
aparecen en ningún fichero consumidor.

## 4. Simplificar

- **`successTransition` tiene el valor por defecto equivocado.** `.preserveCurrentPhase` —el no
  predeterminado— es el que se pasa en 7 de 11 llamadas de AppStarter, 18 de 27 de CareOrganizer
  y en la propia plantilla.
- **Una sola lista de reglas.** Hay 16 implementadas (R1–R16) y la lista vive en seis sitios que
  no coinciden: `AGENTS.md` dice R1-R11 en una línea y R1-R12 en otra; la skill lista R1–R11.
  Propuesta: `Lint.md` como única tabla, con un test que compare sus ids con `Rules.swift`.
- **Más comentario que código.** CoreNetworking: 1.608 líneas de comentario frente a 1.553 de
  código. AppFoundation: 2.808 frente a 3.650. Y 88 líneas citan documentos internos (AF-xx,
  PRD, ARQUITECTURA-KIT) que no viajan con el paquete. Ya en sept., reaparecido.
- **`NetworkingConfiguration`**: 74 líneas de código y 200 de comentario. AppStarter pasa solo
  `baseURL` en 9 de 9 construcciones.
- **La barra de navegación custom es el 18 % del código de AppFoundation** (645 de 3.650 líneas)
  para algo que la propia doc desaconseja. Candidata a salir a su propio producto. Ya en sept.,
  con decisión tomada de dejarla.
- **Dos renderers de fase que divergen:** `PhaseView` desmonta el contenido; `ScreenContainer`
  lo deja montado con opacidad 0.
- **Tres listas distintas de cabeceras sensibles** en CoreNetworking (8, 7 y 4 nombres). Ya en
  sept.
- **La suite de CoreNetworking** (6.857 líneas, 4,4 veces el código) prueba código que no corre
  y sondea en tres sitios, contra su propia regla.

## 5. Agregar: lo que cada app reescribe

| Qué | Evidencia |
|---|---|
| Un vocabulario compartido de fallo de transporte (offline, server, notFound, cancelled, unknown) con sus textos | AppStarter: `TransportMappable` (71 líneas), `CatalogError` (81), `ErrorCopy` (56) y 5 `switch error.category`. Cinco cambios archivados sobre esa duplicación. La forma está por decidir: AppFoundation no importa CoreNetworking |
| Recarga idempotente al aparecer (`performRefresh`) | Existe en el fork de CareOrganizer (6 usos); AppStarter la escribe a mano en tres ViewModels |
| Un envío que se pueda esperar, para `.refreshable` | Hoy `.refreshable { send(.refresh) }` vuelve al instante |
| El cableado autenticado y los targets `Networking`/`PlatformTestSupport` en `archinit --multi` | `NetworkingWiring.swift` (67 líneas) y `NetworkingModule.swift` (79) replican el ejemplo del kit |
| Helpers de test genéricos | `Puerta`, `waitUntil` y `ObservationFlag` viven en `PlatformTestSupport` de AppStarter |
| `InMemoryTransport(exchanges:)`, y fuera de TestSupport si se enlaza en una app | AppStarter enlaza `CoreNetworkingTestSupport` en el target de la app para su modo offline, con un `DispatchSemaphore` |
| Un id estable por petición lógica en `RequestContext` | Hoy cambia en cada intento: un log no une un reintento con su original |
| Un título opcional en `BannerState` | `.banner` enseña solo el mensaje |

## Lo que está bien y no se toca

- **Cero dependencias y compilación limpia** en los dos.
- **Concurrencia.** AppFoundation: 0 `@unchecked Sendable`, 0 `Task.detached`. CoreNetworking: un
  `@unchecked Sendable` con lock, 0 `nonisolated(unsafe)`.
- **`Container` y `Router`:** pequeños y suficientes (el contenedor son 127 líneas de código).
- **`archlint` léxico y sin SwiftSyntax:** 13–77 ms por pasada. Y los plugins no tienen código
  copiado: son 4 symlinks idénticos.
- **`APIError`:** `category`, `statusCode` y `decodeBody` le dan al `Logic` lo que necesita. No
  hacen falta más categorías.
- **`HTTPTransport`, `InMemoryTransport` y `MockAPIService`:** la costura que hace deterministas
  los tests.
- **La privacidad del logging:** URL, cabeceras y cuerpos van con `.private`.
- **R15 y R16:** no hay forma limpia de no pedírselo a cada ViewModel; el lint es la herramienta
  correcta. A R16 solo le falta una condición de retirada.
- **El `ManualClock` duplicado:** una sola línea distinta entre las dos copias; sigue
  compensando.

## Deriva entre proyectos

| Proyecto | AppFoundation | CoreNetworking | Nota |
|---|---|---|---|
| AppStarter | 1.4.2 | 1.3.1 | El único al día |
| iOSAppBaseline | 0.1.1 | 0.1.4 | Anterior a la 1.0, sin migrar |
| CareOrganizer | copia local, fork pre-1.0 | no | Activo. 30 ficheros frente a 49; `BaseViewModel` sigue siendo `ObservableObject`. Tiene cambios que no han vuelto a la base: `performRefresh`, `.baseViewModelFeedback()`, `DateFormatting` |
| iOSandbox | copia local | copia local | Forks pre-1.0, parado desde abril |
| Pelis | no | no | Pila propia |

CareOrganizer es el proyecto con más pantallas (86 ViewModels) y no puede recibir ninguna de
las correcciones de arriba mientras siga en su fork.

## En AppStarter, visto de paso

- `SearchViewModel.swift:99`: la búsqueda va por `performLoad`. El campo sobrevive porque vive
  en la barra, pero cada búsqueda tapa los resultados y un fallo los sustituye por el error.
  Leído, no ejecutado.
- `CoreNetworkingTestSupport` enlazado en el target de la app (`project.yml:57-58`).
- `swift-snapshot-testing` sin fijar: el CI resolvió 1.19.6 el 22 de septiembre; la máquina de
  desarrollo sigue en 1.19.4.
- Login: un toque en el botón puede adelantarse a pulsaciones que el teclado aún entrega.
  Medido el mismo día a velocidad de máquina (63 bytes de 64; 68 de 75).

## Lo que no se pudo comprobar

- El comportamiento en pantalla de los ejemplos: son librerías sin `@main`.
- El defecto 4 en iOS: solo se midió en macOS.
- El defecto 11: es una cadena de lecturas.
- Si bajar la visibilidad de la fontanería pública rompe extensiones genéricas de
  `ScreenContainer`.
- Una hipótesis de la lectura de la librería: que en iOS `.task` se cancele al tapar la vista
  con un push, lo que por el defecto 2 dejaría el indicador colgado al volver.
- Qué coste añade compilar `archlint` y los ~40 `#Preview` en un build de consumidor.

## Por dónde empezar

Tres tandas, de menos a más compromiso:

1. **CoreNetworking 1.3.2, parche.** Defectos 1, 6 y 7. No rompen API y el 1 es el único que
   puede tirar una app en producción.
2. **AppFoundation 1.5.0, aditivo.** El contrato de errores y cancelación (sección 2) junto con
   el defecto 3: ejemplos, documentación y la salida para el error no reintentable. Después,
   AppStarter borra sus tres ficheros y sus 11 bloques.
3. **2.0 de los dos.** Quitar superficie (sección 3), con deprecación previa en la tanda 2, y
   decidir entonces los defaults de CoreNetworking (defectos 5 y 11).

Antes de la tanda 3 conviene resolver la deriva: quitar API con un solo consumidor al día es
decidir a ciegas lo que CareOrganizer necesita.
