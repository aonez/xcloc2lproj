//
//  main.swift
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

let version = "1.0"

func printHelp() {
    printMessage("xcloc2lproj \(version)\n")
    printMessage("Usage: xcloc2lproj <options> [<xcloc_path>...]\n")
    printMessage("Options:")
    printMessage("  -d path                Parse all xcloc files found in `path`")
    printMessage("  -o output_file         Output file, default is the current path")
    printMessage("  -exclude-id id         Exclude translation units that their id match the `id` string")
    printMessage("  -exclude-file file     Exclude origin strings files that match the `file` path")
    printMessage("  -x                     Do not create paths, only strings files")
    printMessage("  -lproj                 Append .lproj extension to the language folder")
    printMessage("  -q                     Be quiet")
}

var verboseLevel = 1
func printMessage(_ any: Any, verbose: Int = 1) {
    if verbose <= verboseLevel {
        print(any)
    }
}

#if DEBUG
if CommandLine.arguments.count == 1 {
    printHelp()
    exit(0)
}
#else
if CommandLine.arguments.isEmpty {
    printHelp()
    exit(0)
}
#endif

var destination: URL = URL(filePath: FileManager.default.currentDirectoryPath)
var xclocFiles: [URL] = []
var excludedIds: [String] = []
var excludedFiles: [String] = []
var doNotCreatePaths = false
var appendLprojExtension = false

var count = 0
var skip = true

#if DEBUG
verboseLevel = 999
#endif

for arg in CommandLine.arguments {
    if !skip {
        if arg == "-o" {
            guard CommandLine.arguments.count > count + 1 else {
                printMessage("No destination path after the -o argument.")
                exit(1)
            }
            destination = URL(filePath: CommandLine.arguments[count + 1])
            skip = true
        }
        else if arg == "-exclude-id" {
            guard CommandLine.arguments.count > count + 1 else {
                printMessage("No `id` argument to exclude.")
                exit(1)
            }
            excludedIds.append(CommandLine.arguments[count + 1])
            skip = true
        }
        else if arg == "-exclude-file" {
            guard CommandLine.arguments.count > count + 1 else {
                printMessage("No `file` path argument to exclude.")
                exit(1)
            }
            excludedFiles.append(CommandLine.arguments[count + 1])
            skip = true
        }
        else if arg == "-lproj" {
            appendLprojExtension = true
        }
        else if arg == "-x" {
            doNotCreatePaths = true
        }
        else if arg == "-v" {
            verboseLevel += 1
        }
        else if arg == "-q" {
            verboseLevel = 0
        }
        else if arg == "-d" {
            guard CommandLine.arguments.count > count + 1 else {
                printMessage("No `path` argument found.")
                exit(1)
            }
            let path = CommandLine.arguments[count + 1]
            if let contents = try? FileManager.default.contentsOfDirectory(at: URL(filePath: path), includingPropertiesForKeys: nil) {
                for file in contents {
                    if file.pathExtension == "xcloc" {
                        xclocFiles.append(file)
                    }
                }
            }
            skip = true
        }
        else {
            xclocFiles.append(URL(filePath: arg))
        }
    }
    else {
        skip = false
    }
    count += 1
}

if let result = try? destination.checkResourceIsReachable(), !result {
    do {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }
    catch {
        printMessage("Unable to reach the destination: \"\(destination.path)\"")
        printMessage(error.localizedDescription, verbose: 2)
        exit(1)
    }
}

guard !xclocFiles.isEmpty else {
    printHelp()
    printMessage("\nThis script should be called with at least one xcloc path argument.")
    exit(1)
}

for xclocFile in xclocFiles {
    printMessage("Reading \(xclocFile.lastPathComponent)")
    
    guard let result = try? xclocFile.checkResourceIsReachable(), result == true else {
        printMessage("The xcloc file does not exists or is not accessible.")
        exit(1)
    }
    
    let xclocLocalizedContentsPath = xclocFile.appending(component: "Localized Contents")
    guard let result = try? xclocFile.checkResourceIsReachable(), result == true else {
        printMessage("The xcloc file does not contain a \"Localized Contents\" folder.")
        exit(1)
    }
    
    guard let xliffContents = try? FileManager.default.contentsOfDirectory(at: xclocLocalizedContentsPath, includingPropertiesForKeys: nil), xliffContents.count > 0 else {
        printMessage("The xcloc file does not contain any xliff translation file.")
        exit(1)
    }
    
    for xliff in xliffContents {
        parse(xliff,
              destination: destination,
              excludedIds: excludedIds,
              excludedFiles: excludedFiles,
              doNotCreatePaths: doNotCreatePaths,
              appendLprojExtension: appendLprojExtension)
    }
}

exit(0)
