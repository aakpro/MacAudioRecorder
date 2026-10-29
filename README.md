# InternalSoundRecorder (macOS)

A native, driverless macOS menu bar application engineered to record internal system audio directly from macOS—regardless of whether headphones are connected, unplugged, or Bluetooth audio devices change. Built with **ScreenCaptureKit** and designed for **continuous fault tolerance** (zero audio corruption upon abrupt power loss, crash, or interrupt).

---

## Key Features

1. **Driverless Native Internal Audio Capture**:
   - Uses Apple's native `ScreenCaptureKit` API to tap into the system audio compositor.
   - **No virtual audio cables or kernel drivers** (no BlackHole, Soundflower, or Loopback required).
   - Independent of audio output route: records audio uninterrupted whether playing through internal speakers, 3.5mm wired headphones, USB DACs, or AirPods.
   - **Two-Way Meeting Mode (MS Teams, Zoom, Calls)**: Simultaneously captures your microphone and mixes your voice in real time with the other meeting participants into a single unified stereo audio track. Never miss either side of a call!

2. **Fault-Tolerant Disk Persistence (Save Whatever It Can)**:
   - **Fragmented MP4 (`fMP4`)**: Uses `AVAssetWriter` configured with `movieFragmentInterval` (2.0s chunks). Rather than writing a single metadata atom (`moov`) only at the end of the file, each 2-second fragment (`moof` + `mdat`) is committed and synced atomically to disk.
   - **Abrupt Termination Resilience**: If the app is killed with `kill -9`, the Mac battery dies, or the system crashes, all audio up to the last 2 seconds remains **100% valid and playable** in QuickTime, VLC, and standard media players without repair.
   - **Multi-Format Support**: Also supports Uncompressed WAV (`.wav`) and Core Audio Format (`.caf`).

3. **Route & Interruption Resilience**:
   - Auto-reconnection logic when audio routing changes or displays wake from sleep.
   - Flushes buffers to disk immediately on `NSWorkspace.willSleepNotification`.
   - Low disk space detection stops recording safely before disk exhaustion causes file corruption.

4. **Sleek Menu Bar Interface & Lifecycle Management**:
   - Lives in the macOS menu bar as a `MenuBarExtra` window with custom high-resolution native App Icon.
   - **Single-Instance Lifecycle Enforcement**: Guarantees that only one instance of the app runs at any time, terminating stale or duplicate background instances when launching from Xcode or Terminal.
   - Real-time animated audio level visualizer (RMS & Peak dBFS meter computed with Apple's `Accelerate` / `vDSP` framework).
   - One-click Start, Pause, Resume, Stop & Save.
   - Recent recordings list with quick "Play" and "Show in Finder" buttons.
   - Permission status banner with direct deep link to macOS Privacy & Security settings.

5. **Universal 2 Binary Support**:
   - Compiles native slices for both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs.

---

## Makefile Targets

| Command | Action |
| :--- | :--- |
| `make build` | Compiles Universal 2 release binary (`arm64` + `x86_64`), packages into `build/InternalSoundRecorder.app`, embeds App Icon, and applies ad-hoc codesign. |
| `make open` | Opens the project directly in Xcode (`open Package.swift`). |
| `make run` | Builds and launches `build/InternalSoundRecorder.app`. |
| `make test` | Runs the full test suite (24 unit and fault-tolerance integration tests). |
| `make build-debug` | Compiles debug binary quickly via `swift build`. |
| `make clean` | Removes build directories and cached compilation artifacts. |

---

## Requirements & Permissions

* **OS**: macOS 14.0 (Sonoma) or newer (tested on macOS 14 / macOS 15 / macOS 26).
* **Toolchain**: Xcode 15+ / Swift 6.0+.
* **Permission**: macOS classifies internal system audio capture under **Screen & System Audio Recording**. The app provides a direct button to open:
  `System Settings > Privacy & Security > Screen & System Audio Recording`.

---

## Running Tests

```bash
make test
```

### Included Tests:
- `AudioLevelMeterTests`:
  - `testSilenceProducesZeroLevels`
  - `testSineWaveProducesAccurateLevels`
  - `testSampleBufferProcessing`
  - `testPeakDecayAfterLoudSound`
- `FaultTolerantWriterTests`:
  - `testFragmentedM4AWritingAndFinalization` (validates fMP4 playable audio stream with `AVURLAsset`)
  - `testCrashResiliencePeriodicFlush` (simulates hard termination without clean finish; verifies physical file data)
  - `testWavPCMRecording`
  - `testCafLosslessRecording`
- `RecordingSessionTests`:
  - `testRecordingItemFormatting`
  - `testRecordingSettingsDefaultValues`
  - `testRecordingStatusProperties`
