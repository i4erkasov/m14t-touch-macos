import CoreGraphics

/// Something that can show where the panel thinks fingers are.
///
/// A diagnostic rather than a feature: it answers "is the panel seeing my
/// finger, and does it think it is where I put it?" — two questions that look
/// identical when nothing happens, and which no amount of watching the pointer
/// can separate.
///
/// Calls arrive on the touch queue at the rate the panel reports, so an
/// implementation is expected to coalesce rather than touch the interface once
/// per frame. The same contract as `PenPointerDisplay`, and for the same
/// reasons.
protocol TouchPointDisplay: AnyObject {

    /// Where every contact currently is, in Quartz global coordinates. Empty
    /// when nothing is touching.
    func show(_ points: [CGPoint])
}
