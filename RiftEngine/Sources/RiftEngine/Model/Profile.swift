/// content profile parameterizing the ladder's rules (sdd §3.3)
public enum Profile: String, Sendable, Hashable, Codable, CaseIterable {
    case prose
    case code
    case plain
}
