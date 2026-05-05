import Foundation

//
//  ExportError.swift
//  Yay (cross-platform — shared by macOS and iOS exporters)
//

public enum ExportError: LocalizedError {
    case timeout
    case printFailed

    public var errorDescription: String? {
        switch self {
        case .timeout: return "PDF rendering timed out"
        case .printFailed: return "Failed to generate PDF"
        }
    }
}
