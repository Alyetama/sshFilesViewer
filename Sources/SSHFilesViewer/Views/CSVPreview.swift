import SwiftUI

// MARK: - Parsed CSV model

struct CSVData {
    let columns: [String]   // header row, normalized to columnCount
    let rows: [[String]]    // data rows, normalized to columnCount
    let maxLengths: [Int]   // per-column max character length (incl. header)
    let truncated: Bool     // row cap was hit

    var columnCount: Int { maxLengths.count }
    var isEmpty: Bool { columns.isEmpty && rows.isEmpty }
}

// MARK: - RFC 4180-ish CSV parser

enum CSVParser {
    /// Parses delimited text. Handles quoted fields, escaped quotes (`""`),
    /// embedded delimiters/newlines, and CRLF. Caps rows/columns for previews.
    static func parse(_ text: String, delimiter: Character, maxRows: Int, maxColumns: Int = 200) -> CSVData {
        // Scan over Unicode scalars (not Characters) so CR and LF stay distinct —
        // Swift would otherwise bond "\r\n" into a single grapheme cluster.
        let scalars = Array(text.unicodeScalars)
        let n = scalars.count
        let delim = delimiter.unicodeScalars.first ?? ","
        let quote: Unicode.Scalar = "\""
        let lf: Unicode.Scalar = "\n"
        let cr: Unicode.Scalar = "\r"

        var records: [[String]] = []
        var field = String.UnicodeScalarView()
        var record: [String] = []
        var inQuotes = false
        var truncated = false
        let maxRecords = maxRows + 1 // + header
        var i = 0

        func endField() { record.append(String(field)); field = String.UnicodeScalarView() }
        func endRecord() { endField(); records.append(record); record = [] }

        loop: while i < n {
            let c = scalars[i]
            if inQuotes {
                if c == quote {
                    if i + 1 < n, scalars[i + 1] == quote { field.append(quote); i += 2 }
                    else { inQuotes = false; i += 1 }
                } else {
                    field.append(c); i += 1
                }
            } else {
                if c == quote {
                    inQuotes = true; i += 1
                } else if c == delim {
                    endField(); i += 1
                } else if c == lf {
                    endRecord(); i += 1
                    if records.count >= maxRecords { truncated = true; break loop }
                } else if c == cr {
                    i += 1 // skip CR (handles CRLF and bare CR)
                } else {
                    field.append(c); i += 1
                }
            }
        }
        if !truncated, !field.isEmpty || !record.isEmpty { endRecord() }

        guard !records.isEmpty else {
            return CSVData(columns: [], rows: [], maxLengths: [], truncated: false)
        }

        var columnCount = min(records.reduce(0) { max($0, $1.count) }, maxColumns)
        if columnCount == 0 { columnCount = 1 }

        func normalize(_ row: [String]) -> [String] {
            var r = row
            if r.count > columnCount { r = Array(r.prefix(columnCount)) }
            else if r.count < columnCount { r.append(contentsOf: Array(repeating: "", count: columnCount - r.count)) }
            return r
        }

        let header = normalize(records[0])
        var maxLengths = header.map(\.count)
        var dataRows: [[String]] = []
        dataRows.reserveCapacity(records.count - 1)
        for raw in records.dropFirst() {
            let row = normalize(raw)
            for j in 0..<columnCount { maxLengths[j] = max(maxLengths[j], row[j].count) }
            dataRows.append(row)
        }

        return CSVData(columns: header, rows: dataRows, maxLengths: maxLengths, truncated: truncated)
    }
}

// MARK: - Spreadsheet-style table view

struct CSVTableView: View {
    let data: CSVData
    let theme: HighlightTheme
    let fontSize: Double

    private var charWidth: CGFloat { CGFloat(fontSize) * 0.62 }
    private var rowHeight: CGFloat { CGFloat(fontSize) + 13 }

    private var columnWidths: [CGFloat] {
        data.maxLengths.map { length in
            min(max(CGFloat(length) * charWidth + 18, 56), 360)
        }
    }

    private var gutterWidth: CGFloat {
        let digits = max(2, String(max(data.rows.count, 1)).count)
        return CGFloat(digits) * charWidth + 20
    }

    var body: some View {
        let widths = columnWidths
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(data.rows.indices, id: \.self) { r in
                            row(data.rows[r], number: r + 1, zebra: r % 2 == 1,
                                widths: widths, minWidth: geo.size.width)
                        }
                    } header: {
                        headerRow(widths: widths, minWidth: geo.size.width)
                    }
                }
            }
        }
        .background(theme.bg)
    }

    private func headerRow(widths: [CGFloat], minWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            cell("#", width: gutterWidth, header: true, alignment: .center)
            ForEach(data.columns.indices, id: \.self) { j in
                cell(data.columns[j].isEmpty ? "—" : data.columns[j],
                     width: widths[j], header: true)
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .background(
            ZStack {
                theme.bg
                theme.fg.opacity(0.10)
            }
        )
        .overlay(Rectangle().fill(theme.fg.opacity(0.22)).frame(height: 1), alignment: .bottom)
    }

    private func row(_ cells: [String], number: Int, zebra: Bool, widths: [CGFloat], minWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            cell("\(number)", width: gutterWidth, header: false, gutter: true, alignment: .trailing)
            ForEach(0..<widths.count, id: \.self) { j in
                cell(j < cells.count ? cells[j] : "", width: widths[j], header: false)
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .background(zebra ? theme.fg.opacity(0.04) : Color.clear)
        .overlay(Rectangle().fill(theme.fg.opacity(0.07)).frame(height: 1), alignment: .bottom)
    }

    private func cell(_ text: String, width: CGFloat, header: Bool,
                      gutter: Bool = false, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: header ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(color(header: header, gutter: gutter))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9)
            .frame(width: width, height: rowHeight, alignment: alignment)
            .overlay(Rectangle().fill(theme.fg.opacity(0.07)).frame(width: 1), alignment: .trailing)
    }

    private func color(header: Bool, gutter: Bool) -> Color {
        if header { return theme.fg }
        if gutter { return theme.commentColor }
        return theme.fg.opacity(0.9)
    }
}
