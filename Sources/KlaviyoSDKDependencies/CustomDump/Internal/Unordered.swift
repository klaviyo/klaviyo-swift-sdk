/// Copied verbatim from swift-case-paths v1.3.2 on 11/15/2024
/// https://github.com/pointfreeco/swift-custom-dump/tree/1.3.2

import Foundation

public protocol _UnorderedCollection {}
extension Dictionary: _UnorderedCollection {}
extension NSDictionary: _UnorderedCollection {}
extension NSSet: _UnorderedCollection {}
extension Set: _UnorderedCollection {}
