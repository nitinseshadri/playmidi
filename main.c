// pim (Playmidi IMproved)
// (c) 2020 Nitin Seshadri.
// Based on initial work (c) 2012 PrZhu.
//
// clang -o playmidi main.c -framework CoreFoundation -framework AudioToolbox -framework CoreMIDI

#include <CoreFoundation/CoreFoundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <stdlib.h>
#include <stdio.h>

// ____________________________________________________________________________
// Obtain the name of an endpoint without regard for whether it has connections.
// The result should be released by the caller.
// From https://developer.apple.com/library/archive/qa/qa1374/_index.html
static CFStringRef GetEndpointDisplayName(MIDIEndpointRef endpoint) {
  CFStringRef result = CFSTR(""); // default
  MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &result);
  return result;
}

int main(int argc, const char * argv[]) {
  CFShow(CFSTR("pim (Playmidi IMproved)\n"));

  // Check for input file
  if (argc > 1) {
    printf("%s\n", argv[1]);
  } else {
    printf("usage: %s <file> [<device-number>]\n", argv[0]);
    return 0;
  }

  CFStringRef filename = CFStringCreateWithCString(nil, argv[1], kCFStringEncodingUTF8);
  CFURLRef url = CFURLCreateWithFileSystemPath(nil, filename, 0, false);

  MusicSequence ms;
  NewMusicSequence(&ms);
  MusicSequenceFileLoad(ms, url, kMusicSequenceFile_MIDIType, 0);

  if (argc > 2) {
    int midiDestination = atoi(argv[2]);
    CFShow(GetEndpointDisplayName(MIDIGetDestination(midiDestination)));
    MusicSequenceSetMIDIEndpoint(ms, MIDIGetDestination(midiDestination));
  } else {
    CFShow(CFSTR("CoreAudio Software Synthesizer\n"));
  }

  // Adapted from https://developer.apple.com/library/archive/samplecode/PlaySequence/Listings/main_cpp.html
  UInt32 ntracks;
  MusicSequenceGetTrackCount(ms, &ntracks);
  MusicTimeStamp sequenceLength = 0;
  for (UInt32 i = 0; i < ntracks; ++i) {
    MusicTrack track;
    MusicTimeStamp trackLength;
    UInt32 propsize = sizeof(MusicTimeStamp);
    MusicSequenceGetIndTrack(ms, i, &track);
    MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &propsize);
    if (trackLength > sequenceLength) {
      sequenceLength = trackLength;
    }
  }
  printf("Length: %lf\n", sequenceLength);

  MusicPlayer mp;
  NewMusicPlayer(&mp);
  MusicPlayerSetSequence(mp, ms);
  MusicPlayerStart(mp);
  MusicTimeStamp t;
  do {
    usleep(1000);
    MusicPlayerGetTime(mp, &t);
    printf("\r%lf", t);
    fflush(stdout);
  } while (t < sequenceLength);
  MusicPlayerStop(mp);
  puts("");
  return 0;
}