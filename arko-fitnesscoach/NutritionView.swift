import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Nutrition Models
// ════════════════════════════════════════════════════════════════════════════

struct FoodItem: Identifiable, Hashable {
    let id: Int          // fdcId from USDA
    let name: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
}

struct FoodLog: Identifiable {
    let id = UUID()
    let food: FoodItem
    var gramsConsumed: Double
    let loggedAt: Date

    var kcal:    Double { food.kcalPer100g    * gramsConsumed / 100 }
    var protein: Double { food.proteinPer100g * gramsConsumed / 100 }
    var carbs:   Double { food.carbsPer100g   * gramsConsumed / 100 }
    var fat:     Double { food.fatPer100g     * gramsConsumed / 100 }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - USDA FoodData Service
// Free API — no key required for basic search
// Docs: fdc.nal.usda.gov
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class FoodDataService: ObservableObject {
    static let shared = FoodDataService()

    @Published var searchResults: [FoodItem] = []
    @Published var isSearching = false

    private let apiKey = "DEMO_KEY"   // Free rate: 30/hr · 50/day. Get free key at api.data.gov
    private let base   = "https://api.nal.usda.gov/fdc/v1"

    func search(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "\(base)/foods/search?query=\(q)&dataType=Survey%20(FNDDS)&pageSize=15&api_key=\(apiKey)"
        guard let url = URL(string: urlStr) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            searchResults = resp.foods.compactMap { FoodItem(from: $0) }
        } catch { searchResults = [] }
    }
}

// MARK: USDA Response Models

private struct USDASearchResponse: Decodable {
    let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    let fdcId: Int
    let description: String
    let foodNutrients: [USDANutrient]?
}

private struct USDANutrient: Decodable {
    let nutrientId: Int
    let value: Double?
}

private extension FoodItem {
    init?(from usda: USDAFood) {
        let nutrients = usda.foodNutrients ?? []
        func val(_ id: Int) -> Double {
            nutrients.first { $0.nutrientId == id }?.value ?? 0
        }
        // USDA nutrient IDs: 1008=kcal, 1003=protein, 1005=carbs, 1004=fat
        self.id            = usda.fdcId
        self.name          = usda.description.capitalized
        self.kcalPer100g   = val(1008)
        self.proteinPer100g = val(1003)
        self.carbsPer100g  = val(1005)
        self.fatPer100g    = val(1004)
        if kcalPer100g == 0 { return nil }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - NutritionView
// ════════════════════════════════════════════════════════════════════════════

struct NutritionView: View {
    @StateObject private var foodService = FoodDataService.shared
    @State private var searchText = ""
    @State private var foodLog: [FoodLog] = []
    @State private var selectedFood: FoodItem?
    @State private var gramsInput = "100"
    @State private var showAddSheet = false
    @State private var calorieGoal: Int = UserProfile.load().calorieGoal

    private var dailyKcal:    Double { foodLog.reduce(0) { $0 + $1.kcal } }
    private var dailyProtein: Double { foodLog.reduce(0) { $0 + $1.protein } }
    private var dailyCarbs:   Double { foodLog.reduce(0) { $0 + $1.carbs } }
    private var dailyFat:     Double { foodLog.reduce(0) { $0 + $1.fat } }

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    dailySummaryCard
                    macroRingCard
                    searchCard
                    if !foodLog.isEmpty { logCard }
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
        .sheet(item: $selectedFood) { food in
            addPortionSheet(food: food)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nutrition").font(.caption).foregroundStyle(Color.arkoTextDim)
                Text("Today's Intake").font(.title2.weight(.bold)).foregroundStyle(.white)
            }
            Spacer()
            Text(Date(), style: .date)
                .font(.caption)
                .foregroundStyle(Color.arkoTextDim)
        }
        .padding(.top, 8)
    }

    // MARK: - Daily Summary

