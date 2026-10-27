import Foundation

public enum ArtCNNError: Error, LocalizedError {
    case unavailable(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .invalidInput(message): message
        }
    }
}
