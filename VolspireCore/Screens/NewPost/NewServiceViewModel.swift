//
//  NewServiceViewModel.swift
//  Volspire
//
//  Service creation — mirrors the web's service-create page: type +
//  gradient + cover, details, per-tier packages, deliverables, process
//  steps, portfolio clips, tags, FAQs, and the create_service RPC.
//

import DesignSystem
import Foundation
import Services
import SharedUtilities
import SwiftUI

struct ServiceTypeOption: Identifiable, Sendable {
    let id: String
    let icon: LucideIcon.Name
}

/// Web SERVICE_TYPES + SERVICE_ICONS.
let serviceTypes: [ServiceTypeOption] = [
    .init(id: "Mixing", icon: .zap),
    .init(id: "Mastering", icon: .sparkles),
    .init(id: "Production", icon: .music),
    .init(id: "Recording", icon: .users),
    .init(id: "Songwriting", icon: .star),
    .init(id: "Vocal Tuning", icon: .refreshCw),
    .init(id: "Sound Design", icon: .zap),
    .init(id: "Other", icon: .briefcase),
]

/// Web GRADIENT_OPTIONS (service-create) — swatch top colour derived via TailwindGradient.
let serviceGradients: [UploadGradientOption] = [
    .init(id: "from-blue-950 via-slate-950 to-black", label: "Blue"),
    .init(id: "from-purple-950 via-violet-950 to-black", label: "Violet"),
    .init(id: "from-rose-950 via-pink-950 to-black", label: "Rose"),
    .init(id: "from-cyan-950 via-teal-950 to-black", label: "Cyan"),
    .init(id: "from-amber-950 via-yellow-950 to-black", label: "Amber"),
    .init(id: "from-emerald-950 via-green-950 to-black", label: "Emerald"),
    .init(id: "from-orange-950 via-red-950 to-black", label: "Orange"),
    .init(id: "from-neutral-800 via-neutral-900 to-black", label: "Slate"),
]

let serviceCurrencies = ["USD", "EUR", "GBP", "CAD", "AUD"]
let servicePackageTiers = ["Basic", "Standard", "Premium", "Starter", "Pro", "Enterprise", "Custom"]

/// Web REVISIONS_OPTIONS — 999 is the "Unlimited" sentinel.
let serviceRevisionsOptions: [(value: String, label: String)] = [
    ("0", "0"), ("1", "1"), ("2", "2"), ("3", "3"),
    ("5", "5"), ("10", "10"), ("999", "Unlimited"),
]

func currencySymbol(_ currency: String) -> String {
    switch currency {
    case "EUR": "€"
    case "GBP": "£"
    default: "$"
    }
}

@MainActor
@Observable
final class NewServiceViewModel {
    struct PackageDraft: Identifiable {
        let id = UUID()
        var name: String = "Basic"
        var price: String = ""
        var delivery: String = ""
        var revisions: String = "1"
        var features: [String] = [""]
    }

    struct StepDraft: Identifiable {
        let id = UUID()
        var step: String = ""
        var description: String = ""
    }

    struct FaqDraft: Identifiable {
        let id = UUID()
        var question: String = ""
        var answer: String = ""
    }

    var serviceType: String = serviceTypes[0].id
    var gradient: String = serviceGradients[0].id
    var title: String = ""
    var longDescription: String = ""
    var currency: String = "USD"
    var tags: [String] = []
    var deliverables: [String] = [""]
    var packages: [PackageDraft] = [PackageDraft()]
    var faqs: [FaqDraft] = [FaqDraft()]
    var processSteps: [StepDraft] = [StepDraft()]
    var portfolio: [AudioClipDraft] = []
    var visibility: String = "public"

    // Cover (optional) — staged via the shared CoverDraft.
    private var cover = CoverDraft()
    var coverImage: UIImage? { cover.image }
    var coverData: Data? { cover.data }
    var coverFileName: String? { cover.fileName }

