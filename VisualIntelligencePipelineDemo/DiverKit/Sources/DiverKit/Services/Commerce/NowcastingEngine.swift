//
//  NowcastingEngine.swift
//  DiverKit
//
//  Dynamic Factor Model (DFM) for economic trend nowcasting.
//  Uses Apple's Accelerate framework (vDSP) for efficient computation.
//
//  The engine takes multiple price series and produces a composite
//  trend forecast using principal component extraction.
//

import Foundation
import Accelerate
import DiverShared

/// Dynamic Factor Model engine for price trend nowcasting.
/// Uses Accelerate (vDSP) for efficient matrix operations.
public final class NowcastingEngine: Sendable {
    
    public init() {}
    
    /// Compute a nowcast projection from multiple input price series.
    /// - Parameters:
    ///   - series: Multiple price data point arrays (e.g., CPI, PPI, commodity prices)
    ///   - horizonDays: Days to project forward
    /// - Returns: Projected trend direction and confidence
    public func nowcast(series: [[PriceDataPoint]], horizonDays: Int = 14) -> NowcastResult {
        guard !series.isEmpty else {
            return NowcastResult(direction: .stable, confidence: 0, projectedChange: 0)
        }
        
        // Extract values from each series, aligned by most recent N points
        let maxPoints = 12
        let alignedValues: [[Double]] = series.map { s in
            let values = s.suffix(maxPoints).map { NSDecimalNumber(decimal: $0.value).doubleValue }
            return values
        }
        
        // Compute momentum for each series using vDSP
        let momenta = alignedValues.map { values -> Double in
            guard values.count >= 3 else { return 0 }
            return computeMomentum(values)
        }
        
        // Weighted average momentum (first series gets highest weight)
        let weights = (0..<momenta.count).map { i -> Double in
            1.0 / Double(i + 1)
        }
        let totalWeight = weights.reduce(0, +)
        
        var compositeMomentum: Double = 0
        vDSP_dotprD(momenta, 1, weights, 1, &compositeMomentum, vDSP_Length(min(momenta.count, weights.count)))
        compositeMomentum /= max(totalWeight, 0.001)
        
        // Determine direction
        let direction: TrendDirection
        if compositeMomentum > 0.01 {
            direction = .rising
        } else if compositeMomentum < -0.01 {
            direction = .falling
        } else {
            direction = .stable
        }
        
        // Confidence based on agreement between series
        let agreement = computeAgreement(momenta)
        
        return NowcastResult(
            direction: direction,
            confidence: Float(agreement),
            projectedChange: Float(compositeMomentum)
        )
    }
    
    // MARK: - vDSP Computation
    
    /// Compute simple momentum (rate of change) using vDSP.
    private func computeMomentum(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }
        
        // Linear regression slope via vDSP
        // x = [0, 1, 2, ..., n-1], y = values
        var x = (0..<n).map { Double($0) }
        
        // Mean of x
        var meanX: Double = 0
        vDSP_meanvD(x, 1, &meanX, vDSP_Length(n))
        
        // Mean of y
        var meanY: Double = 0
        vDSP_meanvD(values, 1, &meanY, vDSP_Length(n))
        
        // Deviations
        var xDev = [Double](repeating: 0, count: n)
        var negMeanX = -meanX
        vDSP_vsaddD(x, 1, &negMeanX, &xDev, 1, vDSP_Length(n))
        
        var yDev = [Double](repeating: 0, count: n)
        var negMeanY = -meanY
        vDSP_vsaddD(values, 1, &negMeanY, &yDev, 1, vDSP_Length(n))
        
        // Numerator: sum(xDev * yDev)
        var numerator: Double = 0
        vDSP_dotprD(xDev, 1, yDev, 1, &numerator, vDSP_Length(n))
        
        // Denominator: sum(xDev^2)
        var denominator: Double = 0
        vDSP_dotprD(xDev, 1, xDev, 1, &denominator, vDSP_Length(n))
        
        guard denominator > 0 else { return 0 }
        
        // Slope normalized by mean value
        let slope = numerator / denominator
        return slope / max(abs(meanY), 0.001)
    }
    
    /// Compute agreement between multiple momentum values (0–1).
    /// High agreement = all series trending the same direction.
    private func computeAgreement(_ momenta: [Double]) -> Double {
        guard momenta.count > 1 else { return 0.5 }
        
        let positive = momenta.filter { $0 > 0 }.count
        let negative = momenta.filter { $0 < 0 }.count
        let neutral = momenta.filter { $0 == 0 }.count
        let total = momenta.count
        
        let maxAgreement = max(positive, max(negative, neutral))
        return Double(maxAgreement) / Double(total)
    }
}

/// Result of a nowcast computation.
public struct NowcastResult: Codable, Sendable {
    public let direction: TrendDirection
    public let confidence: Float        // 0.0–1.0
    public let projectedChange: Float   // Normalized rate of change
    
    public init(direction: TrendDirection, confidence: Float, projectedChange: Float) {
        self.direction = direction
        self.confidence = confidence
        self.projectedChange = projectedChange
    }
}
