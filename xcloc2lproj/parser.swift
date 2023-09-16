//
//  parser.swift
//  xcloc2lproj
//
//  Created by aone on 15/9/23.
//
//  Copyright © aone. All rights reserved.
//
//  This source code is licensed under both the BSD-style license (found in the
//  LICENSE file in the root directory of this source tree) and the GPLv2 (found
//  in the COPYING file in the root directory of this source tree).
//  You may select, at your option, one of the above-listed licenses.
//

import Foundation

public func parse(_ xliffFile: URL,
                  destination: URL,
                  excludedIds: [String],
                  excludedFiles: [String],
                  doNotCreatePaths: Bool,
                  appendLprojExtension: Bool) {
    printMessage("Parsing \(xliffFile.lastPathComponent)", verbose: 1)
    
    guard let parser = XMLParser(contentsOf: xliffFile) else {
        printMessage("Unable to create the parser for the file.")
        exit(1)
    }
    
    let parserDelegate = XCLOCParser(xliffFile,
                                     destination: destination,
                                     excludedIds: excludedIds,
                                     doNotCreatePaths: doNotCreatePaths,
                                     excludedFiles: excludedFiles,
                                     appendLprojExtension: appendLprojExtension)
    parser.delegate = parserDelegate
    
    if !parser.parse() {
        printMessage("Unable to parse the file.")
        exit(1)
    }
}

public class XCLOCParser : NSObject, XMLParserDelegate {
    
    public enum TranslationUnitType {
        case source, target, note
    }
    
    public struct TranslationUnit {
        var id: String?
        var source: String?
        var target: String?
        var note: String?
        var isPlistLocalization: Bool = false
        
        var description: String {
            "Id: `\(id ?? "nil")`, Source: `\(source ?? "nil")`, target: `\(target ?? "nil")`, note: `\(note ?? "nil")`"
        }
        
        private func escapeLocalizableString(_ string: String?) -> String? {
            string?
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        
        var localizableString: String {
            var string = ""
            
            // Comment
            string += "/* \(note ?? (isPlistLocalization ? "(No Comment)" : "No comment provided by engineer.")) */\n"
            
            // Key
            string += "\"\(escapeLocalizableString(id) ?? "")\" = "
            
            // Value
            if target != nil {
                string +=  "\"\(escapeLocalizableString(target) ?? "")\";"
            }
            else {
                string += "\"\(escapeLocalizableString(source) ?? "")\"; // THIS IS NOT LOCALIZED"
            }
            
            return string + "\n\n"
        }
        
        var localizableData: Data {
            guard let data = localizableString.data(using: .utf8) else {
                printMessage("Unable to produce the translation unit data.")
                exit(1)
            }
            return data
        }
    }
    
    private var transUnits: [TranslationUnit]?
    private var excludedIds: [String]
    private var excludedFiles: [String]
    private var doNotCreatePaths: Bool
    private var appendLprojExtension: Bool
    
    private var file: URL
    private var destination: URL

    private var isPlistLocalization: Bool = false
    private var currentLanguage: String?
    private var currentDestinationPath: URL?
    private var currentFile: URL?
    private var currentFileHanlde: FileHandle?
    private var currentTranslationUnit: TranslationUnit?
    private var currentTranslationUnitType: TranslationUnitType?


    public let fileKey = "file"
    public let filePathKey = "original"
    public let transUnitKey = "trans-unit"
    public let transUnitIdKey = "id"
    public let transSourceKey = "source"
    public let transTargetKey = "target"
    public let transNoteKey = "note"

    public init(_ file: URL,
                destination: URL,
                excludedIds: [String],
                doNotCreatePaths: Bool,
                excludedFiles: [String],
                appendLprojExtension: Bool) {
        self.file = file
        self.destination = destination
        self.excludedIds = excludedIds
        self.doNotCreatePaths = doNotCreatePaths
        self.excludedFiles = excludedFiles
        self.appendLprojExtension = appendLprojExtension
    }
    
    private func resetLanguage() {
        printMessage("Language done", verbose: 3)
        currentLanguage = nil
        currentDestinationPath = nil
    }
    
    private func resetFile() {
        printMessage("Strings file done", verbose: 3)
        currentFile = nil
        try? currentFileHanlde?.close()
        currentFileHanlde = nil
        currentTranslationUnit = nil
        currentTranslationUnitType = nil
        transUnits = nil
        isPlistLocalization = false
    }
    
    private func createLanguagePath() {
        currentLanguage = file.deletingPathExtension().lastPathComponent
        guard let currentLanguage = currentLanguage else {
            printMessage("No currentLanguage set.")
            exit(1)
        }
        printMessage("Reading language document \(currentLanguage)", verbose: 2)
        currentDestinationPath = destination.appending(component: currentLanguage)
        if appendLprojExtension {
            currentDestinationPath?.appendPathExtension("lproj")
        }
        guard let currentDestinationPath = currentDestinationPath else {
            printMessage("No currentDestinationPath set.")
            exit(1)
        }
        do {
            try FileManager.default.createDirectory(at: currentDestinationPath, withIntermediateDirectories: true)
        }
        catch {
            printMessage("Unable to create the file destination for the file \"\(currentDestinationPath)\".")
            printMessage(error.localizedDescription, verbose: 2)
            exit(1)
        }
    }
    
