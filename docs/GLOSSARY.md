# Glossary

Every word Silvanus puts on screen. One name per idea.

| Term | Means | Not |
| --- | --- | --- |
| Meeting | One recorded or imported conversation: notes, transcript, audio, and details | call, session, note, recording (as a noun for the whole thing) |
| Recording | The state of capturing audio for a meeting right now | session, capture |
| New Meeting | Start a meeting page for notes, without recording | New Note, New Session |
| Start Recording | Begin capturing audio: into the open meeting if it has no audio yet, otherwise a new one | Record, New Session |
| Quick Note | The microphone button: a new meeting that starts recording right away (⌥⌘N) | Voice memo, Quick record |
| Record This Meeting | Start Recording, when it will record into the open meeting | |
| Stop | End the recording; transcription starts | End, Finish |
| Pause / Resume | Stop writing audio for a while, then continue in the same meeting; nothing is kept while paused, and the time leaves the pause out (⇧⌘P, the recording controls, the menu bar) | Mute, Hold |
| My notes | What I type on a meeting's page | Memos, Notes (alone), Notepad |
| Transcript | Who said what, with times | captions, text |
| Draft | The live transcript shown during the recording; replaced after Stop | live captions, preview |
| Transcribing | The after-call pass that turns audio into the transcript | Processing, Analyzing |
| Summary | The view holding agent notes and, for imported meetings, the Granola summary | AI notes, Overview |
| Agent notes | Text agents write into a meeting through the MCP server | AI summary |
| Me | The microphone side of a meeting; shown as my name | You, Mic, Host |
| Them | The call-audio side, before speakers are named | Others, Remote, System |
| Speaker | One voice in the call audio, named or numbered | Participant, Voice (in labels) |
| Name Speakers | Assign names to the voices in a meeting | Identify, Label |
| Recording controls | The small floating bar shown for the whole recording, whichever app is in front: the grip, the state and time, five level bars, Pause/Resume, and Stop. Its VoiceOver name is "Silvanus recording controls" | Recording pill, toolbar, HUD, Recording bar |
| Show Recording Controls / Hide Recording Controls | The menu bar and Window menu items that bring the recording controls back or put them away for this recording; hiding isn't stopping | Close, Dismiss |
| Reset Recording Controls Position | The menu bar and Window menu item (and Home on the focused grip) that puts the recording controls back at the bottom center above the Dock | Reset Position, Recenter |
| Move recording controls | The grip's VoiceOver name: drag it, or focus it and use the arrow keys (Shift moves farther) | Drag handle |
| Paused | The recording controls' state while paused; the note above reads "Audio isn't being saved." and the time reads "12:34 paused" | On hold, Muted |
| Audio lost | The recording controls' state when the microphone stops capturing (a device that won't come back, a disk that can't be written); the time holds ("12:34 stopped"), nothing is saved, and the note reads "The microphone stopped. Check your audio devices, then retry." Silence is never Audio lost | Audio interrupted, Disconnected, Error |
| Retry | On the recording controls, the menu bar, and the banner while audio is lost: start the microphone again in the same meeting; also the banner's action after a failed transcription | Reconnect, Try again |
| Mic only | The recording controls' state when call audio stopped and the microphone records on its own; the menu bar offers Retry Call Audio | Mic-only mode |
| Retry Call Audio | The menu bar item that starts call audio again while the recording is Mic only | Reconnect system audio |
| Record Meeting | The menu bar item shown while a detected call waits to be recorded, after Not now too, until the call ends | Record This Call |
| Meeting detected | The floating prompt shown once per call when a call app starts using the microphone while Silvanus isn't recording: "Meeting detected", "Silvanus · (App) is using your microphone", "Start recording this meeting?", with Not now and Record meeting. When no one app is known to use the microphone it reads "Microphone in use", "Start a recording?", and Start recording. No countdown: it stays until answered or the call ends | Call detected, Incoming meeting, Notification |
| Not now | The Meeting detected prompt's dismiss button: hides it for this call only; nothing is recorded, and Record Meeting stays in the menu bar | Dismiss, Ignore |
| Recording since (time) | The menu bar item's line while recording ("Recording since 10:30 AM"); a clock time, never a running timer | Recording for, Live |
| Open Silvanus | The menu bar item that brings the window forward | Show App |
| Timestamp | The time a note line or transcript block starts, from the start of the meeting | time code |
| Microphone access / System audio access | The two macOS permissions Silvanus needs | Mic permission, Screen Recording |
| Silvanus needs two permissions to record | The sheet the first Start Recording opens when access is missing; its buttons are Allow Microphone Access, Allow System Audio Access, Open System Settings…, Not Now, and Start Recording (or Quick Note) | Grant access, Setup |
| Recording your microphone only. (reason) | The warning when call audio couldn't start; the microphone records on its own | Mic-only mode |
| Call ended | The note above the recording controls when a recording started during a call sees no call app using audio (the microphone, or playing the call, so muted still counts as in the call) for 15 seconds: "Call ended. Stopping in 10 seconds.", with Keep recording. Never from silence: talking alone in a call is normal | Call over, Meeting ended, Hung up |
| Stopping in 10 seconds | The countdown in the Call ended note, one second at a time down to "Stopping in 1 second"; at 0 the recording stops as Stop does | Auto-stop, Ending in |
| Keep recording | The Call ended note's button: records on, and the recording won't stop on its own until a new call starts using the microphone | Cancel, Don't stop, Continue |
| Nothing was recorded. | The banner after a Stop that came before any audio; nothing is transcribed | Empty recording |
| Couldn't restart the microphone: (reason) | Why audio is lost after the microphone changed and couldn't come back, or Retry couldn't start it | Device error |
| A meeting is recording. Stop and quit? | What ⌘Q asks while recording; Stop and Quit saves the recording (it's transcribed at the next launch), Cancel keeps recording | Are you sure? |
| Transcription failed. (reason) | The open meeting's banner while its transcription has failed, with Retry; after 3 failures in a row it isn't retried on its own | Error, Failed to process |
| Couldn't start recording: (reason) / Couldn't write audio: (reason) | Why a recording didn't start, or why audio is lost; the audio saved so far is kept | Recording error, Capture failed |
| Couldn't transcribe this meeting: (reason) | The banner when the after-call pass fails; Retry runs it again on the saved audio | Transcription error |
| Close | Dismisses a banner | Dismiss, OK |
| Finished transcribing an interrupted recording | The banner after a recording cut off by a quit or crash is transcribed at launch | Recovered, Restored |
| Transcribing… | The canvas header's label, with its bar, while the after-call pass runs | Processing… |
| Folder | A group of meetings the user makes | Project, Space, Tag |
| All meetings | The sidebar's list with no folder chosen: every meeting | All Notes, Everything, Inbox |
| Folders | The sidebar section that lists every folder, under the meetings | Collections, Groups |
| Today / Yesterday | Sidebar day headings; older days show the weekday, then the date ("Mon, Nov 2") | Recent, Earlier |
| No meetings yet | The sidebar when there are no meetings at all | Empty, Nothing here |
| No meetings in this folder | The sidebar when the chosen folder holds no meetings | Folder is empty |
| Move to Trash | Remove a meeting so it can be restored from the Trash | Delete (unless it can't come back) |
| Attendees | The people in a meeting, listed from the date chip; "No attendees" when there are none | Participants, Guests |
| Add to folder | The folder chip on a meeting that isn't in a folder; its menu (and Meeting > Move to Folder) has the folders, None, and New Folder… | Move to Project, Tag |
| No summary yet | The Summary view before a meeting has one | Nothing here |
| No transcript yet | The Transcript view before a meeting has one | No captions |
| Pick a meeting or start one | The canvas with no meeting open | Nothing selected |
| Settings | The panes that open inside the main window (⌘,): General, Appearance, About, Transcription, Summaries | Preferences, Options |
| Show in Dock | The General switch that keeps Silvanus's icon in the Dock | Dock icon |
| Prompt when a meeting starts | The General switch (on by default) that shows Meeting detected when a call app starts using the microphone; its description reads "When a call app starts using the microphone, offer to start recording." | Auto-detect meetings, Meeting notifications |
| Stop when the call ends | The General switch (on by default) that stops a recording started during a call once the call app stops using audio, after the Call ended countdown; never for Quick Note. Its description reads "When the call app stops using audio, stop recording after a short countdown." with the footnote "Needs the Mac's per-app audio list; without it, waits for the call app to quit." | Auto-stop, End with call |
| Open at login | The General switch that starts Silvanus when you log in; "Coming soon" for now | Launch at startup |
| Theme | The Appearance choice: System, Light, or Dark | Mode, Color scheme |
| Model | The Transcription pane's speech model, "Parakeet TDT v2, on this Mac"; and the Summaries pane's model file, which writes to-dos and summaries on this Mac ("No model" when there's none). Its footnote says where the file came from: "The file you chose.", "Found in (app), so it isn't downloaded twice.", or "Choose a GGUF model file, or download Gemma in Biscotti." | Engine, LLM, AI |
| Choose… | The Summaries pane's button that picks a model file (the panel is Choose a Model File) | Browse, Select |
| Use Default | The Summaries pane's button, shown after a file was chosen, that goes back to the model another app downloaded | Reset, Clear |
| Couldn't save notes: (reason) | The banner over My notes when writing notes.md fails; the reason is the system's | Save error, Sync failed |
| Retry | Try the failed step again, from its banner: the notes' save, or a meeting's transcription | Try again, Resave |
