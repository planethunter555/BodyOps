import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence（オンデバイスLLM）の利用可否。
/// FoundationModelsに依存しないファサードとして全OSバージョンから安全に呼べる。
enum OnDeviceAvailability: Equatable {
    case available
    case unavailable(reason: String)
    /// iOS 26未満、またはFoundationModels SDKなしでビルドされた場合
    case unsupportedOS

    static func check() -> OnDeviceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable(reason: "このデバイスはApple Intelligenceに対応していません")
                case .appleIntelligenceNotEnabled:
                    return .unavailable(reason: "設定アプリでApple Intelligenceを有効にしてください")
                case .modelNotReady:
                    return .unavailable(reason: "AIモデルをダウンロード中です。しばらくお待ちください")
                @unknown default:
                    return .unavailable(reason: "Apple Intelligenceは現在利用できません")
                }
            @unknown default:
                return .unavailable(reason: "Apple Intelligenceは現在利用できません")
            }
        }
        return .unsupportedOS
        #else
        return .unsupportedOS
        #endif
    }

    var isAvailable: Bool { self == .available }

    var statusDescription: String {
        switch self {
        case .available:
            return "利用可能"
        case .unavailable(let reason):
            return reason
        case .unsupportedOS:
            return "iOS 26以降で利用できます"
        }
    }
}
