/// Copied verbatim from Swift Issue Reporting v1.3.0 on 11/15/2024
/// https://github.com/pointfreeco/swift-issue-reporting/tree/1.3.0


// NB: Deprecated after 1.2.2

#if canImport(Darwin)
  @available(*, unavailable, renamed: "_BreakpointReporter")
  public typealias BreakpointReporter = _BreakpointReporter
#endif

@available(*, unavailable, renamed: "_FatalErrorReporter")
public typealias FatalErrorReporter = _FatalErrorReporter

@available(*, unavailable, renamed: "_RuntimeWarningReporter")
public typealias RuntimeWarningReporter = _RuntimeWarningReporter
