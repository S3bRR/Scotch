import Foundation
import CryptoKit
import Security

// Private material never leaves the macOS Keychain or appears in output.
let account = "com.s3brr.Scotch.runtime-updates"
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: account, kSecAttrAccount as String: "ed25519"]
func privateKey(create: Bool) throws -> Curve25519.Signing.PrivateKey {
    var lookup = query
    lookup[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data { return try .init(rawRepresentation: data) }
    guard status == errSecItemNotFound, create else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    let key = Curve25519.Signing.PrivateKey()
    var entry = query
    entry[kSecValueData as String] = key.rawRepresentation
    entry[kSecAttrLabel as String] = "Scotch runtime update signing key"
    let added = SecItemAdd(entry as CFDictionary, nil)
    guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
    return key
}
do {
    let args = CommandLine.arguments
    if args.count == 2 && args[1] == "public-key" {
        print(try privateKey(create: true).publicKey.rawRepresentation.base64EncodedString())
    } else if args.count == 4 && args[1] == "sign" {
        let payload = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let signature = try privateKey(create: false).signature(for: payload)
        let envelope = ["payload": payload.base64EncodedString(), "signature": signature.base64EncodedString()]
        try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    } else { throw NSError(domain: "RuntimeSigner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: RuntimeSigner public-key | sign payload.json signed-runtime.json"]) }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
