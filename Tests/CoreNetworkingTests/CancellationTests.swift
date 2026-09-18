import CoreNetworkingTestSupport
import Foundation
import Testing

@testable import CoreNetworking

/// Cancelación REAL: el mock entrega con latencia larga (5 s) y `stopLoading`
/// cancela la entrega pendiente. Se assertan el error Y el desmontaje de la
/// transferencia en vuelo — este último con la señal observable del mock
/// (`MockURLProtocol.cancelledDeliveries`), no con el reloj.
///
/// Antes se medía "tardó menos de 2 s, luego se canceló": la misma afirmación por vía
/// indirecta, y falsa en cuanto la máquina va cargada. En el simulador de un runner de
/// CI estos cinco tests fallaban a la vez con ~4 s de elapsed, todos por el mismo
/// motivo — la máquina, no el paquete. La señal no depende de lo rápido que vaya nadie:
/// o el mock vio cancelada su entrega pendiente, o no la vio.
@Suite("Cancelación de execute / upload / download / backoff")
struct CancellationTests {
    private struct SlowRequest: BaseRequest {
        typealias Response = Payload
        let path = "/slow"
        let method: HTTPMethod = .get
    }

    private struct SlowPut: BaseRequest {
        typealias Response = Payload
        let path = "/slow"
        let method: HTTPMethod = .put
    }

    private struct Payload: Decodable, Sendable { let ok: Bool }

    private func makeService(
        host: String,
        policy: RetryPolicy = .noRetry,
        retriers: [any RequestRetrier] = []
    ) throws -> (APIService, URL) {
        let baseURL = try #require(URL(string: "https://\(host)"))
        let configuration = NetworkingConfiguration(baseURL: baseURL, protocolClasses: [MockURLProtocol.self])
        return (
            APIService(configuration: configuration, retryPolicy: policy, retriers: retriers),
            baseURL
        )
    }

