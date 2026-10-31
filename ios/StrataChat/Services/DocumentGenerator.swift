import Foundation
import UIKit
import PDFKit

public class DocumentGenerator {
    public static let shared = DocumentGenerator()
    
    public var generatedDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Generated", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {}
    
    // MARK: - PDF Generation via UIGraphicsPDFRenderer
    public func createPDF(filename: String, title: String, markdown: String) throws -> GeneratedFileInfo {
        let cleanName = sanitizeFilename(filename, defaultName: "Document", ext: "pdf")
        let fileURL = generatedDirectory.appendingPathComponent(cleanName)
        
        let pageWidth: CGFloat = 612.0 // US Letter width in points (8.5 inches)
        let pageHeight: CGFloat = 792.0 // US Letter height in points (11.0 inches)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let marginX: CGFloat = 46.0
        let marginY: CGFloat = 46.0
        let contentWidth = pageWidth - (marginX * 2)
        let contentBottom = pageHeight - marginY - 24.0 // Reserve footer space
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let data = renderer.pdfData { context in
            var currentPage = 1
            var cursorY: CGFloat = marginY
            
            func startNewPage() {
                context.beginPage()
                cursorY = marginY
                drawPageFooter(pageNumber: currentPage, pageRect: pageRect)
                currentPage += 1
            }
            
            // First page
            startNewPage()
            
            // 1. Draw Document Header (Title + Subtitle + Divider)
            let titleFont = UIFont.systemFont(ofSize: 22, weight: .heavy)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor(red: 0.05, green: 0.10, blue: 0.20, alpha: 1.0)
            ]
            let titleString = NSAttributedString(string: title.isEmpty ? "Strata Document" : title, attributes: titleAttrs)
            let titleHeight = titleString.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).height
            
            titleString.draw(in: CGRect(x: marginX, y: cursorY, width: contentWidth, height: titleHeight))
            cursorY += titleHeight + 4
            
