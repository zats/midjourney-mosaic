import CoreGraphics
import XCTest
@testable import MidjourneyMosaic

final class MosaicLayoutTests: XCTestCase {
    private let aspects: [CGFloat] = [0.56, 1, 0.67, 1.5, 0.75, 1, 0.5, 1.33, 0.8, 1, 0.56, 1.5]

    func testEveryItemIsPlacedInsideLandscapeBounds() {
        assertValidLayout(size: CGSize(width: 1440, height: 900), minimumColumns: 3)
    }

    func testEveryItemIsPlacedInsidePortraitBounds() {
        assertValidLayout(size: CGSize(width: 900, height: 1440), minimumColumns: 2)
    }

    func testEveryItemIsPlacedInsideUltrawideBounds() {
        assertValidLayout(size: CGSize(width: 2560, height: 720), minimumColumns: 5)
    }

    func testMixedShapesProduceVariedWaterfallHeights() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let placements = WaterfallMosaicLayout.placements(aspectRatios: aspects, in: bounds)
        let uniqueHeights = Set(placements.map { Int($0.frame.height.rounded()) })

        XCTAssertGreaterThanOrEqual(uniqueHeights.count, 4)
    }

    func testDenseNinetySixItemLayoutStillFillsViewport() {
        let denseAspects = (0..<96).map { aspects[$0 % aspects.count] }
        let bounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let placements = WaterfallMosaicLayout.placements(aspectRatios: denseAspects, in: bounds)

        XCTAssertEqual(placements.count, denseAspects.count)
        XCTAssertEqual(Set(placements.map(\.itemIndex)).count, denseAspects.count)
        XCTAssertTrue(placements.allSatisfy { bounds.contains($0.frame) })
    }

    private func assertValidLayout(
        size: CGSize,
        minimumColumns: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bounds = CGRect(origin: .zero, size: size)
        let gap: CGFloat = 2
        let placements = WaterfallMosaicLayout.placements(aspectRatios: aspects, in: bounds, gap: gap)

        XCTAssertEqual(placements.count, aspects.count, file: file, line: line)
        XCTAssertEqual(Set(placements.map(\.itemIndex)).count, aspects.count, file: file, line: line)
        for placement in placements {
            XCTAssertGreaterThan(placement.frame.width, 0, file: file, line: line)
            XCTAssertGreaterThan(placement.frame.height, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(placement.frame.minX, bounds.minX - 0.001, file: file, line: line)
            XCTAssertGreaterThanOrEqual(placement.frame.minY, bounds.minY - 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(placement.frame.maxX, bounds.maxX + 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(placement.frame.maxY, bounds.maxY + 0.001, file: file, line: line)
        }

        for first in placements.indices {
            for second in placements.indices where second > first {
                let intersection = placements[first].frame.intersection(placements[second].frame)
                XCTAssertTrue(intersection.isNull || intersection.width < 0.001 || intersection.height < 0.001, file: file, line: line)
            }
        }

        let groupedColumns = Dictionary(grouping: placements) {
            Int(($0.frame.minX * 1_000).rounded())
        }
        let columns = groupedColumns.values
            .map { $0.sorted { $0.frame.minY < $1.frame.minY } }
            .sorted { $0[0].frame.minX < $1[0].frame.minX }

        XCTAssertGreaterThanOrEqual(columns.count, minimumColumns, file: file, line: line)
        XCTAssertEqual(columns[0][0].frame.minX, bounds.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(columns[columns.count - 1][0].frame.maxX, bounds.maxX, accuracy: 0.001, file: file, line: line)

        for column in columns {
            XCTAssertEqual(column[0].frame.minY, bounds.minY, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(column[column.count - 1].frame.maxY, bounds.maxY, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(Set(column.map { Int(($0.frame.width * 1_000).rounded()) }).count, 1, file: file, line: line)

            for index in 1..<column.count {
                XCTAssertEqual(
                    column[index].frame.minY - column[index - 1].frame.maxY,
                    gap,
                    accuracy: 0.001,
                    file: file,
                    line: line
                )
            }
        }

        for index in 1..<columns.count {
            XCTAssertEqual(
                columns[index][0].frame.minX - columns[index - 1][0].frame.maxX,
                gap,
                accuracy: 0.001,
                file: file,
                line: line
            )
        }

        let cropScales = placements.map {
            ($0.frame.width / $0.frame.height) / aspects[$0.itemIndex]
        }
        XCTAssertLessThan(
            cropScales.max()! - cropScales.min()!,
            0.02,
            "Every image should receive essentially the same crop adjustment",
            file: file,
            line: line
        )
    }
}

final class AspectMixingTests: XCTestCase {
    private let items: [MidjourneyItem] = {
        let aspects = Array(repeating: 0.65, count: 34)
            + Array(repeating: 1.0, count: 13)
            + Array(repeating: 1.5, count: 2)
        return aspects.enumerated().map {
            MidjourneyItem(id: "item-\($0.offset)", index: 0, aspectRatio: $0.element)
        }
    }()

    func testDiversifiedPrefixesStayBalancedUntilEachShapeIsExhausted() {
        let mixed = AspectMixing.diversified(items)
        let capacities = ArtworkShape.allCases.map { shape in
            items.filter { $0.shape == shape }.count
        }

        XCTAssertEqual(Set(mixed.map(\.id)), Set(items.map(\.id)))
        for prefixLength in 1...mixed.count {
            let prefix = mixed.prefix(prefixLength)
            let counts = ArtworkShape.allCases.map { shape in
                prefix.filter { $0.shape == shape }.count
            }
            let unfinishedCounts = ArtworkShape.allCases.compactMap { shape -> Int? in
                let index = shape.rawValue
                return counts[index] < capacities[index] ? counts[index] : nil
            }

            if let minimum = unfinishedCounts.min(), let maximum = unfinishedCounts.max() {
                XCTAssertLessThanOrEqual(maximum - minimum, 1, "Unexhausted shapes drifted at prefix \(prefixLength)")
            }
        }

        let firstTwentyFour = Array(mixed.prefix(24))
        XCTAssertEqual(firstTwentyFour.filter { $0.shape == .portrait }.count, 11)
        XCTAssertEqual(firstTwentyFour.filter { $0.shape == .square }.count, 11)
        XCTAssertEqual(firstTwentyFour.filter { $0.shape == .landscape }.count, 2)
    }

    func testLikeForLikeReplacementsPreserveVisibleMix() {
        let mixed = AspectMixing.diversified(items)
        var visible = Set(0..<24)
        var cursor = 24
        let originalCounts = shapeCounts(in: visible, items: mixed)

        for step in 0..<100 {
            let shape: ArtworkShape = step.isMultiple(of: 2) ? .portrait : .square
            let outgoing = visible.first { mixed[$0].shape == shape }!
            let replacement = AspectMixing.nextReplacementIndex(
                in: mixed,
                excluding: visible,
                matching: shape,
                startingAt: cursor
            )

            XCTAssertNotNil(replacement)
            visible.remove(outgoing)
            visible.insert(replacement!)
            cursor = (replacement! + 1) % mixed.count
            XCTAssertEqual(shapeCounts(in: visible, items: mixed), originalCounts)
        }

        XCTAssertNil(
            AspectMixing.nextReplacementIndex(
                in: mixed,
                excluding: visible,
                matching: .landscape,
                startingAt: cursor
            ),
            "Both landscape records are already visible, so they should remain pinned"
        )
    }

    func testExpandedInventorySupportsBalancedNinetySixItemViewport() {
        let aspects = Array(repeating: 0.65, count: 94)
            + Array(repeating: 1.0, count: 45)
            + Array(repeating: 1.5, count: 11)
        let expanded = aspects.enumerated().map {
            MidjourneyItem(id: "expanded-\($0.offset)", index: 0, aspectRatio: $0.element)
        }
        let firstNinetySix = AspectMixing.diversified(expanded).prefix(MosaicLimits.maximumItemCount)

        XCTAssertEqual(firstNinetySix.count, 96)
        XCTAssertEqual(firstNinetySix.filter { $0.shape == .portrait }.count, 43)
        XCTAssertEqual(firstNinetySix.filter { $0.shape == .square }.count, 42)
        XCTAssertEqual(firstNinetySix.filter { $0.shape == .landscape }.count, 11)
        XCTAssertEqual(expanded.count - firstNinetySix.count, 54)
    }

    private func shapeCounts(in indices: Set<Int>, items: [MidjourneyItem]) -> [Int] {
        ArtworkShape.allCases.map { shape in
            indices.filter { items[$0].shape == shape }.count
        }
    }
}
