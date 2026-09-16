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
- [ ] 2.3 Correr el CI en la rama y confirmar que pasa con el código actual. **Si falla, el
      hallazgo es real**: lo publicado no cumple el mínimo que los README prometen; se trata
      antes de continuar y se anota aquí qué se encontró. Verificación: la corrida de la
      rama termina con ese job en verde, o con el hallazgo escrito en este fichero.

## 3. El aviso temprano del toolchain de desarrollo

- [x] 3.1 Añadir un job sobre la imagen `xcode-27` con `continue-on-error: true` que compile
      y teste ambos paquetes. Verificación: la corrida muestra el job y su resultado no
      cambia la conclusión de la corrida.
- [x] 3.2 Escribir en el propio workflow la condición para volverlo bloqueante: que
      `xcode-27` deje de estar en preview (seguimiento en `actions/runner-images#14404`).
      Verificación: el comentario cita la incidencia.
- [ ] 3.3 Confirmar si la label `xcode-27` está disponible para esta cuenta. Si no lo está,
      retirar el job y dejar escrito aquí por qué, en vez de dejarlo fallando en cada
      corrida. Verificación: o el job corre, o este fichero explica su ausencia.

## 4. Declarar el desfase donde se decide

- [x] 4.1 Añadir a `AppFoundation/AGENTS.md` y `CoreNetworking/AGENTS.md` una nota que diga
      con qué toolchain valida el CI y que una verificación local con un toolchain más nuevo
      NO prueba compatibilidad con el mínimo. Verificación: ambos ficheros la contienen.
- [x] 4.2 Revisar que el límite ya declarado en `kit.conf` sigue siendo cierto tras este
      cambio y ajustarlo si la versión fijada cambia lo que allí se afirma. Verificación:
      leer el bloque de límites de `kit.conf` y contrastarlo con las variables nuevas.

## 5. Cierre

- [x] 5.1 `/kit-verifica` en verde.
