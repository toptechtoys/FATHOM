@testable import FathomKit
import Foundation
import Testing

@Test
func publicIPParserAcceptsOnlyAnAddressAndISOCode() throws {
    let date = Date(timeIntervalSince1970: 1_000)
    let snapshot = try PublicIPService.parse(
        Data("ip=203.0.113.8\nloc=AE\ncolo=DXB\n".utf8),
        fetchedAt: date
    )
    #expect(snapshot.address == "203.0.113.8")
    #expect(snapshot.countryCode == "AE")
    #expect(snapshot.fetchedAt == date)

    #expect(throws: PublicIPServiceError.invalidResponse) {
        try PublicIPService.parse(Data("ip=not-an-ip\nloc=AE\n".utf8), fetchedAt: date)
    }
    #expect(throws: PublicIPServiceError.invalidResponse) {
        try PublicIPService.parse(Data("ip=203.0.113.8\nloc=Dubai\n".utf8), fetchedAt: date)
    }
}

@Test
func publicIPLookupIsDisabledWithoutCallingTheNetwork() async throws {
    let counter = PublicIPFetchCounter()
    let service = PublicIPService(
        cacheURL: temporaryPublicIPCache(),
        fetch: { request in
            await counter.record(request)
            return (Data(), 200)
        }
    )
    #expect(
        await service.read(enabled: false) ==
            .notPublished(reason: "Public IP lookup is disabled")
    )
    #expect(await counter.count == 0)
}

@Test
func publicIPCachePreventsASecondRequestForSixHours() async throws {
    let counter = PublicIPFetchCounter()
    let cacheURL = temporaryPublicIPCache()
    let service = PublicIPService(
        cacheURL: cacheURL,
        fetch: { request in
            await counter.record(request)
            return (Data("ip=2001:db8::8\nloc=US\n".utf8), 200)
        }
    )
    let firstDate = Date(timeIntervalSince1970: 10_000)
    let first = await service.read(enabled: true, now: firstDate)
    let cached = await service.read(
        enabled: true,
        now: firstDate.addingTimeInterval(PublicIPService.cacheLifetime - 1)
    )
    #expect(first == cached)
    #expect(await counter.count == 1)
    #expect(await counter.lastURL == PublicIPService.endpoint)
}

private actor PublicIPFetchCounter {
    private(set) var count = 0
    private(set) var lastURL: URL?

    func record(_ request: URLRequest) {
        count += 1
        lastURL = request.url
    }
}

private func temporaryPublicIPCache() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("public-ip.json")
}
