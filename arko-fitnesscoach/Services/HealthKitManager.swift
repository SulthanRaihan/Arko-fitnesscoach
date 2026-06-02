import HealthKit
import Foundation

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    @Published var activeEnergy: Double = 0
    @Published var steps: Int = 0
    @Published var restingHR: Int = 0
    @Published var isAuthorized = false

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
    ]

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            await MainActor.run { isAuthorized = true }
            await fetchAll()
        } catch {}
    }

    func fetchAll() async {
        async let e = fetchTodaySum(id: .activeEnergyBurned, unit: .kilocalorie())
        async let s = fetchTodaySum(id: .stepCount, unit: .count())
        async let h = fetchMostRecent(id: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        let (energy, stepCount, hr) = await (e, s, h)
        await MainActor.run {
            activeEnergy = energy
            steps        = Int(stepCount)
            restingHR    = Int(hr)
        }
    }

    private func fetchTodaySum(id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, r, _ in
                cont.resume(returning: r?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func fetchMostRecent(id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: .distantPast, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteMostRecent) { _, r, _ in
                cont.resume(returning: r?.mostRecentQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }
}
