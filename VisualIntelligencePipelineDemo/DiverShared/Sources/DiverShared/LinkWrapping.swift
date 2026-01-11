import CryptoKit
import Foundation

public struct DiverLinkPayload: Codable, Equatable, Hashable, Sendable {
    public let url: String
    public let title: String?

    public init(url: URL, title: String? = nil) {
        self.url = url.absoluteString
        self.title = title
    }

    public var resolvedURL: URL? {
        URL(string: url)
    }
}

public struct DiverLink: Equatable {
    public let id: String
    public let version: Int
    public let signature: String
    public let payload: String?
}

public enum DiverLinkError: Error, Equatable {
    case invalidURL
    case invalidPath
    case missingSignature
    case invalidVersion
    case invalidSignature
    case invalidPayload
}

public enum DiverLinkWrapper {
    public static let baseURL = URL(string: "https://secretatomics.com")!
    public static let currentVersion = 1

    public static func id(for url: URL, salt: String? = nil, length: Int = 24) -> String {
        var input = url.absoluteString
        if let salt, !salt.isEmpty {
            input += "|" + salt
        }

        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(length))
    }

    public static func wrap(
        url: URL,
        secret: Data,
        payload: DiverLinkPayload? = nil,
        salt: String? = nil,
        includePayload: Bool = true
    ) throws -> URL {
        let id = id(for: url, salt: salt)
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.path = "/w/\(id)"

        var payloadValue: String?
        var queryItems = [URLQueryItem(name: "v", value: String(currentVersion))]

        if includePayload, let payload {
            let payloadData = try JSONEncoder().encode(payload)
            payloadValue = base64urlEncode(payloadData)
            queryItems.append(URLQueryItem(name: "p", value: payloadValue))
        }

        let signature = sign(id: id, version: currentVersion, payload: payloadValue, secret: secret)
        queryItems.append(URLQueryItem(name: "sig", value: signature))

        components.queryItems = queryItems

        guard let wrapped = components.url else {
            throw DiverLinkError.invalidURL
        }

        return wrapped
    }

    public static func parse(_ url: URL) throws -> DiverLink {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DiverLinkError.invalidURL
        }

        let pathComponents = components.path.split(separator: "/").map(String.init)
        guard pathComponents.count == 2, pathComponents.first == "w" else {
            throw DiverLinkError.invalidPath
        }

        let id = pathComponents[1]
        let queryItems = components.queryItems ?? []
        let pairs: [(String, String)] = queryItems.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        }
        let queryMap = Dictionary(uniqueKeysWithValues: pairs)

        guard let sig = queryMap["sig"], !sig.isEmpty else {
            throw DiverLinkError.missingSignature
        }

        guard let versionString = queryMap["v"], let version = Int(versionString) else {
            throw DiverLinkError.invalidVersion
        }

        return DiverLink(
            id: id,
            version: version,
            signature: sig,
            payload: queryMap["p"]
        )
    }

    public static func verify(_ link: DiverLink, secret: Data) -> Bool {
        let expected = sign(id: link.id, version: link.version, payload: link.payload, secret: secret)
        return expected == link.signature
    }

    public static func resolvePayload(from url: URL, secret: Data) throws -> DiverLinkPayload? {
        let link = try parse(url)
        guard verify(link, secret: secret) else {
            throw DiverLinkError.invalidSignature
        }

        guard let payload = link.payload else {
            return nil
        }

        guard let data = base64urlDecode(payload) else {
            throw DiverLinkError.invalidPayload
        }

        return try JSONDecoder().decode(DiverLinkPayload.self, from: data)
    }

    private static func sign(id: String, version: Int, payload: String?, secret: Data) -> String {
        let payloadValue = payload ?? ""
        let message = "v=\(version)&id=\(id)&p=\(payloadValue)"
        let key = SymmetricKey(data: secret)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return base64urlEncode(Data(signature))
    }

    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64urlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}
