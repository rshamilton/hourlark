import Foundation

/// Starting points offered in onboarding and on the empty state.
struct CauseTemplate: Identifiable {
    let id: String
    let title: String
    /// Pre-filled cause name. Empty for the "something else" template.
    let name: String
    let symbol: String
    let tint: CauseColor
    let requiresSignOff: Bool
    let blurb: String

    static let all: [CauseTemplate] = [
        .init(id: "service", title: "Community Service", name: "Community Service",
              symbol: "heart.fill", tint: .red, requiresSignOff: true,
              blurb: "Volunteer hours a supervisor signs off"),
        .init(id: "school", title: "School Requirement", name: "School Service Hours",
              symbol: "graduationcap.fill", tint: .purple, requiresSignOff: true,
              blurb: "Hours your school needs verified"),
        .init(id: "internship", title: "Internship", name: "Internship",
              symbol: "building.2.fill", tint: .indigo, requiresSignOff: true,
              blurb: "Hours an employer or program verifies"),
        .init(id: "work", title: "Work", name: "Work",
              symbol: "briefcase.fill", tint: .blue, requiresSignOff: false,
              blurb: "Jobs, shifts and paid work hours"),
        .init(id: "study", title: "Study", name: "Study",
              symbol: "book.fill", tint: .orange, requiresSignOff: false,
              blurb: "Homework and learning"),
        .init(id: "custom", title: "Something Else", name: "",
              symbol: "sparkles", tint: .teal, requiresSignOff: false,
              blurb: "Your own category")
    ]

    func makeCause() -> Cause {
        Cause(name: name, symbol: symbol, tint: tint, requiresSignOff: requiresSignOff)
    }
}
