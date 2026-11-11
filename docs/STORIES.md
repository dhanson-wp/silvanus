# Silvanus: user stories

The meeting screen layout comes from `design/KIT.md`. It follows the notes canvas: notes on the page, with Transcript and Summary one click away in a pill at the top, and a live bar at the bottom while recording.

The transcription engine (Parakeet through FluidAudio) and the bleed cleanup are proven first, in a command-line prototype. Stories that depend on that result say `Depends: engine spike`.

Snapshot pages: `meeting-notes`, `meeting-transcript`, `meeting-summary`, `recording-bar`, `menubar-menu`, `call-prompt`, `name-speakers`, `sidebar-filters`, `search`, `settings-recording`, `settings-transcription`, `settings-summaries`, `todos`, `settings-agents`, `settings-storage`, `import-granola`, `onboarding-permissions`, `empty-library`.

## M1 Record and read
One call, recorded and transcribed on this Mac, readable the same day, and still there after a restart.

### S-001 Grant microphone and system audio access
As the user, on first launch I see why Silvanus needs the microphone and system audio, and I grant both from one screen.
Screens: onboarding-permissions
Acceptance:
- [snap] The screen shows the two permissions, each with a one-line reason and its status (Not asked, Allowed, Denied).
- [manual] Clicking Allow triggers each macOS prompt; a denied permission shows a button that opens the right System Settings pane.
- [self] The status is read again when the app becomes active, so returning from System Settings updates it.
UX:
- Flow: first launch -> Welcome window with both permissions -> Allow Microphone Access -> macOS prompt -> Allow System Audio Access -> macOS prompt -> Continue opens the empty library
- Surface: its own window (a self-contained first-run task)
- States: Not asked shows the Allow button; Allowed shows a checkmark and "Allowed"; Denied shows "Open System Settings…" and why recording can't start without it
- Words: title "Silvanus needs two permissions"; "Microphone access: so your side of the call is in the transcript."; "System audio access: so the other people on the call are in the transcript."; buttons "Allow Microphone Access", "Allow System Audio Access", "Continue"
- Access: Tab moves between the buttons; status is read as words, not only by checkmark color
Status: done
Note: macOS has no public API for the system audio permission, so the screen shows "Asked" rather than "Allowed". Silence is normal, so the recording bar never warns about it.

### S-002 Start and stop a recording from the menu bar
As the user, I click the menu bar item and choose Start recording, then Stop.
Screens: menubar-menu, recording-bar
Depends: S-001
Acceptance:
- [snap] The menu shows Start recording with its shortcut, plus the last meeting.
- [self] While recording, the menu bar item turns ink red and shows the elapsed time.
- [self] The mic and system audio are written as two 16 kHz tracks in 30-second segment files under the meeting's audio folder.
- [unit] A segment cut off by a crash is truncated on the next launch; the meeting's earlier segments are kept.
UX:
- Flow: menu bar item, global shortcut, or File > Start Recording (⇧⌘R) -> recording starts at once, the new meeting opens on My notes -> Stop in the recording bar, the menu, or the same shortcut
- Surface: menu bar menu (a place people come back to all day), plus the recording bar inline in the meeting
- States: idle menu shows Start Recording and the last meeting; recording shows red dot and elapsed time; a missing permission opens the S-001 window instead of failing
- Words: "Start Recording", "Stop", menu bar tooltip "Silvanus: recording 24:18"
- Access: VoiceOver reads the menu bar item as "Silvanus, recording, 24 minutes"; red is never the only signal (the dot and the time change too)
Status: done
Note: the crash-truncation unit test is still to write; the stitcher already skips a segment that will not open.

### S-003 Write notes during the call
As the user, I type in the meeting's notes canvas while recording; each line gets a quiet timestamp.
Screens: meeting-notes, recording-bar
Depends: S-002
Acceptance:
- [snap] A new recording opens on My notes with an editable title, the date, and an empty page with the cursor in it.
- [unit] Each new line stores the elapsed time when typing started on it.
- [self] Notes are saved to the meeting's Markdown file under `## My notes` as I type, and are still there after a forced quit.
- [unit] Notes are Markdown: headings, bullets, numbered lists, to-dos, quotes, bold, italic, code, and links. Return continues a list; Return on an empty item ends it.
- [snap] Lines not being edited show formatted; clicking one shows its Markdown. To-do boxes can be ticked in place.
UX:
- Flow: Start Recording -> cursor is already in My notes -> type, Return for a new line -> lines save as typed -> ⌘Z undoes
- Surface: the meeting page itself (inline, the notes canvas)
- States: empty page shows placeholder "Type notes as you go. Each line gets a timestamp."; a long title wraps to two lines, then truncates with the full title on hover
- Words: placeholder above; timestamp shown as "04:12" in monospace
- Access: the title and notes are text fields VoiceOver reads as "Meeting title" and "My notes"; timestamps are read as "4 minutes 12 seconds"
Status: done

