import SwiftUI
import AppKit

struct SQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    
    init(text: Binding<String>, selectedRange: Binding<NSRange> = .constant(NSRange(location: 0, length: 0))) {
        self._text = text
        self._selectedRange = selectedRange
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        
        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        
        // Set initial text
        textView.string = text
        
        // Set up text container
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 5
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        
        // Set background color to ensure visibility
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.controlAccentColor
        
        scrollView.documentView = textView
        
        // Set delegate
        textView.delegate = context.coordinator
        
        // Make text view first responder when window is available
        DispatchQueue.main.async {
            if let window = scrollView.window {
                window.makeFirstResponder(textView)
            }
        }
        
        // Apply initial syntax highlighting
        applySyntaxHighlighting(to: textView)
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            let currentSelectedRange = textView.selectedRange()
            textView.string = text
            applySyntaxHighlighting(to: textView)
            
            // Restore cursor position if valid
            let newRange = NSRange(
                location: min(currentSelectedRange.location, text.count),
                length: 0
            )
            textView.setSelectedRange(newRange)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func applySyntaxHighlighting(to textView: NSTextView) {
        guard !text.isEmpty else { return }
        
        let currentSelectedRange = textView.selectedRange()
        
        // Create attributed string with basic SQL syntax highlighting
        let attributedString = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.textColor
        ])
        
        // SQL Keywords
        let keywords = ["SELECT", "FROM", "WHERE", "ORDER", "BY", "GROUP", "HAVING", "INSERT", "UPDATE", "DELETE", 
                       "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "DATABASE", "SCHEMA", "DISTINCT", 
                       "COUNT", "SUM", "AVG", "MIN", "MAX", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON",
                       "AS", "AND", "OR", "NOT", "IN", "EXISTS", "LIKE", "BETWEEN", "NULL", "IS", "ASC", "DESC",
                       "LIMIT", "OFFSET", "UNION", "INTERSECT", "EXCEPT"]
        
        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: text.count)
            
            regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range {
                    attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: matchRange)
                    attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: matchRange)
                }
            }
        }
        
        // String literals
        let stringPattern = "'[^']*'"
        let stringRegex = try? NSRegularExpression(pattern: stringPattern, options: [])
        let stringRange = NSRange(location: 0, length: text.count)
        
        stringRegex?.enumerateMatches(in: text, options: [], range: stringRange) { match, _, _ in
            if let matchRange = match?.range {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemRed, range: matchRange)
            }
        }
        
        // Numbers
        let numberPattern = "\\b\\d+(\\.\\d+)?\\b"
        let numberRegex = try? NSRegularExpression(pattern: numberPattern, options: [])
        let numberRange = NSRange(location: 0, length: text.count)
        
        numberRegex?.enumerateMatches(in: text, options: [], range: numberRange) { match, _, _ in
            if let matchRange = match?.range {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: matchRange)
            }
        }
        
        // Comments
        let commentPattern = "--[^\n]*"
        let commentRegex = try? NSRegularExpression(pattern: commentPattern, options: [])
        let commentRange = NSRange(location: 0, length: text.count)
        
        commentRegex?.enumerateMatches(in: text, options: [], range: commentRange) { match, _, _ in
            if let matchRange = match?.range {
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: matchRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: matchRange)
            }
        }
        
        textView.textStorage?.setAttributedString(attributedString)
        
        // Restore selection
        let safeRange = NSRange(
            location: min(currentSelectedRange.location, textView.string.count),
            length: min(currentSelectedRange.length, textView.string.count - min(currentSelectedRange.location, textView.string.count))
        )
        textView.setSelectedRange(safeRange)
    }
    
    // Helper method to get the current query based on cursor position
    func getCurrentQuery() -> String {
        let cursorLocation = selectedRange.location
        return extractQueryAtPosition(cursorLocation, from: text)
    }
    
    private func extractQueryAtPosition(_ position: Int, from text: String) -> String {
        let queries = text.components(separatedBy: ";")
        var currentPosition = 0
        
        for query in queries {
            let queryEndPosition = currentPosition + query.count
            if position <= queryEndPosition {
                let cleanedQuery = cleanQuery(query)
                if !cleanedQuery.isEmpty {
                    return cleanedQuery
                }
            }
            currentPosition = queryEndPosition + 1 // +1 for the semicolon
        }
        
        // If no semicolon found or cursor is at the end, return the cleaned entire text
        let cleanedText = cleanQuery(text)
        return cleanedText.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedText
    }
    
    private func cleanQuery(_ query: String) -> String {
        let lines = query.components(separatedBy: .newlines)
        var sqlLines: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip empty lines and comment lines
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("--") {
                sqlLines.append(line) // Keep original indentation for non-comment lines
            }
        }
        
        let cleanedQuery = sqlLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedQuery
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SQLTextEditor
        
        init(_ parent: SQLTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Update parent binding immediately
            self.parent.text = textView.string
            self.parent.selectedRange = textView.selectedRange()
            
            // Apply syntax highlighting with a slight delay to improve performance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.parent.applySyntaxHighlighting(to: textView)
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            DispatchQueue.main.async {
                self.parent.selectedRange = textView.selectedRange()
            }
        }
    }
}