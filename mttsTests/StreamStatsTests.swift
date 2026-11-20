import Foundation
import Testing
@testable import mtts

struct StreamStatsTests {
    private let interval = 0.04

    private func feed(_ times: [TimeInterval], delay: Double = 0.03) -> StreamStats {
        times.reduce(StreamStats()) { $0.recording(t: $1, arrival: $1 + delay) }
    }

    private func steady(count: Int, from start: TimeInterval = 100) -> [TimeInterval] {
        (0..<count).map { start + Double($0) * interval }
    }

    @Test func emptyStreamReportsNothing() {
        let stats = StreamStats()
        #expect(stats.rate == 0)
        #expect(stats.jitter == nil)
        #expect(stats.latency == nil)
        #expect(stats.displayTime(at: 10) == nil)
    }

    @Test func steadyStreamMeasuresRateJitterAndLatency() throws {
        let stats = feed(steady(count: 60))
        #expect(abs(stats.rate - 25) < 1e-6)
        #expect(try #require(stats.jitter) < 1e-9)
        #expect(abs(try #require(stats.latency) - 0.03) < 1e-9)
        #expect(stats.dropped == 0)
        #expect(stats.count == 60)
        #expect(stats.intervals.count == StreamStats.window)
    }

    @Test func gapsCountAsDroppedSamples() {
        let times = steady(count: 20) + steady(count: 20, from: 100 + 23 * interval)
        let stats = feed(times)
        #expect(stats.dropped == 3)
    }

    @Test func jitterIgnoresGaps() throws {
        let times = steady(count: 20) + steady(count: 20, from: 100 + 23 * interval)
        #expect(try #require(feed(times).jitter) < 1e-9)
    }

    @Test func differentClocksHideLatencyButKeepDisplayTiming() throws {
        let times = steady(count: 30)
        let stats = feed(times, delay: 5000)
        #expect(stats.latency == nil)
        let newest = try #require(times.last)
        let edge = try #require(stats.displayTime(at: newest + 5000))
        #expect(abs(edge - (newest - interval * StreamStats.edgeLead)) < 1e-6)
    }

    @Test func edgeNeverRunsPastTheNewestSample() throws {
        let times = steady(count: 30)
        let stats = feed(times)
        let newest = try #require(times.last)
        let edge = try #require(stats.displayTime(at: newest + 10))
        #expect(edge <= newest + interval / 2 + 1e-9)
    }

    @Test func offsetFollowsFasterArrivalsQuickly() throws {
        let slow = steady(count: 30).reduce(StreamStats()) { $0.recording(t: $1, arrival: $1 + 0.2) }
        let fast = steady(count: 10, from: 102).reduce(slow) { $0.recording(t: $1, arrival: $1 + 0.03) }
        #expect(try #require(fast.latency) < 0.06)
    }

    @Test func edgeLagIgnoresGapsInTheSpacing() throws {
        let times = steady(count: 20) + steady(count: 20, from: 100 + 60 * interval)
        let stats = feed(times)
        let newest = try #require(times.last)
        let edge = try #require(stats.displayTime(at: newest + 0.03))
        #expect(abs((newest - edge) - interval * StreamStats.edgeLead) < 1e-6)
    }

    @Test func liveEdgeTrailsTheNewestSample() throws {
        let times = steady(count: 30)
        let stats = feed(times)
        let newest = try #require(times.last)
        let edge = try #require(stats.displayTime(at: newest + 0.03))
        #expect(edge < newest)
        #expect(newest - edge < 0.1)
    }

    @Test func repeatedOrOlderTimestampsDontAddIntervals() {
        let stats = feed([100, 100.04, 100.04, 100.02, 100.08])
        #expect(stats.intervals.count == 2)
        #expect(stats.lastT == 100.08)
    }
}

@MainActor
struct HeadphoneMotionServiceTests {
    @Test func firstSampleStartsTheStreamFacingForward() throws {
        let service = HeadphoneMotionService()
        service.ingest(MotionSample(t: 10, attitude: (0.1, 0, 1.2)), arrival: 10.03)
        #expect(service.status == .streaming)
        #expect(service.streamStartedAt != nil)
        #expect(service.yawReference == 1.2)
        let frame = LiveFrame(samples: service.history, edge: 10, yawReference: try #require(service.yawReference))
        #expect(frame.pose?.yaw == 0)
    }

    @Test func recenterUsesTheLatestHeading() {
        let service = HeadphoneMotionService()
        service.ingest(MotionSample(t: 10, attitude: (0, 0, 0.2)), arrival: 10)
        service.ingest(MotionSample(t: 10.04, attitude: (0, 0, 0.9)), arrival: 10.04)
        #expect(service.yawReference == 0.2)
        service.recenter()
        #expect(service.yawReference == 0.9)
    }

    @Test func clockRestartStartsANewStream() {
        let service = HeadphoneMotionService()
        service.ingest(MotionSample(t: 100, attitude: (0, 0, 0.3)), arrival: 100)
        service.ingest(MotionSample(t: 100.04, attitude: (0, 0, 0.3)), arrival: 100.04)
        let stream = service.streamID
        service.ingest(MotionSample(t: 5, attitude: (0, 0, -1)), arrival: 100.1)
        #expect(service.history.count == 1)
        #expect(service.yawReference == -1)
        #expect(service.streamID == stream + 1)
        #expect(service.stats.count == 1)
    }

    @Test func stallStartsOverButKeepsTheHeading() {
        let service = HeadphoneMotionService()
        service.ingest(MotionSample(t: 10, attitude: (0, 0, 0.3)), arrival: 10)
        service.ingest(MotionSample(t: 10.04, attitude: (0, 0, 0.5)), arrival: 10.04)
        service.ingest(MotionSample(t: 12, attitude: (0, 0, 0.9)), arrival: 12)
        #expect(service.history.count == 1)
        #expect(service.yawReference == 0.3)
    }

    @Test func duplicateTimestampsAreIgnored() {
        let service = HeadphoneMotionService()
        service.ingest(MotionSample(t: 10), arrival: 10)
        service.ingest(MotionSample(t: 10), arrival: 10.01)
        #expect(service.history.count == 1)
        #expect(service.sampleCount == 1)
    }

    @Test func watchdogMarksAStalledStreamAsWaiting() {
        let service = HeadphoneMotionService()
        service.ingest(MotionSample(t: 10, attitude: (0, 0, 0.2)), arrival: 10)
        service.checkStall(at: 10.5)
        #expect(service.status == .streaming)
        service.checkStall(at: 11.2)
        #expect(service.status == .waiting)
        service.recenter()
        #expect(service.yawReference == 0.2)
    }

    @Test func historyKeepsTheLastTenSeconds() {
        let service = HeadphoneMotionService()
        var received = 0
        service.onSample = { _ in received += 1 }
        for i in 0..<400 {
            let t = Double(i) * 0.04
            service.ingest(MotionSample(t: t), arrival: t)
        }
        let span = (service.history.last?.t ?? 0) - (service.history.first?.t ?? 0)
        #expect(span <= HeadphoneMotionService.historySeconds)
        #expect(span > HeadphoneMotionService.historySeconds - 0.1)
        #expect(received == 400)
        #expect(service.sampleCount == 400)
        #expect(abs(service.sampleRate - 25) < 1e-6)
    }
}
