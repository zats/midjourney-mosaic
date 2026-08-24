import Foundation

struct MidjourneyItem: Hashable, Identifiable, Sendable {
    let id: String
    let index: Int
    let aspectRatio: Double

    var imageURL: URL {
        URL(string: "https://cdn.midjourney.com/\(id)/0_\(index)_640_N.webp?method=shortest")!
    }
}

enum ArtworkShape: Int, CaseIterable, Hashable, Sendable {
    case portrait
    case square
    case landscape

    init(aspectRatio: Double) {
        if aspectRatio < 0.85 {
            self = .portrait
        } else if aspectRatio <= 1.15 {
            self = .square
        } else {
            self = .landscape
        }
    }
}

extension MidjourneyItem {
    var shape: ArtworkShape { ArtworkShape(aspectRatio: aspectRatio) }
}

enum AspectMixing {
    static func diversified(_ items: [MidjourneyItem]) -> [MidjourneyItem] {
        let buckets = ArtworkShape.allCases.map { shape in
            items.filter { $0.shape == shape }
        }
        var offsets = Array(repeating: 0, count: buckets.count)
        var result: [MidjourneyItem] = []

        // Round-robin exhausts scarce shapes gradually. With the current fixture,
        // prefixes stay P/S/L-balanced until the two landscapes run out, then P/S
        // stay balanced until the thirteen squares run out.
        while result.count < items.count {
            for shape in ArtworkShape.allCases {
                let bucketIndex = shape.rawValue
                guard offsets[bucketIndex] < buckets[bucketIndex].count else { continue }
                result.append(buckets[bucketIndex][offsets[bucketIndex]])
                offsets[bucketIndex] += 1
            }
        }
        return result
    }

    static func nextReplacementIndex(
        in items: [MidjourneyItem],
        excluding visibleIndices: Set<Int>,
        matching shape: ArtworkShape,
        startingAt startIndex: Int
    ) -> Int? {
        guard !items.isEmpty else { return nil }
        for offset in items.indices {
            let index = (startIndex + offset) % items.count
            if !visibleIndices.contains(index), items[index].shape == shape {
                return index
            }
        }
        return nil
    }
}

protocol ImageFeedSource {
    func items() -> [MidjourneyItem]
}

@MainActor
enum StaticExploreSource {
    private static var cachedItems: [MidjourneyItem]?
    private final class ResourceBundleMarker {}

    static func load() -> [MidjourneyItem] {
        if let cachedItems { return cachedItems }

        let resourceBundle = Bundle(for: ResourceBundleMarker.self)
        guard let url = resourceBundle.url(forResource: "explore-top", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        let parsed = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> MidjourneyItem? in
                let fields = line.split(separator: "\t")
                guard fields.count == 3,
                      let index = Int(fields[1]),
                      let aspect = Double(fields[2]) else { return nil }
                return MidjourneyItem(id: String(fields[0]), index: index, aspectRatio: aspect)
            }

        let diversified = AspectMixing.diversified(parsed)
        cachedItems = diversified
        return diversified
    }
}
