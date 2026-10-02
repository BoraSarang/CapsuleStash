import Foundation
import Security

/// Credential 시크릿의 Keychain 보관소 (T-10).
/// library.json에는 홈페이지·아이디(비밀값 아님)만 두고,
/// password/secondSecret은 블록 ID 단위로 Keychain generic-password에 JSON으로 보관한다.
/// [HARD] 로그·에러 메시지에 비밀값을 포함하지 않는다.
enum KeychainStore {
    static let service = "com.borasarang.CapsuleStash.credential"

    /// 시크릿 페이로드 (비밀값만, 홈페이지·아이디 제외).
    struct Secrets: Codable {
        var password: String
        var secondSecret: String

        init(password: String = "", secondSecret: String = "") {
            self.password = password
            self.secondSecret = secondSecret
        }
    }

    /// 테스트 격리용. nil이 아니면 실제 Keychain 대신 메모리 딕셔너리를 쓴다.
    /// 키는 블록 ID 문자열, 값은 JSON 인코딩된 Secrets.
    static var inMemory: [String: Data]?

    // MARK: - 단건 CRUD

    static func save(blockId: UUID, secrets: Secrets) throws {
        let data = try JSONEncoder().encode(secrets)
        if inMemory != nil {
            inMemory?[blockId.uuidString] = data
            return
        }
        var query = baseQuery(blockId: blockId)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else { throw storeError(updateStatus) }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw storeError(addStatus) }
        } else {
            throw storeError(status)
        }
    }

    /// 없으면 nil (조용히). 그 외 실패는 에러 로그 후 nil.
    /// [HARD] 반환 외에는 비밀값을 어디에도 남기지 않는다.
    static func load(blockId: UUID) -> Secrets? {
        if let memory = inMemory {
            guard let data = memory[blockId.uuidString] else { return nil }
            return try? JSONDecoder().decode(Secrets.self, from: data)
        }
        var query = baseQuery(blockId: blockId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                DebugLogger.error(code: ErrorCode.keychain, "Keychain 조회 실패")
            }
            return nil
        }
        return try? JSONDecoder().decode(Secrets.self, from: data)
    }

    /// best-effort. 없음(errSecItemNotFound)은 정상으로 간주한다.
    static func delete(blockId: UUID) {
        if inMemory != nil {
            inMemory?.removeValue(forKey: blockId.uuidString)
            return
        }
        let status = SecItemDelete(baseQuery(blockId: blockId) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            DebugLogger.error(code: ErrorCode.keychain, "Keychain 삭제 실패")
        }
    }

    // MARK: - 일괄

    /// 저장 커밋 시 호출. 둘 다 비어 있으면 낡은 항목을 지운다.
    /// [HARD] 값 자체는 로그에 남기지 않고 블록 ID·건수만 기록한다.
    static func sync(_ entries: [(UUID, Secrets)]) {
        for (blockId, secrets) in entries {
            if secrets.password.isEmpty && secrets.secondSecret.isEmpty {
                delete(blockId: blockId)
            } else {
                do {
                    try save(blockId: blockId, secrets: secrets)
                } catch {
                    DebugLogger.error(code: ErrorCode.keychain, "Keychain 저장 실패: \(blockId.uuidString)")
                }
            }
        }
    }

    /// DebugPanel용 보관 건수. 실패 시 0 (조용히).
    static func count() -> Int {
        if let memory = inMemory { return memory.count }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess, let list = items as? [Any] else { return 0 }
        return list.count
    }

    // MARK: - 내부

    private static func baseQuery(blockId: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: blockId.uuidString,
        ]
    }

    private static func storeError(_ status: OSStatus) -> CapsuleError {
        CapsuleError.store(code: ErrorCode.keychain, message: "Keychain 오류 \(status)")
    }
}
