# PRD-CN-02 — Pinning: configuración segura y `NSPinnedDomains` como opción por defecto

Paquete: CoreNetworking · Oleada 1 · Cubre: CN-19 · Rompe API pública: **sí** (`pinnedHosts`, `validateCertificateChain`)

## Problema
Un solo pin brickea la app al rotar clave; `validateCertificateChain: Bool` es un flag peligroso con nombre inocente;
falta RSA-3072; `pinnedHosts: Set<String>?` usa `nil` como comodín; y no se documenta que Apple ofrece pinning
declarativo (`NSPinnedDomains`, iOS 14+) que cubre el caso común sin código.

## Diseño

```swift
public struct SSLPinningConfiguration: Sendable, Equatable {
    public enum Hosts: Sendable, Equatable { case all; case only(Set<String>) }
    public let publicKeyHashes: [String]
    public let hosts: Hosts
    public let chainValidation: ChainValidation
    public enum ChainValidation: Sendable, Equatable {
        case system                       // default: SecTrustEvaluateWithError antes de comparar pins
        case unsafeSkipForDevelopment     // solo compila su uso en DEBUG: `#if DEBUG` alrededor del case NO es posible; en su lugar, `init` hace `assertionFailure` en Release si se usa, y el doc lo explica
    }
    public init(publicKeyHashes: [String], hosts: Hosts = .all, chainValidation: ChainValidation = .system)
    // precondition(publicKeyHashes.count >= 2, "Se requieren al menos 2 pins (RFC 7469: pin de respaldo) …")
    // precondition: cada pin es base64 válido de 32 bytes
    public static let disabled: SSLPinningConfiguration   // hosts: .only([]) — mantener semántica actual
}
```
- Tabla ASN.1: añadir RSA-3072 (`30 82 01 A2 30 0D 06 09 2A 86 48 86 F7 0D 01 01 01 05 00 03 82 01 8F 00`). Verificar
  el header generando una clave RSA-3072 con openssl en el test (vector embebido, como los existentes).
- `requiresPinning(host:)` y `decision(...)` se adaptan; la lógica de 3 estados no cambia.
- README: nueva subsección «Pinning declarativo (recomendado)» con el bloque `Info.plist` de `NSPinnedDomains` /
  `NSPinnedLeafIdentities` / `NSPinnedCAIdentities` (`SPKI-SHA256-BASE64`), cuándo basta (pins estáticos, sin
  WKWebView) y cuándo usar el programático (rotación remota, hosts dinámicos). Comando openssl ya existente se
  conserva; añadir cómo generar el pin de respaldo desde un CSR/clave futura.

## Ficheros
Sources: `SSLPinningConfiguration.swift`. Tests: `PinningTests.swift`, `PinningDelegateTests.swift` (solo adaptar
constructores). README: sección «SSL Pinning». **No tocar** `SessionDelegates.swift` ni `APIService.swift` (CN-04).

## Criterios de aceptación
- [ ] `SSLPinningConfiguration(publicKeyHashes: ["x"])` falla con `precondition` cuyo mensaje menciona RFC 7469 (test con `#expect(processExitsWith:)` si el toolchain lo soporta; si no, test de la función pura `validatePins` extraída).
- [ ] Vector RSA-3072 pasa en `SPKI hashing`.
- [ ] `Hosts.all` / `.only([...])` sustituyen al opcional; `grep -n "pinnedHosts" Sources` vacío.
- [ ] `chainValidation: .unsafeSkipForDevelopment` dispara `assertionFailure` fuera de DEBUG (documentado y con test en DEBUG de que **no** dispara).
- [ ] README con bloque `NSPinnedDomains` completo y verificable.
