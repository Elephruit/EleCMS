import Foundation
import Combine
import SwiftUI

final class SyncService: ObservableObject {
    let dataStore: DataStore
    let fetcher = CMSFetcher()
    let ingestion: IngestionService
    
    @Published var status: String = "Ready"
    @Published var isSyncing: Bool = false
    
    private let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    
    init(dataStore: DataStore) {
        self.dataStore = dataStore
        self.ingestion = IngestionService(dataStore: dataStore)
    }
    
    func syncSpecific(year: Int, month: Int?) async {
        print("DEBUG: syncSpecific called for year: \(year), month: \(month ?? 0)")
        await MainActor.run {
            isSyncing = true
            status = "Scraping CMS for \(year)\(month != nil ? "-\(month!)" : "")..."
        }
        
        do {
            if let m = month {
                print("DEBUG: Handling Monthly CPSC sync")
                let tasks = try await fetcher.scrapeCPSCPage()
                
                var urlsToTry: [URL] = []
                
                // 1. Scraped tasks
                if let task = tasks.first(where: { $0.year == year && $0.month == m }) {
                    urlsToTry.append(task.url)
                }
                
                // 2. Full Month Name Pattern (observed in 2026: cpsc-january-2026.zip)
                let fullMonthName = monthNames[m-1]
                urlsToTry.append(URL(string: "https://www.cms.gov/files/zip/monthly-enrollment-cpsc-\(fullMonthName)-\(year).zip")!)
                
                // 3. Numeric Patterns
                urlsToTry.append(URL(string: "https://www.cms.gov/files/zip/monthly-enrollment-cpsc-\(year)-\(String(format: "%02d", m)).zip")!)
                urlsToTry.append(URL(string: "https://www.cms.gov/files/zip/monthly_enrollment_cpsc_\(year)_\(String(format: "%02d", m)).zip")!)
                
                var zipURL: URL? = nil
                var lastError: Error? = nil
                
                for url in urlsToTry {
                    print("DEBUG: Trying URL: \(url)")
                    do {
                        let task = CMSDownloadTask(url: url, type: .cpscEnrollment, year: year, month: m)
                        zipURL = try await fetcher.download(task: task)
                        if zipURL != nil { 
                            print("DEBUG: Download successful for: \(url)")
                            break 
                        }
                    } catch {
                        lastError = error
                        print("DEBUG: Attempt failed for \(url): \(error.localizedDescription)")
                    }
                }
                
                guard let finalZipURL = zipURL else {
                    throw lastError ?? NSError(domain: "Sync", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find file for \(year)-\(m) on CMS server."])
                }
                
                await MainActor.run { status = "Extracting..." }
                let extractedFiles = try fetcher.unzip(url: finalZipURL)
                print("DEBUG: Extracted \(extractedFiles.count) files")
                for file in extractedFiles {
                    print("DEBUG: Extracted file: \(file.lastPathComponent)")
                }
                
                // Flexible search for enrollment and contract files based on observed naming
                let enrollmentCSV = extractedFiles.first { file in
                    let name = file.lastPathComponent.lowercased()
                    return name.contains("enrollment") && name.contains("info") && name.hasSuffix(".csv")
                } ?? extractedFiles.first { file in
                    let name = file.lastPathComponent.lowercased()
                    return name.contains("enrollment") && name.hasSuffix(".csv")
                }
                
                let contractCSV = extractedFiles.first { file in
                    let name = file.lastPathComponent.lowercased()
                    return name.contains("contract") && name.contains("info") && name.hasSuffix(".csv")
                } ?? extractedFiles.first { file in
                    let name = file.lastPathComponent.lowercased()
                    return name.contains("contract") && name.hasSuffix(".csv")
                }
                
                guard let eCSV = enrollmentCSV, let cCSV = contractCSV else {
                    print("DEBUG: Missing expected CSVs. Found: \(extractedFiles.map { $0.lastPathComponent })")
                    throw NSError(domain: "Sync", code: 404, userInfo: [NSLocalizedDescriptionKey: "Required Enrollment/Contract CSV files not found in the ZIP archive. Found: \(extractedFiles.map { $0.lastPathComponent }.joined(separator: ", "))"])
                }
                
                print("DEBUG: Selected Enrollment CSV: \(eCSV.lastPathComponent)")
                print("DEBUG: Selected Contract CSV: \(cCSV.lastPathComponent)")
                
                await MainActor.run { status = "Ingesting..." }
                try await ingestion.ingestCPSC(enrollmentURL: eCSV, contractsURL: cCSV, year: year, month: m)
                
            } else {
                // Annual Landscape logic
                let tasks = try await fetcher.scrapeLandscapePage()
                let task = tasks.first(where: { $0.year == year }) ??
                           CMSDownloadTask(url: URL(string: "https://www.cms.gov/files/zip/cy\(year)-landscape-files.zip")!, type: .landscape, year: year, month: nil)
                
                let zipURL = try await fetcher.download(task: task)
                let extractedFiles = try fetcher.unzip(url: zipURL)
                
                if let landscapeCSV = extractedFiles.first(where: { $0.pathExtension.lowercased() == "csv" }) {
                    await MainActor.run { status = "Ingesting Landscape..." }
                    try await ingestion.ingestLandscape(url: landscapeCSV)
                }
            }
            
            await MainActor.run {
                status = "Success!"
                isSyncing = false
            }
        } catch {
            print("DEBUG: Sync FAILED: \(error)")
            await MainActor.run {
                status = "Failed: \(error.localizedDescription)"
                isSyncing = false
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { isSyncing = false }
        }
    }
}