### S-004 See the live draft while recording
As the user, I see the latest words from the call in the recording bar, and the full draft at the end of the transcript.
Screens: recording-bar, meeting-transcript
Depends: S-002, engine spike
Acceptance:
- [snap] The bar shows a red dot, the latest draft line with the speaker side (me or them), the elapsed time, Pause, and Stop.
- [self] The draft line trails speech by under 3 seconds on this Mac.
- [snap] In Transcript, draft lines are marked Draft and shown in a muted color.
- [snap] While recording, the floating recording controls (above all apps) show five level bars that move with the captured audio, the state and captured time, Pause/Resume, and Stop (design/KIT.md "Recording controls").
UX:
- Flow: recording runs -> the recording bar shows the latest draft line -> Transcript shows the full draft at the end -> nothing to do
- Surface: inline (the recording bar at the bottom of the meeting)
- States: before anyone speaks, "Listening…"; draft model still downloading, "Draft starts when the speech model is ready (240 MB of 470 MB)". Silence on either side is normal and never warns
- Words: "Draft" label in Transcript; Me shown as my name, Them as "Them"
- Access: the bar's draft line is not announced on every change (VoiceOver would talk over the call); Pause and Stop have labels "Pause recording", "Stop recording"
Status: todo

### S-005 Get the after-call transcript
As the user, I stop the recording and, a few minutes later, the draft is replaced by the cleaned transcript.
Screens: recording-bar, meeting-transcript
Depends: S-004, engine spike
Acceptance:
- [snap] After Stop, the bar shows "Transcribing" with time left, then goes away.
- [unit] Mic words that repeat the call track (headset or speaker bleed) are removed before the transcript is written.
- [unit] The transcript is written to the meeting's Markdown, and words, timings, and confidences to the sidecar JSON.
- [self] A 1-hour test recording finishes in under 3 minutes.
- [self] If processing fails, the meeting shows the reason and Try again; the audio is kept.
UX:
- Flow: Stop -> bar shows "Transcribing… about 2 min left" with a progress bar -> bar goes away, Transcript shows the final text -> a notification "Transcript ready: <meeting>" only if the window is not in front
- Surface: inline (the recording bar), plus a notification when the app is in the background
- States: progress known, so a bar with time left; failure shows "Unable to transcribe this meeting. The audio is saved." with "Try Again"
- Words: "Transcribing…", "Try Again", "Transcript ready"
- Access: VoiceOver announces once when transcription finishes
Status: done
Note: the bar shows a spinner, not time left, while transcribing. Scored on a 31-minute test call against a reference transcript: 85 s to transcribe; call side about 10% off; mic side 21% off (bar 25%), down from 43% before bleed was removed word by word, by level and then by matching the call (`EchoCleanup`). A second call (65 minutes, headphones, the first 37 scored): mic side 12% off, then 7% once the leak was silenced in the audio before the speech model hears it (`EchoCleanup.bleedFrames`). Still thin evidence: score more calls, and one on speakers.

### S-006 Read the transcript and jump to a moment
As the user, I open Transcript, read the turns, and click a line to hear it.
Screens: meeting-transcript
Depends: S-005
Acceptance:
- [snap] Transcript shows the player strip on top, then blocks with speaker, timestamp, and text; my side is labeled with my name and theirs as Them until speakers are named.
- [self] Clicking a block plays from its start; the playing block is highlighted.
- [snap] Words below the confidence threshold are underlined.
UX:
- Flow: pill > Transcript (⌘3) -> read -> click a block or press Space on it -> audio plays from there -> Space pauses
- Surface: a view of the meeting page, switched by the pill
- States: transcript not ready shows the draft and "Transcribing…"; a meeting with no audio (imported) hides the player and says "Imported from Granola. No audio."
- Words: pill labels "Summary", "My notes", "Transcript"; player tooltips "Play from here (Space)"
- Access: blocks are a list; arrow keys move between them, Space plays; underlined low-confidence words also carry a VoiceOver hint "low confidence"
- Shortcuts follow the pill order: ⌘1 Summary, ⌘2 My notes, ⌘3 Transcript
Status: done
Note: [manual] playback still needs a real recording to try.

