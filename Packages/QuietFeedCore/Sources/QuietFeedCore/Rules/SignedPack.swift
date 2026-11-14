import Foundation
import CryptoKit

/// The file the official rules host serves (Architecture 4.5). Signing the raw payload bytes means there is
/// no JSON canonicalisation to get wrong: the signature covers exactly the bytes that were base64 encoded.
public struct SignedPackEnvelope: Codable, Equatable, Sendable {
    public let keyId: String
    /// Base64 of the rule pack JSON bytes.
    public let payload: String
    /// Base64 of an Ed25519 signature over the payload bytes.
    public let signature: String

    public init(keyId: String, payload: String, signature: String) {
        self.keyId = keyId
        self.payload = payload
        self.signature = signature
    }
}

public enum VerifyError: Error, Equatable, Sendable {
    case malformedEnvelope
    case unknownKey
    case badSignature
    case badPayloadEncoding
}

/// Checks a signed envelope against the public keys built into the app.
public struct PackVerifier: Sendable {
    /// Raw 32 byte Ed25519 public keys by key id. Several keys allow rotation.
    public let publicKeys: [String: Data]

    public init(publicKeys: [String: Data]) {
        self.publicKeys = publicKeys
    }

    /// Returns the payload bytes only when the signature is valid for the key named in the envelope.
    /// Nothing in the payload is looked at before that.
    public func verify(_ envelopeData: Data) -> Result<Data, VerifyError> {
        guard let envelope = try? JSONDecoder().decode(SignedPackEnvelope.self, from: envelopeData) else {
            return .failure(.malformedEnvelope)
        }
        guard let raw = publicKeys[envelope.keyId],
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
            return .failure(.unknownKey)
        }
        guard let signature = Data(base64Encoded: envelope.signature) else {
            return .failure(.badSignature)
        }
        guard let payload = Data(base64Encoded: envelope.payload) else {
            return .failure(.badPayloadEncoding)
        }
        guard key.isValidSignature(signature, for: payload) else {
            return .failure(.badSignature)
        }
        return .success(payload)
    }
}
