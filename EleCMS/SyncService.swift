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
                if let task = tasks.first(where: { $0.year == year && $0.month == m }) { urlsToTry.append(task.url) }
                let fullMonthName = monthNames[m-1]
                urlsToTry.append(URL(string: "https://www.cms.gov/files/zip/monthly-enrollment-cpsc-\(fullMonthName)-\(year).zip")!)
                urlsToTry.append(URL(string: "https://www.cms.gov/files/zip/monthly-enrollment-cpsc-\(year)-\(String(format: "%02d", m)).zip")!)
                urlsToTry.append(URL(string: "https://www.cms.gov/files/zip/monthly_enrollment_cpsc_\(year)_\(String(format: "%02d", m)).zip")!)
                
                var zipURL: URL? = nil
                var lastError: Error? = nil
                for url in urlsToTry {
                    print("DEBUG: Trying URL: \(url)")
                    do {
                        let task = CMSDownloadTask(url: url, type: .cpscEnrollment, year: year, month: m)
                        zipURL = try await fetcher.download(task: task)
                        if zipURL != nil { break }
                    } catch {
                        lastError = error
                    }
                }
                
                guard let finalZipURL = zipURL else {
                    throw lastError ?? NSError(domain: "Sync", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find file for \(year)-\(m) on CMS server."])
                }
                
                await MainActor.run { status = "Extracting..." }
                let extractedFiles = try fetcher.unzip(url: finalZipURL)
                let enrollmentCSV = extractedFiles.first { $0.lastPathComponent.localizedCaseInsensitiveContains("enrollment") && $0.pathExtension.lowercased() == "csv" }
                let contractCSV = extractedFiles.first { $0.lastPathComponent.localizedCaseInsensitiveContains("contract") && $0.pathExtension.lowercased() == "csv" }
                
                guard let eCSV = enrollmentCSV, let cCSV = contractCSV else {
                    throw NSError(domain: "Sync", code: 404, userInfo: [NSLocalizedDescriptionKey: "Required Enrollment/Contract CSV files not found."])
                }
                
                await MainActor.run { status = "Ingesting..." }
                try await ingestion.ingestCPSC(enrollmentURL: eCSV, contractsURL: cCSV, year: year, month: m)
                
            } else {
                print("DEBUG: Handling Annual Landscape sync for year \(year)")
                let tasks = try await fetcher.scrapeLandscapePage()
                
                var urlsToTry: [URL] = []
                if let directTask = tasks.first(where: { $0.year == year && $0.month == nil }) { urlsToTry.append(directTask.url) }
                if let rangeTask = tasks.first(where: { ($0.month ?? 0) <= year && $0.year >= year }) { urlsToTry.append(rangeTask.url) }
                urlsToTry.append(URL(string: "https://www.cms.gov/files/zip/cy\(year)-landscape-files.zip")!)
                
                var zipURL: URL? = nil
                var lastError: Error? = nil
                for url in urlsToTry {
                    print("DEBUG: Trying Landscape URL: \(url)")
                    do {
                        let task = CMSDownloadTask(url: url, type: .landscape, year: year, month: nil)
                        zipURL = try await fetcher.download(task: task)
                        if zipURL != nil { break }
                    } catch {
                        lastError = error
                    }
                }
                
                guard let finalZipURL = zipURL else {
                    throw lastError ?? NSError(domain: "Sync", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find Landscape file for \(year)."])
                }
                
                await MainActor.run { status = "Extracting Landscape..." }
                let extractedFiles = try fetcher.unzip(url: finalZipURL)
                
                var csvFiles: [URL] = []
                func collectCSVs(from files: [URL], forYear targetYear: Int) throws {
                    let yearStr = "\(targetYear)"
                    for file in files {
                        let name = file.lastPathComponent
                        if file.pathExtension.lowercased() == "zip" {
                            // ONLY drill into ZIPs that strictly mention our target year
                            if name.contains(yearStr) {
                                print("DEBUG: Unzipping strictly relevant ZIP: \(name)")
                                let nestedFiles = try fetcher.unzip(url: file)
                                try collectCSVs(from: nestedFiles, forYear: targetYear)
                            }
                        } else if file.pathExtension.lowercased() == "csv" {
                            // ONLY collect CSVs that strictly match the year OR are in a path that does
                            if name.contains(yearStr) || file.path.contains(yearStr) {
                                let lower = name.lowercased()
                                if !lower.contains("readme") && !lower.contains("read_me") {
                                    csvFiles.append(file)
                                }
                            }
                        }
                    }
                }
                
                try collectCSVs(from: extractedFiles, forYear: year)
                
                if csvFiles.isEmpty {
                    throw NSError(domain: "Sync", code: 404, userInfo: [NSLocalizedDescriptionKey: "No data files matching \(year) were found in the archive."])
                }
                
                print("DEBUG: Found \(csvFiles.count) Landscape CSVs for \(year)")
                await MainActor.run { status = "Ingesting Landscape..." }
                
                // Clear staging once for the year
                try dataStore.database.execute(sql: "DELETE FROM staging_landscape;")
                for csv in csvFiles {
                    print("DEBUG: Ingesting: \(csv.lastPathComponent)")
                    try await ingestion.ingestLandscape(url: csv, year: year)
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
    
    func syncEntireYear(year: Int) async {
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        
        let maxMonth = (year == currentYear) ? currentMonth : 12
        
        for m in 1...maxMonth {
            await syncSpecific(year: year, month: m)
            // Small pause between months to avoid overwhelming the server/local IO
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
