# Fix log

## 2026-11-05 Recording froze the app
Symptom: after Start Recording, the window stopped responding and Stop did nothing; the app sat at 100% CPU and grew to 6 GB while still writing audio.
Cause: the menu bar label showed `Text(start, style: .timer)`. Every tick changed the status item's width, so AppKit re-laid out the menu bar on the main thread continuously.
Fix: the menu bar item shows a static icon (red record icon while recording); the elapsed time lives in the recording bar inside the window and in the menu as "Recording since…". Interrupted recordings are now finished and transcribed on the next launch.
Rule: never put a live timer or other per-second content in a MenuBarExtra label.

## 2026-11-10 The call showed up on my side, with headphones on
Symptom: on an hour-long call with headphones, the mic side came back with stray, garbled scraps of what the others said, and some of my short replies missing.
Cause: three things. Headphones still leak a little (here about 34 dB under the call, 20 to 25 dB under my voice), and the speech model writes down speech at any level, garbling it. The levels the cleanup trusted were measured on the whole signal, where rumble under 100 Hz was louder than the leak. And the level frames drifted early (1.5 s over the hour), because a short read from the audio file dropped the rest of a frame.
Fix: the leak is silenced in the audio before the speech model hears my side (`EchoCleanup.bleedFrames`, `AfterCall.split`); levels are measured on the speech band (`HighPass`); `SpeechLevels` carries part-frames over between reads. On that call the mic side went from 12% off to 7% against a reference transcript.
Rule: clean the audio before the speech model, not its words after. Measure levels on the speech band. Never assume a file read fills the buffer.

