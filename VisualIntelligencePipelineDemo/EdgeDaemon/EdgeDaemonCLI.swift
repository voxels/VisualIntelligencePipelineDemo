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
        
        print("--- Installed Models ---")
        for model in service.loadedModels {
            print(" • \(model)")
        }
        print("------------------------")
        
        // Print the first prompt
        print("> ", terminator: "")
        fflush(stdout)
        
        for try await line in FileHandle.standardInput.bytes.lines {
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
                  download <model_id>    - Download an ML model (e.g., fastvlm-7b)
                  chat                   - Interactive search REPL against local data spaces
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
            case "chat":
                await service.startChatREPL()
            case let cmd where cmd.hasPrefix("download "):
                let modelName = String(cmd.dropFirst("download ".count)).trimmingCharacters(in: .whitespaces)
                Task {
                    await service.downloadModel(name: modelName)
                    print("\n> ", terminator: "")
                    fflush(stdout)
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
            
            // Only print next prompt if not downloading (download completion will print its own prompt)
            if !command.hasPrefix("download ") {
                print("> ", terminator: "")
                fflush(stdout)
            }
        }
    }
}
