package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type CTAMatch struct {
	Timestamp   string `json:"timestamp"`
	Text        string `json:"text"`
	Pattern     string `json:"pattern"`
	PatternType string `json:"pattern_type"`
}

type match struct {
	pos         int
	pattern     string
	patternType string
}

var engagementPatterns = map[string][]string{
	"like": {
		"like this video",
		"like the video",
		"give it a like",
		"smash that like",
		"hit the like",
		"don't forget to like",
		"please like",
	},
	"subscribe": {
		"subscribe for more",
		"subscribe if you want",
		"don't forget to subscribe",
		"make sure to subscribe",
		"please subscribe",
		"hit subscribe",
	},
	"like_and_subscribe": {
		"like and subscribe",
		"like comment subscribe",
		"like share subscribe",
	},
	"bell_notification": {
		"hit that bell",
		"ring that bell",
		"smash that bell",
		"notification bell",
		"turn on notifications",
	},
	"general_cta": {
		"support the channel",
		"thanks for watching",
		"see you in the next",
	},
}

// Buffer pool to reduce allocations
var bufferPool = sync.Pool{
	New: func() interface{} {
		return new(bytes.Buffer)
	},
}

func detectEngagementPrompts(vttContent []byte) []CTAMatch {
	vttLower := bytes.ToLower(vttContent)

	// Collect all matches with their positions in a single pass
	var allMatches []match

	// Single pass through content finding all pattern occurrences
	for patternType, patterns := range engagementPatterns {
		for _, pattern := range patterns {
			patternBytes := []byte(pattern)
			pos := 0

			// Find all occurrences of this pattern
			for {
				idx := bytes.Index(vttLower[pos:], patternBytes)
				if idx == -1 {
					break
				}

				absolutePos := pos + idx
				allMatches = append(allMatches, match{
					pos:         absolutePos,
					pattern:     pattern,
					patternType: patternType,
				})

				pos = absolutePos + 1
			}
		}
	}

	// Now parse only the blocks containing matches
	seen := make(map[int]bool)
	var results []CTAMatch

	for _, m := range allMatches {
		// Skip if we've already processed this position
		if seen[m.pos] {
			continue
		}
		seen[m.pos] = true

		// Parse the block at this position
		timestamp, text := parseBlockAtPosition(vttContent, m.pos)
		if timestamp != "" {
			// Extract the actual matched text from original content
			matchedText := string(vttContent[m.pos : m.pos+len(m.pattern)])

			results = append(results, CTAMatch{
				Timestamp:   timestamp,
				Text:        text,
				Pattern:     matchedText,
				PatternType: m.patternType,
			})
		}
	}

	return results
}

func parseBlockAtPosition(vttContent []byte, matchPos int) (string, string) {
	// Walk backwards up to 300 bytes to find block start
	searchStart := matchPos - 300
	if searchStart < 0 {
		searchStart = 0
	}

	// Find the last "\n\n" before the match (block separator)
	blockStart := searchStart
	searchContent := vttContent[searchStart:matchPos]

	lastSep := bytes.LastIndex(searchContent, []byte("\n\n"))
	if lastSep != -1 {
		blockStart = searchStart + lastSep + 2 // +2 to skip "\n\n"
	}

	// Find the end of this block (next "\n\n" or end of content)
	blockEnd := len(vttContent)
	remainingContent := vttContent[blockStart:]

	nextSep := bytes.Index(remainingContent, []byte("\n\n"))
	if nextSep != -1 {
		blockEnd = blockStart + nextSep
	}

	// Extract and parse the block
	block := vttContent[blockStart:blockEnd]
	return parseSubtitleBlock(block)
}

func parseSubtitleBlock(block []byte) (string, string) {
	lines := bytes.Split(block, []byte("\n"))

	// Filter out empty lines
	var nonEmptyLines [][]byte
	for _, line := range lines {
		trimmed := bytes.TrimSpace(line)
		if len(trimmed) > 0 {
			nonEmptyLines = append(nonEmptyLines, trimmed)
		}
	}

	if len(nonEmptyLines) < 2 {
		return "", ""
	}

	timestampLine := nonEmptyLines[0]
	textLines := nonEmptyLines[1:]

	// Check if this looks like a timestamp line
	if !bytes.Contains(timestampLine, []byte("-->")) {
		return "", ""
	}

	// Clean timestamp line of alignment/position attributes
	timestamp := string(timestampLine)
	if idx := strings.Index(timestamp, " align:"); idx != -1 {
		timestamp = timestamp[:idx]
	}
	timestamp = strings.TrimSpace(timestamp)

	// Join all text lines and clean up
	var textParts []string
	for _, line := range textLines {
		textParts = append(textParts, string(line))
	}
	text := strings.Join(textParts, " ")
	text = cleanText(text)

	return timestamp, text
}

func cleanText(text string) string {
	// Simple HTML tag removal
	var result strings.Builder
	inTag := false

	for _, ch := range text {
		if ch == '<' {
			inTag = true
		} else if ch == '>' {
			inTag = false
		} else if !inTag {
			result.WriteRune(ch)
		}
	}

	// Normalize whitespace
	normalized := strings.Join(strings.Fields(result.String()), " ")
	return strings.TrimSpace(normalized)
}

func handleDetect(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Limit request body size to 10MB
	r.Body = http.MaxBytesReader(w, r.Body, 10*1024*1024)

	// Get buffer from pool
	buf := bufferPool.Get().(*bytes.Buffer)
	buf.Reset()
	defer bufferPool.Put(buf)

	// Read request body
	if _, err := io.Copy(buf, r.Body); err != nil {
		http.Error(w, "Failed to read request body", http.StatusBadRequest)
		return
	}

	// Process VTT content
	matches := detectEngagementPrompts(buf.Bytes())

	// Write response
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(matches); err != nil {
		log.Printf("Failed to encode response: %v", err)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/detect", handleDetect)
	mux.HandleFunc("/health", handleHealth)

	// Get port from environment variable, default to 8080
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := ":" + port

	server := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
		// Increase max header size for larger requests
		MaxHeaderBytes: 1 << 20, // 1MB
	}

	log.Printf("CTA Extractor HTTP service listening on %s", addr)
	log.Fatal(server.ListenAndServe())
}
