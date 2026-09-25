//
//  AIChatView.swift
//  GetSeen Cloud
//
//  Native Chat-UI für den Mistral-basierten KI-Assistenten.
//  Spricht das ai_chat Action am bestehenden api.php an.
//

import SwiftUI

struct AIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.gradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("GetSeen AI")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Mistral · Cloud-Assistent")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !messages.isEmpty {
                    Button {
                        messages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Chat löschen")
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Schließen")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .sheetHeaderInset()
            .background(Color.platformWindowBackground)

            Divider().opacity(0.5)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            emptyChat
                        } else {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if isStreaming {
                                HStack(spacing: 4) {
                                    ForEach(0..<3, id: \.self) { i in
                                        Circle()
                                            .fill(Theme.purple.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                            .scaleEffect(isStreaming ? 1.2 : 0.8)
                                            .animation(
                                                .easeInOut(duration: 0.6)
                                                .repeatForever()
                                                .delay(Double(i) * 0.2),
                                                value: isStreaming
                                            )
                                    }
                                }
                                .padding(.leading, 16)
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let err = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11))
                    Spacer()
                    Button("✕") { errorMessage = nil }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.10))
            }

            Divider().opacity(0.5)

            // Input
            HStack(spacing: 8) {
                TextField("Frage stellen…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Button {
                    send()
                } label: {
                    Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.gradient)
                        .clipShape(Circle())
                        .shadow(color: Theme.purple.opacity(0.4), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 500, idealHeight: 600)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear { inputFocused = true }
    }

    // MARK: - Empty State
    private var emptyChat: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.gradient)
                    .frame(width: 64, height: 64)
                    .opacity(0.20)
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.gradient)
            }
            Text("Wie kann ich dir helfen?")
                .font(.system(size: 16, weight: .semibold))
            Text("Frage mich nach Dateien, Speicherplatz oder erstelle neue Dokumente.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            VStack(spacing: 6) {
                ForEach([
                    "Wie viel Speicherplatz habe ich noch?",
                    "Welche Datei habe ich zuletzt geöffnet?",
                    "Erstelle ein neues Dokument."
                ], id: \.self) { suggestion in
                    Button {
                        input = suggestion
                        send()
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Senden
    private func send() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        errorMessage = nil

        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        isStreaming = true

        // PHP erwartet ein JSON-Array unter Key 'messages' mit allen bisherigen Nachrichten
        let payload: [[String: String]] = messages.map { msg in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        }
        let jsonData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        Task {
            do {
                let json = try await APIService.shared.post("ai_chat", params: ["messages": jsonString])
                let answer = (json["reply"] as? String) ?? (json["answer"] as? String) ?? (json["response"] as? String) ?? ""
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: answer))
                    isStreaming = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                    isStreaming = false
                }
            }
        }
    }
}

// MARK: - Message Model
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let content: String
}

// MARK: - Bubble
struct MessageBubble: View {
    let message: ChatMessage

    /// Rendert **fett**, *kursiv*, `code`, Links usw. aus Markdown –
    /// mit erhaltenen Zeilenumbrüchen. Fällt bei Fehlern auf reinen Text zurück.
    private func rendered(_ raw: String) -> Text {
        if let attr = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attr)
        }
        return Text(raw)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
                rendered(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Theme.purple.opacity(0.25), radius: 4, y: 1)
            } else {
                ZStack {
                    Circle()
                        .fill(Theme.gradient)
                        .frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                rendered(message.content)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 40)
            }
        }
    }
}
