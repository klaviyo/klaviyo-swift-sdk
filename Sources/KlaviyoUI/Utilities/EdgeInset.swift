//
//  EdgeInset.swift
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 11/8/24.
//

import Foundation

enum EdgeInset {
    case top(constant: CGFloat?)
    case leading(constant: CGFloat?)
    case bottom(constant: CGFloat?)
    case trailing(constant: CGFloat?)
    case all(constant: CGFloat?)
    case horizontal(constant: CGFloat?)
    case vertical(constant: CGFloat?)

    static var top: Self { .top(constant: nil) }
    static var leading: Self { .leading(constant: nil) }
    static var bottom: Self { .bottom(constant: nil) }
    static var trailing: Self { .trailing(constant: nil) }
    static var all: Self { .all(constant: nil) }
    static var horizontal: Self { .horizontal(constant: nil) }
    static var vertical: Self { .vertical(constant: nil) }

    var constant: CGFloat? {
        switch self {
        case let .top(constant),
             let .leading(constant),
             let .bottom(constant),
             let .trailing(constant),
             let .horizontal(constant),
             let .vertical(constant),
             let .all(constant):
            return constant
        }
    }
}

extension EdgeInset {
    var containsTop: Bool {
        switch self {
        case .top, .vertical, .all:
            return true
        default:
            return false
        }
    }

    var containsLeading: Bool {
        switch self {
        case .leading, .horizontal, .all:
            return true
        default:
            return false
        }
    }

    var containsBottom: Bool {
        switch self {
        case .bottom, .vertical, .all:
            return true
        default:
            return false
        }
    }

    var containsTrailing: Bool {
        switch self {
        case .trailing, .horizontal, .all:
            return true
        default:
            return false
        }
    }
}
