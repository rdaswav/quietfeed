import XCTest
import CryptoKit
@testable import QuietFeedCore

final class SignedPackTests: XCTestCase {
    private let privateKey = Curve25519.Signing.PrivateKey()
    private let otherKey = Curve25519.Signing.PrivateKey()
    private let payload = Data("{\"schemaVersion\":1}".utf8)

    private var verifier: PackVerifier {
        PackVerifier(publicKeys: ["k1": privateKey.publicKey.rawRepresentation])
    }

    private func envelope(
        keyId: String = "k1", payload: Data? = nil, signWith: Curve25519.Signing.PrivateKey? = nil,
        payloadText: String? = nil, signatureText: String? = nil
    ) -> Data {
        let body = payload ?? self.payload
        let signature = try! (signWith ?? privateKey).signature(for: body)
        let env = SignedPackEnvelope(
            keyId: keyId,
            payload: payloadText ?? body.base64EncodedString(),
            signature: signatureText ?? signature.base64EncodedString())
        return try! JSONEncoder().encode(env)
    }

    func testValidEnvelopeReturnsThePayloadBytes() throws {
        XCTAssertEqual(try verifier.verify(envelope()).get(), payload)
    }

    func testTamperedPayloadIsRejected() {
        // Signed bytes differ from the bytes that were shipped.
        let signedFor = Data("{\"schemaVersion\":1}".utf8)
        let shipped = Data("{\"schemaVersion\":2}".utf8)
        let sig = try! privateKey.signature(for: signedFor).base64EncodedString()
        let data = envelope(payloadText: shipped.base64EncodedString(), signatureText: sig)
        XCTAssertEqual(verifier.verify(data), .failure(.badSignature))
    }

    func testTamperedSignatureIsRejected() {
        var sig = [UInt8](try! privateKey.signature(for: payload))
        sig[0] ^= 0x01
        let data = envelope(signatureText: Data(sig).base64EncodedString())
        XCTAssertEqual(verifier.verify(data), .failure(.badSignature))
    }

    func testSignedByTheWrongKeyIsRejected() {
        XCTAssertEqual(verifier.verify(envelope(signWith: otherKey)), .failure(.badSignature))
    }

    func testUnknownKeyIdIsRejected() {
        XCTAssertEqual(verifier.verify(envelope(keyId: "k2")), .failure(.unknownKey))
    }

    func testNoKeysAtAllRejectsEverything() {
        XCTAssertEqual(PackVerifier(publicKeys: [:]).verify(envelope()), .failure(.unknownKey))
    }

    func testAKeyOfTheWrongLengthIsTreatedAsUnknown() {
        let v = PackVerifier(publicKeys: ["k1": Data([1, 2, 3])])
        XCTAssertEqual(v.verify(envelope()), .failure(.unknownKey))
    }

    func testBadBase64IsRejected() {
        XCTAssertEqual(verifier.verify(envelope(payloadText: "not base64 !!")), .failure(.badPayloadEncoding))
        XCTAssertEqual(verifier.verify(envelope(signatureText: "not base64 !!")), .failure(.badSignature))
    }

    func testGarbageIsAMalformedEnvelope() {
        XCTAssertEqual(verifier.verify(Data("hello".utf8)), .failure(.malformedEnvelope))
        XCTAssertEqual(verifier.verify(Data("{\"keyId\":\"k1\"}".utf8)), .failure(.malformedEnvelope))
        XCTAssertEqual(verifier.verify(Data()), .failure(.malformedEnvelope))
    }

    func testAPlainRulePackIsNotAnEnvelope() throws {
        let plain = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("rules/rulepack.json"))
        XCTAssertEqual(verifier.verify(plain), .failure(.malformedEnvelope))
    }
}
