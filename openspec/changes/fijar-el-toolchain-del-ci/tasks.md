## 1. Fijar la versión del toolchain

- [x] 1.1 En `.github/workflows/ci.yml`, sustituir `env.XCODE_VERSION: latest-stable` por dos
      variables explícitas: `XCODE_MINIMO` (la Xcode 26 más antigua de `macos-15`, hoy
      `26.0.1`) y `XCODE_ACTUAL` (la 26.x con la que corre el grueso de la matriz, hoy
      `26.3`). Verificación: `grep -c "latest-stable" .github/workflows/ci.yml` devuelve `0`.
- [x] 1.2 Dejar junto a esas variables un comentario con la fecha de la comprobación y el
      comando que la sustenta (`gh api repos/actions/runner-images/contents/images/macos/…`),
      más qué imagen ofrece qué rango. Verificación: el comentario nombra fecha, comando y
      el hecho de que `26.0.x` solo existe en `macos-15`.
- [x] 1.3 Apuntar los jobs existentes a `XCODE_ACTUAL`. Verificación: ningún job del workflow
      referencia ya `XCODE_VERSION`.

## 2. El job del mínimo soportado

- [x] 2.1 Añadir un job bloqueante sobre `macos-15` con `XCODE_MINIMO`, que compile y ejecute
      los tests de ambos paquetes en modo estricto (`SWIFT_STRICT_WARNINGS=1 swift build
      --build-tests` y `swift test --parallel`). Verificación: el job aparece en la corrida y
      su paso de versiones imprime Xcode 26.0.1.
- [x] 2.2 Nombrarlo de forma que diga lo que es —el mínimo soportado, no «otra» versión—.
      Verificación: el nombre del job contiene «mínimo soportado».
- [x] 2.3 Correr el CI en la rama y confirmar que pasa con el código actual. **Hallazgo
      (run `35127837096`, 2026-09-16): no pasa, y por dos causas distintas.** CoreNetworking
      compila pero su suite no corre —cuatro *exit tests* de swift-testing, no implementados
      en ese toolchain: `Testing/ExitTest.swift:398: Fatal error: Unimplemented`—.
      AppFoundation ni compila las pruebas: `ViewModelOwnershipTests.swift:99` y `:127` usan
      `weak let`, que ese compilador rechaza. Las dos librerías SÍ compilan. Enmienda escrita
      en `proposal.md` y en el spec; continúa en el grupo 6.

## 6. Separar compilar del mínimo de ejecutar los tests (enmienda 2026-09-16)

- [x] 6.1 El job del mínimo deja de ejecutar tests y solo compila (`swift build`, sin
      `--build-tests`: las pruebas son justamente lo que no compila en 26.0.1).
      Verificación: el job pasa en verde para ambos paquetes con Xcode 26.0.1.
- [x] 6.2 Medir en CI cuál es la 26.x más baja donde las suites corren, probando 26.1.1 y
      26.2 en una matriz temporal. **Resultado (run `35134647002`, 2026-09-16): 26.2.**
      26.0.1 → no; 26.1.1 → no, con las MISMAS dos causas (exit tests sin implementar en
      CoreNetworking, `weak let` rechazado en AppFoundation); 26.2 → sí, los dos paquetes.
      Los dos jobs de `Mínimo soportado` pasaron en verde, así que ambas librerías compilan
      con 26.0.1: el contrato publicado se cumple.
- [x] 6.3 Fijar esa versión en una variable propia y dejar un job que ejecute las suites con
      ella, con un comentario que diga qué lo impide en el mínimo (exit tests y `weak let`).
      Verificación: el workflow nombra ambas causas.
- [x] 6.4 Los tres README distinguen el mínimo para **consumir** del mínimo para
      **desarrollar**. Verificación: los tres lo dicen.

## 3. El aviso temprano del toolchain de desarrollo

- [x] 3.1 Añadir un job sobre la imagen `xcode-27` con `continue-on-error: true` que compile
      y teste ambos paquetes. Verificación: la corrida muestra el job y su resultado no
      cambia la conclusión de la corrida.
- [x] 3.2 Escribir en el propio workflow la condición para volverlo bloqueante: que
      `xcode-27` deje de estar en preview (seguimiento en `actions/runner-images#14404`).
      Verificación: el comentario cita la incidencia.
- [x] 3.3 Confirmar si la label `xcode-27` está disponible para esta cuenta. **Sí lo está**:
      en el run `35127837096` los dos jobs de aviso temprano corrieron y además pasaron en
      verde, con ambos paquetes compilando y testeando sobre Xcode 27 beta 6.

## 4. Declarar el desfase donde se decide

