import Foundation

/// A block length such as `25 min`, `1 h` or `1 h 30`, already localized.
func blockLength(_ minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 {
        return String(localized: "\(minutes) min")
    }
    if rest == 0 {
        return String(localized: "\(hours) h")
    }
    return String(localized: "\(hours) h \(String(format: "%02d", rest))")
}
