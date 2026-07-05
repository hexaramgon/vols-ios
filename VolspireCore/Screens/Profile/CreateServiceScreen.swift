//
//  CreateServiceScreen.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct CreateServiceScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileScreenViewModel

    let editing: ProfileService?

    @State private var title = ""
    @State private var description = ""
    @State private var serviceType = ""
    @State private var priceText = ""
    @State private var currency = "USD"
    @State private var deliveryDaysText = ""

    private let serviceTypes = ["Mixing", "Mastering", "Production", "Recording", "Songwriting", "Vocal Tuning", "Sound Design", "Other"]
    private let currencies = ["USD", "EUR", "GBP", "CAD", "AUD"]

    private var isEditing: Bool { editing != nil }

    init(viewModel: ProfileScreenViewModel, editing: ProfileService? = nil) {
        self.viewModel = viewModel
        self.editing = editing
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !description.trimmingCharacters(in: .whitespaces).isEmpty
            && !serviceType.isEmpty
            && Double(priceText) != nil
    }

    private var isBusy: Bool {
        isEditing ? viewModel.isEditingService : viewModel.isCreatingService
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())
                }

                Spacer()

                Text(isEditing ? "Edit Service" : "New Service")
                    .font(.appBodyLargeSemibold)

                Spacer()

                // Balance spacer
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)

            // MARK: - Content

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    detailsSection
                    typeSection
                    pricingSection
                    deliverySection
                    actionButton
                        .padding(.top, 28)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .gradientBackground()
        .onAppear {
            if let service = editing {
                title = service.title
                description = service.description
                serviceType = service.serviceType
                let numStr = service.price
                    .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                priceText = numStr
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Details")

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.secondary)
                TextField("What do you offer?", text: $title)
                    .font(.appBody)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.secondary)
                TextField("Describe your service...", text: $description, axis: .vertical)
                    .font(.appBody)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Type

    private var typeSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Service Type")

            let columns = [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(serviceTypes, id: \.self) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            serviceType = type
                        }
                    } label: {
                        Text(type)
                            .font(.appSubheadlineMedium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                serviceType == type
                                    ? Color.brand
                                    : Color(.secondarySystemGroupedBackground)
                            )
                            .foregroundStyle(serviceType == type ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(serviceType == type ? Color.brand : .clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Pricing")

            VStack(alignment: .leading, spacing: 6) {
                Text("Currency")
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(currencies, id: \.self) { c in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                currency = c
                            }
                        } label: {
                            Text(c)
                                .font(.appFootnoteSemibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    currency == c
                                        ? Color.brand
                                        : Color(.secondarySystemGroupedBackground)
                                )
                                .foregroundStyle(currency == c ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Price")
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Text(currencySymbol)
                        .font(.appBodyMedium)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)

                    TextField("0.00", text: $priceText)
                        .font(.appBody)
                        .keyboardType(.decimalPad)
                        .padding(12)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Delivery

    private var deliverySection: some View {
        VStack(spacing: 16) {
            sectionHeader("Delivery")

            VStack(alignment: .leading, spacing: 6) {
                Text("Delivery Time")
                    .font(.appFootnoteMedium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    TextField("e.g. 3", text: $deliveryDaysText)
                        .font(.appBody)
                        .keyboardType(.numberPad)
                        .padding(12)

                    Text("days")
                        .font(.appSubheadline)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Optional — leave blank if not applicable")
                    .font(.appCaption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            Task {
                if let service = editing {
                    await viewModel.updateService(
                        serviceId: service.id,
                        title: title.trimmingCharacters(in: .whitespaces),
                        description: description.trimmingCharacters(in: .whitespaces),
                        serviceType: serviceType,
                        price: Double(priceText) ?? 0,
                        currency: currency,
                        deliveryTimeDays: Int(deliveryDaysText)
                    )
                } else {
                    await viewModel.createService(
                        title: title.trimmingCharacters(in: .whitespaces),
                        description: description.trimmingCharacters(in: .whitespaces),
                        serviceType: serviceType,
                        price: Double(priceText) ?? 0,
                        currency: currency,
                        deliveryTimeDays: Int(deliveryDaysText)
                    )
                }
            }
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18))
                }
                Text(
                    isBusy
                        ? (isEditing ? "Saving..." : "Creating...")
                        : (isEditing ? "Save Changes" : "Create Service")
                )
                .font(.appHeadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isFormValid && !isBusy ? Color.brand : Color(.systemGray3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isFormValid || isBusy)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 20)
            HStack {
                Text(title)
                    .font(.appFootnoteSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    private var currencySymbol: String {
        switch currency {
        case "EUR": "€"
        case "GBP": "£"
        default: "$"
        }
    }
}
