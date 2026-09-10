import Combine
import Foundation

/// XLab 的界面语言。
enum XLLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var title: String {
        switch self {
        case .system:
            XLLocalization.text("language.system")
        case .simplifiedChinese:
            "简体中文"
        case .english:
            "English"
        }
    }
}

/// UIKit 与 SwiftUI 共用的界面语言设置，不影响服务区域和生成内容。
@MainActor
final class XLLocalization: ObservableObject {
    // 共享实例与通知
    static let shared = XLLocalization()
    static let didChangeNotification = Notification.Name("XLabLanguageDidChange")

    // 持久化配置
    private nonisolated static let languageStorageKey = "xlab.language"

    // 语言状态
    @Published private(set) var language: XLLanguage

    private init() {
        language = Self.savedLanguage
    }

    /// 保存界面语言并通知已显示的页面刷新。
    ///
    /// - Parameter language: 用户选择的语言，或跟随系统。
    func setLanguage(_ language: XLLanguage) {
        guard language != self.language else { return }

        UserDefaults.standard.set(language.rawValue, forKey: Self.languageStorageKey)
        self.language = language
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// 当前界面的区域设置，可传入 SwiftUI 的 locale 环境。
    var locale: Locale {
        Locale(identifier: Self.languageCode)
    }

    /// 读取当前界面语言对应的文案。
    ///
    /// - Parameter key: Localizable 字符串目录中的键。
    /// - Returns: 本地化文案。
    nonisolated static func text(_ key: String) -> String {
        guard let url = Bundle.main.url(forResource: languageCode, withExtension: "lproj"),
              let bundle = Bundle(url: url) else {
            return Bundle.main.localizedString(forKey: key, value: nil, table: "Localizable")
        }

        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    /// 格式化带参数的本地化文案。
    ///
    /// - Parameters:
    ///   - key: Localizable 字符串目录中的键。
    ///   - arguments: 与文案占位符对应的参数。
    /// - Returns: 填入参数后的本地化文案。
    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: languageCode), arguments: arguments)
    }

    nonisolated static var languageCode: String {
        let language = savedLanguage
        guard language == .system else { return language.rawValue }

        return Bundle.preferredLocalizations(
            from: ["en", "zh-Hans"],
            forPreferences: Locale.preferredLanguages
        ).first ?? "en"
    }

    private nonisolated static var savedLanguage: XLLanguage {
        UserDefaults.standard.string(forKey: languageStorageKey)
            .flatMap(XLLanguage.init(rawValue:)) ?? .system
    }
}
