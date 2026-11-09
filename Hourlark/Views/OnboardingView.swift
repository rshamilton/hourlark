import SwiftUI
import SwiftData

private struct CauseDraft: Identifiable {
    let id = UUID()
    var name: String
    var symbol: String
    var tint: CauseColor
    var requiresSignOff: Bool
    var organization = ""
    var verifier = ""
    var goalText = ""
}

/// First-run setup: welcome, your name, what you track, then a short setup per cause.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("participantName") private var participant = ""
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("lastCauseID") private var lastCauseID = ""

    private enum Step: Int { case welcome, name, pick, setup, ready }
    @State private var showGuide = false

    @State private var step: Step = .welcome
    @State private var picked: [String] = []
    @State private var drafts: [CauseDraft] = []
    @State private var index = 0
    @State private var goingForward = true
    @State private var showRestore = false
    @State private var restoreURL: URL?
    @State private var iCloudBackup: URL?

    private var progress: Double {
        switch step {
        case .welcome: 0.08
        case .name: 0.25
        case .pick: 0.42
        case .setup: 0.5 + 0.4 * Double(index + 1) / Double(max(drafts.count, 1))
        case .ready: 1
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome, .name, .ready: true
        case .pick: !picked.isEmpty
        case .setup:
            drafts.indices.contains(index)
                && !drafts[index].name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var isLastSetupStep: Bool { step == .setup && index >= drafts.count - 1 }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .name: "Continue"
        case .pick: picked.count > 1 ? "Set Up \(picked.count) Causes" : "Continue"
        case .setup: isLastSetupStep ? "Continue" : "Next Cause"
        case .ready: "Start Tracking"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case .welcome: welcome
                case .name: nameStep
                case .pick: pickStep
                case .setup:
                    if drafts.indices.contains(index) { setupStep($drafts[index]).id(drafts[index].id) }
                case .ready: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)))
            footer
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .restoreFlow(isPresented: $showRestore, url: $restoreURL)
        .sheet(isPresented: $showGuide) { GuideView() }
        .task { iCloudBackup = await BackupManager.iCloudLatestBackupURL() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button { back() } label: { Image(systemName: "chevron.left").font(.body.weight(.semibold)) }
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
                .accessibilityLabel("Back")
            ProgressView(value: progress)
                .animation(.smooth, value: progress)
            Button("Skip") { onboardingDone = true }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        Button { advance() } label: {
            Text(primaryTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canContinue)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, step == .welcome ? 4 : 12)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if step == .welcome {
                VStack(spacing: 6) {
                    if let iCloudBackup {
                        Button { restoreURL = iCloudBackup } label: {
                            Label("Restore from my iCloud backup", systemImage: "icloud.and.arrow.down")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    Button("I have a backup file") { showRestore = true }
                        .font(.subheadline)
                }
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(Color.accentColor.gradient)
                    .padding(.top, 24)
                VStack(spacing: 8) {
                    Text("Welcome to Hourlark").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("Time, signed & sealed.").font(.title3).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    feature("lock.shield.fill", .green, "Private by design",
                            "No account, no ads and no Hourlark servers. Your hours are stored on this iPhone and backed up automatically to your own private iCloud Drive. You can turn that off in Settings.")
                    feature("timer", .blue, "Track anything",
                            "Volunteering, work, school, a side project. Make a cause for each.")
                    feature("signature", .orange, "Signatures are optional",
                            "Only if someone needs to verify your hours. You choose per cause, and most people won't need it.")
                }
                .padding(.horizontal, 8)
            }
            .padding(24)
        }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var nameStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                title("What's your name?",
                      "Only used to print your name on your own sheets and reports. It never leaves this iPhone.")
                TextField("Your full name", text: $participant)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .font(.title3)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                Text("Optional. You can skip this and add it later in Settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var pickStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                title("What will you track?",
                      "Pick everything that applies. These are just starting points, and you can rename or add more later.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(CauseTemplate.all) { template in
                        templateCard(template)
                    }
                }
            }
            .padding(24)
        }
    }

    private func templateCard(_ t: CauseTemplate) -> some View {
        let isOn = picked.contains(t.id)
        return Button {
            if isOn { picked.removeAll { $0 == t.id } } else { picked.append(t.id) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CauseBadge(symbol: t.symbol, tint: t.tint, size: 38)
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                Text(t.title).font(.headline).foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(t.blurb).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func setupStep(_ draft: Binding<CauseDraft>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    CauseBadge(symbol: draft.wrappedValue.symbol, tint: draft.wrappedValue.tint, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cause \(index + 1) of \(drafts.count)")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Set up your cause").font(.title2.bold())
                    }
                }

                TextField("Name (e.g. Food Bank)", text: draft.name)
                    .font(.title3)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Does anyone need to sign off on these hours?").font(.headline)
                    Text("Most people choose No. Choose Yes only if a supervisor, teacher or organization wants proof. You can change this later.")
                        .font(.footnote).foregroundStyle(.secondary)
                    choice(selected: draft.wrappedValue.requiresSignOff,
                           symbol: "signature", title: "Yes, someone has to sign",
                           detail: "You print a sheet, they sign the paper, and you photograph it as proof. They never need the app.") {
                        draft.wrappedValue.requiresSignOff = true
                    }
                    choice(selected: !draft.wrappedValue.requiresSignOff,
                           symbol: "person.fill", title: "No, nobody signs",
                           detail: "Just track your time. You can still export PDFs and spreadsheets whenever you like.") {
                        draft.wrappedValue.requiresSignOff = false
                    }
                }

                if draft.wrappedValue.requiresSignOff {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Who signs? (optional)").font(.headline)
                        TextField("Organization", text: draft.organization)
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        TextField("Supervisor's name", text: draft.verifier)
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Hours goal (optional)").font(.headline)
                    TextField("e.g. 40", text: draft.goalText)
                        .keyboardType(.decimalPad)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    Text("Shows your progress toward a required number of hours.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .animation(.smooth, value: draft.wrappedValue.requiresSignOff)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var readyStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                title("You're all set", "Here's what to know before you start.")
                VStack(alignment: .leading, spacing: 20) {
                    feature("lock.shield.fill", .green, "Private",
                            "Hourlark has no account, no ads and no servers, and never shares your data with anyone. Your own iCloud account holds your backup.")
                    feature("folder.fill", .blue, "Backed up automatically",
                            "Copies of your hours are saved in the Files app and in your own iCloud Drive. Turn the iCloud copy off any time in Settings, Backup & Files.")
                    feature("doc.richtext", .orange, "Reports for anyone",
                            "PDFs and spreadsheets work for every cause. Signatures are an extra, only when you need them.")
                }
                Button { showGuide = true } label: {
                    Label("See how printing, signing & reports work", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                Text("Optional. It's also in Settings any time.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func choice(selected: Bool, symbol: String, title: String, detail: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func title(_ text: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.largeTitle.bold())
            Text(detail).font(.body).foregroundStyle(.secondary)
        }
    }

    // MARK: Navigation

    private func go(forward: Bool, _ change: () -> Void) {
        goingForward = forward
        withAnimation(.smooth(duration: 0.35)) { change() }
    }

    private func advance() {
        switch step {
        case .welcome: go(forward: true) { step = .name }
        case .name: go(forward: true) { step = .pick }
        case .pick:
            drafts = CauseTemplate.all.filter { picked.contains($0.id) }.map {
                CauseDraft(name: $0.name, symbol: $0.symbol, tint: $0.tint, requiresSignOff: $0.requiresSignOff)
            }
            index = 0
            go(forward: true) { step = .setup }
        case .setup:
            if isLastSetupStep { go(forward: true) { step = .ready } } else { go(forward: true) { index += 1 } }
        case .ready: finish()
        }
    }

    private func back() {
        switch step {
        case .welcome: break
        case .setup where index > 0: go(forward: false) { index -= 1 }
        default: go(forward: false) { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
        }
    }

    private func finish() {
        var first: UUID?
        for d in drafts {
            let goal = Double(d.goalText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let cause = Cause(name: d.name.trimmingCharacters(in: .whitespaces),
                              organization: d.requiresSignOff ? d.organization : "",
                              supervisorName: d.requiresSignOff ? d.verifier : "",
                              symbol: d.symbol, tint: d.tint,
                              goalHours: max(0, goal), requiresSignOff: d.requiresSignOff)
            context.insert(cause)
            if first == nil { first = cause.uuid }
        }
        if let first { lastCauseID = first.uuidString }
        onboardingDone = true
    }
}
