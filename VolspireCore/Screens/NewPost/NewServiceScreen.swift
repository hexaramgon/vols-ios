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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        .gradientBackground()
        .photosPicker(isPresented: $showCoverPicker, selection: $selectedPhoto, matching: .images)
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
        VStack(spacing: 10) {
            if case .error(let message) = viewModel.uploadState {
                statusRow(message, color: UploadTheme.errorText)
            } else if let hint = viewModel.validationHint {
                statusRow(hint, color: Color.vText3)
            }

            Button {
                Task { await viewModel.publish() }
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(isSaving ? "Saving…" : (viewModel.isEditing ? "Save Changes" : "Publish Service"))
                        .font(.appHeadline)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canPublish || isSaving)
            .opacity(viewModel.canPublish && !isSaving ? 1 : 0.3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            // Same chrome tone as the Library header / tab bar (~#121212).
            Color(white: 0.07)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.vBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        }
    }

    private func statusRow(_ message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIcon(.triangleAlert, .sm)
                .foregroundStyle(color)
            Text(message)
                .font(.appFootnote)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Identity")

            HStack(alignment: .top, spacing: 16) {
                Button {
                    showCoverPicker = true
                } label: {
                    coverBox
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional cover image. When uploaded it replaces the gradient on tiles and the service page.")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText3)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.coverImage != nil {
                        Button {
                            viewModel.clearCover()
                        } label: {
                            HStack(spacing: 6) {
                                LucideIcon(.x, .xs)
                                Text("Remove cover")
                                    .font(.appFootnote)
                            }
                            .foregroundStyle(Color.vText3)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
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

    private var coverBox: some View {
        ZStack {
            if let img = viewModel.coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                UploadTheme.fieldFill
                VStack(spacing: 6) {
                    LucideIcon(.image, .lg)
                        .foregroundStyle(Color.vText3)
                    Text("Cover art")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if viewModel.coverImage == nil {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
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
            .foregroundStyle(.white)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .uploadFieldShell()
            .onChange(of: viewModel.title) { _, newValue in
                if newValue.count > 80 {
                    viewModel.title = String(newValue.prefix(80))
                }
            }

            VStack(alignment: .trailing, spacing: 4) {
                TextField(
                    "",
                    text: $viewModel.longDescription,
                    prompt: Text("Describe your process, your sound, what makes your service stand out…")
                        .foregroundStyle(Color.vText3),
                    axis: .vertical
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .lineLimit(4...8)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .uploadFieldShell()
                .onChange(of: viewModel.longDescription) { _, newValue in
                    if newValue.count > 1000 {
                        viewModel.longDescription = String(newValue.prefix(1000))
                    }
                }

                Text("\(viewModel.longDescription.count)/1000")
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
            }
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
                Menu {
                    ForEach(serviceCurrencies, id: \.self) { currency in
                        Button(currency) {
                            viewModel.currency = currency
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.currency)
                            .font(.appFootnote)
                        LucideIcon(.chevronDown, .xs)
                    }
                    .foregroundStyle(Color.vText2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(UploadTheme.border, lineWidth: 1))
                    .contentShape(.rect)
                }
                Spacer()
            }

            ForEach($viewModel.packages) { $pkg in
                packageCard($pkg)
            }

            Button {
                viewModel.packages.append(.init(name: "Standard"))
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(.plus, .sm)
                    Text("Add another tier")
                        .font(.appCallout)
                }
                .foregroundStyle(Color.vText3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func packageCard(_ pkg: Binding<NewServiceViewModel.PackageDraft>) -> some View {
        let row = pkg.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(servicePackageTiers, id: \.self) { tier in
                        Button(tier) {
                            pkg.wrappedValue.name = tier
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(row.name)
                            .font(.appBodyMedium)
                            .foregroundStyle(.white)
                        LucideIcon(.chevronDown, .xs)
                            .foregroundStyle(Color.vText3)
                    }
                    .contentShape(.rect)
                }

                Spacer()

                Button {
                    viewModel.packages.removeAll { $0.id == row.id }
                } label: {
                    LucideIcon(.x, .sm)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
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
                        text: Binding(
                            get: { pkg.wrappedValue.price },
                            set: { pkg.wrappedValue.price = $0.filter { "0123456789.".contains($0) } }
                        ),
                        prompt: Text("Price").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
                    .keyboardType(.numberPad)
                    .focused($numberFieldFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .uploadFieldShell()

                Menu {
                    ForEach(serviceRevisionsOptions, id: \.value) { option in
                        Button(option.label) {
                            pkg.wrappedValue.revisions = option.value
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(row.revisions == "999" ? "∞" : row.revisions)
                            .font(.appBody)
                            .foregroundStyle(.white)
                        LucideIcon(.chevronDown, .xs)
                            .foregroundStyle(Color.vText3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .uploadFieldShell()
                    .contentShape(.rect)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        numberFieldFocused = false
                    }
                    .font(.appCallout)
                }
            }

            Text("Price · delivery days · revision rounds")
                .font(.appCaption)
                .foregroundStyle(Color.vText3)

            VStack(spacing: 8) {
                ForEach(Array(row.features.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 10) {
                        LucideIcon(.circleCheck, .xs)
                            .foregroundStyle(Color.vText3)
                        TextField(
                            "",
                            text: Binding(
                                get: {
                                    guard index < pkg.wrappedValue.features.count else { return "" }
                                    return pkg.wrappedValue.features[index]
                                },
                                set: {
                                    guard index < pkg.wrappedValue.features.count else { return }
                                    pkg.wrappedValue.features[index] = $0
                                }
                            ),
                            prompt: Text("Feature…").foregroundStyle(Color.vText3)
                        )
                        .font(.appBody)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .uploadFieldShell()

                        if row.features.count > 1 {
                            Button {
                                pkg.wrappedValue.features.remove(at: index)
                            } label: {
                                LucideIcon(.x, .xs)
                                    .foregroundStyle(Color.vText3)
                                    .frame(width: 32, height: 32)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    pkg.wrappedValue.features.append("")
                } label: {
                    HStack(spacing: 6) {
                        LucideIcon(.plus, .xs)
                        Text("Add feature")
                            .font(.appFootnote)
                    }
                    .foregroundStyle(Color.vText3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 23)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
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

            ForEach(Array(viewModel.deliverables.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 10) {
                    LucideIcon(.circleCheck, .sm)
                        .foregroundStyle(Color.vText3)
                    TextField(
                        "",
                        text: Binding(
                            get: {
                                guard index < viewModel.deliverables.count else { return "" }
                                return viewModel.deliverables[index]
                            },
                            set: {
                                guard index < viewModel.deliverables.count else { return }
                                viewModel.deliverables[index] = $0
                            }
                        ),
                        prompt: Text("e.g. Full stereo mix (WAV 24-bit)").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .uploadFieldShell()

                    if viewModel.deliverables.count > 1 {
                        Button {
                            viewModel.deliverables.remove(at: index)
                        } label: {
                            LucideIcon(.x, .sm)
                                .foregroundStyle(Color.vText3)
                                .frame(width: 36, height: 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                viewModel.deliverables.append("")
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(.plus, .xs)
                    Text("Add item")
                        .font(.appFootnote)
                }
                .foregroundStyle(Color.vText3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - How it works

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            UploadSectionDivider("How It Works")

            Text("Walk buyers through your process step by step — numbered automatically.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            ForEach(Array(viewModel.processSteps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06))
                        Circle().strokeBorder(Color.vBorder, lineWidth: 1)
                        Text("\(index + 1)")
                            .font(.appLabel)
                            .foregroundStyle(Color.vText3)
                    }
                    .frame(width: 26, height: 26)
                    .padding(.top, 8)

                    VStack(spacing: 8) {
                        TextField(
                            "",
                            text: Binding(
                                get: { viewModel.processSteps.first { $0.id == step.id }?.step ?? "" },
                                set: { newValue in
                                    if let i = viewModel.processSteps.firstIndex(where: { $0.id == step.id }) {
                                        viewModel.processSteps[i].step = newValue
                                    }
                                }
                            ),
                            prompt: Text("Step title…").foregroundStyle(Color.vText3)
                        )
                        .font(.appBody)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .uploadFieldShell()

                        TextField(
                            "",
                            text: Binding(
                                get: { viewModel.processSteps.first { $0.id == step.id }?.description ?? "" },
                                set: { newValue in
                                    if let i = viewModel.processSteps.firstIndex(where: { $0.id == step.id }) {
                                        viewModel.processSteps[i].description = newValue
                                    }
                                }
                            ),
                            prompt: Text("Describe what happens in this step…").foregroundStyle(Color.vText3),
                            axis: .vertical
                        )
                        .font(.appFootnote)
                        .foregroundStyle(.white)
                        .lineLimit(2...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .uploadFieldShell()
                    }

                    if viewModel.processSteps.count > 1 {
                        Button {
                            viewModel.processSteps.removeAll { $0.id == step.id }
                        } label: {
                            LucideIcon(.x, .sm)
                                .foregroundStyle(Color.vText3)
                                .frame(width: 36, height: 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }

            Button {
                viewModel.processSteps.append(.init())
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(.plus, .sm)
                    Text("Add Step")
                        .font(.appCallout)
                }
                .foregroundStyle(Color.vText3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(UploadTheme.border, style: UploadTheme.dashed)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Portfolio

    private var portfolioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Portfolio")

            Text("Showcase past work — each entry needs a title and an audio file.")
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

            Text("Optional — answer common buyer questions upfront.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            ForEach($viewModel.faqs) { $faq in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 8) {
                        TextField(
                            "",
                            text: $faq.question,
                            prompt: Text("Question…").foregroundStyle(Color.vText3)
                        )
                        .font(.appBody)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .uploadFieldShell()

                        TextField(
                            "",
                            text: $faq.answer,
                            prompt: Text("Answer…").foregroundStyle(Color.vText3),
                            axis: .vertical
                        )
                        .font(.appFootnote)
                        .foregroundStyle(.white)
                        .lineLimit(2...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .uploadFieldShell()
                    }

                    if viewModel.faqs.count > 1 {
                        Button {
                            viewModel.faqs.removeAll { $0.id == faq.id }
                        } label: {
                            LucideIcon(.x, .sm)
                                .foregroundStyle(Color.vText3)
                                .frame(width: 36, height: 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }

            Button {
                viewModel.faqs.append(.init())
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(.plus, .xs)
                    Text("Add FAQ")
                        .font(.appFootnote)
                }
                .foregroundStyle(Color.vText3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Visibility

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Visibility")

            HStack(spacing: 8) {
                UploadPill("Public", icon: .globe, expands: true, selected: viewModel.visibility == "public") {
                    viewModel.visibility = "public"
                }
                UploadPill("Private", icon: .lock, expands: true, selected: viewModel.visibility == "private") {
                    viewModel.visibility = "private"
                }
            }

            Text(
                viewModel.visibility == "public"
                    ? "Public — appears in the marketplace and on your profile."
                    : "Private — hidden from the marketplace. You can make it public later from the service page."
            )
            .font(.appFootnote)
            .foregroundStyle(Color.vText3)
        }
    }
}
