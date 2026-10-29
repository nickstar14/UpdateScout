import Foundation

/// The package managers themselves. They're Homebrew formulae, so they still
/// come from HomebrewSource and install through the Homebrew lane, keeping
/// their item ids; the window just shows them in their own Tools section.
enum Tools {
    /// The lane of the packages a tool manages, or nil when it has none here.
    /// A tool and its packages never update at the same time: updating node
    /// swaps out the npm that an npm package update would be running.
    static func packageLane(ofFormula name: String) -> String? {
        if name == "node" || name.hasPrefix("node@") { return "npm" }
        if ["pipx", "uv", "python"].contains(name) || name.hasPrefix("python@") { return "pip" }
        if name == "mas" { return "mas" }
        return nil
    }

    static func isTool(formula name: String) -> Bool {
        packageLane(ofFormula: name) != nil || name == "rust"
    }

    /// The formula name when this item is a tool, else nil.
    static func formula(of item: UpdateItem) -> String? {
        guard item.sourceID == "homebrew", item.installToken.hasPrefix("formula:") else { return nil }
        let name = String(item.installToken.dropFirst("formula:".count))
        return isTool(formula: name) ? name : nil
    }
}

extension UpdateItem {
    /// Which window section shows this item: its source, except that
    /// package-manager formulae go under Tools.
    var sectionID: String { Tools.formula(of: self) != nil ? "tools" : sourceID }
}
