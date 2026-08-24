import CoreGraphics

struct MosaicPlacement: Equatable {
    let itemIndex: Int
    let frame: CGRect
}

/// Builds an edge-to-edge waterfall without forcing the images into horizontal bands.
///
/// Every candidate column is first sized at the source images' natural aspect ratios.
/// One shared scale is then applied to all column widths, so the entire viewport is
/// covered while every image receives the same, minimal aspect-fill crop.
enum WaterfallMosaicLayout {
    private struct Candidate {
        let columns: [[Int]]
        let naturalWidths: [CGFloat]
        let widthScale: CGFloat
        let score: CGFloat
    }

    static func placements(
        aspectRatios: [CGFloat],
        in bounds: CGRect,
        gap: CGFloat = 2
    ) -> [MosaicPlacement] {
        guard !aspectRatios.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }

        let ratios = aspectRatios.map { min(max($0, 0.35), 3.0) }
        let maximumColumns = min(ratios.count, 14)
        var best: Candidate?

        for columnCount in 1...maximumColumns {
            guard let candidate = makeCandidate(
                ratios: ratios,
                columnCount: columnCount,
                bounds: bounds,
                gap: gap
            ) else { continue }

            if best == nil || candidate.score < best!.score {
                best = candidate
            }
        }

        guard let best else { return [] }

        var x = bounds.minX
        var placements: [MosaicPlacement] = []

        for columnIndex in best.columns.indices {
            let column = variedOrder(best.columns[columnIndex], ratios: ratios, columnIndex: columnIndex)
            let width: CGFloat
            if columnIndex == best.columns.count - 1 {
                width = max(1, bounds.maxX - x)
            } else {
                width = max(1, best.naturalWidths[columnIndex] * best.widthScale)
            }

            let usableHeight = max(1, bounds.height - gap * CGFloat(column.count - 1))
            let inverseTotal = column.reduce(CGFloat.zero) { $0 + 1 / ratios[$1] }
            var top = bounds.maxY

            for itemOffset in column.indices {
                let itemIndex = column[itemOffset]
                let height: CGFloat
                if itemOffset == column.count - 1 {
                    height = max(1, top - bounds.minY)
                } else {
                    height = max(1, usableHeight * (1 / ratios[itemIndex]) / inverseTotal)
                }

                let y = top - height
                placements.append(
                    MosaicPlacement(
                        itemIndex: itemIndex,
                        frame: CGRect(x: x, y: y, width: width, height: height)
                    )
                )
                top = y - gap
            }

            x += width + gap
        }

        return placements.sorted { $0.itemIndex < $1.itemIndex }
    }

    private static func makeCandidate(
        ratios: [CGFloat],
        columnCount: Int,
        bounds: CGRect,
        gap: CGFloat
    ) -> Candidate? {
        let columns = balancedColumns(ratios: ratios, count: columnCount)
        guard columns.allSatisfy({ !$0.isEmpty }) else { return nil }

        let naturalWidths = columns.map { column -> CGFloat in
            let usableHeight = max(1, bounds.height - gap * CGFloat(column.count - 1))
            let inverseTotal = column.reduce(CGFloat.zero) { $0 + 1 / ratios[$1] }
            return usableHeight / max(0.001, inverseTotal)
        }
        let availableWidth = max(1, bounds.width - gap * CGFloat(columnCount - 1))
        let naturalWidthTotal = naturalWidths.reduce(0, +)
        guard naturalWidthTotal > 0 else { return nil }

        let widthScale = availableWidth / naturalWidthTotal
        let meanWidth = availableWidth / CGFloat(columnCount)
        let variance = naturalWidths.reduce(CGFloat.zero) {
            let finalWidth = $1 * widthScale
            return $0 + pow((finalWidth - meanWidth) / max(1, meanWidth), 2)
        } / CGFloat(columnCount)
        let singletonCount = columns.filter { $0.count == 1 }.count
        let narrowest = naturalWidths.min()! * widthScale
        let narrowPenalty = max(0, (72 - narrowest) / 72)

        // The crop term dominates. The remaining terms avoid awkward sliver columns
        // when two column counts offer nearly equivalent source-aspect preservation.
        let score = abs(log(max(0.001, widthScale))) * 100
            + sqrt(variance) * 5
            + CGFloat(singletonCount) * 2
            + narrowPenalty * 20

        return Candidate(
            columns: columns,
            naturalWidths: naturalWidths,
            widthScale: widthScale,
            score: score
        )
    }

    private static func balancedColumns(ratios: [CGFloat], count: Int) -> [[Int]] {
        var columns = Array(repeating: [Int](), count: count)
        var loads = Array(repeating: CGFloat.zero, count: count)

        // Tall images contribute the most height, so placing them first produces
        // balanced columns while retaining a varied mix of portrait and square art.
        let orderedIndices = ratios.indices.sorted {
            let lhs = 1 / ratios[$0]
            let rhs = 1 / ratios[$1]
            return lhs == rhs ? $0 < $1 : lhs > rhs
        }

        for itemIndex in orderedIndices {
            let columnIndex = loads.indices.min {
                loads[$0] == loads[$1] ? $0 < $1 : loads[$0] < loads[$1]
            }!
            columns[columnIndex].append(itemIndex)
            loads[columnIndex] += 1 / ratios[itemIndex]
        }

        return columns
    }

    private static func variedOrder(
        _ column: [Int],
        ratios: [CGFloat],
        columnIndex: Int
    ) -> [Int] {
        guard column.count > 1 else { return column }
        var ordered = column.sorted {
            ratios[$0] == ratios[$1] ? $0 < $1 : ratios[$0] < ratios[$1]
        }
        if columnIndex.isMultiple(of: 2) {
            ordered.reverse()
        }
        let rotation = columnIndex % ordered.count
        return Array(ordered[rotation...] + ordered[..<rotation])
    }
}
