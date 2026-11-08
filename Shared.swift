import Foundation

enum RCConst {
    static let scheme = "superrightclick"
    static let appID = "com.superrightclick.app"
    static let extensionID = "com.superrightclick.app.FinderExtension"
}

enum RCAction: Int {
    case cut = 1
    case paste = 2
    case openTerminal = 3
    case screenshot = 4
    case deleteForever = 5

    case newTxt = 10
    case newMd = 11
    case newDocx = 12
    case newXlsx = 13
    case newPptx = 14
    case newPy = 15
    case newHtml = 16
    case newJson = 17

    case copyPath = 30
    case copyName = 31
    case copyDirPath = 32

    case moveTo = 40
    case copyTo = 41
    case batchRename = 42
    case zip = 43
    case toggleHidden = 44
}

/// 扩展 -> 主程序 的请求，编码进 URL：superrightclick://run?d=<base64url(JSON)>
struct RCPayload: Codable {
    var a: Int          // 动作
    var p: [String]     // 选中的文件路径
    var t: String?      // 当前所在文件夹

    func url() -> URL? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "\(RCConst.scheme)://run?d=\(b64)")
    }
}

extension RCPayload {
    init?(url: URL) {
        guard url.scheme == RCConst.scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var b64 = comps.queryItems?.first(where: { $0.name == "d" })?.value else { return nil }
        b64 = b64.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONDecoder().decode(RCPayload.self, from: data) else { return nil }
        self = obj
    }
}
