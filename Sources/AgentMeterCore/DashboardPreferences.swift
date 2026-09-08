import Foundation

public final class DashboardPreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var firstProvider: Provider {
        get { providers[0] }
        set { providers = [newValue] + providers.filter { $0 != newValue } }
    }

    public var providers: [Provider] {
        get {
            if let saved = defaults.stringArray(forKey: "dashboardProviderOrder") {
                return Self.normalized(saved.compactMap(Provider.init(rawValue:)))
            }
            let legacy = Provider(rawValue: defaults.string(forKey: "dashboardFirstProvider") ?? "") ?? .claude
            return Self.normalized([legacy])
        }
        set {
            let order = Self.normalized(newValue)
            defaults.set(order.map(\.rawValue), forKey: "dashboardProviderOrder")
            defaults.set(order[0].rawValue, forKey: "dashboardFirstProvider")
        }
    }

    /// Moves an agent to its final zero-based position, preserving all other agents' order.
    public func moveProvider(_ provider: Provider, to index: Int) {
        var order = providers
        guard order.indices.contains(index), let source = order.firstIndex(of: provider), source != index else { return }
        order.remove(at: source)
        order.insert(provider, at: index)
        providers = order
    }

    private static func normalized(_ order: [Provider]) -> [Provider] {
        var seen = Set<Provider>()
        return (order + Provider.allCases).filter { seen.insert($0).inserted }
    }
}
