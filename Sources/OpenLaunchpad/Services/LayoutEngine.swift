import Foundation

// MARK: - Layout Engine

/// Calculates grid layout parameters based on screen size, icon dimensions, and spacing.
/// Sequoia-style: 7 columns × 5 rows per page, icons 72–80pt with 24–32pt spacing.
enum LayoutEngine {

    // MARK: - Defaults

    static let defaultColumns = 7
    static let defaultRows = 5
    static let defaultIconSize: CGFloat = 80
    static let defaultRowSpacing: CGFloat = 32
    static let defaultColumnSpacing: CGFloat = 52

    // MARK: - Layout Result

    struct GridLayout {
        let columns: Int
        let rows: Int
        let iconSize: CGFloat
        let itemsPerPage: Int
        let pageCount: Int
        let rowSpacing: CGFloat
        let columnSpacing: CGFloat
        let gridWidth: CGFloat
        let gridHeight: CGFloat
    }

    // MARK: - Calculation

    /// Computes the grid layout for a given screen size and item count.
    /// Automatically scales down for smaller displays (e.g., MacBook 13").
    static func layout(
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        itemCount: Int,
        iconSize: CGFloat = defaultIconSize,
        rowSpacing: CGFloat = defaultRowSpacing,
        columnSpacing: CGFloat = defaultColumnSpacing
    ) -> GridLayout {
        let columns = defaultColumns
        let rows = defaultRows

        // Scale down for small screens (below ~950pt height = 13" MacBook)
        let isSmallScreen = screenHeight < 950
        let scaleFactor: CGFloat = isSmallScreen ? 0.75 : 1.0

        let scaledIconSize = iconSize * scaleFactor
        let scaledRowSpacing = rowSpacing * scaleFactor
        let scaledColumnSpacing = columnSpacing * scaleFactor

        let itemsPerPage = columns * rows
        let pageCount = max(1, Int(ceil(Double(itemCount) / Double(itemsPerPage))))

        let cellWidth = scaledIconSize + 20  // icon + label width
        let cellHeight = scaledIconSize + 40 // icon + label height

        let gridWidth = CGFloat(columns) * cellWidth + CGFloat(columns - 1) * scaledColumnSpacing
        let gridHeight = CGFloat(rows) * cellHeight + CGFloat(rows - 1) * scaledRowSpacing

        return GridLayout(
            columns: columns,
            rows: rows,
            iconSize: scaledIconSize,
            itemsPerPage: itemsPerPage,
            pageCount: pageCount,
            rowSpacing: scaledRowSpacing,
            columnSpacing: scaledColumnSpacing,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }

    /// Returns the items belonging to a specific page.
    static func itemsForPage(_ page: Int, items: [LaunchpadItem], layout: GridLayout) -> [LaunchpadItem] {
        let start = page * layout.itemsPerPage
        let end = min(start + layout.itemsPerPage, items.count)
        guard start < items.count else { return [] }
        return Array(items[start..<end])
    }
}
