# Changelog

Todos los cambios notables de este repositorio se documentan en este fichero.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el
versionado, [SemVer](https://semver.org/lang/es/). Los dos paquetes viajan en el
mismo repo y comparten tag, así que cada versión lleva una subsección por paquete.
Cada PRD añade sus entradas bajo `[Unreleased]` en la subsección de su paquete;
X-02 cierra la versión.

## [Unreleased]

### AppFoundation
- pendiente

### CoreNetworking

#### Changed

- **Rompe API pública** — `SSLPinningConfiguration`: `pinnedHosts: Set<String>?`
  se reemplaza por `hosts: Hosts` (`.all` / `.only(Set<String>)`), y
  `validateCertificateChain: Bool` por `chainValidation: ChainValidation`
  (`.system` / `.unsafeSkipForDevelopment`, esta última con efecto solo en
  builds `DEBUG`). El constructor ahora exige, con `precondition`, al menos
  dos pines válidos (RFC 7469 §2.5: pin de respaldo) — con un solo pin, rotar
  la clave del servidor deja la app instalada sin poder conectar. Añadido
  `SSLPinningConfiguration.validatePins(_:)` para validar pines de origen
  remoto sin arriesgarse a un crash.
- Tabla ASN.1 de SPKI: añadido RSA-3072 (antes solo RSA-2048/4096 y EC
  P-256/P-384).
- README: nueva sección «Pinning declarativo (recomendado)» documentando
  `NSPinnedDomains` (`NSPinnedLeafIdentities` / `NSPinnedCAIdentities`,
  `SPKI-SHA256-BASE64`) como opción por defecto desde iOS 14, y cuándo el
  pinning programático de este paquete sigue siendo necesario.

PRD: [PRD-CN-02](PRD/PRD-CN-02.md).

<!-- PRD-CN-01 -->

#### Breaking

- `APIError` pasa de ser un `enum` cerrado a un `struct` extensible con
  `Code` (conjunto abierto), `RequestSummary`, `ResponseSummary` y
  `underlying`. Añadir un `Code` nuevo ya no rompe a los consumidores.
  `TransportError` y `APIMessageError` desaparecen: `APIError.category`
  cubre la clasificación de alto nivel que daba `TransportError`, y
  `decodeBody<T>(_:using:)` permite decodificar cualquier sobre de error del
  servidor con el tipo y el `JSONDecoder` del consumidor.
- `APIError` deja de ser `Equatable` (un `==` que ignorase `underlying`
  mentiría). `CoreNetworkingTestSupport` añade `APIError.stub(code:...)`
  para tests.
- `RetryPolicy.shouldRetry` pasa a `@Sendable (APIError, Int) -> Bool`;
  `RetryPolicy` deja de ser `Equatable` (el predicado es un closure).
- `RequestInterceptor.didFail(_:error:)` tipa `error: APIError` en vez de
  `Error`.

#### Fixed

- Ningún `catch` del pipeline pierde ya el error original: un `NSError`
  arbitrario del transporte llega como `code == .unexpected` con
  `underlying` intacto; un fallo de decodificación conserva el body de la
  respuesta para diagnóstico.
- 401 y 403 ya no colapsan en la misma categoría (`.unauthorized` vs.
  `.forbidden`).
- `isRetryable` ya no reintenta `notConnectedToInternet` (sin red no hay
  nada que reintentar en medio segundo) y sí reintenta `dnsLookupFailed` /
  `cannotFindHost`, que son transitorios.

#### Added

- `APIError.errorDescription` (`LocalizedError`): frase neutra y
  localizable (inglés/español, string catalog del paquete) por `category`,
  nunca un código pelado.

PRD: [PRD-CN-01](PRD/PRD-CN-01.md).

## [0.1.4]

Estado previo a la auditoría técnica de 2026-09-01 (`AUDITORIA-2026-09-01.md`).
Los cambios anteriores a este punto se documentan solo en el historial de git.
