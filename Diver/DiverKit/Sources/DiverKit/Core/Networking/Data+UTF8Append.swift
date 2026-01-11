import Foundation

extension Data {
    mutating func appendUTF8String(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}

