import Foundation
import AgentMeterCore

let arguments = CommandLine.arguments
let destination: URL
if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
    destination = URL(fileURLWithPath: arguments[index + 1])
} else { destination = ClaudeBridge.defaultDestination }
do {
    try ClaudeBridge.capture(data: FileHandle.standardInput.readDataToEndOfFile(), destination: destination)
    let windows = try JSONDecoder().decode([QuotaWindow].self, from: Data(contentsOf: destination))
    let summary = windows.map { "\($0.label) \(Int($0.usedPercent))%" }.joined(separator: " · ")
    print(summary.isEmpty ? "Agent Meter · 한도 정보 대기" : "Agent Meter · " + summary)
} catch {
    FileHandle.standardError.write(Data("Agent Meter: 한도 정보를 수집하지 못했습니다.\n".utf8))
    exit(1)
}
