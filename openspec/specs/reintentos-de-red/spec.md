# reintentos-de-red Specification

## Purpose

Fija cuándo reintenta CoreNetworking una petición que falló y cuánto espera antes de volver a
enviarla, incluido qué hace con el `Retry-After` que manda el servidor, de forma que ninguna
respuesta pueda tirar la app ni dejar una petición esperando sin límite.

## Requirements

### Requirement: Solo se acepta un Retry-After que permite RFC 9110

`APIError.retryAfter` SHALL devolver una espera solo cuando la cabecera `Retry-After` es un
número entero de segundos escrito solo con dígitos, o una HTTP-date. Cualquier otro valor
SHALL tratarse como si la cabecera no estuviera. Ningún valor de la cabecera SHALL poder
terminar el proceso.

#### Scenario: Segundos válidos

- **WHEN** la respuesta trae `Retry-After: 7`
- **THEN** `retryAfter` es 7 segundos

#### Scenario: Un valor que no es delay-seconds ni HTTP-date

- **WHEN** la respuesta trae `Retry-After` con `inf`, `nan`, `1e30`, `2.5`, `+5` o `-5`
- **THEN** `retryAfter` es `nil`
- **AND** el proceso sigue vivo

#### Scenario: Un número que no cabe

- **WHEN** la respuesta trae `Retry-After` con un número de 30 dígitos
- **THEN** `retryAfter` es `nil`
- **AND** el proceso sigue vivo

#### Scenario: Una HTTP-date pasada

- **WHEN** la respuesta trae `Retry-After` con una HTTP-date anterior al momento actual
- **THEN** `retryAfter` es cero

### Requirement: Un reintento no espera más que el techo de la política

Cuando un reintento usaría el `Retry-After` del servidor, la espera SHALL ser ese valor si no
supera `RetryPolicy.maxDelay`. Si lo supera, la petición SHALL NOT reintentarse: el error se
devuelve a quien llamó, con su `retryAfter` intacto. Una espera fijada por un retrier con
`RetryDecision.retryAfter(_:)` no tiene ese techo.

#### Scenario: El servidor pide menos que el techo

- **WHEN** una petición reintentable falla con `Retry-After` menor o igual que `maxDelay`
- **THEN** se reintenta tras exactamente esa espera

#### Scenario: El servidor pide más que el techo

- **WHEN** una petición reintentable falla con `Retry-After` mayor que `maxDelay`
- **THEN** no se reintenta ni se espera
- **AND** quien llamó recibe el error, cuyo `retryAfter` es el valor que pidió el servidor

#### Scenario: Un retrier pide reintentar sin fijar la espera

- **WHEN** un retrier devuelve `RetryDecision.retry` y el servidor mandó un `Retry-After` mayor
  que `maxDelay`
- **THEN** no se reintenta
- **AND** quien llamó recibe el error

#### Scenario: Un retrier fija la espera

- **WHEN** un retrier devuelve `RetryDecision.retryAfter(_:)` con una espera mayor que
  `maxDelay`
- **THEN** se reintenta tras esa espera
