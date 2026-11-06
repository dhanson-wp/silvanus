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
| Pause / Resume | Stop writing audio for a while, then continue; nothing is kept while paused | Mute, Hold |
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
| Recording pill | The small floating bar with the time, Pause, and Stop, shown while recording when Silvanus's window isn't in front | toolbar, HUD, Recording bar |
| Meeting detected | The small floating prompt shown when a call app starts using the microphone while Silvanus isn't recording; its line reads "A call is using the microphone.", its buttons are Start Recording and Dismiss, and it hides itself after 20 seconds | Call detected, Incoming meeting, Notification |
| Recording since (time) | The menu bar item's line while recording ("Recording since 10:30 AM"); a clock time, never a running timer | Recording for, Live |
| Open Silvanus | The menu bar item that brings the window forward; "Show Silvanus" is the recording pill's live button | Show App |
| Timestamp | The time a note line or transcript block starts, from the start of the meeting | time code |
| Microphone access / System audio access | The two macOS permissions Silvanus needs | Mic permission, Screen Recording |
| Silvanus needs two permissions to record | The sheet the first Start Recording opens when access is missing; its buttons are Allow Microphone Access, Allow System Audio Access, Open System Settings…, Not Now, and Start Recording (or Quick Note) | Grant access, Setup |
| Recording your microphone only. (reason) | The warning when call audio couldn't start; the microphone records on its own | Mic-only mode |
| Nobody on the call is audible yet. Check System Audio access in Settings. | The warning when call audio stays silent for 30 seconds during a call; never for Quick Note, nor for a recording with no call app using the microphone at its start or since (a browser that's merely open doesn't count) | No call audio yet, No system audio |
| No microphone audio yet. Check the input in System Settings > Sound. | The warning when the microphone stays silent for 30 seconds while recording | Mic muted |
| Nothing was recorded. | The banner after a Stop that came before any audio; nothing is transcribed | Empty recording |
| Couldn't restart the microphone: (reason) | Why a recording stopped after the microphone changed and couldn't come back | Device error |
| A meeting is recording. Stop and quit? | What ⌘Q asks while recording; Stop and Quit saves the recording (it's transcribed at the next launch), Cancel keeps recording | Are you sure? |
| Transcription failed. (reason) | The open meeting's banner while its transcription has failed, with Retry; after 3 failures in a row it isn't retried on its own | Error, Failed to process |
| Couldn't start recording: (reason) / Couldn't write audio: (reason) | Why a recording didn't start, or stopped early; the audio saved so far is kept | Recording error, Capture failed |
| Couldn't transcribe this meeting: (reason) | The banner when the after-call pass fails; Retry runs it again on the saved audio | Transcription error |
| Close | Dismisses a banner, or the recording pill after a failure | Dismiss (except on the Meeting detected prompt), OK |
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
| Settings | The panes that open inside the main window (⌘,): General, Appearance, About, Transcription | Preferences, Options |
| Show in Dock | The General switch that keeps Silvanus's icon in the Dock | Dock icon |
| Prompt when a meeting starts | The General switch (on by default) that shows Meeting detected when a call app starts using the microphone; its description reads "When a call app starts using the microphone, offer to start recording." | Auto-detect meetings, Meeting notifications |
| Open at login | The General switch that starts Silvanus when you log in; "Coming soon" for now | Launch at startup |
| Theme | The Appearance choice: System, Light, or Dark | Mode, Color scheme |
| Model | The Transcription pane's speech model, "Parakeet TDT v2, on this Mac" | Engine |
| Couldn't save notes: (reason) | The banner over My notes when writing notes.md fails; the reason is the system's | Save error, Sync failed |
| Retry | Try the failed step again, from its banner: the notes' save, or a meeting's transcription | Try again, Resave |
