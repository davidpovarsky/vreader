// Purpose: Inline chat card presenting AI tool action confirmation requests.
// Connects directly to AIActionConfirmationBroker and enforces "Always ask" on destructive actions.

#if canImport(UIKit)
import SwiftUI

struct ChatActionConfirmationCard: View {
    let request: AIActionConfirmationRequest
    let theme: ReaderThemeV2
    let onResolve: (AIActionConfirmationResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(theme.accentColor))
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Spacer()
                if request.isDestructive {
                    Text("Requires Confirmation")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }

            Text(request.actionDescription)
                .font(.system(size: 13))
                .foregroundStyle(Color(theme.inkColor).opacity(0.85))

            if let server = request.externalServerName {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.caption2)
                    Text("Server: \(server)")
                        .font(.caption2)
                }
                .foregroundStyle(Color.secondary)
            }

            if request.requestedReadAhead {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.caption2)
                    Text("Includes unread content ahead of current position")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }

            Divider()

            HStack(spacing: 8) {
                Button(role: .cancel) {
                    onResolve(.deny)
                } label: {
                    Text("Deny")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(Color(theme.inkColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("confirmDenyButton")

                Button {
                    onResolve(.allowOnce)
                } label: {
                    Text("Allow Once")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(theme.accentColor))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("confirmAllowOnceButton")

                // Only show Always Allow for non-destructive, eligible categories
                if request.rememberAllowEligible && !request.isDestructive && request.permissionCategory != .removeData {
                    Button {
                        onResolve(.alwaysAllow)
                    } label: {
                        Text("Always Allow")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(theme.accentColor).opacity(0.15))
                            .foregroundStyle(Color(theme.accentColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityIdentifier("confirmAlwaysAllowButton")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(theme.sheetCardSurfaceColor))
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(theme.inkColor).opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .accessibilityIdentifier("actionConfirmationCard")
    }

    private var iconName: String {
        switch request.permissionCategory {
        case .writeAnnotations, .modifyAnnotations: return "pencil.circle"
        case .removeData: return "trash.circle"
        case .navigateReader: return "arrow.right.circle"
        case .readOtherBooks: return "books.vertical"
        case .readAhead: return "eye.circle"
        case .externalNetwork: return "network"
        case .readCurrentBook: return "book"
        }
    }

    private var titleText: String {
        switch request.permissionCategory {
        case .removeData: return "Confirm Deletion"
        case .writeAnnotations: return "Create Annotation"
        case .modifyAnnotations: return "Update Annotation"
        case .externalNetwork: return "External Network Request"
        case .readAhead: return "Read Ahead Spoiler Confirmation"
        case .readOtherBooks: return "Access Other Books"
        case .readCurrentBook: return "Read Book Content"
        case .navigateReader: return "Navigate Reader"
        }
    }
}
#endif
