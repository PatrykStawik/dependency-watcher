//
//  ContentView.swift
//  dependency-watcher
//
//  Created by Patryk Stawik on 15/08/2024.
//


import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @State private var selectedDirectory: URL?
    @State private var folderInfos: [(name: String, url: URL, size: Double)] = []
    @State private var selectedFolders: Set<URL> = []
    @State private var searchText: String = ""
    @State private var isShowing = false

    @State private var filename = "Filename"
    @State private var showFileChooser = false
    
    @State private var isProcessing = false

    var body: some View {
        VStack {
            Text("Selected Directory: \(filename)")
                .padding()

            Button("Select Directory") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK {
                    if let url = panel.url {
                        self.selectedDirectory = url
                        self.filename = url.lastPathComponent
                        self.searchForNodeModules(in: url)
                    }
                }
            }
            .padding()

            if isProcessing {
                ProgressView("Calculating...")
                    .padding()
            } else {
                List(folderInfos, id: \.url) { folderInfo in
                    HStack {
                        Toggle(isOn: Binding<Bool>(
                            get: { selectedFolders.contains(folderInfo.url) },
                            set: { isSelected in
                                if isSelected {
                                    selectedFolders.insert(folderInfo.url)
                                } else {
                                    selectedFolders.remove(folderInfo.url)
                                }
                            }
                        )) {
                            Text(folderInfo.name)
                        }
                        Spacer()
                        Text(String(format: "%.2f MB", folderInfo.size))
                    }
                }
                .padding()
                
                Text("Selected Size: \(String(format: "%.2f MB", selectedSizeInMB()))")
                    .font(.headline)
                    .padding()
                
                Button("Delete Selected Folders") {
                    deleteSelectedFolders()
                }
                .disabled(selectedFolders.isEmpty)
                .padding()
                
                Text("Total Size: \(String(format: "%.2f MB", totalSizeInMB()))")
                    .font(.headline)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchForNodeModules(in directory: URL) {
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
                
                let foundFolderInfos = contents.compactMap { folderURL in
                    let nodeModulesURL = folderURL.appendingPathComponent("node_modules")
                    if FileManager.default.fileExists(atPath: nodeModulesURL.path) {
                        let sizeInBytes = calculateFolderSize(at: nodeModulesURL)
                        let sizeInMB = sizeInBytes / (1024 * 1024)
                        return (name: folderURL.lastPathComponent, url: folderURL, size: sizeInMB)
                    }
                    return nil
                }
                .sorted(by: { $0.size > $1.size })

                DispatchQueue.main.async {
                    self.folderInfos = foundFolderInfos
                    self.selectedFolders.removeAll()
                    self.isProcessing = false
                }
            } catch {
                print("Error reading contents of directory: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
            }
        }
    }

    private func calculateFolderSize(at url: URL) -> Double {
        var folderSize: Double = 0
        let fileManager = FileManager.default

        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
            for case let fileURL as URL in enumerator {
                do {
                    let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    folderSize += Double(attributes.fileSize ?? 0)
                } catch {
                    print("Error calculating size for file \(fileURL): \(error.localizedDescription)")
                }
            }
        }

        return folderSize
    }

    private func totalSizeInMB() -> Double {
        return folderInfos.reduce(0) { $0 + $1.size }
    }
    
    private func selectedSizeInMB() -> Double {
        return folderInfos.filter { selectedFolders.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    private func deleteSelectedFolders() {
        for folderInfo in folderInfos.filter({ selectedFolders.contains($0.url) }) {
            do {
                let nodeModulesURL = folderInfo.url.appendingPathComponent("node_modules")
                try FileManager.default.removeItem(at: nodeModulesURL)
            } catch {
                print("Error deleting node_modules folder \(folderInfo.url): \(error.localizedDescription)")
                showErrorAlert(for: folderInfo.url)
            }
        }
        searchForNodeModules(in: selectedDirectory!)
    }

    private func showErrorAlert(for folderURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Error Deleting Folder"
        alert.informativeText = "Could not delete folder \(folderURL.lastPathComponent) because you don’t have permission to access it."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}

