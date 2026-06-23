import KlaviyoSwift

// MARK: - ProfileKey emoji shorthands

extension Profile.ProfileKey {
    public static var 👆: Self { .firstName }
    public static var 👇: Self { .lastName }
    public static var 🏠: Self { .address1 }
    public static var 🏘️: Self { .address2 }
    public static var 💼: Self { .title }
    public static var 🏢: Self { .organization }
    public static var 🌆: Self { .city }
    public static var 🗺️: Self { .region }
    public static var 🌍: Self { .country }
    public static var 📮: Self { .zip }
    public static var 🖼️: Self { .image }
    public static var 🧭: Self { .latitude }
    public static var 🌐: Self { .longitude }
    public static func 🗝️(_ key: String) -> Self { .custom(customKey: key) }
}
