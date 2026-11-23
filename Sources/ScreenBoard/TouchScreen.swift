import Foundation
import IOKit
import IOKit.hid

enum TouchScreen {
    /// Whether any connected display takes touch input: a HID device that
    /// reports the Digitizer page's Touch Screen usage (0x0D / 0x04).
    /// Trackpads report Touch Pad (0x05) instead, so they don't count.
    /// Reading the IORegistry needs no Input Monitoring permission.
    static var isAvailable: Bool {
        let digitizerPage = kHIDPage_Digitizer
        let touchScreenUsage = kHIDUsage_Dig_TouchScreen

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching(kIOHIDDeviceKey),
                                           &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            if matches(service, page: digitizerPage, usage: touchScreenUsage) { return true }
        }
        return false
    }

    private static func matches(_ service: io_service_t, page: Int, usage: Int) -> Bool {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }
        if (property(kIOHIDPrimaryUsagePageKey) as? Int) == page,
           (property(kIOHIDPrimaryUsageKey) as? Int) == usage {
            return true
        }
        // A composite device lists every top-level collection here.
        let pairs = property(kIOHIDDeviceUsagePairsKey) as? [[String: Any]] ?? []
        return pairs.contains {
            ($0[kIOHIDDeviceUsagePageKey] as? Int) == page && ($0[kIOHIDDeviceUsageKey] as? Int) == usage
        }
    }
}
