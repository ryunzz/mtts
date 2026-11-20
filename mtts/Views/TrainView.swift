import SwiftUI

struct TrainView: View {
    var body: some View {
        HSplitView {
            VocabularyColumn()
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            TrainDetail()
                .frame(minWidth: 520)
        }
    }
}

struct TrainDetail: View {
    var body: some View {
        Page {
            HeadphoneBanner()
            CaptureCard()
            TakesCard()
            SignalCheckCard()
        }
    }
}

private struct VocabularyColumn: View {
    @Environment(AppModel.self) private var model
    @State private var newWord = ""
    @State private var pendingDelete: String?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            List(selection: $model.selectedWord) {
                Section("Vocabulary") {
                    ForEach(model.dataset.vocabulary, id: \.self) { word in
                        WordRow(word: word, count: model.templates(for: word).count)
                            .tag(word)
                            .contextMenu {
                                Button("Delete “\(word)”…", role: .destructive) { pendingDelete = word }
                            }
                    }
                }
                Section("Gestures") {
                    WordRow(word: Template.displayName(Template.clickLabel),
                            count: model.clickTakeCount,
                            target: Layout.clickTakeTarget,
                            symbol: "cursorarrow.click.2")
                        .tag(Template.clickLabel)
                }
            }
            .listStyle(.inset)
            Divider()
            HStack(spacing: 8) {
                TextField("Add a word", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWord)
                Button("Add", systemImage: "plus", action: addWord)
                    .labelStyle(.iconOnly)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog(
            "Delete “\(pendingDelete ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { word in
            Button("Delete Word and \(model.allTakeCount(for: word)) Takes", role: .destructive) {
                model.removeWord(word)
            }
        } message: { word in
            Text("This removes “\(word)” and every take of it, including takes recorded with other headphones.")
        }
    }

    private func addWord() {
        model.addWord(newWord)
        newWord = ""
    }
}

private struct WordRow: View {
    var word: String
    var count: Int
    var target = Layout.takeTarget
    var symbol: String?

    var body: some View {
        HStack {
            if let symbol {
                Label(word, systemImage: symbol)
            } else {
                Text(word)
            }
            Spacer()
            if count >= target {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Text("\(count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct CaptureCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let word = model.selectedWord
        let count = word.map { model.templates(for: $0).count } ?? 0
        let isClick = word == Template.clickLabel
        Card(isClick ? "Record your click gesture" : word.map { "Record “\($0)”" } ?? "Choose a word",
             caption: isClick
                ? "Hold Space, do the motion you want to click with (say, open your mouth wide), release. Keep your head still. 5–8 takes."
                : "Silently mouth the word while holding Space. Keep your head still.") {
            TakeProgress(count: count, target: isClick ? Layout.clickTakeTarget : Layout.takeTarget)
        } content: {
            CapturePad(
                title: isClick ? "Do your click gesture" : word.map { "Mouth “\($0)”" } ?? "Pick a word on the left",
                isCapturing: model.capture.isCapturing,
                isEnabled: word != nil && model.motion.status == .streaming,
                onBegin: model.capture.begin,
                onEnd: model.capture.end)
        }
    }
}

private struct TakesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let word = model.selectedWord {
            let takes = Array(model.templates(for: word).reversed())
            Card("Takes", caption: "Rotation rate per take, newest first") {
                if takes.isEmpty {
                    Text(word == Template.clickLabel
                         ? "No takes yet. Hold Space and do your click gesture."
                         : "No takes yet. Hold Space and mouth “\(word)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(takes) { take in
                            TakeTile(template: take, isNew: take.id == model.lastTemplateID) {
                                model.deleteTemplate(take.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TakeTile: View {
    var template: Template
    var isNew: Bool
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SignalPlot(title: "", samples: template.samples, channels: SignalPlot.rotation,
                       minScale: 0.05, height: 46, showsHeader: false)
            HStack {
                Text(String(format: "%.2f s · %d frames", template.duration, template.samples.count))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Delete Take", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .opacity(hovering ? 1 : 0)
            }
        }
        .padding(8)
        .background(Color.subtleFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isNew ? Color.accentColor : .clear, lineWidth: 1.5))
        .onHover { hovering = $0 }
    }
}

/// Leave-one-out accuracy against shuffled labels: does the motion carry word information?
private struct SignalCheckCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card("Signal Check", caption: "Leave-one-out accuracy against \(500) shuffled-label runs") {
            Button(model.isEvaluating ? "Evaluating…" : "Evaluate") { model.evaluate() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isEvaluating || model.featureSet.isEmpty)
        } content: {
            HStack(spacing: 14) {
                Text("Channels").font(.callout).foregroundStyle(.secondary)
                FeatureToggle(title: "Acceleration", option: .acceleration)
                FeatureToggle(title: "Rotation", option: .rotation)
                FeatureToggle(title: "Attitude", option: .attitude)
            }
            if let result = model.evaluation {
                EvaluationResultView(result: result)
            } else {
                Text("Needs at least 2 words with 2 takes each. Each take is classified against the others, then the same is repeated with shuffled labels to show what chance looks like.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FeatureToggle: View {
    @Environment(AppModel.self) private var model
    var title: String
    var option: FeatureSet

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { model.featureSet.contains(option) },
            set: { on in
                if on { model.featureSet.insert(option) } else { model.featureSet.remove(option) }
            }))
        .toggleStyle(.checkbox)
    }
}

private struct EvaluationResultView: View {
    var result: Evaluation

    private var significant: Bool { result.pValue < 0.05 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                Metric(title: "Accuracy", value: percent(result.accuracy), tint: significant ? .green : .primary)
                Metric(title: "Chance", value: percent(result.chance))
                Metric(title: "Shuffled 95th pct", value: percent(result.permutationP95))
                Metric(title: "p-value", value: result.pValue < 0.001 ? "< 0.001" : String(format: "%.3f", result.pValue))
            }
            AccuracyBar(result: result)
            Label(verdict, systemImage: significant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(significant ? .green : .orange)
            ConfusionMatrix(result: result)
        }
    }

    private var verdict: String {
        significant
            ? "Motion tells these words apart better than chance across \(result.templateCount) takes."
            : "Not distinguishable from chance yet. Record more takes or try other channels."
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

/// Accuracy as a bar, with chance and the shuffled 95th percentile marked on the same scale.
private struct AccuracyBar: View {
    var result: Evaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(result.pValue < 0.05 ? Color.green : Color.orange)
                        .frame(width: width * result.accuracy)
                    tick(at: result.chance, width: width, color: .secondary)
                    tick(at: result.permutationP95, width: width, color: .primary)
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                legend(color: .secondary, text: "Chance")
                legend(color: .primary, text: "Shuffled 95th percentile")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func tick(at value: Double, width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: 14)
            .offset(x: width * min(max(value, 0), 1) - 1)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text(text)
        }
    }
}

private struct ConfusionMatrix: View {
    var result: Evaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Confusion matrix · rows are what you mouthed, columns what was predicted")
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(result.labels, id: \.self) { label in
                        Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ForEach(result.labels.indices, id: \.self) { row in
                    let total = max(result.confusion[row].reduce(0, +), 1)
                    GridRow {
                        Text(result.labels[row])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        ForEach(result.labels.indices, id: \.self) { col in
                            let count = result.confusion[row][col]
                            let share = Double(count) / Double(total)
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(count == 0 ? .tertiary : .primary)
                                .frame(minWidth: 38, minHeight: 26)
                                .background((row == col ? Color.accentColor : Color.orange).opacity(0.08 + share * 0.5),
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}
