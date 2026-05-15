import Foundation
import Quartz

// Ancla para encontrar el bundle del plugin en tiempo de ejecución
private final class PluginBundleMarker {}

@_cdecl("GeneratePreviewForURL")
func GeneratePreviewForURL(
    _ thisInterface: UnsafeMutableRawPointer?,
    _ preview: QLPreviewRequest,
    _ url: CFURL,
    _ contentTypeUTI: CFString,
    _ options: CFDictionary
) -> OSStatus {
    let fileURL = url as URL
    guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8),
          !QLPreviewRequestIsCancelled(preview) else {
        return noErr
    }

    let html = HTMLTemplate.build(body: MarkdownRenderer().render(markdown))
    guard let htmlData = html.data(using: .utf8) else { return noErr }

    // Carga los archivos JS desde los recursos del propio bundle del plugin
    let bundle = Bundle(for: PluginBundleMarker.self)
    var attachments: [String: Any] = [:]
    for name in ["highlight.min.js", "mermaid.min.js"] {
        if let jsURL = bundle.url(forResource: name, withExtension: nil),
           let data = try? Data(contentsOf: jsURL) {
            attachments[name] = [
                kQLPreviewPropertyMIMETypeKey as String: "application/javascript",
                kQLPreviewPropertyAttachmentDataKey as String: data
            ]
        }
    }

    // Los attachments se sirven al WebView interno de QL como URLs relativas,
    // que coinciden con los src="highlight.min.js" y src="mermaid.min.js" del HTML
    let props: [String: Any] = [
        kQLPreviewPropertyStringEncodingKey as String: NSNumber(value: String.Encoding.utf8.rawValue),
        kQLPreviewPropertyAttachmentsKey as String: attachments
    ]
    QLPreviewRequestSetDataRepresentation(
        preview,
        htmlData as CFData,
        "public.html" as CFString,
        props as CFDictionary
    )
    return noErr
}

@_cdecl("CancelPreviewGeneration")
func CancelPreviewGeneration(
    _ thisInterface: UnsafeMutableRawPointer?,
    _ preview: QLPreviewRequest
) {}

@_cdecl("GenerateThumbnailForURL")
func GenerateThumbnailForURL(
    _ thisInterface: UnsafeMutableRawPointer?,
    _ thumbnail: QLThumbnailRequest,
    _ url: CFURL,
    _ contentTypeUTI: CFString,
    _ options: CFDictionary,
    _ maxSize: CGSize
) -> OSStatus {
    return noErr
}

@_cdecl("CancelThumbnailGeneration")
func CancelThumbnailGeneration(
    _ thisInterface: UnsafeMutableRawPointer?,
    _ thumbnail: QLThumbnailRequest
) {}