    private var dailySummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Calories")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.arkoLime)
                Spacer()
                Text("\(Int(dailyKcal)) / \(calorieGoal) kcal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.arkoTextDim)
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(LinearGradient(
                            colors: dailyKcal > Double(calorieGoal)
                                ? [.red, .red.opacity(0.7)]
                                : [Color.arkoLime, Color.arkoGreen],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * min(dailyKcal / Double(max(calorieGoal, 1)), 1.0))
                        .animation(.easeInOut, value: dailyKcal)
                }
            }
            .frame(height: 10)
        }
        .arkoCard()
    }

    // MARK: - Macro rings

    private var macroRingCard: some View {
        HStack(spacing: 0) {
            macroCell("Protein", value: dailyProtein, goal: 150, color: .blue,     unit: "g")
            Divider().frame(height: 44).overlay(Color.white.opacity(0.08))
            macroCell("Carbs",   value: dailyCarbs,   goal: 250, color: .orange,   unit: "g")
            Divider().frame(height: 44).overlay(Color.white.opacity(0.08))
            macroCell("Fat",     value: dailyFat,     goal: 65,  color: .yellow,   unit: "g")
        }
        .arkoCard()
    }

    private func macroCell(_ label: String, value: Double, goal: Double, color: Color, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Color.arkoTextDim)
            Text(String(format: "%.0f\(unit)", value))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text("/ \(Int(goal))\(unit)")
                .font(.caption2)
                .foregroundStyle(Color.arkoTextDim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Log Food", systemImage: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.arkoTextDim)
                TextField("Search food (e.g. chicken breast)", text: $searchText)
                    .foregroundStyle(.white)
                    .submitLabel(.search)
                    .onSubmit { Task { await foodService.search(searchText) } }
                if foodService.isSearching {
                    ProgressView().tint(Color.arkoLime).scaleEffect(0.8)
                }
            }
            .padding(12)
            .background(Color.arkoCard2)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !foodService.searchResults.isEmpty {
                VStack(spacing: 1) {
                    ForEach(foodService.searchResults.prefix(8)) { food in
                        Button {
                            selectedFood = food
                            showAddSheet = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(String(format: "%.0f kcal · %.1fg P · %.1fg C · %.1fg F per 100g",
                                                food.kcalPer100g, food.proteinPer100g,
                                                food.carbsPer100g, food.fatPer100g))
                                        .font(.caption2)
                                        .foregroundStyle(Color.arkoTextDim)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.arkoLime)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 2)
                        }
                        .buttonStyle(.plain)
                        if food.id != foodService.searchResults.prefix(8).last?.id {
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
                .padding(10)
                .background(Color.arkoCard2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .arkoCard()
    }

    // MARK: - Food Log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today's Log", systemImage: "list.clipboard.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.arkoLime)
                Spacer()
                Button("Clear") { foodLog.removeAll() }
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            ForEach(foodLog) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.food.name).font(.subheadline).lineLimit(1)
                        Text("\(Int(entry.gramsConsumed))g · \(Int(entry.protein))g P · \(Int(entry.carbs))g C · \(Int(entry.fat))g F")
                            .font(.caption2)
                            .foregroundStyle(Color.arkoTextDim)
                    }
                    Spacer()
                    Text("\(Int(entry.kcal)) kcal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.arkoLime)
                }
                .padding(.vertical, 4)
                Divider().background(Color.white.opacity(0.06))
            }
        }
        .arkoCard()
    }

    // MARK: - Add Portion Sheet

    private func addPortionSheet(food: FoodItem) -> some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            VStack(spacing: 20) {
                Text(food.name)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                // Per 100g info
                HStack(spacing: 20) {
                    macroTag("\(Int(food.kcalPer100g)) kcal", color: Color.arkoLime)
                    macroTag("\(Int(food.proteinPer100g))g protein", color: .blue)
                    macroTag("\(Int(food.carbsPer100g))g carbs", color: .orange)
                }

                Text("per 100g").font(.caption2).foregroundStyle(Color.arkoTextDim)

                // Grams input
                VStack(spacing: 8) {
                    Text("Amount (grams)")
                        .font(.subheadline)
                        .foregroundStyle(Color.arkoTextDim)
                    TextField("100", text: $gramsInput)
                        .keyboardType(.numberPad)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.arkoCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 40)
                }

                // Preview
                let grams = Double(gramsInput) ?? 100
                HStack(spacing: 16) {
                    previewStat("\(Int(food.kcalPer100g * grams / 100))", "kcal",    Color.arkoLime)
                    previewStat(String(format: "%.1f", food.proteinPer100g * grams / 100), "g protein", .blue)
                    previewStat(String(format: "%.1f", food.carbsPer100g   * grams / 100), "g carbs",  .orange)
                    previewStat(String(format: "%.1f", food.fatPer100g     * grams / 100), "g fat",    .yellow)
                }
                .padding()
                .background(Color.arkoCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)

                Button("Add to Log") {
                    foodLog.append(FoodLog(
                        food: food,
                        gramsConsumed: grams,
                        loggedAt: Date()
                    ))
                    selectedFood = nil
                    searchText = ""
                    foodService.searchResults = []
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.arkoLime)
                .clipShape(Capsule())
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func macroTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func previewStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Color.arkoTextDim)
        }
        .frame(maxWidth: .infinity)
    }
}

struct NutritionView_Previews: PreviewProvider {
    static var previews: some View {
        NutritionView().preferredColorScheme(.dark)
    }
}
