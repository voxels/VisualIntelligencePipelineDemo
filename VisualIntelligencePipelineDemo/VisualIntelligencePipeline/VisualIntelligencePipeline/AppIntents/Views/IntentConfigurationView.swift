import SwiftUI

/// A configuration view for saving a link to Visual Intelligence, with validation and preview.
struct IntentConfigurationView: View {
    @State private var urlString: String = ""
    @State private var title: String = ""
    @State private var tags: [String] = []
    @State private var validationMessage: String?
    
    // Optional: basic tag entry UI
    @State private var newTag: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Link")) {
                TextField("Paste or enter URL", text: $urlString)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section(header: Text("Title (optional)")) {
                TextField("Title", text: $title)
            }
            Section(header: Text("Tags (optional)")) {
                HStack {
                    TextField("Add tag", text: $newTag)
                    Button("Add") {
                        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tag.isEmpty && !tags.contains(tag) {
                            tags.append(tag)
                        }
                        newTag = ""
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            Label(tag, systemImage: "tag")
                                .padding(.horizontal, 6)
                                .background(Capsule().foregroundColor(.blue.opacity(0.15)))
                                .onTapGesture {
                                    tags.removeAll { $0 == tag }
                                }
                        }
                    }
                }
            }
            Section {
                Button("Preview Save Action") {
                    validateURL()
                }
            }
        }
        .navigationTitle("Save Link to Visual Intelligence")
        .onChange(of: urlString) { _, _ in
            validationMessage = nil
        }
    }
    
    private func validateURL() {
        guard let url = URL(string: urlString),
              url.scheme?.hasPrefix("http") == true else {
            validationMessage = "Please enter a valid http or https URL."
            return
        }
        validationMessage = "URL is valid. Ready to save!"
        // You could trigger a preview or pass to intent for preview here
    }
}

#Preview {
    IntentConfigurationView()
}
