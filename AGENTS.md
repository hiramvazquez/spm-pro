# CoreNetworking — guía para agentes

Este paquete es la capa de red. En la arquitectura View → ViewModel → Logic →
Services/Stores (ver `AppFoundation/AGENTS.md`), CoreNetworking solo lo toca un
**Service**: nunca un ViewModel, nunca un Logic directamente.

## Regla: un Service, una llamada a API

- Un **Service** declara `protocol XxxServicing: Sendable` + una implementación (`struct`
  normalmente) que es la ÚNICA pieza de la app que referencia `APIServiceProtocol` y
  `BaseRequest`. Si necesita más de una llamada, sigue siendo el único sitio que lo hace —
  el `Logic` que lo usa nunca ve `APIServiceProtocol`.
- `EndpointService` (`Sources/CoreNetworking/EndpointService.swift`) es una PLANTILLA
  cómoda, no un requisito: `protocol EndpointService: Sendable { var api: any
  APIServiceProtocol { get } }` con `call(_:)` gratis vía `extension`. Un Service con más
  de un patrón de llamada puede ignorarlo y llamar `api.execute` directamente.
- Cada request es su propio `BaseRequest`: `path`, `method`, `body` (opcional),
  `Response` (opcional, `Empty` si no hay). No reutilices un `BaseRequest` genérico con
  parámetros — un endpoint, un tipo.

```swift
struct LoginRequest: BaseRequest {
    struct Response: Decodable, Sendable { let token: String }
    let path = "/login"
    let method = HTTPMethod.post
    let body: Body?
    struct Body: Encodable, Sendable { let email: String; let password: String }
}

struct LoginService: LoginServicing, EndpointService {
    let api: any APIServiceProtocol
    func login(email: String, password: String) async throws(APIError) -> Session {
        let response = try await call(LoginRequest(body: .init(email: email, password: password)))
        return Session(token: response.token)
    }
}
```

## Mapeo de errores

Todo lo que puede fallar es un `APIError` (typed throws) — el Service lo propaga tal cual,
nunca lo interpreta. Es el **Logic** que llama al Service quien clasifica con `category`
(`.offline`, `.unauthorized`, `.untrustedServer`, `.server`, …) y lo traduce a su propio
`XxxError: DomainError` (AppFoundation, `docs/ARQUITECTURA-KIT-2026-09-02.md` §8, M1) — el
`ErrorPresenting` de la app nunca ve un `APIError`, solo `DomainError`s. Para leer el
cuerpo de un error de servidor con TU propio envelope, usa `error.decodeBody(MiEnvelope.self)`
desde el Logic — este paquete nunca interpreta el body, solo lo conserva.

## Cómo testear un Service

- **Caso feliz / error puntual**: `MockAPIService` — `stub(RequestType.self, returning:)` /
  `stub(RequestType.self, throwing:)`. Construye el Service con el MISMO `init(api:)` que
  usa producción, pasando el mock en vez de un `APIService` real.
- **Pipeline real** (retries, interceptores, refresh de token, 401 → refresh → 200):
  `InMemoryTransport` + `ManualClock` (retry/backoff sin esperas reales) — nunca
  `Task.sleep`/polling en un test.
- Ambos productos viven en `CoreNetworkingTestSupport` (producto separado: nunca en el
  binario de producción).

## Qué NO hacer

- No construyas un `APIService` dentro de un `Logic` o `ViewModel` — eso es trabajo del
  Service (y de la composición en `DependencyModule`).
- No decodifiques el body de error de CoreNetworking en la app fuera de
  `decodeBody(_:using:)` — no hay otra vía soportada para leer `response.body`.
- No agregues un segundo `BaseRequest` genérico con parámetros para "ahorrar" tipos: un
  endpoint, un `BaseRequest`, un Service que lo llama.

Ver también: `AppFoundation/AGENTS.md` (capas View/ViewModel/Logic),
`AppFoundation/Examples/LoginApp` (el Service de referencia, con sus tres niveles de test),
`Examples/APIClientApp` (un consumidor mínimo, sin AppFoundation) y
`Sources/CoreNetworking/Documentation.docc/` (Xcode: **Product ▸ Build Documentation**)
para la referencia completa por pieza, con ejemplos que compilan (`Snippets/`).

Los ejemplos de DocC están sincronizados con `Snippets/` por CI (`Scripts/check-doc-snippets.sh`, job `docs`).

## El toolchain que manda no es el tuyo

El CI valida este paquete con **Xcode 26.0.1 (el mínimo que prometen los README) y con
26.3**, fijados en `.github/workflows/ci.yml`. Quien desarrolla suele ir por delante
—hoy Xcode 27 / Swift 6.4—, y eso NO es equivalente: **una verificación local en verde no
prueba compatibilidad con el mínimo soportado**.

Medido el 2026-09-16, y por eso está escrito aquí: Swift 6.4 no emite los diagnósticos de
`MemberImportVisibility` que sí emite 6.2.4, y no hay forma de reproducir 6.2.4 en una
máquina con el SDK de macOS 27 (ni instalando el toolchain suelto: no compila). Ignorarlo
costó dos versiones publicadas con el CI en rojo y tres rondas para cerrarlo.

La consecuencia práctica, para no repetirlo: **cada fichero importa lo que usa**, sin
apoyarse en que otro módulo lo reexporte. Es lo que pide `MemberImportVisibility`, y es
invisible en 6.4 — no lo vas a ver fallar aquí.
