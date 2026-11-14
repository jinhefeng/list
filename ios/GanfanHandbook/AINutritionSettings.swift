import Foundation
import Security
import SwiftUI
import UIKit

struct AIServiceConfiguration {
    var endpoint: String
    var model: String
    var enabled: Bool

    var completionURL: URL? {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let base = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base.hasSuffix("/chat/completions") ? base : base + "/chat/completions")
    }
}

@MainActor
enum AISettingsStore {
    private static let endpointKey = "ganfan.ai.endpoint.v1"
    private static let modelKey = "ganfan.ai.model.v1"
    private static let enabledKey = "ganfan.ai.enabled.v1"
    private static let keychainService = "cn.ganfanhandbook.ai-nutrition"
    private static let keychainAccount = "provider-api-key"

    static func load() -> AIServiceConfiguration {
        AIServiceConfiguration(
            endpoint: UserDefaults.standard.string(forKey: endpointKey) ?? "https://api.openai.com/v1",
            model: UserDefaults.standard.string(forKey: modelKey) ?? "",
            enabled: UserDefaults.standard.bool(forKey: enabledKey)
        )
    }

    static var isReady: Bool {
        let config = load()
        return config.enabled && config.completionURL != nil &&
            !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !(apiKey() ?? "").isEmpty
    }

    static func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ configuration: AIServiceConfiguration, newKey: String) throws {
        guard configuration.completionURL != nil,
              !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AISettingsError.invalidConfiguration
        }
        let normalizedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedKey.isEmpty {
            try storeKey(normalizedKey)
        }
        if configuration.enabled && (apiKey() ?? "").isEmpty {
            throw AISettingsError.missingKey
        }
        UserDefaults.standard.set(configuration.endpoint, forKey: endpointKey)
        UserDefaults.standard.set(configuration.model, forKey: modelKey)
        UserDefaults.standard.set(configuration.enabled, forKey: enabledKey)
    }

    static func clearKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    private static func storeKey(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw AISettingsError.keychainFailure
            }
        } else if status != errSecSuccess {
            throw AISettingsError.keychainFailure
        }
    }
}

enum AISettingsError: LocalizedError {
    case invalidConfiguration
    case missingKey
    case keychainFailure
    case noPhoto
    case invalidResponse
    case invalidRecognition
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "请输入有效的 HTTPS API 地址及模型名称。"
        case .missingKey: "启用 AI 识别需要先保存 API Key。"
        case .keychainFailure: "无法将 API Key 安全保存到本机钥匙串。"
        case .noPhoto: "无法读取可分析的照片。"
        case .invalidResponse: "模型没有返回可识别的结果。"
        case .invalidRecognition: "识别结果格式不正确，请重试或手动记录。"
        case .httpError(let status): "模型 API 请求失败（HTTP \(status)），请检查配置或额度。"
        }
    }
}

struct AIFoodRecognition: Decodable {
    let dishName: String
    let ingredients: [EstimatedFoodIngredient]
}

@MainActor
struct AIPhotoNutritionService {
    func recognize(photo: Data, configuration: AIServiceConfiguration, apiKey: String) async throws -> AIFoodRecognition {
        guard let endpoint = configuration.completionURL else { throw AISettingsError.invalidConfiguration }
        guard let original = UIImage(data: photo), original.size.width > 0,
              original.size.height > 0 else { throw AISettingsError.noPhoto }

        // Re-render to JPEG to strip GPS/EXIF and avoid sending the original high-resolution asset.
        let ratio = min(1, 1024 / max(original.size.width, original.size.height))
        let imageSize = CGSize(width: max(1, original.size.width * ratio),
                               height: max(1, original.size.height * ratio))
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let resized = renderer.image { _ in original.draw(in: CGRect(origin: .zero, size: imageSize)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.65) else { throw AISettingsError.noPhoto }

        let instructions = """
        你是食物图片识别助手。请只输出 JSON 对象，格式：
        {"dishName":"菜品名","ingredients":[{"name":"食材名","grams":120}]}
        尝试拆分可见的主要食材并估计每种食材的克数，考虑可能存在的烹调用油。
        不能确认的食材或数量请保守估算，不要声称测量准确。最多列出 12 种食材。
        不要输出 Markdown、卡路里或其他无关字段。若无法看清，ingredients 返回空数组。
        """
        let base64 = jpeg.base64EncodedString()
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": [
                    ["type": "text", "text": "识别这张菜品照片并估计分量。"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                ]]
            ],
            "max_tokens": 700
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AISettingsError.invalidResponse }
        guard http.statusCode == 200 else { throw AISettingsError.httpError(http.statusCode) }

        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let content = try JSONDecoder().decode(Completion.self, from: data).choices.first?.message.content,
              let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") else {
            throw AISettingsError.invalidResponse
        }
        let json = Data(content[start...end].utf8)
        guard let result = try? JSONDecoder().decode(AIFoodRecognition.self, from: json),
              !result.dishName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.ingredients.count <= 12 else {
            throw AISettingsError.invalidRecognition
        }
        return result
    }
}

struct AINutritionSettingsView: View {
    @State private var endpoint = "https://api.openai.com/v1"
    @State private var model = ""
    @State private var secret = ""
    @State private var enabled = false
    @State private var hasSavedKey = false
    @State private var feedback: String?

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI 拍照识别", isOn: $enabled)
                TextField("API 地址（HTTPS）", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("支持图片理解的模型 ID", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(hasSavedKey ? "已保存密钥；留空则不修改" : "API Key", text: $secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("仅在配置完整并启用时，菜品记录中才会显示 AI 识别入口。图片仅在您主动点击识别并确认后上传给配置的服务商，可能产生 API 费用。")
            }

            Section {
                Button("保存设置") {
                    do {
                        try AISettingsStore.save(AIServiceConfiguration(endpoint: endpoint, model: model, enabled: enabled),
                                                 newKey: secret)
                        secret = ""
                        hasSavedKey = AISettingsStore.apiKey() != nil
                        feedback = "设置已保存"
                    } catch {
                        feedback = error.localizedDescription
                    }
                }
                Button("删除 API Key 并关闭识别", role: .destructive) {
                    AISettingsStore.clearKey()
                    secret = ""
                    enabled = false
                    hasSavedKey = false
                    feedback = "API Key 已从本机删除"
                }
                .disabled(!hasSavedKey)
            }
            if let feedback {
                Section { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .navigationTitle("AI 模型设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let config = AISettingsStore.load()
            endpoint = config.endpoint
            model = config.model
            enabled = config.enabled
            hasSavedKey = AISettingsStore.apiKey() != nil
        }
    }
}
