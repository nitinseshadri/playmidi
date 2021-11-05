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
    
    // To be added in the future.
    /*
    enum ResetType: String, ExpressibleByArgument {
        case gm
        case gs
        case xg
        case none
    }
    
    @Option(name: [.customShort("r"), .long], help: "The type of MIDI reset message to send before playback begins. Valid types are gm (General MIDI), gs (Roland GS), xg (Yamaha XG), and none. (default: none)")
    var resetType: ResetType?
     */
    
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
            print(GetEndpointDisplayName(endpoint: MIDIGetDestination(midiDestination)))
            MusicSequenceSetMIDIEndpoint(ms, MIDIGetDestination(midiDestination))
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
            
PlayMIDI.main()
