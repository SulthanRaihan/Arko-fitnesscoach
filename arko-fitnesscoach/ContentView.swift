import SwiftUI

struct ContentView: View {
    @State private var selected = 0

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selected) {
                HomeView().tag(0)
                WorkoutsView().tag(1)
                FormCheckView().tag(2)
                StatsView().tag(3)
                ToolsView().tag(4)
                ProfileView().tag(5)
            }
            .ignoresSafeArea(edges: .bottom)

            ARKOTabBar(selected: $selected)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Custom Tab Bar

private struct TabItem {
    let icon: String
    let tag: Int
}

private struct ARKOTabBar: View {
    @Binding var selected: Int

    private let items: [TabItem] = [
        TabItem(icon: "house.fill",              tag: 0),
        TabItem(icon: "squares.below.rectangle", tag: 1),
        TabItem(icon: "camera.fill",             tag: 2),
        TabItem(icon: "chart.bar.fill",          tag: 3),
        TabItem(icon: "wrench.and.screwdriver.fill", tag: 4),
        TabItem(icon: "person.fill",             tag: 5),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { i in
                let item = items[i]
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selected = item.tag
                    }
                } label: {
                    ZStack {
                        if selected == item.tag {
                            Circle()
                                .fill(Color.arkoLime)
                                .frame(width: 48, height: 48)
                        }
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: selected == item.tag ? .bold : .regular))
                            .foregroundStyle(selected == item.tag ? .black : Color.white.opacity(0.5))
                            .frame(width: 48, height: 48)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.arkoCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
