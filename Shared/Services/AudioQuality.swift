import Foundation
import MusicKit
#if os(macOS)
import CoreAudio
#else
import AVFoundation
#endif

/// What Apple Music is sending, as the player reports it.
///
/// On iPhone, MusicKit plays in the quality set in Settings ▸ Apps ▸ Music ▸ Audio Quality (Lossless and Hi-Res
/// Lossless included), and the system player picks the output rate for a USB DAC itself. On the Mac, Apple gives apps
/// only the AAC stream (MusicKit's player service logs "Enhanced audio is not available - fallback to stereo
/// asset" and plays 256 kbps AAC at 44.1 kHz even when the Music app is set to Hi-Res Lossless), and it doesn't report
/// a variant: Lossless and Hi-Res Lossless play only in the Music app.
enum StreamQuality: Equatable {
    case hiResLossless, lossless, dolbyAtmos, aac, preview

    init(_ variant: AudioVariant) {
        switch variant {
        case .highResolutionLossless: self = .hiResLossless
        case .lossless: self = .lossless
        case .dolbyAtmos, .dolbyAudio, .spatialAudio: self = .dolbyAtmos
        default: self = .aac
        }
    }

    var isLossless: Bool { self == .hiResLossless || self == .lossless }

    /// "Hi-Res Lossless", "AAC 256 kbps".
    var label: String {
        switch self {
        case .hiResLossless: "Hi-Res Lossless"
        case .lossless: "Lossless"
        case .dolbyAtmos: "Dolby Atmos"
        case .aac: "AAC 256 kbps"
        case .preview: "AAC preview"
        }
    }

    /// "24-bit/48–192 kHz ALAC": what Apple Music's variants are (Apple doesn't say a song's exact rate).
    var detail: String {
        switch self {
        case .hiResLossless: "ALAC, 24-bit up to 192 kHz"
        case .lossless: "ALAC, 16–24-bit up to 48 kHz"
        case .dolbyAtmos: "Spatial audio"
        case .aac, .preview: "AAC, 44.1 kHz"
        }
    }

    /// The best of a song's variants, for saying what the Music app (or the Audio Quality setting) would give.
    static func best(of variants: [AudioVariant]) -> StreamQuality? {
        let q = variants.map(StreamQuality.init)
        return [.hiResLossless, .lossless].first(where: q.contains)
    }
}

/// Where the sound goes: "Scarlett 2i2 4th Gen · 44.1 kHz", "Living Room · AirPlay".
struct AudioOutputInfo: Equatable {
    var name: String
    var sampleRate: Double?
    var isAirPlay = false
    var isBluetooth = false
    /// A USB DAC or wired headphones.
    var isWired = false

    var summary: String {
        if isAirPlay { return "\(name) · AirPlay" }
        if isBluetooth { return "\(name) · Bluetooth" }
        guard let sampleRate, sampleRate > 0 else { return name }
        return "\(name) · \(Self.kHz(sampleRate)) kHz"
    }

    /// 44100 → "44.1", 96000 → "96".
    static func kHz(_ rate: Double) -> String {
        let k = rate / 1000
        return k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k)
    }

    #if os(iOS)
    /// The route's first output (every AirPlay speaker, by name) and the rate the hardware runs at.
    static func current() -> AudioOutputInfo? {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        guard let port = outputs.first else { return nil }
        let airPlay = outputs.filter { $0.portType == .airPlay }
        if !airPlay.isEmpty {
            return AudioOutputInfo(name: airPlay.map(\.portName).formatted(.list(type: .and)), isAirPlay: true)
        }
        let bluetooth: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        return AudioOutputInfo(name: port.portName, sampleRate: session.sampleRate,
                               isBluetooth: bluetooth.contains(port.portType),
                               isWired: port.portType == .usbAudio || port.portType == .headphones)
    }
    #endif
}

#if os(macOS)
/// The Mac's default output device through the CoreAudio HAL, and switching its sample rate to the stream's (as
/// Audio MIDI Setup does, for every app using the device), so a USB DAC gets Apple Music's 44.1 kHz without the Mac
/// resampling it to the device's rate first. The rate the device had is put back when playback stops or the app quits.
/// Modeled on Music Library's `OutputMatcher`.
final class OutputRateMatcher: @unchecked Sendable {
    /// Every change runs here, in the order asked (a stop's restore before the next song's match). Setting a rate
    /// waits for the device, so it stays off the main thread.
    private let queue = DispatchQueue(label: "io.github.davidlago.JazzDiscovery.output-rate")
    /// Each device's rate before the app changed it, by UID. Only touched on `queue`.
    private var originals: [String: Double] = [:]

