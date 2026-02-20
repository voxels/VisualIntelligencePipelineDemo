//
//  main.swift
//  EdgeDaemon
//
//  macOS command-line tool that serves as an ML edge node for the
//  Visual Intelligence pipeline.
//

import Foundation
import DiverKit

@main
struct EdgeDaemonCLI {
    static func main() async throws {
        print("🚀 Starting Visual Intelligence Edge Daemon...")
        
        let service = EdgeDaemonService()
        service.startListening()
        print("Type 'help' for available commands.")
        
        let runLoop = Task {
            while let line = readLine() {
                let command = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                switch command {
                case "help":
                    print("""
                    Available Commands:
                      status                 - Show daemon state and metrics
                      start                  - Start Bonjour listener
                      stop                   - Stop Bonjour listener
                      clients                - List connected iOS clients
                      models                 - List available ML models
                      download <model_id>    - Download an ML model (e.g., fastvlm-1.5b)
                      quit                   - Exit EdgeDaemon
                    """)
                case "status":
                    print("--- EdgeDaemon Status ---")
                    print("State: \(service.status.rawValue)")
                    print("Listening: \(service.isListening ? "Yes" : "No")")
                    print("Total Requests: \(service.totalRequests)")
                    print("-------------------------")
                case "start":
                    service.startListening()
                case "stop":
                    service.stopListening()
                case "clients":
                    print("--- Connected Clients (\(service.connectedClients.count)) ---")
                    for client in service.connectedClients {
                        print(" • \(client)")
                    }
                    if service.connectedClients.isEmpty { print(" (None)") }
                    print("-----------------------------")
                case "models":
                    print("--- Loaded Models ---")
                    for model in service.loadedModels {
                        print(" • \(model)")
                    }
                    print("---------------------")
                case let cmd where cmd.hasPrefix("download "):
                    let modelName = String(cmd.dropFirst("download ".count)).trimmingCharacters(in: .whitespaces)
                    Task {
                        await service.downloadModel(name: modelName)
                        print("> ", terminator: "") // Print prompt again after async task finishes
                    }
                case "quit", "exit":
                    print("Shutting down...")
                    service.stopListening()
                    exit(0)
                case "":
                    break
                default:
                    print("Unknown command: '\(command)'. Type 'help' for options.")
                }
                print("> ", terminator: "")
            }
        }
        
        // Print the first prompt
        print("> ", terminator: "")
        
        // Keep the CLI process alive
        await runLoop.value
    }
}
