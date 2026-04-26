import Foundation
import ZIPFoundation

final class ZipExtractor {
    static func unzip(url: URL, to destinationURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }
        
        // Use ZIPFoundation to extract the entire archive
        try fileManager.unzipItem(at: url, to: destinationURL)
        
        // Return all extracted files recursively (to find files in subfolders like CPSC_Enrollment_2026_01/)
        var allFiles: [URL] = []
        if let enumerator = fileManager.enumerator(at: destinationURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile ?? false {
                    allFiles.append(fileURL)
                }
            }
        }
        return allFiles
    }
}
