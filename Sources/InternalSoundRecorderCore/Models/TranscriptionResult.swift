import Foundation

public struct TranscriptSegment: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID = UUID()
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    public let text: String
    public var confidence: Float?
    public var languageCode: String?

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        duration: TimeInterval,
        text: String,
        confidence: Float? = nil,
        languageCode: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.text = text
        self.confidence = confidence
        self.languageCode = languageCode
    }

    public var endTimestamp: TimeInterval {
        timestamp + duration
    }

    public var formattedTimestamp: String {
        let totalSeconds = Int(timestamp)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    public var formattedTimestampRange: String {
        let start = formattedTimestamp
        let totalSeconds = Int(endTimestamp)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let end = hours > 0 ? String(format: "%02d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
        return "\(start) - \(end)"
    }
}

public struct TranscriptionResult: Sendable {
    public let fullText: String
    public let segments: [TranscriptSegment]
    public let detectedLanguages: [String]

    public init(
        fullText: String,
        segments: [TranscriptSegment],
        detectedLanguages: [String] = []
    ) {
        self.fullText = fullText
        self.segments = segments
        self.detectedLanguages = detectedLanguages
    }

    // MARK: - Smart Subtitle Aggregation (Word -> Conversational Phrase Chunking)

    /// Aggregates word-level segments into natural, readable subtitle phrases.
    /// Breaks on sentence-ending punctuation (.?!), acoustic silence pauses (>0.65s),
    /// or when character length exceeds standard subtitle line width (40-70 characters).
    public func aggregatedPhrases(
        maxCharactersPerCard: Int = 70,
        pauseBreakThreshold: TimeInterval = 0.65,
        minCardDuration: TimeInterval = 1.2,
        maxCardDuration: TimeInterval = 6.0
    ) -> [TranscriptSegment] {
        guard !segments.isEmpty else {
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [TranscriptSegment(timestamp: 0, duration: 3.0, text: fullText.trimmingCharacters(in: .whitespacesAndNewlines))]
            }
            return []
        }

        // If segments are already multi-word sentences (e.g. containing multiple spaces),
        // return them directly to preserve existing phrase segmentations.
        let isAlreadyAggregated = segments.allSatisfy { $0.text.split(separator: " ").count >= 3 }
        if isAlreadyAggregated && segments.count <= 20 {
            return segments
        }

        var aggregated: [TranscriptSegment] = []
        var currentWords: [TranscriptSegment] = []
        var currentLength = 0

        func flushCurrentCard() {
            guard let first = currentWords.first, let last = currentWords.last else { return }
            let combinedText = currentWords.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            let start = first.timestamp
            let rawDuration = max(0.2, (last.timestamp + last.duration) - start)
            let finalDuration = max(minCardDuration, min(maxCardDuration, rawDuration))

            let phraseSegment = TranscriptSegment(
                id: UUID(),
                timestamp: start,
                duration: finalDuration,
                text: combinedText,
                confidence: first.confidence,
                languageCode: first.languageCode
            )
            aggregated.append(phraseSegment)
            currentWords.removeAll(keepingCapacity: true)
            currentLength = 0
        }

        let sentencePunctuation: Set<Character> = [".", "?", "!", ";"]

        for (i, word) in segments.enumerated() {
            let trimmedWord = word.text.trimmingCharacters(in: .whitespaces)
            guard !trimmedWord.isEmpty else { continue }

            let wordLen = trimmedWord.count + 1 // + space
            let hasSentenceEnding = trimmedWord.last.map { sentencePunctuation.contains($0) } ?? false

            // Check if there is an acoustic pause before this word
            let hasAcousticPause: Bool
            if let lastWord = currentWords.last {
                let gap = word.timestamp - (lastWord.timestamp + lastWord.duration)
                hasAcousticPause = gap >= pauseBreakThreshold
            } else {
                hasAcousticPause = false
            }

            // Check if adding this word would exceed comfortable subtitle length
            let wouldExceedLength = (currentLength + wordLen) > maxCharactersPerCard && !currentWords.isEmpty

            // Check duration limit
            let wouldExceedDuration: Bool
            if let first = currentWords.first {
                let currentSpan = (word.timestamp + word.duration) - first.timestamp
                wouldExceedDuration = currentSpan > maxCardDuration
            } else {
                wouldExceedDuration = false
            }

            if hasAcousticPause || wouldExceedLength || wouldExceedDuration {
                flushCurrentCard()
            }

            currentWords.append(word)
            currentLength += wordLen

            // Sentence boundary triggers a clean subtitle card break
            if hasSentenceEnding {
                flushCurrentCard()
            }

            // Final word
            if i == segments.count - 1 {
                flushCurrentCard()
            }
        }

        return aggregated
    }

    // MARK: - SubRip (.srt) Output

    /// Generates compliant SubRip (.srt) subtitle format paired for QuickTime, VLC, and IINA
    public var srtFormat: String {
        let phrases = aggregatedPhrases()
        var srt = ""
        for (index, segment) in phrases.enumerated() {
            let start = formatSRTTime(segment.timestamp)
            let end = formatSRTTime(segment.timestamp + segment.duration)
            srt += "\(index + 1)\n"
            srt += "\(start) --> \(end)\n"

            // Break into 2 lines if longer than 42 characters for TV/media readability
            let formattedText = wrapSubtitleText(segment.text, maxCharsPerLine: 42)
            srt += "\(formattedText)\n\n"
        }
        return srt
    }

    // MARK: - Structured Markdown Meeting Notes (.md)

    /// Generates structured Markdown meeting notes with markers, recording metadata, and timestamped sections
    public func markdownMeetingNotes(
        recordingName: String,
        markers: [MarkerItem] = [],
        audioDuration: TimeInterval? = nil,
        languageName: String? = nil
    ) -> String {
        var md = "# Meeting Notes — \(recordingName)\n\n"
        md += "**Generated by**: MacAudioRecorder (On-Device AI Engine)\n"
        md += "**Date**: \(Date().formatted(date: .long, time: .shortened))\n"

        if let duration = audioDuration, duration > 0 {
            let totalSeconds = Int(duration)
            let mins = totalSeconds / 60
            let secs = totalSeconds % 60
            md += "**Duration**: \(mins)m \(secs)s\n"
        }

        if let lang = languageName {
            md += "**Language**: \(lang)\n"
        } else if !detectedLanguages.isEmpty {
            md += "**Languages Detected**: \(detectedLanguages.joined(separator: ", "))\n"
        }
        md += "\n---\n\n"

        // 1. Key Discussion Markers Section
        if !markers.isEmpty {
            md += "## 📍 Key Discussion Markers\n\n"
            for m in markers {
                md += "- **[\(m.formattedTimestamp)]** \(m.label)\n"
            }
            md += "\n---\n\n"
        }

        // 2. Full Structured Transcript
        md += "## 📝 Full Meeting Transcript\n\n"

        let phrases = aggregatedPhrases(maxCharactersPerCard: 120, pauseBreakThreshold: 0.8, minCardDuration: 1.0, maxCardDuration: 10.0)

        if phrases.isEmpty {
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                md += "\(fullText.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            } else {
                md += "*No spoken dialogue was detected in this recording (audio was silent or purely instrumental).*\n\n"
            }
        } else {
            // Group phrases into conversational paragraphs (blocks of 30-60s or by markers)
            var currentBlockTime: TimeInterval = phrases.first?.timestamp ?? 0
            var currentBlockText: [String] = []

            for phrase in phrases {
                if phrase.timestamp - currentBlockTime >= 45.0 && !currentBlockText.isEmpty {
                    let blockHeader = formatBlockTimestamp(currentBlockTime)
                    md += "### [\(blockHeader)]\n\n"
                    md += "\(currentBlockText.joined(separator: " "))\n\n"

                    currentBlockTime = phrase.timestamp
                    currentBlockText.removeAll(keepingCapacity: true)
                }
                currentBlockText.append(phrase.text)
            }

            if !currentBlockText.isEmpty {
                let blockHeader = formatBlockTimestamp(currentBlockTime)
                md += "### [\(blockHeader)]\n\n"
                md += "\(currentBlockText.joined(separator: " "))\n\n"
            }
        }

        return md
    }

    // MARK: - Format Helpers

    private func formatSRTTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1.0)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", max(0, hours), max(0, minutes), max(0, seconds), max(0, millis))
    }

    private func formatBlockTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func wrapSubtitleText(_ text: String, maxCharsPerLine: Int) -> String {
        guard text.count > maxCharsPerLine else { return text }

        let words = text.split(separator: " ")
        var line1: [Substring] = []
        var line2: [Substring] = []
        var len1 = 0

        let half = text.count / 2
        for w in words {
            if len1 + w.count < half || line1.isEmpty {
                line1.append(w)
                len1 += w.count + 1
            } else {
                line2.append(w)
            }
        }

        if line2.isEmpty {
            return text
        }
        return "\(line1.joined(separator: " "))\n\(line2.joined(separator: " "))"
    }
}