### S-007 Jump from a note to the transcript
As the user, I click a note's timestamp and the transcript opens at that moment.
Screens: meeting-notes, meeting-transcript
Depends: S-003, S-006
Acceptance:
- [self] Clicking a timestamp switches to Transcript and scrolls to the block that covers that time.
UX:
- Flow: click a note's timestamp -> Transcript opens scrolled to that time, block highlighted -> ⌘[ goes back to My notes at the same line
- Surface: inline (the timestamp is a link)
- States: no transcript yet shows the draft at that time, or "Transcript isn't ready yet" as a tooltip
- Words: tooltip "Show this moment in the transcript"
- Access: timestamps are buttons in the tab order with that label
Status: todo

### S-008 Find a meeting in the sidebar after a restart
As the user, I quit and reopen Silvanus and find my meeting in the sidebar, grouped by day.
Screens: meeting-notes, empty-library
Depends: S-003
Acceptance:
- [snap] The sidebar lists meetings under day headers, each row with title and time; a recording row shows the elapsed time in red.
- [unit] The index rebuilds from the Markdown files if `index.sqlite` is deleted.
- [snap] With no meetings, the canvas shows how to start the first recording.
UX:
- Flow: launch -> sidebar shows Today, Yesterday, then dates -> click a row -> the meeting opens on My notes
- Surface: sidebar (a place people come back to)
- States: empty library shows "No meetings yet" with "Start Recording" and the shortcut; a recording row shows "● 24:18" in red with the word "Recording" for VoiceOver; long titles truncate with the full title on hover
- Words: day headers "Today", "Yesterday", then "Thursday, Nov 5"
- Access: arrow keys move through rows; Return opens; ⌘F jumps to search (M5)
Status: todo

### S-039 Take notes without a call, and record later
As the user, I start a meeting page with ⌘N to take notes on my own, and if a conversation starts I record into that same meeting.
Screens: meeting-notes, empty-library, menubar-menu
Depends: S-002, S-003
Acceptance:
- [snap] The empty library offers New Meeting and Start Recording side by side.
- [self] Start Recording (⇧⌘R) records into the open meeting when it has no audio yet and started in the last 12 hours; otherwise it starts a new meeting.
- [snap] A notes-only meeting shows a Start Recording button in its toolbar; the File menu calls it Record This Meeting.
- [self] New Meeting is also in the menu bar menu.
- [snap] The sidebar has New Meeting (compose) and Quick Note (microphone) buttons; Quick Note (⌥⌘N) starts a new meeting and records it right away.
- [snap] The meeting toolbar shows a labeled Record button with a red dot (Stop with the elapsed time while recording).
UX:
- Flow: ⌘N, toolbar compose button, or menu bar > New Meeting -> notes page with the cursor in it -> optionally ⇧⌘R or the toolbar record button -> recording into this meeting
- Surface: inline (toolbar button on the meeting page; no new window)
- Words: "New Meeting", "Quick Note", "Record", "Start Recording", "Record This Meeting"; notes placeholder "Start writing…"; tooltips "Start a meeting page for notes, without recording (⌘N)", "Record this meeting (⇧⌘R)"
- Access: both commands are in the File menu with shortcuts
Status: done

## M2 Trustworthy capture
Calls survive real life: pauses, unplugged headsets, sleep, and long sessions.

### S-009 Pause and resume a recording
As the user, I pause from the bar, the menu, or ⌃⌥P, and nothing is written until I resume.
Screens: recording-bar, menubar-menu, meeting-transcript
Depends: S-002
Acceptance:
- [unit] While paused, no audio is written to either track.
- [snap] The bar and menu bar item turn grey with a pause glyph, and the time freezes.
- [snap] The transcript shows a "Paused 14:02–17:45" marker.
- [self] After 5 minutes paused, a notification asks whether to resume.
Status: todo

