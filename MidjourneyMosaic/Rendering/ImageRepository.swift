import AppKit
import Foundation

actor ImageDataRepository {
    static let shared = ImageDataRepository()

    private struct CacheMetadata: Codable, Sendable {
        var refreshedAt: Date
        var eTag: String?
        var lastModified: String?
    }

    private struct CacheEntry: Sendable {
        let data: Data
        var metadata: CacheMetadata
    }

    private var memoryCache: [URL: CacheEntry] = [:]
    private var inFlight: [URL: Task<CacheEntry, Error>] = [:]
    private let cacheDirectory: URL
    private let session: URLSession

    init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = root
            .appendingPathComponent("com.zats.screensavers.midjourney-mosaic", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        if let existing = inFlight[url] {
            return try await existing.value.data
        }

        let cached = memoryCache[url] ?? diskEntry(for: url)
        if let cached,
           Date().timeIntervalSince(cached.metadata.refreshedAt) < MosaicLimits.imageCacheLifetime {
            memoryCache[url] = cached
            return cached.data
        }

        let task = Task<CacheEntry, Error> {
            try await refreshedEntry(for: url, staleEntry: cached)
        }
        inFlight[url] = task

        do {
            let entry = try await task.value
            memoryCache[url] = entry
            inFlight[url] = nil
            return entry.data
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    private func refreshedEntry(for url: URL, staleEntry: CacheEntry?) async throws -> CacheEntry {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("MidjourneyMosaic/0.1", forHTTPHeaderField: "User-Agent")
        if let eTag = staleEntry?.metadata.eTag {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = staleEntry?.metadata.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if http.statusCode == 304, var staleEntry {
                staleEntry.metadata.refreshedAt = Date()
                try persist(staleEntry, for: url)
                return staleEntry
            }

            guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                throw URLError(.badServerResponse)
            }

            let entry = CacheEntry(
                data: data,
                metadata: CacheMetadata(
                    refreshedAt: Date(),
                    eTag: http.value(forHTTPHeaderField: "ETag"),
                    lastModified: http.value(forHTTPHeaderField: "Last-Modified")
                )
            )
            try persist(entry, for: url)
            return entry
        } catch {
            // Once an image has rendered successfully, network or CDN failures never
            // blank it. The stale copy remains authoritative until revalidation works.
            if let staleEntry { return staleEntry }
            throw error
        }
    }

    private func diskEntry(for url: URL) -> CacheEntry? {
        let paths = cachePaths(for: url)
        guard let data = try? Data(contentsOf: paths.data),
              let metadataData = try? Data(contentsOf: paths.metadata),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData) else {
            return nil
        }
        return CacheEntry(data: data, metadata: metadata)
    }

    private func persist(_ entry: CacheEntry, for url: URL) throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        let paths = cachePaths(for: url)
        try entry.data.write(to: paths.data, options: .atomic)
        let metadataData = try JSONEncoder().encode(entry.metadata)
        try metadataData.write(to: paths.metadata, options: .atomic)
    }

    private func cachePaths(for url: URL) -> (data: URL, metadata: URL) {
        let jobID = url.deletingLastPathComponent().lastPathComponent
        let imageName = url.lastPathComponent
        let stem = "\(jobID)-\(imageName)"
        return (
            cacheDirectory.appendingPathComponent(stem),
            cacheDirectory.appendingPathComponent(stem + ".json")
        )
    }
}

@MainActor
enum ImageDecoder {
    static func cgImage(from data: Data) -> CGImage? {
        guard let image = NSImage(data: data) else { return nil }
        var proposed = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: [.interpolation: NSImageInterpolation.high])
    }
}
