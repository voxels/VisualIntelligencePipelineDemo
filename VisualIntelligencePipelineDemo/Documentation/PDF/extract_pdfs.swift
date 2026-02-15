import Foundation
import PDFKit

let folderURL = URL(fileURLWithPath: "/Users/voxels/Documents/dev/Diver/App Intents Docs")
let outputURL = URL(fileURLWithPath: "/Users/voxels/Documents/dev/Diver/App Intents Docs/extracted_content.txt")

do {
    let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
    let pdfFiles = files.filter { $0.pathExtension.lowercased() == "pdf" }
    
    var allContent = ""
    
    for pdfURL in pdfFiles {
        print("Processing \(pdfURL.lastPathComponent)...")
        if let pdf = PDFDocument(url: pdfURL) {
            allContent += "========================================\n"
            allContent += "FILE: \(pdfURL.lastPathComponent)\n"
            allContent += "========================================\n"
            
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i) {
                    allContent += page.string ?? ""
                }
            }
            allContent += "\n\n"
        }
    }
    
    try allContent.write(to: outputURL, atomically: true, encoding: .utf8)
    print("Done! Content saved to \(outputURL.path)")
} catch {
    print("Error: \(error)")
}
