import UIKit
import XmaxSDK

enum RealtimeReferenceUploadState {
    case ready
    case uploading
    case failed
}

struct RealtimeReferenceCatalog: Decodable {
    final class Item: Decodable {
        let id: String
        let categoryID: String
        let title: String
        let iconURL: URL
        let prompt: String
        var referencePath: String?
        var uploadState: RealtimeReferenceUploadState

        var context: RealtimeContext? {
            guard uploadState == .ready,
                  let referencePath else {
                return nil
            }
            return RealtimeContext(
                prompt: prompt,
                referencePath: referencePath
            )
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case categoryID
            case title
            case iconURL
            case prompt
            case referencePath
        }

        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            id = try container.decode(String.self, forKey: .id)
            categoryID = try container.decode(
                String.self,
                forKey: .categoryID
            )
            title = try container.decode(String.self, forKey: .title)
            iconURL = try container.decode(URL.self, forKey: .iconURL)
            prompt = try container.decode(String.self, forKey: .prompt)
            referencePath = try container.decode(
                String.self,
                forKey: .referencePath
            )
            uploadState = .ready
        }

        init(categoryID: String, iconURL: URL, prompt: String) {
            id = "custom-\(UUID().uuidString)"
            self.categoryID = categoryID
            title = "自定义参考图"
            self.iconURL = iconURL
            self.prompt = prompt
            referencePath = nil
            uploadState = .uploading
        }
    }

    let items: [Item]

    static func load() -> RealtimeReferenceCatalog {
        guard
            let data = NSDataAsset(name: "RealtimeReferenceCatalog")?.data,
            let catalog = try? JSONDecoder().decode(
                RealtimeReferenceCatalog.self,
                from: data
            )
        else {
            return RealtimeReferenceCatalog(items: [])
        }
        return catalog
    }

    static func prompt(for categoryID: String) -> String {
        switch categoryID {
        case "charx":
            "视频中角色替换成参考图中角色"
        case "clothx":
            "视频中人物衣服替换成参考图中衣服"
        case "vibex":
            "视频风格变为参考图指定的风格"
        case "dimx":
            "指定角色在场景中互动"
        default:
            ""
        }
    }
}
