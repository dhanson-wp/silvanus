import SilvanusKit
import SwiftUI

/// The words Settings > Summaries and Home's model card share (docs/GLOSSARY.md).
enum ModelWords {
    static let modelDescription = "Writes to-dos and summaries. Nothing leaves your Mac."
    static let noModel = "No model yet"
    static let recommended = "Recommended for this Mac"
    static let checking = "Checking…"
    static let downloaded = "Downloaded"
    static let setup = "Silvanus writes your to-dos and a summary after each call, on this Mac."

    /// Where the model in use came from.
    static func source(_ source: LocalModelFile.Source?) -> String {
        switch source {
        case .downloaded: "Downloaded by Silvanus."
        case .chosen: "The file you chose."
        case nil: "Download one below, or choose a model file of your own."
        }
    }

    /// "7.4 GB download. Best with 24 GB of memory or more." One line: a row's description never wraps.
    static func about(_ model: CatalogModel) -> String {
        "\(LocalModelCatalog.size(model.bytes)) download. \(model.bestFor)"
    }

    /// "Gemma 4, 12B by Google · 7.4 GB download · Apache 2.0 license"
    static func offer(_ model: CatalogModel) -> String {
        "\(model.name) by Google · \(LocalModelCatalog.size(model.bytes)) download · \(LocalModelCatalog.licenseName) license"
    }

    /// How far along a model is, for the line beside its bar.
    static func progress(_ done: Int64, of model: CatalogModel) -> String {
        LocalModelCatalog.progress(done, of: model.bytes)
    }
}

/// Settings > Summaries: the model in use, the two models Silvanus can download (each
/// with its size, which Macs it suits, and where its download stands), a file of your own
/// through Choose…, and the models' license.
struct SummariesPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let inUse = model.summaryModel
        // Three-line rows, so a little air between them.
        VStack(alignment: .leading, spacing: Space.md) {
            SettingRow(title: "Model", description: ModelWords.modelDescription, footnote: ModelWords.source(inUse?.source)) {
                HStack(spacing: Space.sm) {
                    Text(inUse?.name ?? ModelWords.noModel)
                        .kitType(.rowTitle)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if inUse?.source == .chosen, model.summaryModels.hasDownloaded {
                        Button("Use Downloaded Model") { model.summaryModelPath = nil }
                            .buttonStyle(KitButtonStyle())
                            .help("Go back to the model Silvanus downloaded")
                    }
                    Button("Choose…") { model.chooseSummaryModel() }
                        .buttonStyle(KitButtonStyle())
                        .help("Use a GGUF model file you already have")
                        .accessibilityLabel("Choose a model file")
                }
            }
            ForEach(model.summaryModels.catalog) { item in
                let state = model.summaryModels.state(of: item)
                SettingRow(title: item.name, description: ModelWords.about(item), footnote: failure(state) ?? item.memoryNote,
                           badge: item.id == model.summaryModels.recommended?.id ? ModelWords.recommended : nil) {
                    ModelDownloadControl(item: item, state: state)
                }
            }
            SettingRow(title: "License", description: LocalModelCatalog.credit, footnote: LocalModelCatalog.conversionCredit) {
                Button("Gemma License") { NSWorkspace.shared.open(LocalModelCatalog.licenseURL) }
                    .buttonStyle(KitButtonStyle())
                    .help("Opens the Apache 2.0 license on ai.google.dev")
            }
        }
    }

    private func failure(_ state: SummaryModels.State) -> String? {
        if case let .failed(reason) = state { reason } else { nil }
    }
}

/// One model's download control, for Settings > Summaries and Home's model card:
/// Download; while it downloads, a bar, "2.1 of 7.4 GB", and Cancel; "Checking…" while
/// the file is checked; Downloaded and Remove once it's there; Resume for one that
/// stopped partway; Retry after a failure.
struct ModelDownloadControl: View {
    @Environment(AppModel.self) private var model
    let item: CatalogModel
    let state: SummaryModels.State
    /// Home's card has no room for Remove, and Settings does.
    var canRemove = true

    var body: some View {
        HStack(spacing: Space.sm) {
            switch state {
            case .notDownloaded:
                Button("Download") { model.summaryModels.download(item) }
                    .buttonStyle(KitButtonStyle())
                    .accessibilityLabel("Download \(item.name)")
            case let .partial(done):
                status(ModelWords.progress(done, of: item))
                if canRemove { remove }
                Button("Resume") { model.summaryModels.download(item) }
                    .buttonStyle(KitButtonStyle())
                    .accessibilityLabel("Resume downloading \(item.name)")
            case let .downloading(done):
                KitProgressBar(value: Double(done) / Double(max(item.bytes, 1)), label: "Downloading \(item.name)")
                status(ModelWords.progress(done, of: item))
                    .monospacedDigit()
                Button("Cancel") { model.summaryModels.cancel(item) }
                    .buttonStyle(KitButtonStyle())
                    .accessibilityLabel("Cancel downloading \(item.name)")
            case .checking:
                KitProgressBar(value: 1, label: "Checking \(item.name)")
                status(ModelWords.checking)
            case .downloaded:
                status(ModelWords.downloaded)
                if canRemove { remove }
            case .failed:
                Button("Retry") { model.summaryModels.download(item) }
                    .buttonStyle(KitButtonStyle())
                    .accessibilityLabel("Retry downloading \(item.name)")
            }
        }
        // The buttons and the bar keep their size; the words beside them give way.
        .fixedSize()
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .kitType(.rowTitle)
            .foregroundStyle(Ink.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var remove: some View {
        Button("Remove") { model.removeSummaryModel(item) }
            .buttonStyle(KitButtonStyle())
            .help("Delete this model's file from this Mac")
            .accessibilityLabel("Remove \(item.name)")
    }
}
