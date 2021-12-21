//
//  main.swift
//  playmidi-swift
//
//  Created by Nitin Seshadri on 11/5/21.
//

import Foundation
import ArgumentParser
import AudioToolbox

struct PlayMIDI: ParsableCommand {
    
    static var configuration = CommandConfiguration(
        commandName: "playmidi",
        abstract: "A utility to play MIDI files from the command line. Supports CoreMIDI devices.",
        version: "1.0.0"
    )
    
    @Argument(help: "The MIDI file to play.", completion: .file(extensions: [".mid", ".smf"]))
    var file: String
    
    @Option(name: [.customShort("d"), .long], help: "The CoreMIDI device number to send MIDI data to. If you do not provide a device number, the built-in software synthesizer will be used.")
    var deviceNumber: Int?
    
    enum ResetType: String, ExpressibleByArgument {
        case gm
        case gs
        case mt
        case xg
        case none
    }
    
    @Option(name: [.customShort("r"), .long], help: "The type of MIDI reset message to send before playback begins. Valid types are gm (General MIDI), gs (Roland GS), mt (Roland MT-32), xg (Yamaha XG), and none. (default: none)")
    var resetType: ResetType?
    
    @Option(name: [.customShort("t"), .long], help: "The tempo to play the MIDI file at. (default: 1.0)")
    var tempo: Double?
    
    func run() throws {
        print("pim (Playmidi IMproved) - Swift version")
        
        let url: URL
        if (FileManager.default.fileExists(atPath: file) && FileManager.default.isReadableFile(atPath: file)) {
            url = URL(fileURLWithPath: file)
            print(file)
        } else {
            print("E: File \(file) does not exist or you do not have sufficient permissions to read it.")
            PlayMIDI.exit(withError: nil)
        }
        
        var ms: MusicSequence? = nil
        NewMusicSequence(&ms)
        guard let ms = ms else {
            print("E: Error creating MusicSequence")
            PlayMIDI.exit(withError: nil)
        }
        MusicSequenceFileLoad(ms, url as CFURL, .midiType, .smf_ChannelsToTracks)
        
        if let midiDestination = deviceNumber {
            let endpoint: MIDIEndpointRef = MIDIGetDestination(midiDestination)
            print(GetEndpointDisplayName(endpoint: endpoint))
            MusicSequenceSetMIDIEndpoint(ms, endpoint)
            
            // Send reset sysex message
            switch (resetType) {
            case .gm: // General MIDI
                sendSysex([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7], to: endpoint)
                print("Sent GM reset")
                break
            case .gs: // Roland GS
                sendSysex([0xF0, 0x41, 0x10, 0x42, 0x12, 0x40, 0x00, 0x7F, 0x00, 0x41, 0xF7], to: endpoint)
                print("Sent GS reset")
                break
            case .mt: // Roland MT-32
                sendSysex([0xF0, 0x41, 0x10, 0x16, 0x12, 0x7F, 0x01, 0xF7], to: endpoint)
                print("Sent MT-32 reset")
                break
            case .xg: // Yamaha XG
                sendSysex([0xF0, 0x43, 0x10, 0x4C, 0x00, 0x00, 0x7E, 0x00, 0xF7], to: endpoint)
                print("Sent XG reset")
                break
            default:
                break
            }
            
            // Wait 100ms after sending a reset per the GM spec
            usleep(100 * 1000)
        } else {
            print("CoreAudio Software Synthesizer")
        }
        
        // Adapted from https://developer.apple.com/library/archive/samplecode/PlaySequence/Listings/main_cpp.html
        // and converted to Swift by me.
        var ntracks: UInt32 = 0
        MusicSequenceGetTrackCount(ms, &ntracks)
        var sequenceLength: MusicTimeStamp = 0
        for i in 0..<ntracks {
            var track: MusicTrack!
            var trackLength: MusicTimeStamp = 0
            var propsize: UInt32 = UInt32(MemoryLayout<MusicTimeStamp>.size)
            MusicSequenceGetIndTrack(ms, i, &track)
            MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &propsize)
            if (trackLength > sequenceLength) {
              sequenceLength = trackLength
            }
        }
        print("Length: \(sequenceLength)")
        
        var mp: MusicPlayer? = nil
        NewMusicPlayer(&mp)
        guard let mp = mp else {
            print("E: Error creating MusicPlayer")
            PlayMIDI.exit(withError: nil)
        }
        MusicPlayerSetSequence(mp, ms)
        
        if let speed = tempo {
            MusicPlayerSetPlayRateScalar(mp, speed)
            print("Tempo: \(speed)")
        } else {
            print("Tempo: 1.0")
        }
        
        MusicPlayerPreroll(mp)
        MusicPlayerStart(mp)
        var t: MusicTimeStamp = 0
        while (t <= sequenceLength) {
            usleep(1000)
            MusicPlayerGetTime(mp, &t)
            print(t, terminator: "\r")
            fflush(stdout)
        }
        
        // Make sure all notes have finished sounding before quitting.
        usleep(1000000)
        
        MusicPlayerStop(mp)
        puts("")
        return
    }
}

func GetEndpointDisplayName(endpoint: MIDIEndpointRef) -> CFString {
    var result: Unmanaged<CFString>!
    MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &result)
    guard let result = result else { return "(null)" as CFString }
    return result.takeUnretainedValue()
}

func sendSysex(_ bytes: [UInt8], to endpoint: MIDIEndpointRef) {
    class SysexCompletion: NSObject {
        var complete: Bool = false
    }
    let completion = SysexCompletion()
    let completionReference = UnsafeMutablePointer<SysexCompletion>.allocate(capacity: 1)
    completionReference.initialize(to: completion)
    
    Data(bytes).withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
        var sysexRequest = MIDISysexSendRequest(
            destination: endpoint,
            data: pointer.baseAddress!.assumingMemoryBound(to: UInt8.self),
            bytesToSend: UInt32(bytes.count),
            complete: false,
            reserved: (0, 0, 0),
            completionProc: { requestPointer in
                guard let completion = requestPointer.pointee.completionRefCon?.assumingMemoryBound(to: SysexCompletion.self).pointee else { return }
                completion.complete = true
            },
            completionRefCon: completionReference
        )
        
        MIDISendSysex(&sysexRequest)
        
        while !(completion.complete) {
            usleep(1000)
        }
    }
}
            
PlayMIDI.main()