- [x] 4.1 Añadir a `AppFoundation/AGENTS.md` y `CoreNetworking/AGENTS.md` una nota que diga
      con qué toolchain valida el CI y que una verificación local con un toolchain más nuevo
      NO prueba compatibilidad con el mínimo. Verificación: ambos ficheros la contienen.
- [x] 4.2 Revisar que el límite ya declarado en `kit.conf` sigue siendo cierto tras este
      cambio y ajustarlo si la versión fijada cambia lo que allí se afirma. Verificación:
      leer el bloque de límites de `kit.conf` y contrastarlo con las variables nuevas.

## 5. Cierre

- [x] 5.1 `/kit-verifica` en verde.

## 7. Cierre del revisor (AMBER, 2026-09-16)

- [x] 7.1 **Dato falso corregido**: se afirmó que `macos-26` ya no trae Xcode 26.0.x, y sí la
      trae —salió de leer la tabla del readme truncada a seis filas—. Corregido en el
      comentario del workflow, en `design.md` (D2, que se apoyaba entero en ese dato) y
      anotado en el proposal. Verificación: `gh api …/macos-26-Readme.md` lista 26.0.1.
- [x] 7.2 **El job del mínimo no compilaba el código iOS-only.** `swift build` construye para
      el host, así que los bloques `#if os(iOS)` de cuatro ficheros —`PopGestureEnabler`
      entero— nunca se type-checkeaban con 26.0.1, que es justo la parte iOS de una librería
      de iOS. Se añade `xcodebuild build -destination 'generic/platform=iOS Simulator'` al
      job. Verificación: el paso aparece y pasa en verde para ambos paquetes.
- [x] 7.3 **Promesa falsa en los AGENTS.md publicados.** Decían que el CI validaba con 26.0.1
      y 26.3 «fijados en `.github/workflows/ci.yml`», y en el repo publicado esa ruta resuelve
      al workflow propio del paquete, que sigue con `latest-stable`. El texto pasa a nombrar
      el CI del monorepo y a advertir de esa diferencia; los README igual. Verificación:
      ninguna afirmación dice ya «lo comprueba el CI» sin decir cuál.
- [x] 7.4 Corrida de CI que confirme el paso nuevo de iOS en el job del mínimo.
      **Run `35166718388`: los dos jobs del mínimo en verde con el paso de iOS incluido.**
      Y como `-quiet` no deja rastro en el log, salir con 0 no probaba nada: se midió con
      una sonda local. Con el código intacto, el comando sale 0; metiendo un error de tipos
      DENTRO del `#if os(iOS)` de `PopGestureEnabler`, sale 65. Ese mismo error es invisible
      para `swift build` en macOS — que es justo el agujero que este paso cierra.

## 8. Hallazgo que NO se arregla aquí

- [ ] 8.1 Los `ci.yml` propios de `AppFoundation/` y `CoreNetworking/` —los que viajan en el
      `subtree split`— siguen con `latest-stable` y sin job de mínimo (7 y 6 apariciones).
      El monorepo es la fuente y sí tiene la puerta, así que no bloquea; pero quien clone el
      repo publicado tiene un CI que no comprueba lo que su README promete. Merece su propio
      cambio: tocarlo aquí sería ampliar el alcance por tercera vez en la misma sesión.

## 9. Cierre del juez (ACEPTADO con defectos de texto, 2026-09-16)

- [x] 9.1 **El acuerdo se contradecía consigo mismo**: el criterio C1 exigía que
      `XCODE_VERSION` nombrara una versión concreta, y las tareas 1.1 y 1.3 exigen que esa
      variable desaparezca. Leído al pie de la letra, no se podía cumplir entero. Los dos
      criterios pasan a hablar de «las variables de versión» sin nombrar una que ya no
      existe. Verificación: ningún criterio nombra `XCODE_VERSION`.
- [x] 9.2 **Dos números vivían en el nombre de un job, al lado de la variable que los
      contiene** («Mínimo soportado — Xcode 26.0.1», «Tests en el mínimo ejecutable — Xcode
      26.2»). Quien suba la variable dejaría el nombre mintiendo, y el nombre es lo que se ve
      en la lista de checks. Se retiran: el paso «Versiones» imprime la que de verdad se usó.
      Verificación: los nombres ya no llevan número.
- [x] 9.3 **`kit.conf` enumeraba dos de las tres versiones**, y omitía justo la 26.2, que es
      la que ejecuta las suites. Pasa a nombrar las tres con su papel. Verificación: el
      bloque de límites cita 26.0.1, 26.2 y 26.3.
- [x] 9.4 **La segunda reducción de alcance vivía solo en `tasks.md`.** La 8.1 —los `ci.yml`
      propios de cada paquete— se declaraba fuera de alcance en las tareas pero no en la
      sección «Fuera de alcance» del proposal, que es la que se archiva y la que alguien
      leerá dentro de un año. Promovida. Verificación: el proposal la menciona.
