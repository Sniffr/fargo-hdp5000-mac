import Foundation

/// Rows from a spreadsheet (CSV) used to fill {{Column}} placeholders, one card per row.
struct BatchData: Equatable {
    var columns: [String] = []
    var rows: [[String: String]] = []
    var fileName = ""

    /// Folder of the loaded CSV; relative photo paths are resolved against it.
    nonisolated(unsafe) static var baseURL: URL? = nil

    static func load(_ url: URL) throws -> BatchData {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let table = parseCSV(raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw)
        guard let header = table.first else { return BatchData() }
        let cols = header.map { $0.trimmingCharacters(in: .whitespaces) }
        let rows = table.dropFirst().filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }.map { r in
            Dictionary(uniqueKeysWithValues: cols.enumerated().map { ($0.element, $0.offset < r.count ? r[$0.offset].trimmingCharacters(in: .whitespaces) : "") })
        }
        baseURL = url.deletingLastPathComponent()
        return BatchData(columns: cols, rows: rows, fileName: url.lastPathComponent)
    }

    /// RFC 4180 CSV (quoted fields, doubled quotes, newlines inside quotes); also accepts ; or tab separators.
    static func parseCSV(_ s: String) -> [[String]] {
        let firstLine = s.prefix { $0 != "\n" && $0 != "\r" }
        let sep: Character = [",", ";", "\t"].max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ","
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        var it = Array(s), i = 0
        while i < it.count {
            let c = it[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < it.count && it[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" { inQuotes = true }
            else if c == sep { row.append(field); field = "" }
            else if c == "\n" || c == "\r" || c == "\r\n" {
                if c == "\r", i + 1 < it.count, it[i + 1] == "\n" { i += 1 }
                row.append(field); rows.append(row); row = []; field = ""
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        it.removeAll()
        return rows
    }
}