    var uploadState: UploadState = .idle

    /// Non-nil when editing an existing service (drives update vs create). Cover and
    /// active state aren't edited by update_service, so they're left untouched.
    private(set) var editingServiceId: String?
    var isEditing: Bool { editingServiceId != nil }

    // MARK: Validation (mirrors web missing/isValid)

    private var portfolioComplete: Bool {
        portfolio.allSatisfy(\.isComplete)
    }

    /// The cheapest fully-priced package — becomes the listing's starting price.
    private var cheapestPackage: PackageDraft? {
        packages
            .filter { !$0.name.isEmpty && (Double($0.price) ?? 0) > 0 }
            .min { (Double($0.price) ?? 0) < (Double($1.price) ?? 0) }
    }

    private var packagesValid: Bool {
        packages.allSatisfy { pkg in
            !pkg.name.trimmingCharacters(in: .whitespaces).isEmpty
                && (Double(pkg.price) ?? 0) > 0
                && (Int(pkg.delivery) ?? 0) > 0
                && pkg.features.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    var missing: [String] {
        var out: [String] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty { out.append("a title") }
        if longDescription.trimmingCharacters(in: .whitespaces).isEmpty { out.append("a description") }
        if cheapestPackage == nil {
            out.append("at least one priced package")
        } else if !packagesValid {
            var needs: [String] = []
            if packages.contains(where: { (Int($0.delivery) ?? 0) <= 0 }) { needs.append("delivery days") }
            if packages.contains(where: { !$0.features.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }) {
                needs.append("at least one feature")
            }
            if !needs.isEmpty { out.append("\(needs.joined(separator: " + ")) on every package") }
        }
        if !portfolioComplete { out.append("a portfolio item (title + audio file)") }
        return out
    }

    var canPublish: Bool { missing.isEmpty }

    var validationHint: String? {
        missing.isEmpty ? nil : "Add \(missing.joined(separator: ", ")) to publish"
    }

    private let supabaseService: SupabaseService
    private let authManager: AuthManager

    init(supabaseService: SupabaseService, authManager: AuthManager) {
        self.supabaseService = supabaseService
        self.authManager = authManager
    }

    /// Edit-mode initialiser — prefills from a loaded service detail.
    init(editing detail: ApiServiceDetail, supabaseService: SupabaseService, authManager: AuthManager) {
        self.supabaseService = supabaseService
        self.authManager = authManager
        editingServiceId = detail.serviceId
        title = detail.title
        serviceType = detail.serviceType ?? serviceTypes[0].id
        longDescription = detail.longDescription ?? ""
        currency = detail.currency ?? "USD"
        tags = detail.tags ?? []
        gradient = detail.gradient ?? serviceGradients[0].id
        deliverables = (detail.deliverables?.isEmpty == false) ? detail.deliverables! : [""]
        if let pkgs = detail.packages, !pkgs.isEmpty {
            packages = pkgs.map { p in
                PackageDraft(
                    name: p.name,
                    price: p.price.map { String($0) } ?? "",
                    delivery: p.delivery.map { String($0) } ?? "",
                    revisions: p.revisions.map { String($0) } ?? "1",
                    features: (p.features?.isEmpty == false) ? p.features! : [""]
                )
            }
        }
        if let steps = detail.process, !steps.isEmpty {
            processSteps = steps.map { StepDraft(step: $0.step, description: $0.description ?? "") }
        }
        if let f = detail.faqs, !f.isEmpty {
            faqs = f.map { FaqDraft(question: $0.q, answer: $0.a ?? "") }
        }
        portfolio = (detail.portfolio ?? []).map { AudioClipDraft(title: $0.title ?? "", existingFileUrl: $0.fileUrl) }
    }

    func handleCoverImage(_ image: UIImage) {
        cover.set(image)
    }

    func clearCover() {
        cover.clear()
    }

    func handlePortfolioFile(rowId: UUID, result: Result<URL, Error>) {
        guard let index = portfolio.firstIndex(where: { $0.id == rowId }) else { return }
        switch result {
        case .success(let url):
            do {
                guard let data = try SecurityScopedFile.read(url) else { return }
                portfolio[index].data = data
                portfolio[index].fileName = url.lastPathComponent
            } catch {
                uploadState = .error("Failed to read audio file")
            }
        case .failure(let error):
            uploadState = .error(error.localizedDescription)
        }
    }

    func publish() async {
        guard canPublish, let cheapest = cheapestPackage else { return }
        guard case .authenticated(let userId) = authManager.state else {
            uploadState = .error("Not authenticated")
            return
        }

        uploadState = .uploading

        do {
            let packagesPayload = packages
                .filter { !$0.name.isEmpty && !$0.price.isEmpty }
                .map { pkg in
                    SupabaseService.ServicePackageInput(
                        name: pkg.name,
                        price: Double(pkg.price) ?? 0,
                        delivery: Int(pkg.delivery) ?? 0,
                        revisions: Int(pkg.revisions) ?? 1,
                        features: pkg.features.filter { !$0.isEmpty }
                    )
                }
            let processPayload = processSteps
                .filter { !$0.step.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { SupabaseService.ServiceProcessStepInput(step: $0.step, description: $0.description) }
            let faqsPayload = faqs
                .filter { !$0.question.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { SupabaseService.ServiceFaqInput(question: $0.question, answer: $0.answer) }
            let trimmedDescription = longDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = trimmedDescription.isEmpty ? nil : trimmedDescription
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            let deliverablesPayload = deliverables.filter { !$0.isEmpty }

            if let editingServiceId {
                // Keep existing portfolio clips (paths) + upload any newly attached.
                let portfolioEdits = portfolio.compactMap { clip -> SupabaseService.ListingAttachmentEdit? in
                    guard clip.existingFileUrl != nil || clip.data != nil else { return nil }
                    return .init(title: clip.title.trimmingCharacters(in: .whitespaces),
                                 existingFileUrl: clip.existingFileUrl, data: clip.data, fileName: clip.fileName)
                }
                try await supabaseService.updateService(
                    serviceId: editingServiceId,
                    userId: userId,
                    title: trimmedTitle,
                    serviceType: serviceType,
                    price: Double(cheapest.price) ?? 0,
                    currency: currency,
                    deliveryTimeDays: Int(cheapest.delivery),
                    longDescription: desc,
                    revisions: Int(cheapest.revisions) ?? 1,
                    gradient: gradient,
                    tags: tags,
                    deliverables: deliverablesPayload,
                    processSteps: processPayload,
                    packages: packagesPayload,
                    portfolio: portfolioEdits,
                    faqs: faqsPayload
                )
            } else {
                let portfolioPayload = portfolio.compactMap { clip -> SupabaseService.ListingAttachmentUpload? in
                    guard let data = clip.data, let fileName = clip.fileName else { return nil }
                    return .init(title: clip.title.trimmingCharacters(in: .whitespaces), fileName: fileName, data: data)
                }
                try await supabaseService.createService(
                    userId: userId,
                    title: trimmedTitle,
                    serviceType: serviceType,
                    price: Double(cheapest.price) ?? 0,
                    currency: currency,
                    deliveryTimeDays: Int(cheapest.delivery),
                    longDescription: desc,
                    revisions: Int(cheapest.revisions) ?? 1,
                    gradient: gradient,
                    tags: tags,
                    deliverables: deliverablesPayload,
                    processSteps: processPayload,
                    packages: packagesPayload,
                    portfolio: portfolioPayload,
                    faqs: faqsPayload,
                    coverData: coverData,
                    coverFileName: coverFileName,
                    isActive: visibility == "public"
                )
            }
            uploadState = .success
        } catch {
            uploadState = .error(error.localizedDescription)
        }
    }
}