### S-010 Remove the last few minutes
As the user, I choose Remove last 2, 5, or 10 minutes while recording.
Screens: menubar-menu, meeting-transcript
Depends: S-002
Acceptance:
- [unit] The matching audio segments are deleted before any transcription runs.
- [snap] The transcript shows a "Removed" marker for that span.
Status: todo

### S-011 Keep recording through a device change
As the user, I unplug my headset mid-call and the recording continues on the built-in mic.
Screens: recording-bar
Depends: S-002
Acceptance:
- [self] Both tracks keep their alignment across the switch; the gap is filled with silence and noted in the sidecar.
- [snap] The bar briefly shows which microphone is now in use.
- [self] A silent call track or microphone never shows a warning: silence is normal (design/KIT.md "Recording controls").
Status: todo

### S-012 Record a 2-hour call without trouble
As the user, I record a long call and the Mac doesn't sleep, memory stays flat, and the transcript finishes.
Depends: S-005
Acceptance:
- [self] A sleep assertion is held while recording; on wake, a new segment continues the same meeting.
- [self] Memory stays under a fixed ceiling over a 2-hour test file.
- [self] Low disk space is checked before and during recording, with a warning before it runs out.
Status: todo

### S-013 Confirm before quitting while recording
As the user, quitting during a recording asks me to stop first.
Screens: menubar-menu
Depends: S-002
Acceptance:
- [manual] ⌘Q while recording shows "Stop recording and quit?" with Stop and Quit, and Cancel.
Status: todo

### S-014 Start recording with a global shortcut
As the user, I press a global shortcut from any app to start or stop recording.
Screens: settings-recording
Depends: S-002
Acceptance:
- [self] The shortcut works with another app in front.
- [snap] Settings › Recording shows the shortcut and lets me change it.
Status: todo

### S-015 Follow the call app's microphone
As the user, Silvanus records the microphone my call app is using, not the system default.
Depends: S-002
Acceptance:
- [manual] With Zoom set to the headset and the Mac default set to the built-in mic, Silvanus records the headset.
Status: todo

## M3 Speakers
Turns are named, and names are remembered.

### S-016 Split the call track into voices
As the user, the transcript shows Speaker 1, Speaker 2, and so on for the other side of the call.
Screens: meeting-transcript
Depends: S-005, engine spike
Acceptance:
- [unit] Diarization runs in windows, so a 2-hour call doesn't run out of memory.
- [snap] Each voice has its own color dot in the transcript.
- [self] If speakers can't be separated, the meeting says so and offers Retry, never a silent fallback.
Status: todo

### S-017 Name the speakers after a call
As the user, I open Name speakers, play a short sample of each voice, and pick a name.
Screens: name-speakers
Depends: S-016
Acceptance:
- [snap] One row per voice: a play button, talk time, a quoted line, and a name field with attendee suggestions.
- [self] Names apply to the transcript immediately and are saved in the Markdown frontmatter.
- [snap] Meetings with unnamed voices show "Name speakers" in the sidebar.
Status: todo

### S-018 Merge or split a voice
As the user, I merge two voices that are the same person, or mark a voice as several people.
Screens: name-speakers
Depends: S-017
Acceptance:
- [unit] Merging relabels every turn of the merged voice.
- [snap] A voice marked "Several people" is shown that way in the transcript.
Status: todo

### S-019 Recognize people I've named before
As the user, voices I've named before are named for me in new meetings.
Screens: name-speakers
Depends: S-017
Acceptance:
- [unit] A stored voice print matches above the similarity threshold and by a clear margin; otherwise it's only a suggestion.
- [snap] A matched name shows that it came from a saved voice.
- [self] Voice prints are stored as embeddings in `speakers.json`, never audio.
Status: todo

### S-020 Manage saved voices
As the user, I see my saved voices and delete one.
Screens: settings-storage
Depends: S-019
Acceptance:
- [snap] A list of saved voices with name, meeting count, and Delete.
- [unit] Deleting removes the embedding; past transcripts keep their names.
Status: todo

### S-021 Name speakers from the call app's highlight
As the user, people highlighted as speaking in Zoom, Meet, or Teams are named for me.
Depends: S-016
Acceptance:
- [unit] Active-speaker log entries vote a name onto each voice by overlap.
- [manual] On a real Zoom call, at least the people who spoke for a minute or more are named correctly.
Status: todo

## M4 Calendar and detection
Meetings start themselves and know what they are.

