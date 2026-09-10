import SwiftUI

/// The full-screen calibration overlay (spec §15).
///
/// Everything is positioned in fractions of the view, the same fractions the
/// session reasons in, so what is drawn and what a touch is measured against
/// cannot disagree.
struct CalibrationOverlayView: View {

    let session: GuidedCalibration
    let onPress: (GuidedCalibration.Button) -> Void
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.88).ignoresSafeArea()

                switch session.phase {
                case .aiming:
                    aiming(in: geometry.size)
                case .verifying:
                    verifying(in: geometry.size)
                case .unusable:
                    message(
                        title: "That didn't work",
                        detail: "The touches didn't say enough about the panel. Try again, and touch each target squarely.",
                        action: "Try again",
                        role: .retry
                    )
                case .finished:
                    Color.clear
                }

                VStack {
                    Spacer()
                    Text("Press Esc to cancel")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 40)
                }
            }
        }
        .background(KeyCatcher(onEscape: onCancel))
    }

    // MARK: - Aiming

    @ViewBuilder
    private func aiming(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            Text("Touch each target")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
            Text("\(session.collector.samples.count + 1) of \(session.collector.targets.count)")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }

        if let target = session.currentTarget {
            Target()
                .position(x: target.x * size.width, y: target.y * size.height)
                // Redrawn from scratch per target, so the ring's attention-getting
                // animation restarts rather than continuing mid-pulse.
                .id(session.collector.samples.count)
        }
    }

    // MARK: - Verifying

    @ViewBuilder
    private func verifying(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            Text("Does the dot follow your finger?")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
            Text("Drag around the edges, then keep it or start over.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
        }
        .position(x: size.width / 2, y: size.height * 0.36)

        ForEach(GuidedCalibration.Button.allCases, id: \.self) { button in
            OverlayButton(title: button.title, isPrimary: button == .save)
                .frame(width: button.rect.width * size.width,
                       height: button.rect.height * size.height)
                .position(x: button.rect.midX * size.width, y: button.rect.midY * size.height)
                .onTapGesture { onPress(button) }
        }

        if let marker = session.marker {
            Circle()
                .fill(.green)
                .frame(width: 26, height: 26)
                .shadow(color: .green.opacity(0.7), radius: 12)
                .position(x: marker.x * size.width, y: marker.y * size.height)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Message

    @ViewBuilder
    private func message(title: String, detail: String, action: String,
                         role: GuidedCalibration.Button) -> some View {
        VStack(spacing: 18) {
            Text(title).font(.system(size: 30, weight: .medium)).foregroundStyle(.white)
            Text(detail)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            OverlayButton(title: action, isPrimary: true)
                .frame(width: 190, height: 54)
                .onTapGesture { onPress(role) }
        }
    }
}

// MARK: - Pieces

private struct Target: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 2)
                .frame(width: pulsing ? 84 : 54, height: pulsing ? 84 : 54)
                .opacity(pulsing ? 0 : 1)
            Circle().stroke(.white, lineWidth: 2).frame(width: 42, height: 42)
            Circle().fill(.white).frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

private struct OverlayButton: View {
    let title: String
    let isPrimary: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isPrimary ? Color.accentColor : Color.white.opacity(0.14))
            Text(title).font(.title3.weight(.medium)).foregroundStyle(.white)
        }
    }
}

/// Escape has to work even though the overlay owns the whole screen and its
/// buttons are reachable by finger; there has to be a way out that does not
/// depend on the calibration being good enough to hit anything.
private struct KeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatchingView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatchingView)?.onEscape = onEscape
    }

    private final class CatchingView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
        override func cancelOperation(_ sender: Any?) { onEscape?() }
    }
}

private extension GuidedCalibration.Button {
    var title: String {
        switch self {
        case .save:  return "Keep it"
        case .retry: return "Start over"
        }
    }
}
