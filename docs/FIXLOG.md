# Fix log

## 2026-11-05 Recording froze the app
Symptom: after Start Recording, the window stopped responding and Stop did nothing; the app sat at 100% CPU and grew to 6 GB while still writing audio.
Cause: the menu bar label showed `Text(start, style: .timer)`. Every tick changed the status item's width, so AppKit re-laid out the menu bar on the main thread continuously.
Fix: the menu bar item shows a static icon (red record icon while recording); the elapsed time lives in the recording bar inside the window and in the menu as "Recording since…". Interrupted recordings are now finished and transcribed on the next launch.
Rule: never put a live timer or other per-second content in a MenuBarExtra label.
