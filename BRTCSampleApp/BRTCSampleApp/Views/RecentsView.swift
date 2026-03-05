import SwiftUI

struct RecentsView: View {
    let callHistory: CallHistoryManager
    /// Called when the user taps a number to redial it.
    var onSelectNumber: ((String, String) -> Void)?   // (e164, formatted)

    @State private var filter: CallFilter = .all

    enum CallFilter: String, CaseIterable {
        case all = "All"
        case missed = "Missed"
    }

    private var filteredRecords: [CallRecord] {
        switch filter {
        case .all:
            return callHistory.records
        case .missed:
            return callHistory.records.filter(\.isMissed)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if callHistory.records.isEmpty {
                    emptyState
                } else if filteredRecords.isEmpty {
                    filteredEmptyState
                } else {
                    callList
                }
            }
            .navigationTitle("Recents")
            .toolbar {
                if !callHistory.records.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") {
                            withAnimation {
                                callHistory.clearAll()
                            }
                        }
                        .foregroundStyle(.red)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $filter) {
                        ForEach(CallFilter.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
        }
    }

    // MARK: - Call List

    private var callList: some View {
        List {
            ForEach(filteredRecords) { record in
                CallRecordRow(record: record) {
                    if !record.e164Number.isEmpty {
                        onSelectNumber?(record.e164Number, record.phoneNumber)
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .onDelete { offsets in
                // Map filtered offsets back to the source array
                let recordIds = offsets.map { filteredRecords[$0].id }
                withAnimation {
                    for id in recordIds {
                        callHistory.deleteRecord(id: id)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.blue.opacity(0.08))
                    .frame(width: 72, height: 72)

                Image(systemName: "clock.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue.opacity(0.4))
            }

            VStack(spacing: 4) {
                Text("No Recent Calls")
                    .font(.headline)

                Text("Your call history will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.red.opacity(0.08))
                    .frame(width: 72, height: 72)

                Image(systemName: "phone.arrow.down.left")
                    .font(.system(size: 32))
                    .foregroundStyle(.red.opacity(0.4))
            }

            VStack(spacing: 4) {
                Text("No Missed Calls")
                    .font(.headline)

                Text("You haven't missed any calls.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Call Record Row

private struct CallRecordRow: View {
    let record: CallRecord
    let onCall: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Phone number with inline direction arrow + date
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Inline direction arrow (small, subtle — iOS style)
                    directionArrow

                    Text(record.phoneNumber)
                        .font(.body.weight(.medium))
                        .foregroundStyle(record.isMissed ? .red : .primary)
                        .lineLimit(1)
                }

                // Secondary line: call type + time
                Text(record.callSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Date/time on the right (iOS style)
            Text(record.formattedDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 12)

            // Call-back button (blue phone icon) — always reserves space for alignment
            Button {
                onCall()
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .opacity(record.e164Number.isEmpty ? 0 : 1)
            .disabled(record.e164Number.isEmpty)
        }
    }

    private var directionArrow: some View {
        Group {
            switch record.direction {
            case .outbound:
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            case .inbound:
                Image(systemName: "arrow.down.left")
                    .foregroundStyle(record.isMissed ? .red : .secondary)
            }
        }
        .font(.system(size: 12, weight: .bold))
    }
}
