import CoreAudio
import AudioToolbox
import Foundation

/// The Mac's output volume (same as the volume keys), kept in sync when it changes elsewhere
/// or when you switch outputs (speakers, AirPods, …).
@MainActor
final class SystemVolume: ObservableObject {
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var muted = false
    @Published private(set) var isAdjustable = true

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var valueListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.attachToDefaultDevice() }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, listener)
        attachToDefaultDevice()
    }

    func set(_ value: Float) {
        var v = min(max(value, 0), 1)
        volume = v
        AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if muted && v > 0 { setMuted(false) }
    }

    func toggleMute() { setMuted(!muted) }

    private func setMuted(_ on: Bool) {
        var flag: UInt32 = on ? 1 : 0
        AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &flag)
        muted = on
    }

    private func attachToDefaultDevice() {
        // Stop listening to the old output.
        if let listener = valueListener, device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        }

        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, 0, nil, &size, &id)
        device = id

        var settable: DarwinBoolean = false
        isAdjustable = AudioObjectHasProperty(id, &Self.volumeAddress)
            && AudioObjectIsPropertySettable(id, &Self.volumeAddress, &settable) == noErr && settable.boolValue

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.read() }
        }
        valueListener = listener
        AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, listener)
        read()
    }

    private func read() {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &v) == noErr { volume = v }
        var m: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &m) == noErr { muted = m != 0 }
    }
}
