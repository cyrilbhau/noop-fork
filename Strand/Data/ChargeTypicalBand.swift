import Foundation
import StrandAnalytics

/// The "typical range" of a personal baseline, as the Recovery screen draws it for heart rate
/// variability, resting heart rate and respiratory rate. Every reader of that range calls this one
/// function, so the screen and anything quoting it cannot disagree.
enum ChargeTypicalBand {
    /// Baseline ± `Baselines.sigma(state)`: the band `Baselines.deviation` calls normal. Nil unless
    /// the baseline is usable (provisional or trusted), which is "not enough history" to a reader.
    static func range(_ state: BaselineState?) -> ClosedRange<Double>? {
        guard let state, state.usable else { return nil }
        let sigma = Baselines.sigma(state)
        return (state.baseline - sigma)...(state.baseline + sigma)
    }
}
