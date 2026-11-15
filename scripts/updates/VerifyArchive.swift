import Foundation
import CryptoKit
let arguments = CommandLine.arguments
let bytes = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: "9yIFm7v7AZzHk/XRbF/ruSLj4BVXKGCG6RmaiO0Tz7k=")!)
guard let signature = Data(base64Encoded: arguments[2]), key.isValidSignature(signature, for: bytes) else {
    FileHandle.standardError.write(Data("App archive signature is invalid\n".utf8)); exit(1)
}
print("App archive EdDSA signature verified.")
