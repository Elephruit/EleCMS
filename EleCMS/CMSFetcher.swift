import Foundation

struct CMSDownloadTask {
    let url: URL
    let type: FileType
    let year: Int
    let month: Int?
    
    enum FileType {
        case cpscEnrollment
        case cpscContractInfo
        case landscape
    }
}

final class CMSFetcher {
    private let session = URLSession.shared
    
    func scrapeCPSCPage() async throws -> [CMSDownloadTask] {
        // Try multiple landing pages as CMS often moves these
        let pages = [
            "https://www.cms.gov/medicare/enrollment-renewal/health-plans/medicare-advantage-part-d-contract-enrollment-data",
            "https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-advantagepart-d-contract-and-enrollment-data/monthly-enrollment-contract/plan/state/county"
        ]
        
        var allTasks: [CMSDownloadTask] = []
        
        for pageURL in pages {
            guard let url = URL(string: pageURL) else { continue }
            do {
                let (data, _) = try await session.data(from: url)
                guard let html = String(data: data, encoding: .utf8) else { continue }
                
                // Be very aggressive with regex
                let patterns = [
                    #"(/files/zip/monthly-enrollment-cpsc-(\d{4})-(\d{2})\.zip)"#,
                    #"(/files/zip/monthly_enrollment_cpsc_(\d{4})_(\d{2})\.zip)"#,
                    #"(/files/zip/CPSC_Enrollment_(\d{4})_(\d{2})\.zip)"#
                ]
                
                for pattern in patterns {
                    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                    let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
                    
                    for match in matches {
                        if let zipRange = Range(match.range(at: 1), in: html),
                           let yearRange = Range(match.range(at: 2), in: html),
                           let monthRange = Range(match.range(at: 3), in: html),
                           let year = Int(html[yearRange]),
                           let month = Int(html[monthRange]) {
                            let zipPath = String(html[zipRange])
                            let zipURL = zipPath.hasPrefix("http") ? URL(string: zipPath)! : URL(string: "https://www.cms.gov" + zipPath)!
                            allTasks.append(CMSDownloadTask(url: zipURL, type: .cpscEnrollment, year: year, month: month))
                        }
                    }
                }
            } catch {
                print("DEBUG: Scraper failed for \(pageURL): \(error)")
            }
        }
        return allTasks
    }
    
    func scrapeLandscapePage() async throws -> [CMSDownloadTask] {
        let url = URL(string: "https://www.cms.gov/medicare/coverage/prescription-drug-coverage")!
        let (data, _) = try await session.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        
        let patterns = [
            #"(/files/zip/cy(\d{4})-landscape-files-(\d+)\.zip)"#,
            #"(/files/zip/cy(\d{4})-landscape-files\.zip)"#
        ]
        
        var tasks: [CMSDownloadTask] = []
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
            
            for match in matches {
                if let zipRange = Range(match.range(at: 1), in: html),
                   let yearRange = Range(match.range(at: 2), in: html),
                   let year = Int(html[yearRange]) {
                    let zipPath = String(html[zipRange])
                    let zipURL = zipPath.hasPrefix("http") ? URL(string: zipPath)! : URL(string: "https://www.cms.gov" + zipPath)!
                    tasks.append(CMSDownloadTask(url: zipURL, type: .landscape, year: year, month: nil))
                }
            }
        }
        return tasks
    }
    
    func download(task: CMSDownloadTask) async throws -> URL {
        let (localURL, response) = try await session.download(from: task.url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("DEBUG: Download failed with status code: \(code) for URL: \(task.url)")
            throw NSError(domain: "CMSFetcher", code: code, userInfo: [NSLocalizedDescriptionKey: "File not found on CMS server (HTTP \(code)). This month's data might not be released yet."])
        }
        
        // Move to a permanent location in tmp because download(from:) deletes it immediately after the block
        let permanentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try? FileManager.default.removeItem(at: permanentURL)
        try FileManager.default.moveItem(at: localURL, to: permanentURL)
        
        return permanentURL
    }
    
    func unzip(url: URL) throws -> [URL] {
        let destinationURL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: ".zip", with: ""))
        try? FileManager.default.removeItem(at: destinationURL)
        return try ZipExtractor.unzip(url: url, to: destinationURL)
    }
}
