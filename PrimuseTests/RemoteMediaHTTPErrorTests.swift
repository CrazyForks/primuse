import Foundation
import XCTest
@testable import Primuse

final class RemoteMediaHTTPErrorTests: XCTestCase {
    func testRetryAfterParsesWholeSecondsWithoutClampingServerDelay() throws {
        for (header, expected) in [("120", 120.0), (" 0 ", 0.0), ("3600", 3600.0)] {
            XCTAssertEqual(
                RemoteMediaHTTPError.retryDelay(from: try response(retryAfter: header)),
                expected
            )
        }
    }

    func testRetryAfterParsesHTTPDatesAgainstProvidedTime() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "1994-11-06T08:49:37Z"))
        for header in [
            "Sun, 06 Nov 1994 08:51:37 GMT",
            "Sunday, 06-Nov-94 08:51:37 GMT",
            "Sun Nov  6 08:51:37 1994"
        ] {
            XCTAssertEqual(
                RemoteMediaHTTPError.retryDelay(from: try response(retryAfter: header), now: now),
                120,
                header
            )
        }
    }

    func testPastRetryAfterDateDoesNotCreateNegativeDelay() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "1994-11-06T08:51:37Z"))
        XCTAssertEqual(
            RemoteMediaHTTPError.retryDelay(
                from: try response(retryAfter: "Sun, 06 Nov 1994 08:49:37 GMT"),
                now: now
            ),
            0
        )
    }

    func testMissingOrMalformedRetryAfterDoesNotInventDelay() throws {
        XCTAssertNil(RemoteMediaHTTPError.retryDelay(from: try response()))
        for header in ["", " ", "-1", "1.5", "1e2", "NaN", "Infinity", "later", "Sun, 40 Nov 1994 08:49:37 GMT"] {
            XCTAssertNil(RemoteMediaHTTPError.retryDelay(from: try response(retryAfter: header)), header)
        }
    }

    func testWebDAVHTTPFailuresPreserveStatusBeforeInspectingHTML() async throws {
        let source = makeWebDAV()
        for status in [401, 403, 404, 429, 503] {
            do {
                _ = try await source.validateStrictRangeResponse(
                    response(status: status, retryAfter: "17", contentType: "text/html"),
                    data: Data("<html>Request failed</html>".utf8),
                    path: "/song.flac",
                    offset: 0,
                    length: 4
                )
                XCTFail("HTTP \(status) must fail before its body can be treated as audio")
            } catch let error as RemoteMediaHTTPError {
                XCTAssertEqual(error.statusCode, status)
                XCTAssertEqual(error.retryAfter, 17)
                XCTAssertEqual(error.service, "WebDAV")
            } catch {
                XCTFail("HTTP \(status) was hidden by a different error: \(error)")
            }
        }
    }

    func testWebDAVSuccessfulStatusStillRejectsLoginPageAndIgnoredRange() async throws {
        let source = makeWebDAV()
        let cases: [(Int, String, Data, Int64)] = [
            (200, "text/html", Data("<html>Log in</html>".utf8), 0),
            (206, "text/html", Data("<html>Log in</html>".utf8), 0),
            (200, "audio/flac", Data([0xFF, 0xFA, 0x00, 0x01]), 4)
        ]
        for (status, contentType, data, offset) in cases {
            do {
                _ = try await source.validateStrictRangeResponse(
                    response(status: status, contentType: contentType),
                    data: data,
                    path: "/song.flac",
                    offset: offset,
                    length: 4
                )
                XCTFail("An HTTP success status must not bypass media and Range validation")
            } catch {
                XCTAssertTrue(error is SourceError, "Unexpected error: \(error)")
                XCTAssertFalse(error is RemoteMediaHTTPError)
            }
        }
    }

    func testWebDAVExactRangeStillReturnsAudio() async throws {
        let source = makeWebDAV()
        let data = Data([0xFF, 0xFA, 0x00, 0x01])
        let http = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://media-errors.invalid/song.flac")!,
            statusCode: 206,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "audio/flac",
                "Content-Range": "bytes 0-3/8",
                "Content-Length": "4"
            ]
        ))
        let result = try await source.validateStrictRangeResponse(
            http,
            data: data,
            path: "/song.flac",
            offset: 0,
            length: 4
        )
        XCTAssertEqual(result, data)
    }

    private func response(
        status: Int = 503,
        retryAfter: String? = nil,
        contentType: String = "audio/flac"
    ) throws -> HTTPURLResponse {
        var headers = ["Content-Type": contentType]
        headers["Retry-After"] = retryAfter
        return try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://media-errors.invalid/song.flac")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeWebDAV() -> WebDAVSource {
        let sourceID = "media-http-errors-\(UUID().uuidString)"
        let source = WebDAVSource(
            sourceID: sourceID,
            host: "media-errors.invalid",
            useSsl: true,
            username: "",
            password: ""
        )
        addTeardownBlock {
            await source.disconnect()
            let cache = FileManager.default.temporaryDirectory
                .appendingPathComponent("primuse_webdav_cache")
                .appendingPathComponent(sourceID)
            try? FileManager.default.removeItem(at: cache)
        }
        return source
    }
}
