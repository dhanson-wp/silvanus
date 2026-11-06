# Silvanus design kit

Every number here was measured from 2x window captures of the reference at a 910 × 600 pt window, unless it's marked **adapted** (a measured number fitted to this grid, with the reason) or **provisional** (not captured yet; verify before calling it done). Coordinates are points from the window's top left corner.

There are two color sets. **Reference** colors are only for the pixel-compare build, where a screen has to land within 2% of the reference capture. **Silvanus** colors are the scribe palette, and they're what ships.

## Feel

Quiet, literate, exact. A writing desk, not a dashboard: warm paper, one ink, gold used sparingly.

## Tokens

### Palette

Silvanus (the scribe):

| Name | Hex | Notes |
| --- | --- | --- |
| midnight | #17142C | ink in light, ground in dark |
| raisedMidnight | #252039 | dark canvas and raised surfaces |
| ivory | #F5EDDF | light ground, ink in dark |
| paper | #FFFBF5 | light canvas |
| parchment | #E6DAC5 | light dividers |
| mutedInk | #6D6674 | light secondary text, dark dividers |
| mutedIvory | #BCB4C5 | dark secondary text |
| gold | #C8AA73 | accent: fill everywhere, text only in dark |
| recordRed | #B42318 | recording fill (ours, not from the palette) |
| recordRedLight | #FF8A80 | recording text on dark surfaces (ours) |

Reference (pixel compare only):

| Name | Light | Dark |
| --- | --- | --- |
| refSidebar | #FAFAF9 | #1F1B19 |
| refCanvas | #FFFFFF | #2D2825 |
| refDivider | #E7E5E4 | #4C4743 |
| refText | #1B1917 | #FAFAF9 |
| refSecondary | #79736D | #928B86 |
| refTertiary | #9A9592 | #77716C |
| refChipText | #525252 | #D4D4D4 |
| refSelection | #F0F0EF | #443F3C |
| refPillTrack | #E8E8E8 | #3A3532 |
| refPillSegment | #FFFFFF | #443F3C |
| refBarBorder | #EEEDEC | #433D3A |
| refRule | #FC5156 | #BD4E50 |
| refSpeaker | #B4445C | #F0788C |
| refControlOn | #2D2825 | #2D2825 track, #FAFAF9 knob |
| refSettingsPane | #FFFFFF | #443F3C |
| refSettingsSelected | #E7E7E4 | #3E3A37 |
| refSearchField | #F5F5F4 | #312D2A |

### Meaning

Parts read only these. Each row gives the reference value (for the pixel-compare build) and the Silvanus value (what ships), in light and dark.

| Token | Reference light | Reference dark | Silvanus light | Silvanus dark | Used for |
| --- | --- | --- | --- | --- | --- |
| Ink.background | #FAFAF9 | #1F1B19 | ivory | midnight | window ground behind the panes |
| Ink.sidebar | #FAFAF9 | #1F1B19 | ivory | midnight | sidebar and settings list |
| Ink.canvas | #FFFFFF | #2D2825 | paper | raisedMidnight | notes canvas, settings pane, cards |
| Ink.text | #1B1917 | #FAFAF9 | midnight | ivory | titles, body, labels |
| Ink.textSecondary | #79736D | #928B86 | mutedInk | mutedIvory | times, folder line, descriptions, placeholders, sidebar icons |
| Ink.textTertiary | #9A9592 | #77716C | mutedInk | mutedIvory | unselected view pill icons |
| Ink.divider | #E7E5E4 | #4C4743 | parchment | mutedInk | pane divider, canvas border, button and chip borders |
| Ink.selection | #F0F0EF | #443F3C | paper | raisedMidnight | selected row fill, sidebar icon button hover |
| Ink.controlHover | #F0F0EF | #443F3C | ivory | midnight | hover and pressed fills of controls on the canvas (header icon buttons, Record, chips) |
| Ink.pillTrack | #E8E8E8 | #3A3532 | parchment | midnight | view pill track |
| Ink.pillSegment | #FFFFFF | #443F3C | paper | raisedMidnight | view pill selected segment |
| Ink.accent | #FC5156 | #BD4E50 | gold | gold | **fill only**: sidebar rule, event rule, today dot, played waveform |
| Ink.accentText | #B4445C | #F0788C | midnight | gold | speaker labels, links, accent text |
| Ink.focus | n/a | n/a | midnight | gold | focus rings |
| Ink.primaryControl | #2D2825 | #2D2825 | midnight | ivory | switch on, primary button fill |
| Ink.onPrimary | #FAFAF9 | #FAFAF9 | ivory | midnight | switch knob, primary button label |
| Ink.recording | n/a | n/a | recordRed | recordRed | Record button fill, live dot |
| Ink.onRecording | n/a | n/a | ivory | ivory | label on the recording fill |
| Ink.recordingText | n/a | n/a | recordRed | recordRedLight | "Recording" text and timer on canvas |
| Ink.barGround | n/a | n/a | midnight | midnight | the recording controls' and the Meeting detected prompt's fill: opaque and dark in both themes, so they read the same over any window |
| Ink.barRaised | n/a | n/a | raisedMidnight | raisedMidnight | hover fills on the bar (Pause, Not now, the grip) |
| Ink.barEdge | n/a | n/a | gold | gold | the bar's and the prompt's 1 pt outer edge, the level bars, the state dot, focus rings on the bar, Record meeting's fill (gold on midnight 8.06:1) |
| Ink.barText | n/a | n/a | ivory | ivory | the state, icons, the note, Stop's fill, the prompt's title and question (15.40:1 on midnight) |
| Ink.barTextSecondary | n/a | n/a | mutedIvory | mutedIvory | the time, the grip's dots, quiet level bars, outlined button edges, the prompt's source line (8.93:1 on midnight, 7.79:1 on raisedMidnight) |