    private func excludeFile(_ file: URL) -> Bool {
        if excludedFiles.contains(file.lastPathComponent) {
            currentFile = file
            printMessage("Skipping this strings file as it is in the exclude list.", verbose: 2)
            return true
        }
        return false
    }
    
    private func noPathsFile(_ file: URL) {
        var count = 0
        currentFile = currentDestinationPath?.appending(component: file.lastPathComponent)
        while let current = currentFile, FileManager.default.fileExists(atPath: current.path) {
            var f = ""
            let pathComponents = file.pathComponents.filter{ $0 != "/" }
            for i in 0...count {
                if pathComponents.count < i {
                    break
                }
                f += pathComponents[i] + "-"
            }
            f += file.deletingPathExtension().lastPathComponent
            if count > pathComponents.count {
                f += "-\(count)"
            }
            f += "." + file.pathExtension
            currentFile = currentDestinationPath?.appending(component: f)
            count += 1
        }
    }
    
    private func startFile(_ file: String) {
        printMessage("Creating file \(file)", verbose: 2)
        let fileURL = URL(filePath: file, relativeTo: URL(filePath: "/"))
        
        if doNotCreatePaths {
            noPathsFile(fileURL)
        }
        else {
            currentFile = currentDestinationPath?.appending(component: file)
        }
        
        guard let currentFile = currentFile else {
            printMessage("No currentFile set.")
            exit(1)
        }
        
        if excludeFile(currentFile) {
            return
        }
        
        do {
            try FileManager.default.createDirectory(at: currentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        catch {
            printMessage("Unable to create the path for the translated file \"\(currentFile)\".")
            printMessage(error.localizedDescription, verbose: 2)
            exit(1)
        }
        
        if !FileManager.default.createFile(atPath: currentFile.path, contents: nil) {
            printMessage("Unable to create the translated file \"\(currentFile)\".")
            exit(1)
        }
        
        do {
            currentFileHanlde = try FileHandle(forWritingTo: currentFile)
        }
        catch {
            printMessage("Unable to open the translated file \"\(currentFile)\".")
            exit(1)
        }
        
        isPlistLocalization = URL(filePath: file).deletingPathExtension().lastPathComponent.lowercased().contains("plist")
        transUnits = []
    }
    
    private func startTranslationUnit() {
        printMessage("Starting translation unit", verbose: 4)
        currentTranslationUnit = TranslationUnit(isPlistLocalization: isPlistLocalization)
    }
    
    private func endTranslationUnit() {
        guard let translationUnit = currentTranslationUnit else {
            printMessage("The translation unit is empty.")
            exit(1)
        }
        
        printMessage("Translation unit parsed: \(translationUnit.description)", verbose: 4)
        
        if !excludedIds.contains(translationUnit.id ?? "") {
            transUnits?.append(translationUnit)
        }
        else {
            printMessage("Skipping this translation unit, matched one or more exclude ids", verbose: 4)
        }
        currentTranslationUnit = nil
    }
    
    private func writeTranslationUnits() {
        printMessage("Writting translation units...", verbose: 2)

        guard let currentFileHanlde else {
            if let currentFile, excludedFiles.contains(currentFile.lastPathComponent) {
                printMessage("Skipping this translation unit as its file is in the exclusion list.", verbose: 2)
                return
            }
            printMessage("Unable to get the translation file handle.")
            exit(1)
        }
        
        let sortedTransUnits = transUnits?.sorted { ltu, rtu in
            ltu.id?.lowercased() ?? "" < rtu.id?.lowercased() ?? ""
        }
        
        sortedTransUnits?.forEach { translationUnit in
            printMessage("Writting translation unit: \(translationUnit.description)", verbose: 4)
            currentFileHanlde.write(translationUnit.localizableData)
        }
    }

    public func parserDidStartDocument(_ parser: XMLParser) {
        createLanguagePath()
    }

    public func parserDidEndDocument(_ parser: XMLParser) {
        resetLanguage()
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == fileKey {
            writeTranslationUnits()
            resetFile()
        }
        if elementName == transUnitKey {
            endTranslationUnit()
        }
    }
    
    public func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {        
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        
        if string == "\"%@\"" || string == "%@" {
            return
        }
        
        guard let currentTranslationUnitType else {
            printMessage("No translation unit type set for value: `\(value)`", verbose: 3)
            return
        }
        
        switch currentTranslationUnitType {
        case .source:
            let currentValue = currentTranslationUnit?.source ?? ""
            currentTranslationUnit?.source = currentValue + string
        case .target:
            let currentValue = currentTranslationUnit?.target ?? ""
            currentTranslationUnit?.target = currentValue + string
        case .note:
            let currentValue = currentTranslationUnit?.note ?? ""
            currentTranslationUnit?.note = currentValue + string
        }
    }
    
    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        if elementName == fileKey {
            for (key, value) in attributeDict {
                if key == filePathKey {
                    startFile(value)
                }
            }
        }
        else if elementName == transUnitKey {
            startTranslationUnit()
            for (key, value) in attributeDict {
                if key == transUnitIdKey {
                    currentTranslationUnit?.id = value
                }
            }
        }
        else if elementName == transSourceKey {
            currentTranslationUnitType = .source
        }
        else if elementName == transTargetKey {
            currentTranslationUnitType = .target
        }
        else if elementName == transNoteKey {
            currentTranslationUnitType = .note
        }
    }
    
}
