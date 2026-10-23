import SwiftUI

struct AccountListView: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var service: UsageService
    let darkMode: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isExpanded = false
    @State private var isEditing = false
    @State private var isAdding = false
    @State private var typedPath = ""
    @State private var typedLabel = ""
    @State private var addConfigFolderError: AddConfigFolderError?

    private var rowBackground: Color {
        darkMode ? Color(hex: "1A1A2E").opacity(0.55) : Color(hex: "F5F5F7").opacity(0.7)
    }
    private var textPrimary: Color {
        darkMode ? .white : Color(hex: "1A1A1A")
    }
    private var textMuted: Color {
        darkMode ? Color(hex: "999999") : Color(hex: "666666")
    }
    private let accent = Color(hex: "E8732A")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            expandButton
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(accountStore.accounts) { account in
                        if isEditing {
                            editingRow(account)
                        } else {
                            accountRow(account)
                        }
                    }
                    if isAdding {
                        addConfigFolderForm
                    } else {
                        linkButton("+ Add config folder", color: accent) {
                            animate { startAdding() }
                        }
                    }
                    HStack {
                        Spacer()
                        linkButton(isEditing ? "Done" : "Edit labels & order", color: accent) {
                            animate {
                                isEditing.toggle()
                                isAdding = false
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var expandButton: some View {
        Button {
            animate { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text("Accounts")
                    .font(.system(size: 12))
                    .foregroundColor(textPrimary)
                Text("\(accountStore.shownAccounts.count) of \(accountStore.accounts.count) shown")
                    .font(.system(size: 12))
                    .foregroundColor(textMuted)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(textMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func accountRow(_ account: ClaudeAccount) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { account.isShownInMenuBar },
                set: { accountStore.setShownInMenuBar($0, configFolderPath: account.configFolderPath) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(accent)
            .labelsHidden()

            Circle()
                .fill(AccountColor.color(position: accountStore.position(of: account)))
                .frame(width: 7, height: 7)

            accountNameAndPath(account)
            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                keychainLoginStatusChip(service.usage(for: account).keychainLoginStatus)
                if account.isFoundAutomatically {
                    chip("Found automatically", color: Color(hex: "60A5FA"))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(rowBackground))
    }

    private func editingRow(_ account: ClaudeAccount) -> some View {
        let position = accountStore.position(of: account)
        return HStack(spacing: 8) {
            VStack(spacing: 2) {
                orderButton(systemName: "chevron.up", isEnabled: position > 0) {
                    animate { accountStore.moveUp(configFolderPath: account.configFolderPath) }
                }
                orderButton(systemName: "chevron.down", isEnabled: position < accountStore.accounts.count - 1) {
                    animate { accountStore.moveDown(configFolderPath: account.configFolderPath) }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                TextField(ClaudeAccount.defaultLabel(configFolderPath: account.configFolderPath), text: Binding(
                    get: { account.label },
                    set: { accountStore.setLabel($0, configFolderPath: account.configFolderPath) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                Text(account.displayPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if accountStore.isRemovable(account) {
                linkButton("Remove", color: Color(hex: "EF4444")) {
                    animate { accountStore.remove(configFolderPath: account.configFolderPath) }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(rowBackground))
    }

    private var addConfigFolderForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("~/.claude-work", text: $typedPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onChange(of: typedPath) { _ in addConfigFolderError = nil }
            TextField("Label (e.g. work)", text: $typedLabel)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Text(keychainServiceNamePreview)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let addConfigFolderError {
                Text(addConfigFolderError.localizedDescription)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "EF4444"))
            }
            HStack {
                Spacer()
                linkButton("Cancel", color: textMuted) {
                    animate { isAdding = false }
                }
                linkButton("Add", color: accent) {
                    addTypedConfigFolder()
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(rowBackground))
    }

    private var keychainServiceNamePreview: String {
        let homeFolderPath = ClaudeAccount.currentHomeFolderPath
        let configFolderPath = ClaudeAccount.normalizedConfigFolderPath(typedPath: typedPath, homeFolderPath: homeFolderPath)
        guard configFolderPath.hasPrefix("/") else {
            return "Type the folder you set as CLAUDE_CONFIG_DIR"
        }
        let keychainServiceName = ClaudeAccount.keychainServiceName(configFolderPath: configFolderPath, homeFolderPath: homeFolderPath)
        return "Keychain entry: \(keychainServiceName)"
    }

    private func startAdding() {
        typedPath = ""
        typedLabel = ""
        addConfigFolderError = nil
        isEditing = false
        isAdding = true
    }

    private func addTypedConfigFolder() {
        do {
            try accountStore.addConfigFolder(typedPath: typedPath, label: typedLabel, isExistingFolder: UsageService.isExistingFolder)
            animate { isAdding = false }
        } catch let error as AddConfigFolderError {
            addConfigFolderError = error
        } catch {
            preconditionFailure("addConfigFolder only throws AddConfigFolderError, got \(error)")
        }
    }

    private func accountNameAndPath(_ account: ClaudeAccount) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(account.labelOrFolderName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(textPrimary)
                .lineLimit(1)
            Text(account.displayPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func keychainLoginStatusChip(_ keychainLoginStatus: KeychainLoginStatus) -> some View {
        switch keychainLoginStatus {
        case .notChecked:
            chip("Checking…", color: textMuted)
        case .found:
            chip("Login found", color: Color(hex: "22C55E"))
        case .tokenExpired:
            chip("Token expired", color: Color(hex: "F59E0B"))
        case .notFound:
            chip("No login found", color: textMuted)
        case .unreadable:
            chip("Login unreadable", color: Color(hex: "EF4444"))
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.18)))
            .fixedSize()
    }

    private func linkButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func orderButton(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(textMuted.opacity(isEnabled ? 1 : 0.3))
                .frame(width: 14, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.easeInOut(duration: 0.25), change)
        }
    }
}