    private func registerSlowMock(url: URL, method: HTTPMethod = .get) {
        MockURLProtocol.register(
            MockNetworkExchange(
                method: method,
                url: url,
                response: MockResponse(statusCode: 200, data: Data(#"{"ok":true}"#.utf8)),
                latency: .seconds(5)
            )
        )
    }

    /// Espera a que el mock haya visto la petición —`startLoading` la registra en
    /// `recordedRequests`— y solo entonces cancela.
    ///
    /// El `ContinuousClock` de aquí es un TECHO de espera, no la afirmación del test: si la
    /// señal no llega, el test falla diciendo que no pudo establecer su premisa. Es la
    /// diferencia con medir el reloj para decidir si algo estuvo bien.
    private func waitUntilInFlight(
        method: HTTPMethod,
        url: URL,
        timeout: Duration = .seconds(10)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            let visto = MockURLProtocol.recordedRequests.contains {
                $0.url == url && ($0.httpMethod ?? "GET").caseInsensitiveCompare(method.rawValue) == .orderedSame
            }
            if visto { return true }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Espera a que el bucle de reintento haya llegado a DORMIR el backoff en el reloj manual.
    ///
    /// `pendingDeadlines` es la señal observable de que alguien duerme en ese reloj, y el
    /// `ContinuousClock` de aquí es un TECHO, igual que en `waitUntilInFlight`: si nadie llega a
    /// dormir, el test falla diciendo que no pudo establecer su premisa.
    ///
    /// Sin este techo, `ManualClock.waitUntilSleeping()` no vuelve NUNCA cuando nadie duerme, y
    /// el test se CUELGA en vez de fallar. No es teórico: el juez amputó el `clock.sleep` del
    /// producto y el proceso siguió vivo 32 minutos sin una línea de salida. En CI no lo mata
    /// nadie —este workflow no fija `timeout-minutes`—, así que serían las seis horas por
    /// defecto del job, y sin decir por qué. Es el mismo motivo por el que
    /// `TaskDelegateTests` pone `.timeLimit` en su test del `completionHandler`.
    private func waitUntilBackoffSleeping(
        _ clock: ManualClock,
        timeout: Duration = .seconds(10)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if !clock.pendingDeadlines.isEmpty { return true }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Lanza `body`, lo cancela y comprueba que sale por `.cancelled`.
    ///
    /// Devuelve si la PREMISA se estableció —la petición llegó a estar en vuelo—, para que
    /// quien encadene más afirmaciones no acuse al sistema de algo que no se ejercitó.
    ///
    /// Con `inFlight`, espera a que la petición esté EN VUELO antes de cancelar. Dormir un
    /// rato fijo y confiar en llegar a tiempo era una carrera contra
    /// `timeoutIntervalForResource` —60 s, que impone el suelo de seguridad—: si la máquina
    /// se atasca más que eso, la petición muere por timeout y el test acusa a la cancelación
    /// de algo que nunca llegó a ejercitar. Pasó en el run 35070600701
    /// (`APIError(code: transport, underlying: URLError(-1001))`) y se reprodujo en local
    /// bajando ese techo a 0,3 s.
    ///
    @discardableResult
    private func expectCancelled(
        inFlight: (method: HTTPMethod, url: URL),
        _ body: @escaping @Sendable () async throws -> Void
    ) async -> Bool {
        let task = Task {
            try await body()
        }

        guard await waitUntilInFlight(method: inFlight.method, url: inFlight.url) else {
            task.cancel()
            _ = await task.result
            Issue.record(
                "no pude poner la petición en vuelo: el mock nunca registró \(inFlight.method.rawValue) \(inFlight.url). Sin esa premisa este test no afirma nada sobre la cancelación"
            )
            return false
        }
        task.cancel()

        let outcome = await task.result

        switch outcome {
        case .success:
            Issue.record("la operación debía cancelarse, no completarse")
        case .failure(let error):
            let apiError = error as? APIError
            #expect(apiError?.code == .cancelled, "esperaba .cancelled, llegó \(error)")
        }
        return true
    }

    /// Cancela y además exige que el mock haya visto cancelada su entrega pendiente:
    /// la transferencia en vuelo se desmontó de verdad, no se quedó corriendo hasta
    /// entregar los 5 s de latencia.
    private func expectCancelledAndTornDown(
        deliveryFor url: URL,
        method: HTTPMethod = .get,
        _ body: @escaping @Sendable () async throws -> Void
    ) async {
        // Si la premisa falló, `expectCancelled` ya lo dijo con su mensaje: seguir aquí añadiría
        // un segundo rojo —«la transferencia siguió viva»— acusando al sistema de un
        // comportamiento que nunca se llegó a ejercitar, que es justo lo que el escenario de la
        // spec prohíbe.
        guard await expectCancelled(inFlight: (method, url), body) else { return }
        let tornDown = await MockURLProtocol.waitForCancelledDelivery(method: method, url: url)
        #expect(
            tornDown,
            "el mock nunca vio cancelada su entrega pendiente: la transferencia siguió viva tras cancelar el Task"
        )
    }

    @Test("execute se cancela de verdad")
    func executeCancels() async throws {
        let (service, baseURL) = try makeService(host: "cancel-exec.test")
        registerSlowMock(url: baseURL.appendingPathComponent("/slow"))

        await expectCancelledAndTornDown(deliveryFor: baseURL.appendingPathComponent("/slow")) {
            let _: Payload = try await service.execute(SlowRequest())
        }
    }

    @Test("upload se cancela de verdad")
    func uploadCancels() async throws {
        let (service, baseURL) = try makeService(host: "cancel-upload.test")
        registerSlowMock(url: baseURL.appendingPathComponent("/slow"), method: .put)

        await expectCancelledAndTornDown(
            deliveryFor: baseURL.appendingPathComponent("/slow"),
            method: .put
        ) {
            let _: Payload = try await service.upload(SlowPut(), data: Data("x".utf8))
        }
    }

    @Test("data(for:) se cancela de verdad")
    func dataCancels() async throws {
        let (service, baseURL) = try makeService(host: "cancel-data.test")
        registerSlowMock(url: baseURL.appendingPathComponent("/slow"))

        await expectCancelledAndTornDown(deliveryFor: baseURL.appendingPathComponent("/slow")) {
            _ = try await service.data(for: SlowRequest(), progress: nil)
        }
    }

    @Test("download(to:) se cancela de verdad, sin fichero huérfano en destination")
    func downloadToDiskCancels() async throws {
        let (service, baseURL) = try makeService(host: "cancel-download-disk.test")
        registerSlowMock(url: baseURL.appendingPathComponent("/slow"))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("cn04-cancel-download-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destination) }

        await expectCancelledAndTornDown(deliveryFor: baseURL.appendingPathComponent("/slow")) {
            try await service.download(SlowRequest(), to: destination, progress: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    /// Aquí no hay transferencia en vuelo que desmontar: el 500 se entrega al instante y lo
    /// que se cancela es la ESPERA del backoff. Antes eso se afirmaba cronometrando la
    /// ventana de espera contra un presupuesto de 3 s, y por eso caía en cuanto el runner
    /// iba cargado.
    ///
    /// Ya no hace falta: el backoff duerme en un `ManualClock` inyectado, y
    /// `waitUntilSleeping()` suspende hasta que el bucle registra el `sleep` — es la premisa
    /// observable («el bucle llegó al backoff»), no una suposición sobre cuánto tarda la
    /// máquina. Desde ahí se cancela y se comprueba lo único que este test afirma: que la
    /// espera se interrumpe y que no hay segundo request.
    ///
    /// Con `InMemoryTransport` en vez de `MockURLProtocol` porque aquí no se prueba el URL
    /// loading system, se prueba el bucle de reintento — mismo patrón que `RetryBehaviorTests`.
    @Test("cancelar durante el backoff del retry → .cancelled sin segundo request")
    func cancelDuringBackoff() async throws {
        let baseURL = try #require(URL(string: "https://cancel-backoff.test"))
        let transport = InMemoryTransport()
        await transport.register(
            InMemoryTransport.Exchange(url: baseURL.appendingPathComponent("/slow"), response: .response(status: 500))
        )
        let clock = ManualClock()
        let backoff = Duration.seconds(5)
        let service = APIService(
            configuration: NetworkingConfiguration(baseURL: baseURL),
            transport: transport,
            retryPolicy: RetryPolicy(maxAttempts: 2, initialDelay: backoff, maxDelay: backoff),
            clock: clock
        )

        let task = Task { () -> Payload in
            try await service.execute(SlowRequest())
        }
        // Premisa: el bucle llegó a dormir el backoff. Sin esto, cancelar antes de tiempo
        // haría pasar el test sin haber ejercitado ninguna espera — y sin el techo, no haber
        // espera colgaba el test en vez de ponerlo rojo.
        guard await waitUntilBackoffSleeping(clock) else {
            task.cancel()
            _ = await task.result
            Issue.record(
                "el bucle no llegó a dormir el backoff: sin espera que cancelar, este test no mide nada"
            )
            return
        }
        task.cancel()

        switch await task.result {
        case .success:
            Issue.record("la operación debía cancelarse durante el backoff, no completarse")
        case .failure(let error):
            let apiError = error as? APIError
            #expect(apiError?.code == .cancelled, "esperaba .cancelled, llegó \(error)")
        }
        #expect(
            await transport.recorded.count == 1,
            "no debe haber segundo request tras cancelar en el backoff"
        )
    }
}
