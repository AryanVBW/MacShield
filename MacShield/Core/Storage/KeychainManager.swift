import Foundation
import Security
import CryptoKit
import CommonCrypto

/// Manages secure storage of passwords (and a tamper-resistant settings backup) in the macOS Keychain.
///
/// Accounts under service `com.macshield.app`:
/// - `backup-password` — the global backup password (shared fallback / Settings gate).
/// - `app-password:<bundleID>` — an optional per-app privacy password.
/// - `protected-apps-v1` — a raw-JSON backup of the protected-apps list (integrity, not secrecy).
///
/// Password records are stored as `v3:<iterations>:<saltHex>:<dkHex>` — PBKDF2-HMAC-SHA256.
/// Older `v2:<saltHex>:<sha256Hex>` (single-iteration salted SHA-256) records still verify and are
/// transparently re-stretched to v3 on the next successful unlock. PBKDF2 makes an extracted hash
/// expensive to brute-force offline; the comparison is constant-time.
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.macshield.app"
    private let backupAccount = "backup-password"
    private let protectedAppsAccount = "protected-apps-v1"

    /// PBKDF2 work factor. Stored inside each record so it can be raised later without
    /// invalidating existing passwords (they re-stretch on next unlock).
    /// ponytail: tuned for ~50–150 ms on Apple Silicon; raise as hardware improves.
    private static let pbkdf2Iterations = 210_000
    private static let saltByteCount = 16
    private static let keyByteCount = 32

    /// Keychain account name for an app-specific privacy password.
    private func account(for bundleIdentifier: String) -> String {
        "app-password:\(bundleIdentifier)"
    }

    private init() {}

    // MARK: - Global Backup Password

    @discardableResult
    func savePassword(_ password: String) -> Bool { save(password, account: backupAccount) }

    func verifyPassword(_ password: String) -> Bool { verify(password, account: backupAccount) }

    func hasPassword() -> Bool { has(account: backupAccount) }

    @discardableResult
    func deletePassword() -> Bool { delete(account: backupAccount) }

    // MARK: - Per-App Privacy Password

    @discardableResult
    func savePassword(_ password: String, forApp bundleIdentifier: String) -> Bool {
        save(password, account: account(for: bundleIdentifier))
    }

    func verifyPassword(_ password: String, forApp bundleIdentifier: String) -> Bool {
        verify(password, account: account(for: bundleIdentifier))
    }

    func hasPassword(forApp bundleIdentifier: String) -> Bool {
        has(account: account(for: bundleIdentifier))
    }

    @discardableResult
    func deletePassword(forApp bundleIdentifier: String) -> Bool {
        delete(account: account(for: bundleIdentifier))
    }

    // MARK: - Protected-Apps Integrity Backup (raw data, not a password)

    /// Persist a tamper-resistant copy of the protected-apps list.
    @discardableResult
    func saveProtectedAppsBackup(_ data: Data) -> Bool {
        setData(data, account: protectedAppsAccount)
    }

    /// Load the protected-apps backup, if any.
    func loadProtectedAppsBackup() -> Data? {
        getData(account: protectedAppsAccount)
    }

    // MARK: - Password Verify / Save (account-keyed)

    @discardableResult
    private func save(_ password: String, account: String) -> Bool {
        guard let data = Self.makeHashRecord(password).data(using: .utf8) else { return false }
        return setData(data, account: account)
    }

    private func verify(_ password: String, account: String) -> Bool {
        guard let stored = retrieve(account: account) else { return false }
        let result = Self.matches(password, record: stored)
        // Transparently re-stretch legacy/under-iterated records to the current v3 target.
        if result.ok && result.needsUpgrade { save(password, account: account) }
        return result.ok
    }

    // MARK: - Raw Keychain Storage (account-keyed)

    @discardableResult
    private func setData(_ data: Data, account: String) -> Bool {
        delete(account: account)   // avoid SecItemAdd collisions
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func getData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private func retrieve(account: String) -> String? {
        guard let data = getData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func has(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    @discardableResult
    private func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Hashing

    /// Build a `v3:<iterations>:<saltHex>:<dkHex>` PBKDF2 record for a new password.
    private static func makeHashRecord(_ password: String) -> String {
        let salt = randomSalt(saltByteCount)
        guard let dk = pbkdf2(password: password, salt: salt, iterations: pbkdf2Iterations, keyLength: keyByteCount) else {
            // PBKDF2 should never fail; fall back to salted SHA-256 so we never store plaintext.
            let saltHex = hex(salt)
            return "v2:\(saltHex):\(sha256Hex(salt: saltHex, password: password))"
        }
        return "v3:\(pbkdf2Iterations):\(hex(salt)):\(hex(dk))"
    }

    /// Compare `password` against a stored record. Reports whether the record uses an
    /// older format / weaker work factor that should be re-stretched on success.
    private static func matches(_ password: String, record: String) -> (ok: Bool, needsUpgrade: Bool) {
        let parts = record.components(separatedBy: ":")

        // v3: PBKDF2-HMAC-SHA256
        if parts.count == 4, parts[0] == "v3",
           let iterations = Int(parts[1]),
           let salt = bytes(fromHex: parts[2]),
           let dk = pbkdf2(password: password, salt: salt, iterations: iterations, keyLength: keyByteCount) {
            let ok = constantTimeEqual(hex(dk), parts[3])
            return (ok, ok && iterations < pbkdf2Iterations)
        }

        // v2: single-iteration salted SHA-256 (legacy) — verify, then upgrade to v3.
        if parts.count == 3, parts[0] == "v2" {
            let ok = constantTimeEqual(sha256Hex(salt: parts[1], password: password), parts[2])
            return (ok, ok)
        }

        // Legacy plaintext — verify, then upgrade to v3.
        let ok = (record == password)
        return (ok, ok)
    }

    /// PBKDF2-HMAC-SHA256 derivation. Returns nil only on an internal CommonCrypto failure.
    private static func pbkdf2(password: String, salt: [UInt8], iterations: Int, keyLength: Int) -> [UInt8]? {
        var derivedKey = [UInt8](repeating: 0, count: keyLength)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, password.utf8.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            &derivedKey, keyLength
        )
        return Int(status) == kCCSuccess ? derivedKey : nil
    }

    /// Salted SHA-256 hex digest of `salt + password` (legacy v2 verification only).
    private static func sha256Hex(salt: String, password: String) -> String {
        SHA256.hash(data: Data((salt + password).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomSalt(_ count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8.random(in: 0...255) }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func bytes(fromHex string: String) -> [UInt8]? {
        guard string.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    /// Length-then-content comparison with no early exit on the content bytes.
    /// Hash outputs are fixed length, so the length branch leaks nothing useful.
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }

    // MARK: - Self-Check (DEBUG)

    #if DEBUG
    /// Pure, side-effect-free check of the hashing + account-derivation contract.
    /// Touches no Keychain state. Returns true when every invariant holds.
    static func _selfCheck() -> Bool {
        // 1. v3 PBKDF2 round-trip: correct verifies, wrong does not, no upgrade needed.
        let record = makeHashRecord("hunter2")
        guard record.hasPrefix("v3:\(pbkdf2Iterations):") else { return false }
        let good = matches("hunter2", record: record)
        guard good.ok, !good.needsUpgrade else { return false }
        guard !matches("hunter2 ", record: record).ok else { return false }

        // 2. Salt is random: two records for the same password differ.
        guard makeHashRecord("hunter2") != makeHashRecord("hunter2") else { return false }

        // 3. Legacy v2 still verifies and is flagged for upgrade to v3.
        let salt = "00112233445566778899aabbccddeeff"
        let v2 = "v2:\(salt):\(sha256Hex(salt: salt, password: "legacy"))"
        let v2match = matches("legacy", record: v2)
        guard v2match.ok, v2match.needsUpgrade else { return false }
        guard !matches("nope", record: v2).ok else { return false }

        // 4. Constant-time equality is correct for equal, unequal, and length-mismatch.
        guard constantTimeEqual("abcd", "abcd"),
              !constantTimeEqual("abcd", "abce"),
              !constantTimeEqual("ab", "abcd") else { return false }

        // 5. Accounts are namespaced.
        let m = shared
        guard m.account(for: "com.a") != m.account(for: "com.b"),
              m.account(for: "com.a") != m.backupAccount,
              m.account(for: "com.a") != m.protectedAppsAccount,
              m.account(for: "com.a").hasPrefix("app-password:") else { return false }

        return true
    }
    #endif
}
