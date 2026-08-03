import Testing
@testable import FathomKit

@Test func temperatureReaderPublishesServicesOrNamesTheRuntimeGap() {
    switch TemperatureSensorReader().read() {
    case let .known(readings, source):
        #expect(source == .ioHIDTemperatureEvent)
        #expect(!readings.isEmpty)
        for reading in readings {
            #expect(!reading.name.isEmpty)
            guard case let .known(value, valueSource) = reading.celsius else {
                Issue.record("A returned service lost its measurement state")
                continue
            }
            #expect(value.isFinite)
            #expect(valueSource == .ioHIDTemperatureEvent)
        }
    case let .notPublished(reason):
        #expect(!reason.isEmpty)
    case .notAttributable:
        Issue.record("A direct sensor read is not an attribution problem")
    }
}
