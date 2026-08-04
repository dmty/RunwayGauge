#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift - <<'SWIFT'
import Foundation

let maxOutputBytes = 8192

func capOutput(_ output: String) -> String {
    guard let data = output.data(using: .utf8), data.count > maxOutputBytes else {
        return output
    }
    var bytes = Array(data.suffix(maxOutputBytes))
    while let first = bytes.first, (first & 0xC0) == 0x80 {
        bytes.removeFirst()
    }
    while !bytes.isEmpty {
        if let decoded = String(bytes: bytes, encoding: .utf8) {
            return decoded
        }
        bytes.removeLast()
    }
    return ""
}

func assert(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let emoji = String(repeating: "🎉", count: 3000)
let emojiBytes = emoji.data(using: .utf8)!.count
assert(emojiBytes > maxOutputBytes, "fixture must exceed cap")

let capped = capOutput(emoji)
let cappedBytes = capped.data(using: .utf8)!.count
assert(cappedBytes <= maxOutputBytes, "capped output exceeds \(maxOutputBytes) bytes (\(cappedBytes))")
assert(!capped.isEmpty, "capped output must not be empty")
assert(capped.data(using: .utf8).flatMap { String(data: $0, encoding: .utf8) } != nil, "capped output must be valid UTF-8")

let ascii = String(repeating: "a", count: 9000)
let cappedAscii = capOutput(ascii)
assert(cappedAscii.data(using: .utf8)!.count == maxOutputBytes, "ascii cap should be exact")

let unchanged = "short"
assert(capOutput(unchanged) == unchanged, "short strings pass through")

print("all cap-output tests passed")
SWIFT