Why these choices:

- **Gold is fill only.** Gold on paper is 2.15:1 and on ivory 1.91:1, too low for text or a focus ring. In light, accent text and focus are midnight (17.37:1 on paper). In dark, gold reads well (7.03:1 on raisedMidnight, 8.06:1 on midnight), so dark uses gold for accent text and focus. Gold as fill: the sidebar rule, the Coming up event rule, the today dot, the played part of the waveform, and the selected tab underline if one is added.
- **Sidebar uses `background`, not `navigation`.** The palette names midnight as `navigation` in light, but a midnight sidebar in the light theme would invert the measured structure (a light sidebar a step darker than the canvas). The sidebar takes ivory and the canvas takes paper, which keeps that one-step relationship. Revisit if the brand wants a dark navigation pane.
- **Selection in light is paper, not parchment.** Secondary text on parchment is 4.00:1, which fails 4.5:1 for the time on a selected row. Paper on the ivory sidebar keeps it at 5.36:1 and stays as subtle as the reference's selection.
- **Controls on the canvas hover with `controlHover`.** In Silvanus, selection equals the canvas (paper, raisedMidnight), so a selection fill on the canvas wouldn't show. controlHover takes the sidebar's ground, one step off the canvas in each theme; text on it still passes (mutedInk 4.75:1 on ivory).
- **Recording red is ours.** recordRed #B42318 carries an ivory label at 5.65:1 in both themes, because the label always sits on the red fill. As text on its own, recordRed passes on paper (6.38:1) but not on raisedMidnight (2.38:1), so dark uses recordRedLight #FF8A80 (6.84:1).
- Secondary text passes everywhere it's used: mutedInk 5.36:1 on paper and 4.75:1 on ivory; mutedIvory 7.79:1 on raisedMidnight and 8.93:1 on midnight.

### Metric

| Token | Value | Why |
| --- | --- | --- |
| windowDefault | 910 × 600 | measured |
| headerHeight | 46 | measured; controls are 28 tall at y 9 |
| controlHeight | 28 | measured: view pill, buttons, chips, icon button hover |
| sidebarWidth | 208, then a 1 pt divider at x 208 | measured |
| canvasX | 209 | measured |
| canvasCorner | 10 | measured 9 to 10.5 on the canvas's left corners |
| contentX | 221 | measured: canvas text and header start, 12 after the canvas edge |
| contentTrailing | 12 | measured: player strip ends 12.5 before the window edge |
| sidebarRowInset | 4 | measured: pills run x 4 to 204 |
| sidebarTextX | 16.5 | measured ink edge; the token is 16, since the first letter's side bearing adds half a point |
| rowCorner | 8 | measured |
| meetingRowPitch | 54 | measured, no folder line |
| meetingRowPitchFolder | 72 | measured: the folder line adds 18 |
| folderRowPitch | 28 | adapted (see Folder row) |
| iconButton | 28 × 28, corner 7 | measured hover square |
| buttonCorner | 6 | measured 5 to 6 on the bordered button |
| hairline | 1 | measured divider width; dashed card dividers are 0.5 |

### Motion

| Token | Curve | Used for |
| --- | --- | --- |
| hover | ease out 0.12 s | hover fills |
| select | ease out 0.18 s | view pill segment slide, row selection |
| level | ease out 0.1 s | the recording controls' level bars following the audio; none with Reduce Motion |

Motion isn't measurable from stills; these are our defaults.

## Type

System font throughout (SF Pro, and SF Mono for times). The reference uses the system face for all text, and its sizes were fitted by rendering the same words in the system font and matching ink widths. The reference's time face is a monospace close to SF Mono; Silvanus uses SF Mono. The reference's settings page title uses a script face; Silvanus doesn't copy it and uses `title` there.

