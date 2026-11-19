//
//  NewServiceScreen.swift
//  Volspire
//
//  Full service listing form, mirroring the web's service-create page:
//  identity (cover + type + gradient), details, packages & pricing,
//  what's included, how it works, portfolio, tags, FAQs, visibility —
//  with the pinned Publish CTA at the bottom.
//

import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct NewServiceScreen: View {
    @State var viewModel: NewServiceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCoverPicker = false
    @State private var showPortfolioPicker = false
    @State private var pickingPortfolioID: UUID?
    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var numberFieldFocused: Bool
    /// The open picker sheet (currency / a package's tier or revisions).
    @State private var picker: Picker?

    enum Picker: Identifiable {
        case currency
        case tier(UUID)
        case revisions(UUID)

        var id: String {
            switch self {
            case .currency: "currency"
            case let .tier(id): "tier-\(id)"
            case let .revisions(id): "revisions-\(id)"
            }
        }
    }

    private let tagSuggestions = [
        "mixing", "mastering", "trap", "r&b", "stems",
        "radio-ready", "fast-delivery", "budget",
    ]

    private let typeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var isSaving: Bool {
        viewModel.uploadState == .uploading
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    identitySection
                    detailsSection
                    packagesSection
                    includedSection
                    processSection
                    portfolioSection
                    tagsSection
                    faqsSection
                    // Active state isn't changed by update_service — hide on edit.
                    if !viewModel.isEditing { visibilitySection }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .tapToDismissKeyboard()
            // Hoisted from the package cards — attached per card, every extra
            // tier duplicated the Done button in the keyboard accessory.
            .doneKeyboardToolbar($numberFieldFocused)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        .gradientBackground()
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
        .sheet(item: $picker) { pickerSheet($0) }
        .fileImporter(
            isPresented: $showPortfolioPicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            guard let rowId = pickingPortfolioID else { return }
            pickingPortfolioID = nil
            if case .success(let urls) = result, let url = urls.first {
                viewModel.handlePortfolioFile(rowId: rowId, result: .success(url))
            } else if case .failure(let error) = result {
                viewModel.handlePortfolioFile(rowId: rowId, result: .failure(error))
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    viewModel.handleCoverImage(image)
                }
            }
        }
        .onChange(of: viewModel.uploadState) { _, newValue in
            if newValue == .success {
                dismiss()
            }
        }
    }

    // MARK: - Header + bottom bar

    private var header: some View {
        UploadFlowHeader(
            icon: .briefcase,
            title: viewModel.isEditing ? "Edit Service" : "New Service",
            subtitle: viewModel.isEditing ? "Update your service" : "Offer a service"
        ) { dismiss() }
    }

    private var bottomBar: some View {
        UploadBottomBar(error: viewModel.uploadState.errorMessage, hint: viewModel.validationHint) {
            PrimaryButton(
                viewModel.isEditing ? "Save Changes" : "Publish Service",
                busy: isSaving,
                enabled: viewModel.canPublish
            ) {
                Task { await viewModel.publish() }
            }
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Identity")

            HStack(alignment: .top, spacing: 16) {
                Button {
                    showCoverPicker = true
                } label: {
                    UploadCoverBox(image: viewModel.coverImage)
                }
                .buttonStyle(.plain)

                UploadCoverCaption(
                    text: "Optional cover image. When uploaded it replaces the gradient on tiles and the service page.",
                    hasCover: viewModel.coverImage != nil
                ) {
                    viewModel.clearCover()
                }
            }

            UploadFieldLabel("Service Type")
            LazyVGrid(columns: typeColumns, spacing: 8) {
                ForEach(serviceTypes) { type in
                    UploadTypeTile(
                        label: type.id,
                        icon: type.icon,
                        selected: viewModel.serviceType == type.id
                    ) {
                        viewModel.serviceType = type.id
                    }
                }
            }

            if viewModel.coverImage == nil {
                UploadFieldLabel("Cover Colour")
                UploadGradientPicker(options: serviceGradients, value: $viewModel.gradient)
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            UploadSectionDivider("Details")

            TextField(
                "",
                text: $viewModel.title,
                prompt: Text("e.g. Professional Stem Mix").foregroundStyle(Color.vText3)
            )
            .font(.appBody)
            .foregroundStyle(Color.vText)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .uploadFieldShell()
            .charLimited($viewModel.title, InputLimits.serviceTitle, singleLine: true)

            UploadDescriptionField(
                text: $viewModel.longDescription,
                prompt: "Describe your process, your sound, what makes your service stand out…",
                limit: InputLimits.serviceDescription,
                lines: 4...8
            )
        }
    }

    // MARK: - Packages & pricing

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Packages & Pricing")

            Text("Each tier sets its own price, delivery time, and revision count. The cheapest package becomes the listing's starting price.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            HStack(spacing: 12) {
                UploadFieldLabel("Currency")
                Button { picker = .currency } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.currency)
                            .font(.appFootnote)
                        LucideIcon(.chevronDown, .xs)
                    }
                    .foregroundStyle(Color.vText2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.vControl, in: Capsule())
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            ForEach($viewModel.packages) { $pkg in
                packageCard($pkg)
            }

            UploadDashedAddButton("Add another tier") {
                viewModel.packages.append(.init(name: "Standard"))
            }
        }
    }

    @ViewBuilder
    private func pickerSheet(_ picker: Picker) -> some View {
        switch picker {
        case .currency:
            ChoiceSheet(title: "Currency", subtitle: "For every package", icon: .tag,
                        choices: serviceCurrencies.map { currency in
                            SheetChoice(title: currency, selected: viewModel.currency == currency) {
                                viewModel.currency = currency
                            }
                        })
        case let .tier(id):
            let current = viewModel.packages.first { $0.id == id }?.name
            ChoiceSheet(title: "Package name", icon: .layers,
                        choices: servicePackageTiers.map { tier in
                            SheetChoice(title: tier, selected: current == tier) {
                                if let i = viewModel.packages.firstIndex(where: { $0.id == id }) {
                                    viewModel.packages[i].name = tier
                                }
                            }
                        })
        case let .revisions(id):
            let current = viewModel.packages.first { $0.id == id }?.revisions
            ChoiceSheet(title: "Revisions", subtitle: "Rounds included", icon: .refreshCw,
                        choices: serviceRevisionsOptions.map { option in
                            SheetChoice(title: option.label, selected: current == option.value) {
                                if let i = viewModel.packages.firstIndex(where: { $0.id == id }) {
                                    viewModel.packages[i].revisions = option.value
                                }
                            }
                        })
        }
    }

    private func packageCard(_ pkg: Binding<NewServiceViewModel.PackageDraft>) -> some View {
        let row = pkg.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { picker = .tier(row.id) } label: {
                    HStack(spacing: 4) {
                        Text(row.name)
                            .font(.appBodyMedium)
                            .foregroundStyle(Color.vText)
                        LucideIcon(.chevronDown, .xs)
                            .foregroundStyle(Color.vText3)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    viewModel.packages.removeAll { $0.id == row.id }
                } label: {
                    LucideIcon(.x, .md)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 36, height: 36)
                        .minimumHitArea(for: 36)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.packages.count == 1)
                .opacity(viewModel.packages.count == 1 ? 0.3 : 1)
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(currencySymbol(viewModel.currency))
                        .font(.appBody)
                        .foregroundStyle(Color.vText3)
                    TextField(
                        "",
                        text: pkg.price.decimalFiltered(),
                        prompt: Text("Price").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(Color.vText)
                    .keyboardType(.decimalPad)
                    .focused($numberFieldFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .uploadFieldShell()

                HStack(spacing: 6) {
                    TextField(
                        "",
                        text: Binding(
                            get: { pkg.wrappedValue.delivery },
                            set: { pkg.wrappedValue.delivery = $0.filter(\.isNumber) }
                        ),
                        prompt: Text("Days").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(Color.vText)
                    .keyboardType(.numberPad)
                    .focused($numberFieldFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .uploadFieldShell()

                Button { picker = .revisions(row.id) } label: {
                    HStack(spacing: 4) {
                        Text(row.revisions == "999" ? "∞" : row.revisions)
                            .font(.appBody)
                            .foregroundStyle(Color.vText)
                        LucideIcon(.chevronDown, .xs)
                            .foregroundStyle(Color.vText3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .uploadFieldShell()
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Text("Price · delivery days · revision rounds")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)

            UploadEditableList(
                items: pkg.features,
                placeholder: "Feature…",
                addLabel: "Add feature",
                compact: true
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.vCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.vBorder, lineWidth: 1)
        )
    }

    // MARK: - What's included

    private var includedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            UploadSectionDivider("What's Included")

            UploadEditableList(
                items: $viewModel.deliverables,
                placeholder: "e.g. Full stereo mix (WAV 24-bit)",
                addLabel: "Add item"
            )
        }
    }

    // MARK: - How it works

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            UploadSectionDivider("How It Works")

            Text("Walk buyers through your process step by step, numbered automatically.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            ForEach(Array(viewModel.processSteps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(Color.ink(0.06))
                        Circle().strokeBorder(Color.vBorder, lineWidth: 1)
                        Text("\(index + 1)")
                            .font(.appLabel)
                            .foregroundStyle(Color.vText3)
                    }
                    .frame(width: 26, height: 26)
                    .padding(.top, 8)

                    UploadTwoFieldRow(
                        title: Binding(
                            get: { viewModel.processSteps.first { $0.id == step.id }?.step ?? "" },
                            set: { newValue in
                                if let i = viewModel.processSteps.firstIndex(where: { $0.id == step.id }) {
                                    viewModel.processSteps[i].step = newValue
                                }
                            }
                        ),
                        detail: Binding(
                            get: { viewModel.processSteps.first { $0.id == step.id }?.description ?? "" },
                            set: { newValue in
                                if let i = viewModel.processSteps.firstIndex(where: { $0.id == step.id }) {
                                    viewModel.processSteps[i].description = newValue
                                }
                            }
                        ),
                        titlePlaceholder: "Step title…",
                        detailPlaceholder: "Describe what happens in this step…",
                        titleLimit: InputLimits.processStepTitle,
                        detailLimit: InputLimits.processStepDetail,
                        onRemove: viewModel.processSteps.count > 1
                            ? { viewModel.processSteps.removeAll { $0.id == step.id } }
                            : nil
                    )
                }
            }

            if viewModel.processSteps.count < InputLimits.serviceMaxItems {
                UploadDashedAddButton("Add Step") {
                    viewModel.processSteps.append(.init())
                }
            }
        }
    }

    // MARK: - Portfolio

    private var portfolioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Portfolio")

            Text("Showcase past work. Each entry needs a title and an audio file.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            UploadClipRows(
                clips: $viewModel.portfolio,
                titlePlaceholder: "Track / project title",
                addLabel: "Add Portfolio Item"
            ) { rowId in
                pickingPortfolioID = rowId
                showPortfolioPicker = true
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Tags")
            UploadTagInput(tags: $viewModel.tags, suggestions: tagSuggestions)
        }
    }

    // MARK: - FAQs

    private var faqsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            UploadSectionDivider("FAQs")

            Text("Optional: answer common buyer questions upfront.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            ForEach($viewModel.faqs) { $faq in
                UploadTwoFieldRow(
                    title: $faq.question,
                    detail: $faq.answer,
                    titlePlaceholder: "Question…",
                    detailPlaceholder: "Answer…",
                    titleLimit: InputLimits.faqQuestion,
                    detailLimit: InputLimits.faqAnswer,
                    onRemove: viewModel.faqs.count > 1
                        ? { viewModel.faqs.removeAll { $0.id == faq.id } }
                        : nil
                )
            }

            if viewModel.faqs.count < InputLimits.serviceMaxItems {
                UploadInlineAddButton("Add FAQ") {
                    viewModel.faqs.append(.init())
                }
            }
        }
    }

    // MARK: - Visibility

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Visibility")

            UploadVisibilityPicker(
                visibility: $viewModel.visibility,
                publicHint: "Public: appears in the marketplace and on your profile.",
                privateHint: "Private: hidden from the marketplace. You can make it public later from the service page."
            )
        }
    }
}
