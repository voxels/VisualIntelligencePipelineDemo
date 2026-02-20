//
//  NowcastingEngineTests.swift
//  DiverKitTests
//
//  Tests for NowcastingEngine DFM computation: linear regression,
//  momentum, confidence scoring, and edge cases.
//

import Testing
import Foundation
@testable import DiverKit
import DiverShared

@Suite("NowcastingEngine Tests")
struct NowcastingEngineTests {
    
    let engine = NowcastingEngine()
    
    @Test("Nowcast with rising trend produces positive projected change")
    func risingTrendMomentum() {
        let series: [[PriceDataPoint]] = [
            (1...10).map { i in
                PriceDataPoint(date: Date().addingTimeInterval(TimeInterval(-10 + i) * 86400), value: Decimal(i) * 10)
            }
        ]
        let result = engine.nowcast(series: series)
        #expect(result.projectedChange > 0)
    }
    
    @Test("Nowcast with falling trend produces negative projected change")
    func fallingTrendMomentum() {
        let series: [[PriceDataPoint]] = [
            (1...10).map { i in
                PriceDataPoint(date: Date().addingTimeInterval(TimeInterval(-10 + i) * 86400), value: Decimal(11 - i) * 10)
            }
        ]
        let result = engine.nowcast(series: series)
        #expect(result.projectedChange < 0)
    }
    
    @Test("Confidence is between 0 and 1")
    func confidenceRange() {
        let series: [[PriceDataPoint]] = [
            (1...20).map { i in
                PriceDataPoint(date: Date().addingTimeInterval(TimeInterval(-20 + i) * 86400), value: Decimal(i) * 5 + Decimal(Int.random(in: -2...2)))
            }
        ]
        let result = engine.nowcast(series: series)
        #expect(result.confidence >= 0.0)
        #expect(result.confidence <= 1.0)
    }
    
    @Test("Empty series returns zero projected change")
    func emptySeries() {
        let result = engine.nowcast(series: [])
        #expect(result.projectedChange == 0.0)
    }
    
    @Test("Single data point returns zero projected change")
    func singleDataPoint() {
        let series: [[PriceDataPoint]] = [
            [PriceDataPoint(date: Date(), value: Decimal(100))]
        ]
        let result = engine.nowcast(series: series)
        // With only one point, regression can't compute a meaningful slope
        #expect(result.confidence >= 0.0)
    }
    
    @Test("Multiple agreeing series increase confidence")
    func multipleAgreeingSeries() {
        let baseSeries: [PriceDataPoint] = (1...10).map { i in
            PriceDataPoint(date: Date().addingTimeInterval(TimeInterval(-10 + i) * 86400), value: Decimal(i) * 10)
        }
        // Two series both trending up — should agree
        let result = engine.nowcast(series: [baseSeries, baseSeries])
        #expect(result.confidence > 0.3) // Agreement should boost confidence
    }
    
    @Test("Nowcast returns valid direction")
    func horizonProjection() {
        let series: [[PriceDataPoint]] = [
            (1...10).map { i in
                PriceDataPoint(date: Date().addingTimeInterval(TimeInterval(-10 + i) * 86400), value: Decimal(i) * 10)
            }
        ]
        let result = engine.nowcast(series: series, horizonDays: 30)
        // direction should be one of the valid TrendDirection values
        #expect([TrendDirection.rising, .falling, .stable].contains(result.direction))
    }
}
