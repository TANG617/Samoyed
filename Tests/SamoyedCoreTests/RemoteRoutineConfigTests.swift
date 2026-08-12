import XCTest
@testable import SamoyedCore

final class RemoteRoutineConfigTests: XCTestCase {
    func testLoaderAcceptsHTTPSAndReturnsUTF8YAML() async throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/workday.yml"))
        let finalURL = try XCTUnwrap(URL(string: "https://cdn.example.com/workday.yml"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: finalURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/yaml"]
            )
        )
        let expectedYAML = "version: 1\nkind: day_blocks\n"
        let loader = SamoyedRemoteRoutineConfigLoader { request in
            XCTAssertEqual(request.url, remoteURL)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertFalse(request.httpShouldHandleCookies)
            return (Data(expectedYAML.utf8), response)
        }

        let loadedConfig = try await loader.load(from: remoteURL)

        XCTAssertEqual(loadedConfig.yaml, expectedYAML)
        XCTAssertEqual(loadedConfig.sourceURL, finalURL)
    }

    func testLoaderRejectsPublicHTTP() throws {
        let remoteURL = try XCTUnwrap(URL(string: "http://example.com/workday.yml"))

        XCTAssertThrowsError(try SamoyedRemoteRoutineConfigLoader.validate(remoteURL)) { error in
            XCTAssertEqual(error as? RemoteRoutineConfigError, .insecureTransport)
        }
    }

    #if DEBUG
    func testLoaderAllowsLocalhostHTTPInDebugBuilds() throws {
        let remoteURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/workday.yml"))

        XCTAssertNoThrow(try SamoyedRemoteRoutineConfigLoader.validate(remoteURL))
    }
    #else
    func testLoaderRejectsLocalhostHTTPInReleaseBuilds() throws {
        let remoteURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/workday.yml"))

        XCTAssertThrowsError(try SamoyedRemoteRoutineConfigLoader.validate(remoteURL)) { error in
            XCTAssertEqual(error as? RemoteRoutineConfigError, .insecureTransport)
        }
    }
    #endif

    func testLoaderRejectsEmbeddedCredentials() throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://user:secret@example.com/workday.yml"))

        XCTAssertThrowsError(try SamoyedRemoteRoutineConfigLoader.validate(remoteURL)) { error in
            XCTAssertEqual(error as? RemoteRoutineConfigError, .embeddedCredentials)
        }
    }

    func testLoaderRejectsUnsuccessfulResponse() async throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/missing.yml"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: remoteURL,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )
        )
        let loader = SamoyedRemoteRoutineConfigLoader { _ in
            (Data(), response)
        }

        do {
            _ = try await loader.load(from: remoteURL)
            XCTFail("Expected an HTTP status error.")
        } catch {
            XCTAssertEqual(error as? RemoteRoutineConfigError, .unsuccessfulStatus(404))
        }
    }

    func testLoaderRejectsOversizedResponse() async throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/large.yml"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: remoteURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )
        )
        let loader = SamoyedRemoteRoutineConfigLoader(maximumBytes: 4) { _ in
            (Data("12345".utf8), response)
        }

        do {
            _ = try await loader.load(from: remoteURL)
            XCTFail("Expected a response size error.")
        } catch {
            XCTAssertEqual(
                error as? RemoteRoutineConfigError,
                .responseTooLarge(maximumBytes: 4)
            )
        }
    }
}