### S-022 Get prompted when a call starts
As the user, when a call app grabs the mic, a notification asks whether to record, named after the calendar event.
Screens: call-prompt
Depends: S-002
Acceptance:
- [snap] The prompt shows the event title, time, and Record and Not now.
- [self] Zoom, Meet in a browser, Slack huddles, Teams, and FaceTime are detected.
- [self] "Never ask for this app" is remembered per app.
Status: todo

### S-022a Stop recording when the call ends
As the user, when I hang up, the recording stops on its own, so I don't have to remember Stop.
Screens: recording-controls
Depends: S-022
Acceptance:
- [unit] A recording started while a call app was using the microphone counts down once no call app has used audio input or output for 15 seconds (muted, playing only, never counts down); input or output coming back cancels; Keep recording holds until a new call starts; no countdown while paused or for Quick Note; at 0 it stops exactly like Stop (`CallEndStop`).
- [self] With the fake call probe: the countdown note shows and is announced, Keep recording, Pause, Quick Note, and the setting off never stop, and at 0 the meeting is closed and transcribed.
- [snap] The note above the bar reads "Call ended. Stopping in 10 seconds." with Keep recording.
- [manual] On a real Meet or Zoom call, hanging up stops the recording about 25 seconds later; talking alone in the call never warns.
UX:
- Signal: a call app's processes stop running audio input and output (Silvanus's own never counts), never how loud anything is. The call app may stay open after hanging up. Without the per-app audio list, it waits for the call app to quit.
- Words: "Call ended. Stopping in 10 seconds." … "Stopping in 1 second."; button "Keep recording"; Settings > General "Stop when the call ends" (on), "When the call app stops using audio, stop recording after a short countdown." and "Needs the Mac's per-app audio list; without it, waits for the call app to quit."
- Access: the countdown is announced once to VoiceOver; the seconds aren't.
Status: done

### S-023 Title a meeting from the calendar
As the user, a recording during a calendar event gets the event's title and attendees.
Screens: meeting-notes
Depends: S-002
Acceptance:
- [unit] The event overlapping the start time is chosen; with two, the one with a video link wins.
- [snap] The meta line shows date, time, call app, and attendee chips.
- [manual] Calendar access is read-only and asked for once.
Status: todo