| Role | Font | Size | Weight | Line height | Used for |
| --- | --- | --- | --- | --- | --- |
| title | system | 24 | bold | 28 | meeting title, H1, settings page title |
| heading | system | 20 | bold | 24 | H2 in notes and summaries |
| subheading | system | 18 | semibold | 22 | H3 in notes, settings section heading |
| body | system | 16 | regular | 24 | notes canvas text |
| transcript | system | 14 | regular | 22.75 | transcript paragraphs |
| rowTitle | system | 14 | regular | 17 | meeting row title, folder row, settings list label, event title, placeholder |
| rowTitleSelected | system | 14 | medium | 17 | selected settings list label |
| settingTitle | system | 14 | medium | 17 | settings row title |
| button | system | 14 | medium | 17 | bordered and primary buttons |
| dayHeading | system | 16 | bold | 19 | sidebar day heading |
| tab | system | 12 | medium | 14 | view pill label |
| chip | system | 12.5 | regular | 15 | folder chip, meeting header chips |
| label | system | 12 | regular | 14 | speaker label, setting description |
| section | system | 12 | regular, uppercase | 14 | settings list group ("App", "AI") |
| meta | system | 11 | regular | 13 | folder line in a meeting row, month and weekday |
| monoTime | SF Mono | 12 | regular | 14 | meeting row time, event time |
| monoSmall | SF Mono | 11 | regular | 13 | player time, transcript timestamp |
| dayNumber | system | 28 | regular | 28 | Coming up day number (adapted) |
| barState | system | 11 | semibold | 13 | the recording controls' state ("Recording", "Paused", "Audio lost", "Mic only") |
| barTime | system, tabular digits | 11 | regular | 13 | the recording controls' time ("12:34 elapsed") |
| barNote | system | 12 | regular | 16 | the note above the recording controls, the prompt's source line (both wrap) |
| promptTitle | system | 15 | semibold | 21 | "Meeting detected" |
| promptBody | system | 13 | regular | 21 | the prompt's question |
| promptButton | system | 12 | semibold | 14 | Record meeting (Not now uses `label`) |

Notes:

- The editor's old scale (body 15, H1 24, H2 19, H3 16 semibold, 1.4 line height) is replaced by body 16 / 24, H1 24 bold, H2 20 bold, H3 18 semibold.
- The reference's chip label measures between 12 and 13 (cap height says 12.75, width says 12.25); 12.5 is closest on both.
- The day number is adapted: the reference for Coming up uses a serif with 20 pt tall digits. 28 pt system digits are about the same height.

## Icons