    /// Switches the default output to `rate`, or the closest rate it has that doesn't lose anything (see
    /// `chooseRate`), and returns once the device runs at it.
    func match(rate: Double) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { self.apply(rate: rate); done.resume() }
        }
    }

    /// Puts back every rate the app changed.
    func restore() { queue.async { self.restoreAll() } }

    /// `restore()`, waiting for it: for when the app quits.
    func restoreNow() { queue.sync { restoreAll() } }

    /// The default output device's name and rate.
    static func current() -> AudioOutputInfo? {
        guard let device = defaultOutputDevice() else { return nil }
        let t = transport(device)
        return AudioOutputInfo(name: name(of: device), sampleRate: nominalRate(device),
                               isAirPlay: t == kAudioDeviceTransportTypeAirPlay,
                               isBluetooth: t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE,
                               isWired: t == kAudioDeviceTransportTypeUSB)
    }

    static func defaultOutputUID() -> String? { defaultOutputDevice().map(uid(of:)) }

    private func apply(rate: Double) {
        guard let device = Self.defaultOutputDevice(), let current = Self.nominalRate(device) else { return }
        // AirPlay and Bluetooth run at their own rate.
        guard ![kAudioDeviceTransportTypeAirPlay, kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
            .contains(Self.transport(device)) else { return }
        guard let target = Self.chooseRate(source: rate, available: Self.availableRates(device)),
              abs(target - current) >= 0.5 else { return }
        let uid = Self.uid(of: device)
        if originals[uid] == nil { originals[uid] = current }
        Self.setNominalRate(device, target)
    }

    private func restoreAll() {
        for (uid, rate) in originals {
            guard let device = Self.device(forUID: uid), let now = Self.nominalRate(device), abs(now - rate) >= 0.5 else { continue }
            Self.setNominalRate(device, rate)
        }
        originals.removeAll()
    }

    /// The source rate when the device has it; otherwise the lowest whole multiple of it (88.2 or 176.4 kHz for
    /// 44.1), so nothing is lost; otherwise the lowest rate above it; otherwise the highest the device has.
    static func chooseRate(source: Double, available: [ClosedRange<Double>]) -> Double? {
        guard !available.isEmpty, source > 0 else { return nil }
        func has(_ r: ClosedRange<Double>, _ x: Double) -> Bool { x >= r.lowerBound - 0.5 && x <= r.upperBound + 0.5 }
        if available.contains(where: { has($0, source) }) { return source }
        let multiples = (2...16).map { source * Double($0) }.filter { m in available.contains { has($0, m) } }
        if let m = multiples.min() { return m }
        if let above = available.map(\.lowerBound).filter({ $0 > source }).min() { return above }
        return available.map(\.upperBound).max()
    }

    // MARK: CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var addr = address(selector), value = initial, size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func getArray<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ element: T) -> [T] {
        var addr = address(selector), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var result = [T](repeating: element, count: Int(size) / MemoryLayout<T>.stride)
        let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? result : []
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = address(selector), str: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &str) == noErr, let str else { return "" }
        return str.takeRetainedValue() as String
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0)).flatMap { $0 == 0 ? nil : $0 }
    }

    private static func device(forUID uid: String) -> AudioObjectID? {
        getArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, AudioObjectID(0)).first { self.uid(of: $0) == uid }
    }

    private static func name(of device: AudioObjectID) -> String { string(device, kAudioDevicePropertyDeviceNameCFString) }
    private static func uid(of device: AudioObjectID) -> String { string(device, kAudioDevicePropertyDeviceUID) }
    private static func transport(_ device: AudioObjectID) -> UInt32 { get(device, kAudioDevicePropertyTransportType, UInt32(0)) ?? 0 }
    private static func nominalRate(_ device: AudioObjectID) -> Double? { get(device, kAudioDevicePropertyNominalSampleRate, Float64(0)) }

    private static func availableRates(_ device: AudioObjectID) -> [ClosedRange<Double>] {
        getArray(device, kAudioDevicePropertyAvailableNominalSampleRates, AudioValueRange())
            .map { $0.mMinimum...max($0.mMinimum, $0.mMaximum) }
    }

    /// Sets the rate and waits (up to 1.5 s) for the device to run at it.
    private static func setNominalRate(_ device: AudioObjectID, _ rate: Double) {
        var addr = address(kAudioDevicePropertyNominalSampleRate), value = Float64(rate)
        guard AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value) == noErr else { return }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, abs((nominalRate(device) ?? 0) - rate) >= 0.5 { Thread.sleep(forTimeInterval: 0.02) }
    }
}
#endif
