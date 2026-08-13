import Foundation

enum InlineRoutineConfigError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case emptyPayload
    case invalidBase64URL
    case payloadTooLarge(maximumBytes: Int)
    case invalidUTF8
}

extension InlineRoutineConfigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "Routine link version \(version) is not supported."
        case .emptyPayload:
            return "The routine link does not contain a config payload."
        case .invalidBase64URL:
            return "The routine link payload is not valid Base64URL data."
        case let .payloadTooLarge(maximumBytes):
            return "The embedded routine config is larger than \(maximumBytes / 1024) KB."
        case .invalidUTF8:
            return "The embedded routine config must be UTF-8 text."
        }
    }
}

/// Decodes the versioned inline transport used by
/// `samoyed://import-routine?v=1&payload=<base64url>`.
///
/// Version 1 carries an unpadded Base64URL representation of a UTF-8 YAML
/// Routine Config. Structural and scheduling validation remains the
/// responsibility of `SamoyedPortableDayBlocks` after transport decoding.
struct SamoyedInlineRoutineConfigDecoder: Sendable {
    static let supportedVersion = 1
    static let defaultMaximumBytes = 32 * 1024

    private let maximumBytes: Int

    init(maximumBytes: Int = defaultMaximumBytes) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
    }

    func decode(version: Int, payload: String) throws -> String {
        guard version == Self.supportedVersion else {
            throw InlineRoutineConfigError.unsupportedVersion(version)
        }
        guard !payload.isEmpty else {
            throw InlineRoutineConfigError.emptyPayload
        }

        let maximumEncodedCharacters = ((maximumBytes + 2) / 3) * 4
        guard payload.utf8.count <= maximumEncodedCharacters else {
            throw InlineRoutineConfigError.payloadTooLarge(maximumBytes: maximumBytes)
        }
        guard payload.utf8.allSatisfy(Self.isBase64URLCharacter) else {
            throw InlineRoutineConfigError.invalidBase64URL
        }

        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        switch base64.utf8.count % 4 {
        case 0:
            break
        case 2:
            base64.append("==")
        case 3:
            base64.append("=")
        default:
            throw InlineRoutineConfigError.invalidBase64URL
        }

        guard let data = Data(base64Encoded: base64) else {
            throw InlineRoutineConfigError.invalidBase64URL
        }
        guard data.count <= maximumBytes else {
            throw InlineRoutineConfigError.payloadTooLarge(maximumBytes: maximumBytes)
        }
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw InlineRoutineConfigError.invalidUTF8
        }
        return yaml
    }

    private static func isBase64URLCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122:
            return true
        default:
            return false
        }
    }
}