Source: SF Symbols, regular weight, at 14 pt (the reference's set is 12 to 15 pt wide with about a 1 pt stroke and round caps and joins). One size and one stroke weight for the set. A size is the ink's longer side, which for every glyph wider than tall is its width, as measured. The kit measures each symbol's ink, not its image: the image has 2 to 4 pt of padding, and sizing by it drew every icon about a fifth too small (the folder line icon 9 wide, not 11). Taller-than-wide glyphs (play, mic, pause, chevrons, waveform) still fit their longer side, so they draw a little narrower than a width would make them. Selected rows and segments keep the outlined form; nothing switches to filled on select.

| Icon | Size | SF Symbol to start from |
| --- | --- | --- |
| hide sidebar | 15 | `sidebar.left` |
| search | 13 | `magnifyingglass` |
| new note | 13 | `square.and.pencil` |
| filter | 13 | `line.3.horizontal.decrease` |
| Summary tab | 11 | `sparkle` |
| My notes tab | 12 | `text.alignleft` |
| Transcript tab | 15 | `waveform` |
| folder (chip and row) | 15 in the header, 11 in a row's folder line, 14 in a folder row | `folder` |
| more | 11 (three 2 pt dots, 4 apart) | `ellipsis` |
| play | 9 | `play` |
| record | 12 | `record.circle` |
| quick note mic | 14 | `mic` |
| pause | 12 | `pause` |
| stop | 12 | `stop` |
| bar pause, bar resume | 9 | `pause.fill`, `play.fill` (the recording controls; Retry uses resume) |
| bar stop | 7 | `stop.fill` |
| date chip | 13 | `calendar` |
| attendees chip | 15 | `person.2` |
| back (settings) | 14 | `chevron.left` |
| settings list | 14 | `gearshape`, `paintbrush`, `waveform`, `mic`, `info.circle` (About; ours) |

Icon color is `Ink.textSecondary` in the sidebar header and trailing header buttons, `Ink.textTertiary` for unselected pill tabs, and `Ink.text` on the selected segment and on bordered buttons.

## Window

- Title bar hidden; the header and sidebar are drawn by the kit. Menus, shortcuts, context menus, sheets, and alerts stay native.
- Default size 910 × 600 (the pixel-compare size).
- Traffic lights: 14 pt circles, centers at (19, 23), (42, 23), and (65, 23), so 23 apart, vertically centered in the 46 pt header.
- Header: 46 tall across both panes, no fill of its own (it shows the sidebar on the left and the canvas on the right) and no bottom border.
- Sidebar: 208 wide, `Ink.sidebar`, custom rows (not `List`). A 1 pt `Ink.divider` line at x 208.
- Canvas: starts at x 209, `Ink.canvas`, a 1 pt `Ink.divider` border on its leading edge and 10 pt corners where it meets the top and bottom of the window. It runs the full window height.

## Parts

### Sidebar header row

Anatomy: traffic lights, then four 28 × 28 icon buttons (hide sidebar, search, new note, filter).

- Icon centers at x 94, 122, 150, 178 (28 apart), y 23.
- Hover square 28 × 28, corner 7, at y 9.

| State | Fill | Icon |
| --- | --- | --- |
| rest | none | textSecondary |
| hover | selection | text |
| pressed | selection, 80% | text |
| focused | 2 pt focus ring, corner 7 | text |
| disabled | none | textSecondary at 40% |

### Sidebar accent rule

A 1 pt line in `Ink.accent` from y 64.5 to 65.5 (its top edge at 64.5), from x 4 to 204 (inset 4). It sits under the header and above the first day heading. Silvanus: gold (fill only).

### Day heading

`dayHeading` (16 bold), `Ink.text`, at x 16.5. Cap top at y 84.5 on a capital (84 counts the antialiased row above), 19 below the rule's bottom edge. The first row's pill starts at y 106, 40.5 below the rule's bottom edge.

### Meeting row

Anatomy: optional folder line (11 pt folder icon, 5.5 gap, `meta` text in `textSecondary`), title (`rowTitle`, one line, truncates with an ellipsis), time (`monoTime`, `textSecondary`).

- Pill: x 4 to 204 (200 wide), corner 8. Rows sit back to back: the pill height is the row pitch.
- Without a folder line: 54 tall. Title cap top at +13.5 on a capital (the +12.5 to +13 first written down was the top of the ascenders in the measured word), set as +13.75; time cap top 20.5 below the title's.
- With a folder line: 72 tall. Folder line cap top at +11.5 (set so the ink lands where measured, +11 on the antialiased edge), title cap top 20 below it, time 20.5 below the title.
- Text and icons start at x 16.5 (12.5 inside the pill).

| State | Fill | Title | Time and folder line |
| --- | --- | --- | --- |
| rest | none | text | textSecondary |
| hover | selection at 50% | text | textSecondary |
| selected | selection | text, medium | textSecondary |
| selected, window inactive | selection at 60% | text, medium | textSecondary |
| focused | 2 pt focus ring inside the pill | text | textSecondary |
| recording now | none | text | recordingText, with a 6 pt live dot before the time |

### Folder row

Organization part, adapted to this grid.

- Icon 14 (`folder`) at x 16.5, label `rowTitle` at x 39.5, trailing glyph (shared, count) right-aligned 15.5 from the sidebar's edge. **Adapted**: the reference for folders puts the icon at +8 for nesting and the label 10 after a 13 pt icon; these take the measured settings-list edges (16.5 and 39.5) so every list in the sidebar shares two left edges.
- Pill: 28 tall, inset 4, corner 8, rows back to back (pitch 28). **Adapted**: the reference for folders uses a 28 pt pill at a 29 pt pitch; Silvanus drops the 1 pt gap so folder rows behave like meeting rows.
- States: same as the meeting row (rest, hover, selected, inactive, focused). A folder with a live recording shows the 6 pt live dot in its trailing slot.

### Coming up card

Organization part, adapted to this grid. It sits in the canvas on the home page.

- Card: x 221 to 897 (the content column), `Ink.canvas` on `Ink.background`, 0.5 pt `Ink.divider` border, corner 12 (measured). **Adapted**: the reference card is 624 wide in a 1200 pt window; here it fills the content column.
- Day group: padding 16 top and bottom (measured). Groups are split by a 0.5 pt dashed `Ink.divider` line.
- Day column: `dayNumber` at +16 from the card's leading edge (**adapted** from 25 to match the 12 pt content rhythm plus a 4 pt card inset), month (`meta`, medium) and weekday (`meta`, `textSecondary`) at +48, month cap top level with the top of the digits and weekday 12 below (measured 12). A 4.5 pt today dot in `Ink.accent` sits 4 after the month (gold, fill only).
- Event rows start at +168 (measured). Each has a 3 pt wide vertical rule in `Ink.accent` (corner 1.5) spanning the title and time, then the title (`rowTitle`) at 14 after the rule, then the time (`monoTime`, `textSecondary`) 20.5 below the title's cap top. **Adapted**: the reference uses 18 between title and time; Silvanus uses the sidebar row's 20.5, so the rule is 32 tall and events repeat every 52 (the reference's 48 plus that 4).
- States per event row: rest; hover (selection fill, corner 8, inset 4 from the card); pressed; focused (ring); now (the rule turns `Ink.recording` while a meeting is live).
- Empty: one row in `textSecondary`, "Nothing on your calendar", same padding.

### Canvas header

All controls are 28 tall at y 9, centered in the 46 pt header.

**View pill** (Summary, My notes, Transcript):

- Track at x 221, 28 tall, fully rounded (corner 14), `Ink.pillTrack`, inset 2.
- Selected segment: 24 tall, corner 12, `Ink.pillSegment` with a soft 1 pt shadow below. Its width is 9 + icon + 8 + label + 9.5 (a five-letter label measured 78 wide; a ten-letter label with a trailing edit glyph, 117). Label `tab` (12 medium), `Ink.text`; icon `Ink.text`.
- Unselected tab: 34 wide, icon only, `Ink.textTertiary`, centered.

| State | Segment | Icon | Label |
| --- | --- | --- | --- |
| selected | pillSegment | text | shown |
| rest | none | textTertiary | hidden |
| hover | pillSegment at 50% | text | hidden; tooltip names the view |
| focused | 2 pt focus ring around the tab | text | as selected or rest |
| disabled (no transcript yet) | none | textTertiary at 40% | hidden |

**Trailing**, right to left from x 893 (17 from the window edge):

- More: three 2 pt dots 4 apart, ending at x 893; 28 × 28 hit area.
- Labeled Record button (takes the reference's bordered-button slot, x 796 to 870): see Record button below.
- Quick-note mic button: 28 × 28 icon button, 8 before the Record button. **Adapted**: the reference has no mic in this slot.
- Folder chip: 15 pt folder icon, 5.5 gap, label `chip` in `Ink.textSecondary`, no border, ending about 10.5 before the next control. With no folder it shows the icon alone (measured at x 770.5 to 785.5). Click opens the folder menu. **Not in Silvanus**: the meeting header's folder chip is the one place to set a folder, so the canvas header's trailing controls are the mic, Start Recording, and More.

### Record button and quick-note mic

**Record** (labeled): the label is "Start Recording" (docs/GLOSSARY.md), so the button is wider than the reference's five-letter slot (about 141 against 74); it keeps the trailing edge at x 870 and the controls before it move left. 28 tall, corner 6, padding 7 before the icon and 10.5 after the label, icon 12, gap 7.5, label `button` (14 medium). Measured from the reference's bordered header button (74 wide with a five-letter label, x 796 to 870).

| State | Fill | Border | Label and icon |
| --- | --- | --- | --- |
| rest | canvas | 1 pt divider | text |
| hover | controlHover | 1 pt divider | text |
| pressed | controlHover, 80% | 1 pt divider | text |
| recording | canvas | 1 pt divider | text, label "Stop"; the icon a stop square in recordingText (measured from the reference's recording state; recordingText, not recording, so the square reads on raisedMidnight) |
| focused | as rest | 2 pt focus ring | text |
| disabled (no input device) | canvas | 1 pt divider at 40% | text at 40% |

**Quick-note mic**: the 28 × 28 icon button (corner 7), `mic` icon. States as the sidebar header buttons (on the canvas, hover and pressed use `controlHover`), plus recording (icon `Ink.recordingText`, fill controlHover).

### Meeting header

Organization part, adapted to this grid. It's the top of the canvas on a meeting page.

- Title: `title` (24 bold), `Ink.text`, at x 221. Cap top at y 65, as measured for a summary title, so the first baseline sits at about y 82.
- Chip row: 15.5 below the title's lowest descender (measured), at x 221. Chips are 28 tall (**adapted**: same as the measured 28 pt controls; the reference's chips are also 28), fully rounded (corner 14), 0.5 pt `Ink.divider` border, no fill, 10 apart (**adapted** from 11 to sit between the two references' 10.5 and 11).
- Date chip: padding 14 leading and 10.5 trailing, calendar icon 13, 5.5 gap, date (`chip`), 8 gap, attendees icon 15, 4.5 gap, count (`chip`). Text `Ink.textSecondary`.
- Folder chip: padding 10.5, folder icon 13, 6.5 gap, folder name (`chip`), truncates. With no folder it reads "Add to folder" in `textSecondary`.
- The canvas body starts 20 below the chip row (**adapted** from 21.5 to the 4 pt rhythm).

| State | Fill | Text |
| --- | --- | --- |
| rest | none | textSecondary |
| hover | controlHover | text |
| pressed | controlHover, 80% | text |
| focused | 2 pt focus ring | text |
| empty value | none | textSecondary, placeholder words |

### Recording controls

**Approved by Derek on November 6, 2026 (the compact bar with a live level meter).** It replaces the 84 × 34 floating pill. Native audio contract: the bars come from the recording's own capture (both tracks), never a microphone of their own.

- Bar: 264 × 48, corner 13, opaque `Ink.barGround`, a 1 pt `Ink.barEdge` gold edge, and a soft offset shadow (radius 12, 4 down, midnight at 31%); the gold edge stays when shadows don't show. Inside 5, parts 6 apart.
- Grip, leading: a 34 × 36 target, corner 8, with six 2 pt dots in `barTextSecondary` (4 across, 5 down, center to center), 3 gap, and the 18 pt scribe (the menu bar glyph as a template, `barText`). It's the only drag region; hover fills it `barRaised`. A plain click focuses it (the panel takes the keyboard only then); the arrow keys move the bar 8 pt (24 with Shift) and Home puts it back. VoiceOver: "Move recording controls", with Move left, right, up, down, and Reset position actions.
- State and time, filling the middle (98 wide): a 5 pt dot (`barEdge` circle; a `barTextSecondary` square while paused), 5 gap, then the state in `barState` `barText`: "Recording", "Mic only" (call audio stopped; the microphone records alone), "Paused", or "Audio lost". Below it the captured time in `barTime` `barTextSecondary`, with "elapsed", "paused", or "stopped". The time leaves out pauses and lost audio, so it matches the saved audio, the transcript, and the notes' margin times. "Audio interrupted" (96 pt) doesn't fit at 11 pt, so the compact label is "Audio lost", as approved.
- Level bars: five, 3 wide, 2 apart, 3 to 18 tall, centered in 26 × 24. Gold (`barEdge`) while there's sound; flat and `barTextSecondary` when it's quiet, paused, or audio is lost. They show the last five smoothed levels: RMS of both tracks' captured audio on a decibel scale (−50 dBFS flat to −12 dBFS full), rising at once and falling softly, sampled 10 times a second (at most 15). Reduce Motion shows a steady 30/60/90/60/30% shape while there's sound and no motion. Never announced.
- Pause/Resume (Retry while audio is lost): 36 × 36, corner 8, outlined in `barTextSecondary` with a `barText` icon (`barPause`, `barResume`). Stop: 36 × 36, corner 8, `barText` fill with a `barGround` icon (`barStop`). Labels and tooltips: "Pause recording", "Resume recording", "Retry audio capture", "Stop recording".
- The note: while paused ("Audio isn't being saved."), with audio lost ("The microphone stopped. Check your audio devices, then retry."), or while Stop when the call ends counts down ("Call ended. Stopping in 10 seconds.", with Keep recording), a `barGround` card the bar's width sits 9 above it: `barNote` in `barText`, 14 × 10 inside, corner 10, a 1 pt `barTextSecondary` edge. Keep recording is the prompt's outlined button at 28 tall, on the trailing edge 8 below the words. The window grows upward for it (measured at "10 seconds", so it holds still while counting); the bar holds still.
- Silence is normal: neither side's silence ever warns or changes the state. Stop when the call ends follows the call app letting go of audio (no call app process running input or output for 15 seconds, so a muted listener stays in the call; Silvanus's own never counts), never amplitude, and only for a recording started during a call; never while paused, never for Quick Note.
- Pause releases both devices (the microphone indicator goes off) and Resume starts them again into the same tracks; a microphone that won't start again is Audio lost. Every release of the clock lines both tracks up with it: each pads its first buffer, or trims at most 50 ms off it, to the same instant, so different buffer sizes never drift apart. Retry after a failure that came while paused goes back to Paused. The note above the bar never moves the bar's saved spot.
- Panel: non-activating, always on top, on every Space and over full-screen apps, left out of window cycling, and shown for the whole recording whichever app is in front, Silvanus included (a persistent companion; hiding it when Silvanus comes forward would make it flicker as focus moves between the call and the notes, and Pause lives here). Pause, Resume, Retry, and Stop never activate Silvanus or take the keyboard. Its title is "Silvanus recording controls". Hide Recording Controls (menu bar, Window menu) puts it away for this recording; Show Recording Controls brings it back.
- Place: bottom center, 16 above the bottom of the visible frame (above the Dock), on the main window's display. Where it's dragged is saved per display (`AppDefaults` `recordingControls.positions` and `recordingControls.display`); it comes back on the display it was last left on while that's connected, else on the main window's display. It's kept inside the screen's visible frame (with room for the note), and comes back onto a screen when one is unplugged or changes size. Reset Recording Controls Position puts it back.
- VoiceOver: the group is "Silvanus recording controls". The state reads as one element ("Recording", value "12 minutes", to the minute); state changes are announced once ("Paused. Audio isn't being saved.", "Recording resumed", "Audio lost. …", "Audio is back. Recording.", "Mic only. …", "Call ended. Stopping in 10 seconds.", "Recording stopped"); the time and the bars never are.
- While recording, the view pill's Transcript tab shows a small live wave (bars 2 wide, 2 apart, 3 to 12 tall) in `recordingText` instead of its icon, from the same meter.
- After Stop, the canvas header shows "Transcribing…" (`label`, `textSecondary`) and a 64 × 4 bar (track `divider`, fill `accent`) before the mic.
- My notes while recording: each line's captured time (`mm:ss`, `monoSmall`, `textSecondary`) in a 64 pt trailing margin, level with the line's first row. The text keeps x 221 and wraps before the margin. Identical lines share one time (the times are keyed by the line's text), and a moved line keeps its time.

| State | State line | Time | Bars | First button |
| --- | --- | --- | --- | --- |
| recording | gold dot, Recording | counts up, "elapsed" | follow the audio | Pause |
| mic only | gold dot, Mic only (reason in the tooltip) | counts up, "elapsed" | follow the audio | Pause |
| call ended | as recording; note above with Keep recording | counts up | follow the audio | Pause |
| paused | muted square, Paused; note above | held, "paused" | flat, muted | Resume |
| audio lost | gold dot, Audio lost; note above | held, "stopped" | flat, muted | Retry |
| quiet | as recording | counts up | flat, muted | Pause |
| hover | Pause: `barRaised` fill; Stop: 6% brighter; grip: `barRaised` | | | |
| pressed | 5% dimmer | | | |
| focused | a 2 pt `barEdge` ring 3 outside the button (the grip: inside its edge) | | | |

### Meeting detected prompt

- An in-app prompt in the recording controls' look: 364 wide, as tall as its words, 20 inside, corner 16, `barGround`, a 1 pt `barEdge` edge, the bar's shadow. Top right of the screen, 16 in.
- The app icon at 42, 12 gap, then the title (`promptTitle`, `barText`) over the source line (`barNote`, `barTextSecondary`); 16 below, the question (`promptBody`, `barText`); 16 below, Not now and Record meeting on the trailing edge, 8 apart.
- Words: "Meeting detected", "Silvanus · (App) is using your microphone", "Start recording this meeting?". The app's name is read at runtime, and only when one app is known to be using the microphone; otherwise "Microphone in use", "Silvanus", "Start a recording?", and Start recording. No calendar line yet.
- Buttons: 40 tall, corner 8, 13 inside. Record meeting: `barEdge` fill, `barGround` text (`promptButton`). Not now: outlined in `barTextSecondary`, `barText` text (`label`), `barRaised` on hover. Focus: a 2 pt `barEdge` ring 3 outside.
- Once per call, never during a recording, never focus-stealing, no countdown, never records on its own. Not now hides it for this call; the menu bar keeps Record Meeting until the call ends. It goes when the call ends or a recording starts.

### Notes canvas text

- Text starts at x 221 (12 after the canvas edge). On My notes the meeting header sits above the notes in the same scroll view, and the first line box starts at the header's bottom: 46 (canvas header) + 104.5 (`MeetingHeader.height`: the title's cap top 19, the title, 15.5 to the chip row, the 28 pt chips, then 20 to the body) = y 150.5, so the first cap top is at about y 158 (measured 157.7). Without the header (the editor alone) the first line box starts 11 below the canvas header, cap top 64.
- Body: `body` (16 / 24). Wrapped lines are 24 apart; list items are 28 apart (4 between items). Each line box centers its glyphs: TextKit sets the line half the extra shorter and adds the other half as line spacing (a baseline offset would center them too, but TextKit 2 takes it off the line's height, which put body lines 21.5 apart).
- Bullets: an 8 pt dot centered at x 229; the text starts at x 246 (25 in from the text start). Silvanus keeps the Markdown dash (faded, like every marker) and centers it at x 229, then widens the space after it so the item's text and its wrapped lines start at x 246.
- Heading spacing (Silvanus): 13.5 above an H3, 5.5 above an H2, 8 above an H1 (no measure), and 3 below every heading. Markers stay visible: an H3's "### " sits at x 221 and pushes its words right of the reference's x 222.5.
- Headings, baseline to baseline (measured on a summary): title to H2 48.7; H2 to its first list item 29 to 30; last list line to the next H2 32. Paragraph to an H3 in notes: 58.5; H3 to its first item 28.
- Caret: 17 tall, `Ink.text`.
- Empty note placeholder: `body` in `textSecondary`, same position as the first line.

### Transcript view

- **Player strip**: x 221 to 897.5, y 52 to 93.5 (42 tall), fully rounded (corner 21), 1 pt `Ink.divider` border, no fill. 6 below the header.
- Play button: 28 × 28 at 5 inside the strip, corner 7, 1 pt `Ink.divider` border, play icon 9 wide.
- Time: `monoSmall` (11) in `Ink.textSecondary`, "00:00 / 00:55" style, starting 9 after the play button.
- Waveform: from 9 after the time to 14 before the strip's end; bars 2 wide, 3 apart, rounded; unplayed `Ink.divider`, played `Ink.accent` (gold, fill only), playhead a 2 pt `Ink.text` bar.
- **Speaker block**: indented 8 from the text start (x 229). Speaker label `label` (12) in `Ink.accentText` (**adapted** to medium weight in Silvanus so a midnight label still separates from midnight body text in light). Paragraph cap top 28.5 below the label's cap top. Paragraph `transcript` (14 / 22.75), `Ink.text`.
- Block to block: 40 from the last line's cap top to the next label's cap top (measured in light; the dark capture had an extra 26 from a blank line).
- **Timestamp** (ours): `monoSmall` in `textSecondary`, 8 after the speaker label on the same line. Click plays from there.
- **Low-confidence underline** (ours): a 1 pt dotted underline in `Ink.textSecondary`, 2 below the baseline, under each word whose confidence is below the threshold. Hover shows the confidence; click plays the word.

| State | Paragraph |
| --- | --- |
| rest | text |
| playing | the current word gets a selection fill, corner 3 |
| hover | selection at 50% behind the block, corner 8, inset −4 |
| focused | 2 pt focus ring around the block |

### Settings

Settings take over the main window, as a grouped list on the left and a pane on the right.

- List: 204 wide, `Ink.sidebar`, then a 1 pt divider at x 204. Back button (`chevron.left`) in the header at x 94.
- Search field: x 4 to 200, y 48 to 80 (32 tall), corner 6, 1 pt `Ink.divider` border, fill `refSearchField` (Silvanus: `Ink.canvas`). Placeholder `rowTitle` in `textSecondary`, icon at x 16.5.
- Group label: `section` (12, uppercase) in `textSecondary` at x 16.5, cap top 92.5 for the first group.
- List row: pill 36 tall, inset 4, corner 8, pitch 38 (2 between pills). Icon 14 at x 16.5, label `rowTitle` at x 39.5, optional trailing glyph 14 at 15.5 from the edge.

| State | Fill | Label |
| --- | --- | --- |
| rest | none | text |
| hover | selection | text |
| selected | `refSettingsSelected` / Silvanus selection | text, medium |
| focused | 2 pt focus ring | text |
| disabled | none | text at 40% |

- Pane: `Ink.canvas`, content at x 229 (24 after the divider). Page title `title` (24 bold, system font, not a script face), baseline at y 55. **Adapted**: the reference's script title spans y 30.5 to 55.5; the system title keeps its bottom edge.
- Setting row: title `settingTitle` (14 medium), description `label` (12) in `textSecondary` 22.5 below (cap top to cap top). Rows repeat every 56. Trailing control right-aligned 24 from the window edge.
- Switch: 44 × 24, fully rounded, knob 20. Off: fill `Ink.sidebar`, 1 pt `Ink.divider` border, knob `Ink.canvas`. On: fill `Ink.primaryControl`, knob `Ink.onPrimary`. Focused: 2 pt focus ring. Disabled: 40%.
- Bordered button: 36 tall, corner 6, 1 pt `Ink.divider` border, fill `Ink.sidebar`, label `button` (14 medium), padding 16.
- Section heading: `subheading` (18 semibold).
- **Adapted** (as built): there's no search field yet, so the first group label sits right under the header, and the list column keeps the window's 208 pt sidebar width rather than 204. The panes are General, Appearance, About (group "App") and Transcription (group "AI"). Switch hover and pressed are ours: off gets a `textSecondary` border, on gets 90% and 80% fill. A bordered button chosen in a group (Theme: System, Light, Dark) is `primaryControl` with an `onPrimary` label. Escape and the back button return to the meeting.

### Empty states

- **No meetings** (sidebar): no day heading; one line in `rowTitle`, `textSecondary`, at x 16.5, cap top at the day heading's y 84: "No meetings yet". Under it, the Record button's label as a hint in `meta`.
- **No note selected** (canvas): centered in the canvas, `subheading` in `Ink.text` ("Pick a meeting or start one"), then 12 below a Record button (primary: `Ink.primaryControl` fill, `Ink.onPrimary` label).
- **Empty note**: the canvas placeholder line (see Notes canvas text).
- **No transcript**: the player strip is hidden; one line of `label` in `textSecondary` at the player strip's y: "No recording for this meeting".
- **Nothing coming up**: the Coming up card's empty row.
- **Empty folder**: the meeting list area shows `rowTitle` in `textSecondary`, "No meetings in this folder".

The empty-state words and their placement are ours; the sizes and colors come from the tokens above.

## Compare

The reference-main snapshot page (`APP_COLORS=reference APP_SNAPSHOT_PAGES=reference-main tools/snap.sh`) lays fictional meetings out like the main reference capture: 910 × 600, seven rows under Yesterday (the first and sixth with a folder line, the fifth truncated, the sixth open), and on the canvas a paragraph, an empty line, an H3, a wrapping bullet, a bullet, and an empty bullet, without the meeting header and without the Folders section. The words are ours, picked to be about as long as the reference's. `tools/compare.sh <reference prefix>` takes the snapshot and runs the design-from-app compare in light and dark, on the whole window and with these parts painted over in both images:

| Mask (x, y, w, h) | Why it's left out |
| --- | --- |
| 255, 8, 135, 30 | The view pill's selected segment and labels: ours are Summary, My notes, and Transcript (docs/GLOSSARY.md), so the segment is wider. The track's start and the first tab still count. |
| 690, 8, 188, 30 | The header's trailing controls: Silvanus has the Quick Note mic and Start Recording where the reference has a folder chip and a share button. The More dots still count. |
| 236, 544, 647, 52 | The reference's floating bottom bar. Silvanus has none. |

The snapshot runs with `-AppleFontSmoothing 0`, because the reference draws text without font smoothing: with it on, the same word drew about a sixth more ink. With it off, the day heading ("Yesterday" in both) differs by no pixels at all.

Results (2026-11-06), percent of unmasked pixels that differ:

| | Light | Dark |
| --- | --- | --- |
| Before (first build of the page) | 4.35% (whole window 4.28%) | 4.44% (whole window 4.36%) |
| After the token fixes | 3.03% (whole window 3.06%) | 2.89% (whole window 2.92%) |
| Same check with the reference's own words, local only | 1.60% (whole window 1.75%) | 1.46% (whole window 1.61%) |

Rows and left edges are within 0.5 pt of the reference, measured with `rows` and `cols`: the rule, day heading, every row's folder line, title, and time, the pills, the divider, the canvas paragraph, heading, bullet lines, and the bullet text edge at x 246. The bullet's dash centers at x 229 like the reference's dot. What's left in the 2.9 to 3.0% is the words themselves: ours differ from the reference's, so their ink lands on different pixels. The gate of 2% isn't met with our own words; with the reference's words (a measurement only, never committed) the window is under 2% in both modes, so the tokens hold.

