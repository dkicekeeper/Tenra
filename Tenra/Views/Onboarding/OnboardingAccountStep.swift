//
//  OnboardingAccountStep.swift
//  Tenra

import SwiftUI

struct OnboardingAccountStep: View {
    @Bindable var vm: OnboardingViewModel
    @State private var showIconPicker = false

    // AmountInput works with String; draftAccount.balance is Double.
    // We maintain a local string and sync to vm on every change.
    @State private var balanceString: String = ""

    // IconPickerView requires Binding<IconSource?> (optional).
    // draftAccount.iconSource is non-optional, so we bridge via local state.
    @State private var pickerSource: IconSource? = nil

    var body: some View {
        OnboardingPageContainer(
            progressStep: 2,
            title: String(localized: "onboarding.account.title"),
            subtitle: String(localized: "onboarding.account.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.next"),
            primaryButtonEnabled: vm.canAdvanceFromAccountStep,
            onPrimaryTap: {
                Task { await vm.advanceToCategoriesStep() }
            }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    formSection
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
        }
        .onAppear {
            // Initialise local state from VM on first appear
            balanceString = vm.draftAccount.balance == 0 ? "" : AmountInputFormatting.cleanAmountString(String(vm.draftAccount.balance))
            pickerSource = vm.draftAccount.iconSource
        }
        .sheet(isPresented: $showIconPicker) {
            // IconPickerView has its own NavigationStack; do NOT wrap again.
            IconPickerView(selectedSource: $pickerSource)
        }
        .onChange(of: pickerSource) { _, newSource in
            if let source = newSource {
                vm.draftAccount.iconSource = source
            }
        }
    }

    @ViewBuilder
    private var formSection: some View {
        VStack(spacing: 0) {
            // Name row
            HStack {
                Text(String(localized: "onboarding.account.nameLabel"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                TextField(
                    String(localized: "onboarding.account.namePlaceholder"),
                    text: $vm.draftAccount.name
                )
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            Divider().padding(.leading, AppSpacing.lg)

            // Icon row
            Button {
                HapticManager.light()
                showIconPicker = true
            } label: {
                HStack {
                    Text(String(localized: "onboarding.account.iconLabel"))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    // .roundedLogo() matches the account row style used throughout the app
                    IconView(source: vm.draftAccount.iconSource, style: .roundedLogo())
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.caption)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, AppSpacing.lg)

            // Balance row
            HStack {
                Text(String(localized: "onboarding.account.balanceLabel"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                AmountInput(
                    amount: $balanceString,
                    baseFontSize: 17,
                    color: AppColors.textPrimary,
                    placeholderColor: AppColors.textSecondary,
                    autoFocus: false,
                    showContextMenu: false
                )
                .frame(maxWidth: 160)
                .onChange(of: balanceString) { _, newValue in
                    let cleaned = AmountInputFormatting.cleanAmountString(newValue)
                    vm.draftAccount.balance = Double(cleaned) ?? 0
                }
                Text(vm.draftCurrency)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .cardStyle()
    }
}
