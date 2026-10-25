import XCTest
@testable import Panel

final class CommunityTests: XCTestCase {
    func testGermanInterpolationAndUnknownText() {
        XCTAssertEqual(WingLanguage.render("Your servers.\nYour Wing.", code: "de"), "Deine Server.\nDein Wing.")
        let name = "{{1}}-custom-name"
        XCTAssertEqual(WingLanguage.render("The action will run for \(name).", code: "de"), "Die Aktion wird für {{1}}-custom-name ausgeführt.")
    }
    func testPanelURLNormalization() throws {
        XCTAssertEqual(try PanelAPI.normalize("panel.example.com/api/client/").absoluteString, "https://panel.example.com")
        XCTAssertEqual(try PanelAPI.normalize("https://example.com/panel/").path, "/panel")
        for input in ["http://example.com", "https://user:password@example.com", "https://example.com?token=secret"] { XCTAssertThrowsError(try PanelAPI.normalize(input)) }
    }
    func testResourceEnvelopeAndPermissions() throws {
        let response = try JSON.parse(#"{"object":"stats","attributes":{"current_state":"offline","resources":{"cpu_absolute":0}}}"#)
        XCTAssertEqual(response.attributes["current_state"].string, "offline")
        XCTAssertEqual(PanelNumbers.number(response.attributes["resources"]["cpu_absolute"]), 0)
        XCTAssertNil(PanelNumbers.number(.null))
        XCTAssertEqual(ServerAccess.requirement("servers/abc/network/allocations/1/primary", method: "POST")?.permission, "allocation.update")
        XCTAssertEqual(ServerAccess.requirement("servers/abc/files/download")?.permission, "file.read-content")
    }
    func testMetadataRejectsWrongPluginAndClientMod() throws {
        let old = try PluginDescriptor.parse("name: Sample\nmain: eu.example.Sample\nversion: 1.0.0\n")
        let wrong = try PluginDescriptor.parse("name: Other\nmain: eu.example.Other\nversion: 2.0.0\n")
        XCTAssertThrowsError(try old.validateUpdate(wrong))
        let mod = try ModArchive.parse(["fabric.mod.json": #"{"id":"sample","name":"Sample","version":"1.0.0","environment":"client"}"#])
        XCTAssertEqual(mod.environment, "client")
        XCTAssertThrowsError(try PluginArchive.descriptor(Data("not a jar".utf8)))
    }
    func testConfigurationPreservesComments() throws {
        let text = "# Keep this\nmax-players=20\nonline-mode=true\n"
        let fields = ConfigurationField.parse(text, properties: true)
        let players = try XCTUnwrap(fields.first { $0.key == "max-players" })
        XCTAssertEqual(try players.replacement("30"), "max-players=30")
        XCTAssertThrowsError(try players.replacement("many"))
    }
    @MainActor func testClientKeyAndDemoSafety() async throws {
        let suite = "wing-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, launchDemo: false)
        do { try await store.add(name: "Test", address: "https://example.com", key: "ptla_do_not_send"); XCTFail("Application key accepted") } catch { XCTAssertTrue(store.profiles.isEmpty) }
        let api = PanelAPI(base: URL(string: "https://example.com")!, key: "", demo: true)
        do { try await api.mutate("servers/demo/power", ["signal":"stop"]); XCTFail("Demo mutation accepted") } catch {}
    }
}

private final class OfflineFixture: URLProtocol {
    static var state = "offline"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"attributes\":{\"current_state\":\"\(Self.state)\"}}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension CommunityTests {
    @MainActor func testOfflineGateReadsStandardEnvelope() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = PanelAPI(base: URL(string: "https://fixture.example")!, key: "ptlc_test", session: session)
        OfflineFixture.state = "offline"
        try await ModInstaller.stopped(api, server: "abc")
        OfflineFixture.state = "running"
        do { try await ModInstaller.stopped(api, server: "abc"); XCTFail("Running server accepted") } catch {}
    }
}
