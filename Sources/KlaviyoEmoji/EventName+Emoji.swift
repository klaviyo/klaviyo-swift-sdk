import KlaviyoSwift

// MARK: - EventName emoji shorthands

extension Event.EventName {
    /// Opened App metric.
    public static var 📱: Self { .openedAppMetric }

    /// Viewed Product metric.
    public static var 👀: Self { .viewedProductMetric }

    /// Added to Cart metric.
    public static var 🛒: Self { .addedToCartMetric }

    /// Started Checkout metric.
    public static var 💳: Self { .startedCheckoutMetric }

    /// A custom event with the given name.
    public static func 🎯(_ name: String) -> Self { .customEvent(name) }
}
