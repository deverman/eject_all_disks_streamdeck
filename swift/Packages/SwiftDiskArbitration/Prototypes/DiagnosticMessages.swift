//
//  DiagnosticMessages.swift
//  SwiftDiskArbitration
//
//  User-friendly diagnostic messages and solutions for common disk ejection issues.
//

import Foundation

/// Provides user-friendly explanations and solutions for disk ejection problems
public struct DiagnosticMessage: Sendable, Codable {
    /// The primary error message
    public let message: String

    /// User-friendly explanation of what went wrong
    public let explanation: String

    /// Suggested actions to resolve the issue
    public let suggestions: [String]

    /// Severity level
    public let severity: Severity

    public enum Severity: String, Sendable, Codable {
        case info
        case warning
        case error
        case critical
    }

    public init(message: String, explanation: String, suggestions: [String], severity: Severity = .error) {
        self.message = message
        self.explanation = explanation
        self.suggestions = suggestions
        self.severity = severity
    }
}

extension DiagnosticMessage {
    /// Generate a user-friendly diagnostic from a DiskError and optional blocking processes
    public static func from(error: DiskError, volumeName: String, blockingProcesses: [String: String]? = nil) -> DiagnosticMessage {
        switch error {
        case .busy, .exclusiveAccess:
            return busyDiskMessage(volumeName: volumeName, blockingProcesses: blockingProcesses)

        case .notPrivileged:
            return privilegeMessage(volumeName: volumeName)

        case .notPermitted:
            return permissionMessage(volumeName: volumeName)

        case .notMounted:
            return notMountedMessage(volumeName: volumeName)

        case .notWritable:
            return readOnlyMessage(volumeName: volumeName)

        case .timeout:
            return timeoutMessage(volumeName: volumeName)

        case .sessionCreationFailed:
            return sessionFailedMessage()

        default:
            return genericMessage(error: error, volumeName: volumeName)
        }
    }

    private static func busyDiskMessage(volumeName: String, blockingProcesses: [String: String]?) -> DiagnosticMessage {
        var explanation = "The disk '\(volumeName)' has files currently in use by one or more applications."
        var suggestions: [String] = []

        if let processes = blockingProcesses, !processes.isEmpty {
            let processNames = processes.keys.sorted()

            // Identify common problematic processes
            let knownBlockers: [String: String] = [
                "mds": "Spotlight",
                "mds_stores": "Spotlight indexing",
                "mdworker": "Spotlight worker",
                "photoanalysisd": "Photos app analysis",
                "bird": "iCloud Drive sync",
                "cloudd": "iCloud sync",
                "backupd": "Time Machine",
                "Music": "Music app",
                "Photos": "Photos app",
                "Finder": "Finder",
                "Preview": "Preview app",
                "com.apple.FileProvider": "File Provider"
            ]

            var identifiedBlockers: [String] = []
            var otherProcesses: [String] = []

            for processName in processNames {
                if let friendlyName = knownBlockers[processName] {
                    identifiedBlockers.append(friendlyName)
                } else {
                    otherProcesses.append(processName)
                }
            }

            if !identifiedBlockers.isEmpty {
                explanation += "\n\nIdentified blockers:"
                for blocker in identifiedBlockers {
                    explanation += "\n  • \(blocker)"
                }
            }

            if !otherProcesses.isEmpty {
                explanation += "\n\nOther processes using the disk:"
                for process in otherProcesses {
                    explanation += "\n  • \(process)"
                }
            }

            // Provide targeted suggestions
            if processNames.contains(where: { $0.hasPrefix("mds") || $0 == "mdworker" }) {
                suggestions.append("Spotlight is indexing. Wait a few minutes for indexing to complete, or disable Spotlight on this volume.")
                suggestions.append("To disable Spotlight: System Settings → Siri & Spotlight → Turn off indexing for this volume")
            }

            if processNames.contains("photoanalysisd") || processNames.contains("Photos") {
                suggestions.append("Photos app is analyzing or accessing the disk. Quit Photos and try again.")
                suggestions.append("If Photos library is on this disk, move it to your internal drive first.")
            }

            if processNames.contains("backupd") {
                suggestions.append("Time Machine is backing up. Pause Time Machine backup and try again.")
                suggestions.append("To pause: Time Machine menu → Skip This Backup")
            }

            if processNames.contains(where: { $0.contains("icloud") || $0 == "bird" || $0 == "cloudd" }) {
                suggestions.append("iCloud is syncing files. Wait for sync to complete or pause iCloud Drive.")
            }

            if processNames.contains("Music") {
                suggestions.append("Quit Music app and try again.")
            }

            if processNames.contains("Finder") || processNames.contains("Preview") {
                suggestions.append("Close any Finder windows showing this disk's contents.")
                suggestions.append("Close any files from this disk in Preview or other apps.")
            }

        } else {
            // No specific process information
            suggestions.append("Close all applications that might be using files on this disk.")
            suggestions.append("Check for open Finder windows showing the disk's contents.")
        }

        // General suggestions always apply
        suggestions.append("Wait a few seconds and try again - some processes release locks quickly.")
        suggestions.append("If the problem persists, restart your Mac to clear all file locks.")

        return DiagnosticMessage(
            message: "Disk is busy",
            explanation: explanation,
            suggestions: suggestions,
            severity: .warning
        )
    }

