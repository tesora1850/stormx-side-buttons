// 화면 언어. 기본은 맥 시스템 언어를 따르고, 설정에서 직접 고를 수 있다.
// 문구는 tr("한국어", "English") 처럼 그 자리에서 두 언어를 같이 적는다.
// 언어를 추가하려면 AppLanguage 에 case 를 넣고 tr 에 인자를 하나 더 받으면 된다.

import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case system, ko, en

    var title: String {
        switch self {
        case .system: return tr("시스템 설정 따르기", "Follow system")
        case .ko: return "한국어"
        case .en: return "English"
        }
    }

    /// 실제로 쓸 언어 (system 이면 맥의 첫 번째 선호 언어로 정한다)
    var resolved: AppLanguage {
        guard self == .system else { return self }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? .ko : .en
    }
}

func tr(_ ko: String, _ en: String) -> String {
    Store.shared.settings.language.resolved == .ko ? ko : en
}
