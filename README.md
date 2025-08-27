# SoundWalk

A SoundWalk app coded in Swift.  

## Current Architecture

- **Zones + LocationService**  
  - Each Zone defines a GPS coordinate and radius.  
  - Zones can specify either:
    - A legacy `audioFile` (single file), or  
    - A `stems` dictionary mapping stem IDs to target gains (e.g. `["drums":1.0, "pads":0.6]`).  
  - LocationService monitors entry/exit and triggers updates.

- **StemTransport**  
  - A global `AVAudioEngine` clock.  
  - All stems are loaded once and looped in perfect sync.  
  - Zone enter/exit ramps stem gains up/down, **quantized to bar boundaries**.  
  - Overlapping zones are supported: each stem’s gain = **max** across all active zones.

- **SoundWalkManager**  
  - Handles persistence of zones (`zones.json` in Documents).  
  - Auto-registers available audio files from **Bundle** and **Documents** as stems.  
  - Supports overlap-safe mixing by tracking all active zones.  
  - Provides helpers to list audio files (`bundleAudioFiles()`, `audioLibraryFiles()`) and resolve URLs.  
  - Fallback: if a zone still has only `audioFile`, it’s treated as a stem with gain = 1.0.

- **ZoneEditorView**  
  - Map interface with colored circles for all zones.  
  - Dropdowns to select zones and audio files.  
  - Import button to bring in audio from the iOS Files app. Imported files are copied into Documents and become available as stems.  
  - “Follow Me” toggle: auto-center map on user location when enabled; pan freely when off.  
  - Zones can be created, updated, and deleted.  

## Audio Notes

- Supported formats: **WAV, AAC `.m4a`, MP3, CAF**.  
- **FLAC not supported natively** — convert with `ffmpeg`.  
- iOS Voice Memos default to ALAC `.m4a` (may not play); convert to AAC or WAV for best results.  
- All stems should be **same length, same BPM, aligned from 0:00** for clean looping.  

## Debugging

- If files show a “?” in Xcode: fix **Target Membership** and ensure they’re in **Copy Bundle Resources**.  
- Use console `print` logs (`ENTER/EXIT`) to see which zones are active and which stems are triggered.  
- For background operation, enable **Background Modes → Location Updates** and **Audio, AirPlay, and Picture in Picture** in Xcode capabilities.  

---

## TODO

- Needs a way to upload the users tracks onto their menu options.  
- Need to make m4a files work. Done (just doent work with voice notes) 
- Need to distribute this to testers.  
- Is there a version of the app that just plays back the positioned tracks with no freedom to move them by the user.  
- Can we have timed released tracks for things like dj sets or track releases.  
- Need to resolve the issue with non stem files not deleting once you get rid of their zone.
