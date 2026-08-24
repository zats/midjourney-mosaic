import SwiftUI

@MainActor
final class MosaicSettings: ObservableObject {
    @Published var itemCount = MosaicLimits.defaultItemCount
    @Published var delay = MosaicLimits.defaultDelay
    @Published var isAnimating = true
    @Published var showsControls = true
}

struct ContentView: View {
    @ObservedObject var settings: MosaicSettings

    var body: some View {
        ZStack(alignment: .bottom) {
            MosaicRepresentable(settings: settings)
                .ignoresSafeArea()

            if settings.showsControls {
                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(Color.black)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(settings.isAnimating ? "Pause" : "Resume") {
                settings.isAnimating.toggle()
            }
            .buttonStyle(.borderedProminent)

            Text("\(settings.itemCount) images")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 86, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(settings.itemCount) },
                    set: { settings.itemCount = Int($0.rounded()) }
                ),
                in: Double(MosaicLimits.minimumItemCount)...Double(MosaicLimits.maximumItemCount),
                step: 1
            )
            .frame(minWidth: 180)

            Divider().frame(height: 20)

            Text("Delay \(settings.delay, specifier: "%.0f")s")
                .monospacedDigit()
                .frame(width: 72, alignment: .leading)

            Slider(
                value: $settings.delay,
                in: MosaicLimits.minimumDelay...MosaicLimits.maximumDelay,
                step: 1
            )
                .frame(width: 110)

            Button {
                settings.showsControls = false
            } label: {
                Image(systemName: "eye.slash")
            }
            .help("Hide controls (relaunch to restore)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
    }
}

private struct MosaicRepresentable: NSViewRepresentable {
    @ObservedObject var settings: MosaicSettings

    func makeNSView(context: Context) -> MosaicView {
        let view = MosaicView()
        view.configure(
            items: StaticExploreSource.load(),
            itemCount: settings.itemCount,
            delay: settings.delay,
            isAnimating: settings.isAnimating
        )
        return view
    }

    func updateNSView(_ view: MosaicView, context: Context) {
        view.configure(
            items: StaticExploreSource.load(),
            itemCount: settings.itemCount,
            delay: settings.delay,
            isAnimating: settings.isAnimating
        )
    }
}