            // Subtitle & Timestamp
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.gray
            ]
            let subString = NSAttributedString(string: "Generated with Strata Chat • \(df.string(from: Date()))", attributes: subAttrs)
            subString.draw(at: CGPoint(x: marginX, y: cursorY))
            cursorY += 18
            
            // Header accent line
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: marginX, y: cursorY))
            linePath.addLine(to: CGPoint(x: pageWidth - marginX, y: cursorY))
            UIColor(red: 0.0, green: 0.65, blue: 0.85, alpha: 0.8).setStroke()
            linePath.lineWidth = 1.5
            linePath.stroke()
            cursorY += 16
            
            // 2. Parse Markdown lines and render blocks
            let lines = markdown.components(separatedBy: .newlines)
            var inCodeBlock = false
            var codeBuffer: [String] = []
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // Code block handling
                if trimmed.hasPrefix("```") {
                    if inCodeBlock {
                        // Flush code block
                        let codeText = codeBuffer.joined(separator: "\n")
                        cursorY = drawCodeBlock(codeText, context: context, cursorY: &cursorY, marginX: marginX, contentWidth: contentWidth, contentBottom: contentBottom, onNewPage: {
                            startNewPage()
                        })
                        codeBuffer.removeAll()
                        inCodeBlock = false
                    } else {
                        inCodeBlock = true
                        codeBuffer.removeAll()
                    }
                    continue
                }
                
                if inCodeBlock {
                    codeBuffer.append(line)
                    continue
                }
                
                if trimmed.isEmpty {
                    cursorY += 8
                    continue
                }
                
                // Headings
                if trimmed.hasPrefix("# ") {
                    let text = String(trimmed.dropFirst(2))
                    cursorY = drawHeading(text, level: 1, cursorY: &cursorY, marginX: marginX, contentWidth: contentWidth, contentBottom: contentBottom, onNewPage: {
                        startNewPage()
                    })
                } else if trimmed.hasPrefix("## ") {
                    let text = String(trimmed.dropFirst(3))
                    cursorY = drawHeading(text, level: 2, cursorY: &cursorY, marginX: marginX, contentWidth: contentWidth, contentBottom: contentBottom, onNewPage: {
                        startNewPage()
                    })
                } else if trimmed.hasPrefix("### ") {
                    let text = String(trimmed.dropFirst(4))
                    cursorY = drawHeading(text, level: 3, cursorY: &cursorY, marginX: marginX, contentWidth: contentWidth, contentBottom: contentBottom, onNewPage: {
                        startNewPage()
                    })
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                    let text = String(trimmed.dropFirst(2))
                    cursorY = drawBulletItem(text, cursorY: &cursorY, marginX: marginX, contentWidth: contentWidth, contentBottom: contentBottom, onNewPage: {
                        startNewPage()
                    })
                } else {
                    cursorY = drawParagraph(trimmed, cursorY: &cursorY, marginX: marginX, contentWidth: contentWidth, contentBottom: contentBottom, onNewPage: {
                        startNewPage()
                    })
                }
            }
            
            if inCodeBlock && !codeBuffer.isEmpty {
                let codeText = codeBuffer.joined(separator: "\n")
                _ = drawCodeBlock(codeText, context: context, cursorY: &cursorY, marginX: marginX, contentWidth: contentWidth, contentBottom: contentBottom, onNewPage: {
                    startNewPage()
                })
            }
        }
        
        try data.write(to: fileURL, options: .atomic)
        
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count
        return GeneratedFileInfo(
            filename: cleanName,
            title: title.isEmpty ? cleanName : title,
            fileType: "pdf",
            sizeBytes: Int64(size),
            localPath: fileURL.path
        )
    }
    
    // MARK: - PDF Rendering Helpers
    private func drawHeading(_ text: String, level: Int, cursorY: inout CGFloat, marginX: CGFloat, contentWidth: CGFloat, contentBottom: CGFloat, onNewPage: () -> Void) -> CGFloat {
        let (fontSize, weight, color): (CGFloat, UIFont.Weight, UIColor) = {
            switch level {
            case 1: return (16.0, .heavy, UIColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 1.0))
            case 2: return (14.0, .bold, UIColor(red: 0.10, green: 0.20, blue: 0.40, alpha: 1.0))
            default: return (12.5, .semibold, UIColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1.0))
            }
        }()
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let rect = attrStr.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        
        cursorY += 10
        if cursorY + rect.height > contentBottom {
            onNewPage()
        }
        
        attrStr.draw(in: CGRect(x: marginX, y: cursorY, width: contentWidth, height: rect.height))
        cursorY += rect.height + 4
        return cursorY
    }
    
    private func drawParagraph(_ text: String, cursorY: inout CGFloat, marginX: CGFloat, contentWidth: CGFloat, contentBottom: CGFloat, onNewPage: () -> Void) -> CGFloat {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 3.5
        paraStyle.paragraphSpacing = 6
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0),
            .paragraphStyle: paraStyle
        ]
        
        let cleanText = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
        let attrStr = NSAttributedString(string: cleanText, attributes: attrs)
        let rect = attrStr.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        
        if cursorY + rect.height > contentBottom {
            onNewPage()
        }
        
        attrStr.draw(in: CGRect(x: marginX, y: cursorY, width: contentWidth, height: rect.height))
        cursorY += rect.height + 6
        return cursorY
    }
    
    private func drawBulletItem(_ text: String, cursorY: inout CGFloat, marginX: CGFloat, contentWidth: CGFloat, contentBottom: CGFloat, onNewPage: () -> Void) -> CGFloat {
        let bulletX = marginX + 6
        let textX = marginX + 20
        let itemWidth = contentWidth - 20
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
        ]
        let cleanText = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
        let attrStr = NSAttributedString(string: cleanText, attributes: attrs)
        let rect = attrStr.boundingRect(with: CGSize(width: itemWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        
        if cursorY + rect.height > contentBottom {
            onNewPage()
        }
        
        // Bullet circle
        let bulletRadius: CGFloat = 2.0
        let bulletPath = UIBezierPath(ovalIn: CGRect(x: bulletX, y: cursorY + 5, width: bulletRadius * 2, height: bulletRadius * 2))
        UIColor(red: 0.0, green: 0.65, blue: 0.85, alpha: 1.0).setFill()
        bulletPath.fill()
        
        attrStr.draw(in: CGRect(x: textX, y: cursorY, width: itemWidth, height: rect.height))
        cursorY += rect.height + 4
        return cursorY
    }
    
    private func drawCodeBlock(_ code: String, context: UIGraphicsPDFRendererContext, cursorY: inout CGFloat, marginX: CGFloat, contentWidth: CGFloat, contentBottom: CGFloat, onNewPage: () -> Void) -> CGFloat {
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9.0, weight: .medium),
            .foregroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        ]
        let attrStr = NSAttributedString(string: code, attributes: codeAttrs)
        let textSize = attrStr.boundingRect(with: CGSize(width: contentWidth - 16, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        
        let blockHeight = textSize.height + 14
        if cursorY + blockHeight > contentBottom {
            onNewPage()
        }
        
        // Background card
        let bgRect = CGRect(x: marginX, y: cursorY, width: contentWidth, height: blockHeight)
        let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 6)
        UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0).setFill()
        bgPath.fill()
        UIColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1.0).setStroke()
        bgPath.lineWidth = 0.8
        bgPath.stroke()
        
        attrStr.draw(in: CGRect(x: marginX + 8, y: cursorY + 7, width: contentWidth - 16, height: textSize.height))
        cursorY += blockHeight + 8
        return cursorY
    }
    
    private func drawPageFooter(pageNumber: Int, pageRect: CGRect) {
        let footerText = "Page \(pageNumber)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.lightGray
        ]
        let str = NSAttributedString(string: footerText, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: (pageRect.width - size.width) / 2.0, y: pageRect.height - 32.0))
    }
    
    // MARK: - Word (.docx) OpenXML Generator
    public func createWordDoc(filename: String, title: String, markdown: String) throws -> GeneratedFileInfo {
        let cleanName = sanitizeFilename(filename, defaultName: "Document", ext: "docx")
        let fileURL = generatedDirectory.appendingPathComponent(cleanName)
        
        // Build OpenXML document.xml content
        var bodyXML = ""
        
        // Title
        let safeTitle = escapeXML(title.isEmpty ? cleanName : title)
        bodyXML += """
        <w:p>
            <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:before="240" w:after="120"/>
            </w:pPr>
            <w:r>
                <w:rPr>
                    <w:b/>
                    <w:color w:val="0B1A30"/>
                    <w:sz w:val="48"/>
                </w:rPr>
                <w:t>\(safeTitle)</w:t>
            </w:r>
        </w:p>
        """
        
        // Subtitle
        let df = DateFormatter()
        df.dateStyle = .medium
        bodyXML += """
        <w:p>
            <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:after="360"/>
            </w:pPr>
            <w:r>
                <w:rPr>
                    <w:color w:val="718096"/>
                    <w:sz w:val="20"/>
                </w:rPr>
                <w:t>Strata Chat • \(df.string(from: Date()))</w:t>
            </w:r>
        </w:p>
        """
        
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("# ") {
                let text = escapeXML(String(trimmed.dropFirst(2)))
                bodyXML += """
                <w:p>
                    <w:pPr><w:spacing w:before="280" w:after="80"/></w:pPr>
                    <w:r><w:rPr><w:b/><w:color w:val="0A3B75"/><w:sz w:val="34"/></w:rPr><w:t>\(text)</w:t></w:r>
                </w:p>
                """
            } else if trimmed.hasPrefix("## ") {
                let text = escapeXML(String(trimmed.dropFirst(3)))
                bodyXML += """
                <w:p>
                    <w:pPr><w:spacing w:before="220" w:after="60"/></w:pPr>
                    <w:r><w:rPr><w:b/><w:color w:val="144A8C"/><w:sz w:val="28"/></w:rPr><w:t>\(text)</w:t></w:r>
                </w:p>
                """
            } else if trimmed.hasPrefix("### ") {
                let text = escapeXML(String(trimmed.dropFirst(4)))
                bodyXML += """
                <w:p>
                    <w:pPr><w:spacing w:before="180" w:after="40"/></w:pPr>
                    <w:r><w:rPr><w:b/><w:color w:val="235B9E"/><w:sz w:val="24"/></w:rPr><w:t>\(text)</w:t></w:r>
                </w:p>
                """
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let text = escapeXML(String(trimmed.dropFirst(2)))
                bodyXML += """
                <w:p>
                    <w:pPr>
                        <w:ind w:left="480" w:hanging="240"/>
                        <w:spacing w:after="60"/>
                    </w:pPr>
                    <w:r><w:rPr><w:color w:val="00A3C4"/><w:sz w:val="22"/></w:rPr><w:t>• </w:t></w:r>
                    <w:r><w:rPr><w:sz w:val="22"/></w:rPr><w:t>\(text)</w:t></w:r>
                </w:p>
                """
            } else {
                let text = escapeXML(trimmed.replacingOccurrences(of: "**", with: ""))
                bodyXML += """
                <w:p>
                    <w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr>
                    <w:r><w:rPr><w:sz w:val="22"/><w:color w:val="2D3748"/></w:rPr><w:t>\(text)</w:t></w:r>
                </w:p>
                """
            }
        }
        
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>
                \(bodyXML)
                <w:sectPr>
                    <w:pgSz w:w="12240" w:h="15840"/>
                    <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
                </w:sectPr>
            </w:body>
        </w:document>
        """
        
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        
        let wordRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        </Relationships>
        """
        
        // Package files into a standard Zip archive
        let zipEntries: [(String, Data)] = [
            ("[Content_Types].xml", contentTypesXML.data(using: .utf8)!),
            ("_rels/.rels", relsXML.data(using: .utf8)!),
            ("word/_rels/document.xml.rels", wordRelsXML.data(using: .utf8)!),
            ("word/document.xml", documentXML.data(using: .utf8)!)
        ]
        
        let zipData = createZipArchive(entries: zipEntries)
        try zipData.write(to: fileURL, options: .atomic)
        
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? zipData.count
        return GeneratedFileInfo(
            filename: cleanName,
            title: title.isEmpty ? cleanName : title,
            fileType: "docx",
            sizeBytes: Int64(size),
            localPath: fileURL.path
        )
    }
    
    // MARK: - Minimal Pure Swift Zip Archive Builder (Stored / Deflate)
    private func createZipArchive(entries: [(String, Data)]) -> Data {
        var body = Data()
        var centralDirectory = Data()
        var localHeaderOffsets: [UInt32] = []
        
        for (filename, fileData) in entries {
            let offset = UInt32(body.count)
            localHeaderOffsets.append(offset)
            let nameData = filename.data(using: .utf8)!
            let crc = SimpleCRC32.checksum(fileData)
            let size = UInt32(fileData.count)
            
            // Local file header: 0x04034b50
            var lh = Data()
            lh.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // signature
            lh.append(contentsOf: [0x14, 0x00])             // version needed (2.0)
            lh.append(contentsOf: [0x00, 0x00])             // flags
            lh.append(contentsOf: [0x00, 0x00])             // compression method: 0 (STORED)
            lh.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // mod time & date
            lh.append(contentsOf: toBytes(crc))             // crc32
            lh.append(contentsOf: toBytes(size))            // compressed size
            lh.append(contentsOf: toBytes(size))            // uncompressed size
            lh.append(contentsOf: toBytes(UInt16(nameData.count))) // filename length
            lh.append(contentsOf: [0x00, 0x00])             // extra field length
            lh.append(nameData)
            lh.append(fileData)
            
            body.append(lh)
            
            // Central directory header: 0x02014b50
            var cd = Data()
            cd.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // signature
            cd.append(contentsOf: [0x14, 0x00])             // version made by (2.0)
            cd.append(contentsOf: [0x14, 0x00])             // version needed
            cd.append(contentsOf: [0x00, 0x00])             // flags
            cd.append(contentsOf: [0x00, 0x00])             // compression: 0
            cd.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // time & date
            cd.append(contentsOf: toBytes(crc))
            cd.append(contentsOf: toBytes(size))
            cd.append(contentsOf: toBytes(size))
            cd.append(contentsOf: toBytes(UInt16(nameData.count)))
            cd.append(contentsOf: [0x00, 0x00])             // extra length
            cd.append(contentsOf: [0x00, 0x00])             // comment length
            cd.append(contentsOf: [0x00, 0x00])             // disk number start
            cd.append(contentsOf: [0x00, 0x00])             // internal file attributes
            cd.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external file attributes
            cd.append(contentsOf: toBytes(offset))          // relative offset of local header
            cd.append(nameData)
            
            centralDirectory.append(cd)
        }
        
        let cdOffset = UInt32(body.count)
        let cdSize = UInt32(centralDirectory.count)
        let numEntries = UInt16(entries.count)
        
        body.append(centralDirectory)
        
        // End of Central Directory Record: 0x06054b50
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // signature
        eocd.append(contentsOf: [0x00, 0x00])             // disk number
        eocd.append(contentsOf: [0x00, 0x00])             // disk with CD
        eocd.append(contentsOf: toBytes(numEntries))      // entries on this disk
        eocd.append(contentsOf: toBytes(numEntries))      // total entries
        eocd.append(contentsOf: toBytes(cdSize))          // central dir size
        eocd.append(contentsOf: toBytes(cdOffset))        // central dir offset
        eocd.append(contentsOf: [0x00, 0x00])             // comment length
        
        body.append(eocd)
        return body
    }
    
    // MARK: - Utilities
    private func toBytes<T>(_ value: T) -> [UInt8] {
        var v = value
        return withUnsafeBytes(of: &v) { Array($0) }
    }
    
    private func escapeXML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func sanitizeFilename(_ raw: String, defaultName: String, ext: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = defaultName }
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        name = name.components(separatedBy: invalidChars).joined(separator: "_")
        if !name.lowercased().hasSuffix("." + ext.lowercased()) {
            name += "." + ext
        }
        return name
    }
}

// MARK: - Pure Swift CRC-32 (Standard IEEE 802.3)
private struct SimpleCRC32 {
    private static let table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
    
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}