    private static func privilegeMessage(volumeName: String) -> DiagnosticMessage {
        DiagnosticMessage(
            message: "Insufficient privileges",
            explanation: """
                The disk '\(volumeName)' requires administrator privileges to eject.

                This usually happens when:
                • The disk was mounted by another user
                • The disk has special permissions
                • macOS security settings require elevated access
                """,
            suggestions: [
                "Configure passwordless ejection: See plugin setup instructions in the property inspector",
                "Run the setup script to enable sudo privileges for the eject binary",
                "Alternatively, use Finder to eject (may prompt for password)",
                "As a last resort, use 'Force Eject' in Finder (may cause data loss if files are open)"
            ],
            severity: .error
        )
    }

    private static func permissionMessage(volumeName: String) -> DiagnosticMessage {
        DiagnosticMessage(
            message: "Permission denied",
            explanation: """
                The system denied permission to eject '\(volumeName)'.

                This is different from privilege issues - it means macOS security policies are blocking the operation.
                """,
            suggestions: [
                "Check System Settings → Privacy & Security for any restrictions",
                "Ensure the Stream Deck app has necessary permissions",
                "Try ejecting from Finder to see if the same error occurs",
                "If this is a company-managed Mac, contact IT support"
            ],
            severity: .error
        )
    }

    private static func notMountedMessage(volumeName: String) -> DiagnosticMessage {
        DiagnosticMessage(
            message: "Volume not mounted",
            explanation: """
                The disk '\(volumeName)' is not currently mounted or was already ejected.

                This can happen if:
                • The disk was manually ejected in Finder
                • Another app already ejected it
                • The disk was physically disconnected
                """,
            suggestions: [
                "Reconnect the disk if it was physically removed",
                "Check Finder to see if the volume is still visible",
                "Try pressing the eject button again - the display may not have refreshed"
            ],
            severity: .info
        )
    }

    private static func readOnlyMessage(volumeName: String) -> DiagnosticMessage {
        DiagnosticMessage(
            message: "Read-only volume",
            explanation: """
                The disk '\(volumeName)' is read-only and cannot be ejected normally.

                This typically happens with:
                • CD/DVD media
                • Write-protected USB drives
                • Disk images mounted as read-only
                """,
            suggestions: [
                "For CDs/DVDs: Press the physical eject button on your Mac",
                "For disk images: Open Disk Utility and eject from there",
                "For USB drives: Check if there's a physical write-protect switch"
            ],
            severity: .warning
        )
    }

    private static func timeoutMessage(volumeName: String) -> DiagnosticMessage {
        DiagnosticMessage(
            message: "Operation timed out",
            explanation: """
                Ejecting '\(volumeName)' took too long and was cancelled.

                This can happen with:
                • Very slow USB drives
                • Network drives with poor connections
                • Drives with many open files being closed
                """,
            suggestions: [
                "Wait 30 seconds and try again",
                "Check the physical connection (cable, hub)",
                "For network drives: Check your network connection",
                "Close all apps that might be using the disk",
                "If using a USB hub, try connecting directly to your Mac"
            ],
            severity: .warning
        )
    }

    private static func sessionFailedMessage() -> DiagnosticMessage {
        DiagnosticMessage(
            message: "System error",
            explanation: """
                Failed to initialize the disk management system.

                This is a critical error that usually indicates a system-level problem.
                """,
            suggestions: [
                "Restart the Stream Deck application",
                "Restart your Mac",
                "If the problem persists, macOS may need to be repaired",
                "Check Console.app for system errors related to DiskArbitration"
            ],
            severity: .critical
        )
    }

    private static func genericMessage(error: DiskError, volumeName: String) -> DiagnosticMessage {
        DiagnosticMessage(
            message: "Ejection failed",
            explanation: """
                Failed to eject '\(volumeName)'.

                Error details: \(error.description)
                """,
            suggestions: [
                "Try ejecting from Finder to see if the same problem occurs",
                "Close all applications and try again",
                "Check Disk Utility for any disk errors or problems",
                "Restart your Mac if the problem persists",
                "If this error continues, please report it as a bug with the error details above"
            ],
            severity: .error
        )
    }
}

// MARK: - Formatted Output

extension DiagnosticMessage {
    /// Formatted message for terminal/log output
    public var formattedDescription: String {
        var output = ""

        // Header with severity indicator
        let severityEmoji = switch severity {
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .error: "❌"
        case .critical: "🚨"
        }

        output += "\(severityEmoji) \(message.uppercased())\n"
        output += "\n"
        output += explanation
        output += "\n\n"

        if !suggestions.isEmpty {
            output += "What you can do:\n"
            for (index, suggestion) in suggestions.enumerated() {
                output += "  \(index + 1). \(suggestion)\n"
            }
        }

        return output
    }

    /// Compact single-line summary
    public var summary: String {
        "\(message): \(explanation.split(separator: "\n").first ?? "")"
    }
}
