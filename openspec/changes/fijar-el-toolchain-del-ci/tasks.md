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