### S-040 See upcoming calls
As the user, I see my next calls for today and tomorrow, and start notes for one with a click.
Screens: coming-up
Depends: S-023
Acceptance:
- [snap] With no meeting open, the page shows Coming up: today and tomorrow, each event with time, title, and attendee avatars; declined events are left out.
- [self] Clicking an event creates a meeting titled after it, with attendees, ready to record; Join opens its Zoom, Meet, or Teams link (only on those services' own domains).
- [snap] The menu bar menu lists the next events (Today, Tomorrow) above Start Recording.
- [self] Events come from EventKit, read-only, from 1 day back to 14 days ahead.
Status: todo

### S-024 Stop automatically when the call ends
As the user, the recording stops when the call app releases the mic near the event's end.
Screens: recording-bar
Depends: S-022
Acceptance:
- [unit] Auto-stop never fires in the first 3 minutes or while paused.
- [self] A warning with Keep recording shows 30 seconds before an auto-stop.
Status: todo

### S-025 Fix a wrong word in the transcript
As the user, I click a word, hear it, and correct it.
Screens: meeting-transcript
Depends: S-006
Acceptance:
- [self] The edit is saved to the Markdown; the sidecar keeps the original word.
- [unit] Custom vocabulary (from settings and attendee names) is used on the next transcription.
Status: todo

## M5 Library
All my meetings, including Granola's, in one place.

### S-026 Import my Granola archive
As the user, I import the exported Granola archive once and see those meetings next to new ones.
Screens: import-granola
Depends: S-008
Acceptance:
- [snap] The import sheet shows counts (meetings, with transcript, folders matched) and progress.
- [unit] Imported meetings keep their notes, summary (read-only, under Summary), folder, and transcript, and are tagged Granola.
- [unit] Running the import again skips meetings already imported.
Status: todo

### S-027 Move a meeting into a folder
As the user, I pick a folder from the meeting's toolbar.
Note: folders show in the sidebar under the meeting list, each opens its own list, and a meeting's folder shows as a breadcrumb at the top of its page.
Screens: meeting-notes, sidebar-filters
Depends: S-008
Acceptance:
- [snap] The chip lists folders and New folder.
- [unit] The meeting's Markdown frontmatter records the folder.
Status: todo

### S-028 Filter the sidebar by folder or status
As the user, I use the filter button to show one folder, Needs speakers, or From Granola.
Screens: sidebar-filters
Depends: S-027
Acceptance:
- [snap] The filter menu lists smart lists and folders with counts.
- [snap] A filtered sidebar shows the filter name at the top with a way to clear it.
Status: todo

### S-029 Search every transcript and note
As the user, I press ⌘F, type words, and see meetings with matching lines.
Screens: search
Depends: S-008
Acceptance:
- [snap] Results show the meeting, date, and the matching line with the words highlighted.
- [self] Clicking a result opens the meeting at that line.
- [self] A search over 300 meetings returns in under 200 ms.
Status: todo

### S-030 Prune old audio
As the user, call audio older than 90 days is deleted, and transcripts stay.
Screens: settings-storage
Depends: S-005
Acceptance:
- [unit] Pruning deletes audio only, and the meeting notes that audio is gone.
- [snap] Settings › Storage shows the retention period and space used.
Status: todo

### S-031 Re-transcribe a meeting
As the user, I re-run transcription on a meeting whose audio is still kept.
Screens: meeting-transcript
Depends: S-005
Acceptance:
- [self] Re-transcribing keeps my notes, speaker names, and word edits that still line up.
Status: todo

### S-032 Remove part of a meeting after the fact
As the user, I select a range in the transcript and choose Remove from meeting.
Screens: meeting-transcript
Depends: S-006
Acceptance:
- [unit] The words go from the Markdown and sidecar, and the span is cut from kept audio.
- [snap] A "Removed" marker takes their place.
Status: todo

## M6 Agents
My agent skills read and annotate meetings, with no cloud service in between.

### S-033 Read meetings through the MCP server
As an agent, I list meetings, get one, get its transcript, and search transcripts.
Depends: S-008
Acceptance:
- [unit] Tools `list_meetings`, `get_meetings`, `get_meeting_transcript`, and `search_transcripts` return the same shapes the existing skills expect.
- [unit] Removed and paused spans come back as markers only.
- [manual] An existing meeting-notes agent skill works against Silvanus without changes.
Status: todo

### S-034 Write agent notes, tags, folder, and speaker names
As an agent, I add notes under Agent notes, set tags or a folder, and name speakers.
Screens: meeting-summary
Depends: S-033
Acceptance:
- [unit] Agents can only write the agent notes section, tags, folder, and speaker names; never my notes or the transcript.
- [snap] Summary shows agent notes with which agent wrote them and when.
- [snap] Settings › Agents lists what agents may write, each with a switch.
Status: todo

### S-035 Use Silvanus from the command line
As the user, I run `silvanus list --since monday` and `silvanus show <id>`.
Screens: settings-agents
Depends: S-033
Acceptance:
- [unit] The CLI and MCP share one library API and talk to the running app, so there's one writer.
- [snap] Settings › Agents shows how to install the CLI and add the MCP server.
Status: todo

## M7 Polish

### S-036 Choose transcription settings
As the user, I pick the speech model, set custom vocabulary, and see model download status.
Screens: settings-transcription
Depends: S-005
Acceptance:
- [snap] Settings › Transcription shows the model, download size and status, and a vocabulary list.
- [self] Everything works offline after the one-time model download.
Status: todo

### S-037 Open the app icon and see it everywhere
As the user, Silvanus has its own icon in the Dock, Finder, and menu bar.
Acceptance:
- [snap] The icon renders in light, dark, and tinted looks.
Status: todo

### S-038 Use Silvanus in dark mode
As the user, every screen reads well in dark mode.
Screens: meeting-notes, meeting-transcript, name-speakers
Acceptance:
- [snap] Each listed page has a dark snapshot that passes the contrast check.
Status: todo

## M8 To-dos and summaries
What I owe after a call, written on this Mac by a local model.

### S-042 Choose the model that writes to-dos and summaries
As the user, Silvanus uses a model file that's already on my Mac, and I can pick another.
Screens: settings-summaries
Acceptance:
- [unit] With nothing chosen, the largest GGUF file another app downloaded (Biscotti's) is used; a chosen file wins while it exists.
- [snap] Settings › Summaries shows the model's name, where it came from, and Choose…; Use Default appears after a file was chosen.
- [self] A chosen file is saved, and Use Default forgets it.
- [manual] `APP_ASK=<question>` on the dev binary loads the model and prints its answer.
Status: done

### S-041 Get a to-do list after a call
As the user, when a call's transcript is ready, I get the to-dos from it: what I said I'd do, and what others said they'd do.
Screens: meeting-summary
Depends: S-005, S-042
Acceptance:
- [unit] To-dos are written to the meeting's `todo.md` as Markdown checkboxes, each with who owns it when the transcript says so.
- [unit] Ticking a box, editing a to-do, or adding one of my own is saved to `todo.md`, and making the list again never overwrites my changes.
- [snap] The meeting shows its to-dos with boxes I can tick in place; a meeting with none says so.
- [self] The list is written by a local Gemma model on this Mac. Nothing is sent anywhere, and it works offline after the one-time model download.
- [manual] On a real call, the list has the to-dos I'd have written down and no made-up ones.
- [self] Meeting › Write To-dos (⌃⌘T) writes the list again for the open meeting; it's off without a transcript.
Status: done
Note: the manual check on a real call is still to do.

### S-043 See every to-do in one place
As the user, I open To-dos in the sidebar and see what's still open across all my meetings, like a light task manager.
Screens: todos
Depends: S-041
Acceptance:
- [unit] The page lists each meeting that has an open to-do, newest first, with all that meeting's to-dos; a meeting drops off once every one is done.
- [snap] The sidebar's To-dos row sits above the meetings with the count of open to-dos; the page shows each meeting's title and date over its to-dos, done ones struck through.
- [self] Ticking or unticking a to-do on the page writes that meeting's `todo.md`, and the count follows.
- [self] Clicking a meeting's title opens its Summary; opening any meeting leaves the page. View › To-dos (⇧⌘T) opens it.
- [self] On the page, a to-do's words can be changed in place (clearing them deletes it), a to-do can be deleted from its menu, and each list ends with a New to-do field. Every change is saved to that list's `todo.md`.
- [self] My to-dos, at the top, holds to-dos that belong to no meeting (`todo.md` in the library's root); they count in the sidebar too.
- [self] Meeting › New To-do (⌥⌘T) adds a to-do to the open meeting, starting its list if it has none, and selects its words on Summary to type over.
Status: done
Note: no due dates, sorting, reordering, or moving a to-do between lists yet. A done to-do on the page is dimmed, not struck through.

### S-044 Get a summary after a call
As the user, when a call's transcript is ready, I get a short summary of it.
Screens: meeting-summary
Depends: S-005, S-042
Acceptance:
- [unit] The summary is written to the meeting's `summary.md`: Overview, then Decisions and Open questions when there were any.
- [unit] A summary that was already there (an imported one) is kept under the new one; writing again replaces only the model's part.
- [self] Meeting › Write Summary (⌃⌘U) writes it for the open meeting; it's off without a transcript.
- [self] The summary is written by the local model on this Mac, after the to-dos.
- [manual] On a real call, the summary says what happened and nothing that didn't.
Status: done
Note: the manual check on a real call is still to do. The summary can't be edited in the app.

### S-045 Get to Home and Settings from the sidebar
As the user, I click Home at the top of the sidebar or Settings at the bottom.
Acceptance:
- [snap] The sidebar starts with Home and To-dos, and ends with Settings.
- [self] Home closes the open meeting and shows the home page; View › Home (⇧⌘H) does the same.
Status: done

## Later
- Connectors, so to-dos and summaries can come from a model you choose: the Ollama app, Claude, or ChatGPT. The local model stays the default.
- Multilingual transcription (WhisperKit).
- "I'm recording for my notes" snippet copied when recording starts.

## Dropped
- Cloud AI summaries, chat, and templates: to-dos and summaries use a local model, and agents do the rest through MCP.
- Sharing, links, teammates, workspaces, and sync: Silvanus is for one person.
- Accounts and sign-in: nothing leaves the Mac.
- Mobile app.
- Screen-share screenshots and a virtual camera.
- Consent auto-paste into the call chat, pausing Music on join, and LLM-judged meeting end (behaviors of other meeting apps we chose not to copy).
- An "Ask anything" bar: replaced by the recording bar, since Silvanus has no built-in AI.
