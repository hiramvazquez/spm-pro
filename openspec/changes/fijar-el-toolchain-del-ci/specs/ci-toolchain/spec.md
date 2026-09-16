## Purpose

Fija qué toolchain valida la integración continua de este monorepo y cómo se mantiene
alineado con el mínimo que los paquetes prometen públicamente, de forma que el contrato
publicado no pueda dejar de comprobarse en silencio.

## ADDED Requirements

### Requirement: El CI valida el mínimo que los paquetes declaran

Los paquetes publican un requisito mínimo de toolchain en su documentación. La integración
continua MUST compilar y ejecutar los tests de ambos paquetes con ese mínimo, y no
únicamente con una versión más reciente que lo satisfaga.

#### Scenario: El mínimo declarado se comprueba en cada corrida

- **WHEN** se ejecuta la integración continua sobre un commit
- **THEN** existe al menos un job que compila y testea ambos paquetes con la versión mínima
  de toolchain que la documentación declara como soportada
- **AND** ese job es bloqueante: si falla, la corrida falla

#### Scenario: Un uso incompatible con el mínimo se detecta

- **WHEN** un cambio introduce código que compila con un toolchain más nuevo pero no con el
  mínimo declarado
- **THEN** la corrida falla en el job del mínimo, antes de que la versión se publique

### Requirement: La versión del toolchain del CI es explícita

La integración continua MUST nombrar la versión de toolchain que usa. NO MUST depender de un
selector que resuelva a «la más reciente disponible», porque esa resolución cambia cuando la
imagen del runner se actualiza y desplazaría el toolchain validado sin intervención humana.

#### Scenario: La imagen del runner incorpora una versión mayor

- **WHEN** la imagen del runner añade una versión de toolchain superior a la que el CI venía
  usando
- **THEN** el CI sigue validando exactamente la versión que tiene escrita
- **AND** adoptar la nueva exige un cambio explícito en el repositorio

#### Scenario: La elección de versión está justificada

- **WHEN** alguien lee la definición del CI para saber por qué se usa esa versión
- **THEN** encuentra, junto a la versión, la fecha de la comprobación y el comando que la
  sustenta

### Requirement: El desfase entre desarrollo y CI está declarado

Cuando el toolchain con el que se desarrolla no coincide con el que valida el CI, esa
diferencia MUST estar escrita donde se toman decisiones sobre el código, indicando que una
verificación local no prueba compatibilidad con el mínimo soportado.

#### Scenario: Alguien va a confiar en una verificación local

- **WHEN** un agente o una persona verifica el repositorio en su máquina antes de publicar
- **THEN** la documentación de cada paquete le dice con qué toolchain valida el CI
- **AND** le advierte de que su verificación local no cubre la compatibilidad con el mínimo

### Requirement: El toolchain de desarrollo tiene aviso temprano

La integración continua MUST ejercitar también el toolchain con el que se desarrolla, para
que una incompatibilidad con él se vea en el CI y no al publicar. Ese ejercicio NO MUST
bloquear la corrida mientras ese toolchain no esté disponible en una versión estable.

#### Scenario: El toolchain de desarrollo rompe algo

- **WHEN** un cambio compila con el mínimo soportado pero no con el toolchain de desarrollo
- **THEN** la corrida lo señala en un job identificable como aviso temprano
- **AND** la corrida no se marca como fallida solo por ese job

#### Scenario: El aviso temprano se vuelve exigible

- **WHEN** el toolchain de desarrollo pasa a estar disponible en una versión estable en la
  imagen del runner
- **THEN** la condición para convertir ese job en bloqueante está escrita en el repositorio
