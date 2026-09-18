## Purpose

Fija con qué puede decidir un test de este monorepo si algo pasa o falla, de manera que un
rojo signifique siempre lo mismo y nadie tenga que preguntar si «es que el runner iba
cargado».

## ADDED Requirements

### Requirement: Un test no decide con el reloj de pared

Un test MUST decidir su resultado a partir de señales observables del sistema que prueba, no
del tiempo transcurrido en la máquina que lo ejecuta.

Cuando lo que se prueba es una espera —un backoff, un timeout, una cadencia—, el test MUST
usar un reloj que él controle, y el componente bajo prueba MUST admitir que se le inyecte.
Si algún caso no puede evitar el reloj real, el test MUST llevar escrito por qué, junto a la
afirmación que lo usa.

#### Scenario: Se prueba una espera

- **WHEN** un test comprueba el comportamiento de una espera del sistema
- **THEN** la espera transcurre en un reloj que el test controla
- **AND** el resultado del test no depende de cuánto tarde la máquina

#### Scenario: La máquina va cargada

- **WHEN** la suite se ejecuta en una máquina mucho más lenta de lo habitual
- **THEN** los tests que pasaban siguen pasando
- **AND** los que fallaban siguen fallando, por el mismo motivo

### Requirement: Un test establece su premisa antes de afirmar sobre ella

Cuando un test necesita que el sistema esté en un estado concreto para que su afirmación
signifique algo —una transferencia en vuelo, una conexión abierta, una espera en curso—, el
test MUST establecer ese estado de forma observable antes de afirmar, y MUST fallar con un
mensaje distinto si el estado no llegó a darse.

Un rojo por «la premisa no se cumplió» NO MUST confundirse con un rojo por «el sistema se
comportó mal».

#### Scenario: La premisa no se cumple

- **WHEN** el estado que el test necesita no llega a producirse
- **THEN** el test falla señalando que no pudo establecer su premisa
- **AND** el mensaje no acusa al sistema de un comportamiento que no se llegó a ejercitar

#### Scenario: La premisa se cumple y el sistema falla

- **WHEN** el estado se establece y el sistema no se comporta como se espera
- **THEN** el test falla señalando el comportamiento incorrecto

### Requirement: Una medición de rendimiento se distingue de una comprobación de corrección

Un test cuyo veredicto depende de cuánto tarda algo MUST estar identificado como medición de
rendimiento, y la definición de la integración continua MUST decir si puede o no tumbar una
publicación.

#### Scenario: Una medición de rendimiento falla

- **WHEN** una medición de rendimiento supera su presupuesto
- **THEN** quien lee el resultado distingue eso de una regresión de corrección
- **AND** el efecto sobre la corrida es el que la definición del CI declara
