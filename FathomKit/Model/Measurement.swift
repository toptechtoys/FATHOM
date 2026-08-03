/// A value that preserves whether macOS published it and whether FATHOM can
/// fully attribute it.
///
/// There is deliberately no `unknown` case or optional convenience accessor.
public enum Measurement<Value: Sendable>: Sendable {
    case known(Value, source: DataSource)
    case notPublished(reason: String)
    case notAttributable(measured: Value, explained: Value)
}

extension Measurement: Equatable where Value: Equatable {}

extension Measurement: Codable where Value: Codable {
    private enum CodingKeys: String, CodingKey {
        case state
        case value
        case source
        case reason
        case measured
        case explained
    }

    private enum State: String, Codable {
        case known
        case notPublished
        case notAttributable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .known:
            self = .known(
                try container.decode(Value.self, forKey: .value),
                source: try container.decode(DataSource.self, forKey: .source)
            )
        case .notPublished:
            self = .notPublished(
                reason: try container.decode(String.self, forKey: .reason)
            )
        case .notAttributable:
            self = .notAttributable(
                measured: try container.decode(Value.self, forKey: .measured),
                explained: try container.decode(Value.self, forKey: .explained)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .known(value, source):
            try container.encode(State.known, forKey: .state)
            try container.encode(value, forKey: .value)
            try container.encode(source, forKey: .source)
        case let .notPublished(reason):
            try container.encode(State.notPublished, forKey: .state)
            try container.encode(reason, forKey: .reason)
        case let .notAttributable(measured, explained):
            try container.encode(State.notAttributable, forKey: .state)
            try container.encode(measured, forKey: .measured)
            try container.encode(explained, forKey: .explained)
        }
    }
}
