# Built-In Player

TangoDisplay includes a native audio player that lets you manage and play your milonga setlist directly — no Music.app, Swinsian, or Embrace required. All display automation (cortina detection, tanda counting, coming-up preview, album artwork) works fully with the built-in player.

> **Screenshot placeholder:** feature banner — full setlist view with tracks loaded

---

## Enabling the Built-in Player

1. Click the display icon in the menu bar › **Show Settings Window**
2. Go to **Player** in the sidebar
3. Under **Player Source**, select **Built-in Player**
4. Switch to the **Setlist** tab to build your setlist

Once the built-in player is active, you can jump straight to the Setlist tab at any time from the menu bar: click the display icon › **Show Setlist**.

> **Screenshot placeholder:** Player Settings view with Built-in Player selected

---

## The Setlist Tab

The Setlist tab is the main workspace for the built-in player. It shows your full track queue, player controls at the top, and setlist statistics at the bottom.

### Adding Tracks

Drag tracks directly from:

- **Music.app** — drag from the track list or search results
- **Swinsian** — drag from the browser
- **Finder** — drag audio files from anywhere on your filesystem

Drop onto the track list or into the empty drop zone when the list is empty. Tracks are added with full metadata read from the audio file itself — they do not need to be in any library.

To insert mid-list, drag onto a specific row to place the new track before it rather than appending to the bottom.

**Supported formats:** MP3, M4A (AAC), AIFF, WAV, FLAC, CAF, Opus.

#### Duplicate Track Protection

When **Duplicate track protection** is enabled in **Player Settings**, dropping a track that is already in the setlist (played or unplayed) shows an alert:

> *This track already exists in this set. Add anyway?*

- **Add** — adds the duplicate.
- **Don't Add** — skips it.
- **Remember for this session** — check this before clicking either button to lock in your choice. Subsequent duplicates are then added or skipped silently for the rest of the session. The remembered choice is cleared when you click **Clear Setlist**.

Non-duplicate tracks in the same drag operation are always added immediately, regardless of this setting.

> **Screenshot placeholder:** setlist view with several tracks showing mixed state (queued, playing, played)

### Track Rows

Each row shows:

| Element | Details |
|---|---|
| State icon | Waveform = playing · Pause = paused/armed · Checkmark = played · Play = next up |
| Title & Artist | Extracted from the audio file's tags |
| Genre tag | Colour-coded: green = playing, orange = paused, blue = next to play, grey = queued/played. Custom colours can be assigned to upcoming tracks by genre keyword (see Genre Colours below). |
| Year | Optional — toggle in Player Settings |
| Duration | Optional — toggle in Player Settings |
| Comments / Album Artist | Optional — toggle in Player Settings |
| Stop marker | Small stop icon when "Stop After This Track" is set |
| Auto-gap icon | Filled green wave = auto-gap silence applied before this track · Outlined grey wave = skipped or ignored |
| Last Tanda flag | Red flag icon = this cortina is marked as the last tanda and will activate the Last Tanda label when it plays |
| Progress bar | Appears beneath the currently-playing row: shows elapsed position, remaining time, the mark-as-played threshold marker, and the auto-fade marker (for cortinas when Auto-fade is enabled) |

The setlist persists across app restarts — it is saved automatically to Application Support.

---

## Player Controls

The player controls sit above the track list.

> **Screenshot placeholder:** player controls area showing level meter, transport, seek bar, fade buttons, volume, eye button, and artwork

The controls are arranged in three columns with a volume row below:

- **Level meter** — dual-channel (L/R) bar graph on the left side of the controls panel. Gradient bars show real-time RMS level from green (quiet) through yellow to red (loud). White peak-hold markers latch for 2 seconds then decay; they turn red when clipping is detected. Tap the meter to reset clip indicators. A dB scale (-0, -3, -6, -12, -24) runs alongside.
- **Eye button** — scrolls the track list to highlight the currently playing track
- **Track info** — title and artist of the current track
- **Transport button** — large central play/stop button (see states below)
- **Fade buttons** — Fade & Stop and Fade & Continue (see below)
- **Volume slider** — master volume for the built-in player (0–100%)
- **Artwork panel** — current track artwork, sized to match the height of the controls column. Falls back to the SetlistLogo placeholder when no artwork is embedded in the file.

### Transport Button States

| Colour | State | Click to… |
|---|---|---|
| Green (play icon) | Stopped / ready | Start playback |
| Accent (waveform) | Playing | Arm stop |
| Orange (pause icon) | Armed — stop pending | Confirm stop |
| Red (stop icon) | Stopped after confirm | Resume or start next |

### Accidental Stop Protection

Stopping playback requires two deliberate clicks to prevent mis-clicks mid-tanda:

1. **First click** while playing → button turns orange, entering an "armed" state for approximately 3 seconds
2. **Second click** within that window → playback stops
3. **No second click** → the armed state expires and playback continues uninterrupted

This means a single accidental tap on the transport never kills the music.

### Fade Buttons (Cortina Controls)

The two fade buttons are enabled only when the currently playing track is a recognised cortina — they are never active on dance tracks. Use them when you want to end a cortina early rather than letting it play to its natural finish:

| Button | What it does |
|---|---|
| **Fade & Stop** | Smoothly fades the cortina volume to zero over the configured duration, then stops. |
| **Fade & Continue** | Smoothly fades the cortina volume to zero, then immediately advances to the next track and restores volume. |

Both buttons are disabled while a fade is already in progress. The fade uses an exponential curve for a natural, professional sound.

Configure the fade duration in **Player Settings › Cortina fade** (1–15 seconds).

When **Auto-fade all cortinas** is enabled, the fade buttons are automatically disabled while a cortina is playing — the auto-fade will handle the transition at the configured time. Right-click the cortina in the setlist and select **Skip Auto-fade** to re-enable manual control for that track.

---

## Managing Your Setlist

### Re-ordering Tracks

Drag rows up or down to reorder. Tracks that have already been played are locked in place and cannot be moved — only queued (unplayed) and paused tracks are draggable. This prevents accidentally scrambling your played history.

### Context Menu Actions

Right-click any row:

| Action | What it does |
|---|---|
| **Mark as Played** | Stamps a queued track as played without playing it |
| **Mark as Not Played** | Resets a played track to queued so it will play again |
| **Stop after Playing** | Sets a stop marker — playback halts automatically when this track finishes. Shows as **Resume after Playing** when already set; click again to clear it. |
| **Delete** | Removes the track from the setlist (asks for confirmation) |
| **Ignore Auto-gap before this Track** | Disables auto-gap for this track only. Shows as **Resume Auto-gap** when already set; click again to re-enable it. |
| **Skip Auto-fade** | Disables auto-fade for this cortina track only, re-enabling the Fade & Stop and Fade & Continue buttons for manual control. Available only when Auto-fade is enabled and fading has not yet started. |
| **Mark as Last Tanda** | Marks this cortina as the last tanda. TangoDisplay will automatically activate the Last Tanda label when this cortina starts and deactivate it when the next cortina begins. A red flag appears on the row. Shows as **Remove Last Tanda** when already set. Available only on cortina tracks. Requires Last Tanda label text to be configured in Appearance Settings. |

> **Screenshot placeholder:** right-click context menu on a setlist row

**Bulk mark:** ⌘-click or Shift-click to select multiple rows, then right-click to apply **Mark as Played** or **Mark as Not Played** to all selected tracks at once.

### Stop After Playing

When **Stop after Playing** is set on a row, a small stop icon appears in that row and playback halts automatically when that track completes. Right-click the same row again and select **Resume after Playing** to clear the marker. Only one stop marker can be active at a time.

### Clearing the Setlist

Click the **Clear Setlist** button in the toolbar. This removes all tracks and resets all playback state.

---

## Setlist Footer

A status bar at the bottom of the track list shows:

> **Screenshot placeholder:** setlist footer showing total duration and estimated end time

- **Total duration & remaining count** — the combined length of all tracks followed by the number of unplayed tracks (e.g. "1h 42m · 28 remaining")
- **Next cortina** — a live countdown showing how much time remains before the next cortina begins, based on the current elapsed position and queued track durations. Shows "0s" when a cortina is already playing.
- **Estimated end time** — a projected clock time when the setlist will finish, calculated from the current elapsed position, all remaining queued tracks, and any stop-after marker (e.g. "Ends ~23:45")
- **Auto-gap status** — when auto-gap is enabled, a small green dot and the live gap duration (e.g. "Auto-gap: 2.0s") appear. The dot turns grey and the label reads "Auto-gap: off" when the feature is disabled. The duration updates in real time as you adjust the slider.
- **Auto-fade status** — when auto-fade is enabled, a small orange dot and "Auto-fade: on" label appear alongside the auto-gap indicator. The dot turns grey and the label reads "Auto-fade: off" when the feature is disabled.

---

## Auto-Gap

Auto-gap analyses the silence at track boundaries and schedules a silent preroll buffer before each track so the gap between songs always meets your target minimum — useful for tango DJs who want consistent, perceptible separations between tandas without adding unnecessary dead air.

> **How it works:** TangoDisplay reads the audio waveform at the end of the finishing track and the start of the incoming track, measures the existing silence, then prepends exactly as much extra silence as needed. Only silence is ever added — it never shortens a gap. If the existing silence already meets the minimum, a 1-second buffer is still inserted so the separation is always audible.

### Enabling Auto-Gap

1. Go to **Settings › Player**
2. Under **Built-in Player**, enable the **Auto-gap** toggle
3. Use the **Minimum gap** slider to set your target (0.5–5 s; default 4 s)

### Skip Gap Before First Track

When **Skip gap before first track** is enabled (the default), the opening track of the setlist starts immediately with no silence preroll — the gap only applies between consecutive tracks. Disable this if you want the same treatment from the very first song.

### Per-Track Override

Right-click any queued track row and select **Ignore Auto-gap before this Track** to exempt that individual track. The option becomes **Resume Auto-gap** when already set; click it again to re-enable. This lets you keep auto-gap active globally while skipping it for specific tracks (e.g. a track you want to follow immediately after its predecessor).

### Reading the Indicators

Three places in the UI reflect auto-gap state:

| Indicator | What it means |
|---|---|
| **Setlist footer dot** | Green dot + "Auto-gap: 4.0s" (live duration) = feature active. Grey dot + "Auto-gap: off" = feature disabled. |
| **Timer toolbar button** | Opens the Auto-gap popover for instant duration changes. Disabled when auto-gap is off. |
| **Filled green wave icon** on a track row | Auto-gap silence was successfully scheduled before this track |
| **Outlined grey wave icon** on a track row | Auto-gap was skipped or ignored for this track (first track with "Skip gap before first track" on, or per-track override active) |
| *(no icon)* | Auto-gap not applicable to this track |

---

## Auto-Fade Cortinas

Auto-fade automatically fades out a cortina and advances to the next track after a configurable play time — useful when you want cortinas to end cleanly without manual intervention.

### Enabling Auto-Fade

1. Go to **Settings › Player**
2. Under **Built-in Player**, enable the **Auto-fade all cortinas** toggle
3. Use the **Cortina play time** slider to set how many seconds of the cortina should play before the fade begins (5–120 s; default 30 s)

When a cortina starts, an orange marker appears on the in-row progress bar to show exactly when the fade will trigger.

> **Short cortinas:** If a cortina is shorter than the play time plus the fade duration, TangoDisplay adjusts automatically — the fade starts early enough to complete before the track ends.

### Fade Buttons and Auto-Fade

When auto-fade is enabled for a cortina, the **Fade & Stop** and **Fade & Continue** buttons in the player controls are disabled — the auto-fade will handle the transition at the right moment. Once the fade begins, it cannot be interrupted.

### Per-Track Override

Right-click any cortina row in the setlist and select **Skip Auto-fade** to disable auto-fade for that track only. The orange progress-bar marker disappears and the fade buttons become active for manual control. The option is hidden once the fade has already started.

### Reading the Indicators

| Indicator | What it means |
|---|---|
| **Orange marker on progress bar** | The point at which auto-fade will begin for the current cortina (visible in the in-row progress bar beneath the playing track) |
| **Setlist footer orange dot** | Orange dot + "Auto-fade: on" = feature active. Grey dot + "Auto-fade: off" = feature disabled. |
| **Fade buttons (disabled)** | Auto-fade is scheduled — the transition will happen automatically |

---

## Last Tanda

Pre-schedule which cortina is the last tanda of your milonga. When that cortina plays, TangoDisplay automatically activates the Last Tanda label on the dancer display — no manual intervention needed mid-set.

### Marking a Cortina

Right-click any cortina row in the setlist and select **Mark as Last Tanda**. A red flag icon appears on the row to confirm. Only one cortina can be marked at a time — marking a new one automatically clears any previous marker.

> If no Last Tanda label text is configured in **Appearance Settings › Last Tanda**, a warning is shown instead of marking the cortina. Configure the label text first.

### How Activation Works

| Moment | What happens |
|---|---|
| Marked cortina starts playing | Last Tanda label activates automatically |
| During dance tracks in the tanda | Label remains visible on every track |
| Next cortina starts | Label deactivates automatically |

### Live Override

The **Last Tanda** toggle on the **Live** screen always takes priority. You can turn it off at any time — the label clears immediately and remains off for the rest of the current tanda, even as new tracks play.

### Removing the Marker

Right-click the marked cortina row and select **Remove Last Tanda**. The flag icon disappears.

---

## Stereo Balance

Click the **Balance** button (dial icon) in the Setlist toolbar to open the balance popover.

- Drag the slider left to shift audio towards the left channel, or right to shift it towards the right.
- The readout above the slider shows **Centre**, **L N%**, or **R N%** depending on the current position.
- Click **Centre** to snap back to balanced (0).

The balance setting persists across app restarts. The Balance button is disabled when the built-in player is not active.

---

## Auto-Gap Quick Access

When auto-gap is enabled, a **timer icon button** appears in the Setlist toolbar alongside EQ and Balance. Click it to open a popover with a duration slider — the same 0.5–5 s range as the full Settings panel, but reachable in one click during a performance.

The button is **disabled** when auto-gap is off (enable it first in **Settings › Player › Auto-gap**).

### Changing the gap mid-performance

You can adjust the duration while a track is playing. The new value takes effect for the very next gap: the gap duration is read at the moment the current track ends, so any change you make during playback applies to the upcoming silence preroll. The setlist footer updates to reflect the new value in real time.

> **Example:** Global gap is 4 s. While Track A plays, open the popover and drag to 2 s. The gap before Track B will be 2 s. Drag back to 4 s before Track C ends and subsequent gaps return to 4 s.

---

## Exporting the Setlist

Click the **Share** button (↑ icon) in the Setlist toolbar to open the export menu. The button is disabled when the setlist is empty.

### Export to Apple Music

Creates a new Apple Music playlist containing all tracks in the current setlist. The playlist is named with the current date and time.

> **Note:** Export to Apple Music requires the **Automation › Music** permission. macOS will prompt for this on first use.

### Export to M3U8…

Opens a Save dialog and writes a standard M3U8 playlist file. Each track is written as an `#EXTINF:` line (with duration and `Artist — Title` metadata) followed by the absolute file path. The default filename is `Tango Display SetList DDMMYY HH:MM.m3u8`.

Use this to import your milonga setlist into any M3U-compatible player or DJ software.

---

## 5-Band Equaliser

Click the **Equaliser** button in the toolbar to open the EQ popover.

> **Screenshot placeholder:** EQ popover with five vertical sliders

| Band | Frequency | Type |
|---|---|---|
| Band 1 | 60 Hz | Low shelf |
| Band 2 | 250 Hz | Peaking |
| Band 3 | 1 kHz | Peaking |
| Band 4 | 4 kHz | Peaking |
| Band 5 | 12 kHz | High shelf |

Each band has a vertical slider with a **±12 dB** range. The current gain is shown above each slider.

Click **Flat** to reset all bands to 0 dB in one click.

EQ settings are saved across sessions.

---

## ReplayGain

ReplayGain adjusts playback volume using loudness metadata so every track sounds equally loud without manual volume tweaking. Click the **ReplayGain** button (waveform icon) in the Setlist toolbar to open the quick-access popover, or go to **Settings › Player › ReplayGain** for the same controls alongside the rest of the player settings.

The ReplayGain button is **never disabled** — you can always reach it to change the mode, even when playback is stopped or mode is currently Off.

### Modes

| Mode | How it works |
|---|---|
| **Off** | No gain adjustment is applied. |
| **Track** | Reads the `REPLAYGAIN_TRACK_GAIN` tag embedded in the audio file and applies it directly. |
| **Album** | Reads the `REPLAYGAIN_ALBUM_GAIN` tag instead, preserving the relative volume between tracks in an album. |
| **Auto** *(Recommended)* | Uses embedded ReplayGain tags when present. When a track has no tags, TangoDisplay analyses the audio and calculates the gain needed to reach the **Target Loudness** setting. Analysis runs in the background; a live status line in the player controls shows progress ("Analysing…") and the result once complete (e.g. "Auto +2.3 dB · −18.0 LUFS"). |

### Controls

**Prevent clipping** — when enabled, the calculated gain is capped so the output never exceeds 0 dBFS, regardless of the Preamp setting. On by default.

**Preamp** — a global gain offset applied on top of the ReplayGain value (−12 to +6 dB). Use this to raise or lower the overall volume without touching individual track tags.

**Target Loudness** — the loudness target used when analysing tracks in Auto mode (−23 to −14 LUFS). Only active when mode is set to **Auto**. Default: −18.0 LUFS.

### Live Status Line

While a track is playing with ReplayGain active, a status line appears below the artist name in the player controls showing the active gain adjustment and mode. For example:

- `Auto +2.3 dB · −18.0 LUFS` — gain calculated from analysis
- `Track −1.5 dB` — gain read from embedded tag

The line clears when playback stops or ReplayGain is set to Off.

### Analysis Cache

Loudness analysis results are cached on disk so each file is only analysed once. Subsequent plays of the same file load instantly from the cache.

---

## Audio Unit Plugin (Beta)

The built-in player can host an Apple Audio Unit effect plugin directly in the audio chain — useful for applying EQ curves, dynamics processing, or filtering to improve the clarity of older recordings without modifying the source files.

> **Beta feature:** Test your plugin at home before using it live. If the plugin fails to load, playback continues unaffected.

### Enabling the Plugin

1. Go to **Settings › Player**
2. In the **Audio Unit Plugin** section, enable the **Enable Audio Unit Plugin** toggle
3. Click **Choose…** to open the plugin picker
4. Select a plugin — it loads immediately into the audio chain

### Supported Plugins

The plugin picker shows only plugins suited to audio restoration work:

| Plugin | Purpose |
|---|---|
| AUNBandEQ | N-band parametric EQ |
| AUGraphicEQ | Graphic EQ |
| AUDynamicsProcessor | Dynamics processing |
| AUMultibandCompressor | Multi-band compression |
| AUPeakLimiter | Peak limiting |
| AUHighShelfFilter | High shelf filter |
| AULowShelfFilter | Low shelf filter |
| AUHipass | High-pass filter |
| AULowpass | Low-pass filter |

### Controls

| Control | What it does |
|---|---|
| **Enable Audio Unit Plugin** | Inserts or removes the plugin from the audio chain |
| **Choose…** | Opens the plugin picker to select a different plugin |
| **Bypass** | Temporarily bypasses the plugin without unloading it |
| **Open Plugin Window** | Opens the plugin's native editor UI |
| **Remove** | Removes the selected plugin entirely |

### Audio Chain

The plugin occupies a single slot in the audio chain — only one plugin can be active at a time:

```
┌─────────────┐    ┌──────────────┐    ┌───────────────────────────┐    ┌───────────┐
│  Audio File │───▶│  ReplayGain  │───▶│  AU Plugin  ← single slot │───▶│  Output   │
│  (decoder)  │    │  (optional)  │    │  (optional, bypassable)   │    │  Device   │
└─────────────┘    └──────────────┘    └───────────────────────────┘    └───────────┘
```

To swap plugins, click **Choose…** again — the previous plugin is unloaded and replaced.

### Setlist Toolbar Quick Access

When a plugin is selected, a **puzzle piece button** appears in the Setlist toolbar next to the ReplayGain button. Click it to open the plugin window directly without navigating to Settings. The button is disabled when the plugin is turned off or bypassed.

---

## Audio Output

By default the built-in player uses the macOS system default output device. To route audio to a specific device (e.g. a dedicated DJ audio interface):

1. Go to **Player** in the Settings sidebar
2. Under **Built-in Player**, open the **Main output** picker
3. Select your device

The list shows all currently available audio output devices. If the selected device is disconnected, playback falls back to the system default automatically.

---

## Integration with the Display

When the built-in player is active, the dancer display responds exactly as it does with Music.app:

- **Cortina detection** — your [Cortina Rules](Cortina-Rules) apply to every setlist track. A track whose genre matches a cortina rule triggers cortina mode on the display automatically.
- **Tanda counting** — TangoDisplay counts consecutive non-cortina tracks to determine tanda position (e.g. "Track 2 of 4").
- **Coming-Up preview** — during a cortina, the next tanda's first dance track is shown as the "Coming Up" track on the display.
- **Album artwork** — extracted from the audio file and shown on the dancer display (if artwork display is enabled in Appearance settings).

No additional configuration is needed — the display sync is fully automatic.

---

## Player Settings Reference

Go to **Player** in the Settings sidebar.

> **Screenshot placeholder:** Player Settings view showing all sections

### Player Source

Choose which player TangoDisplay listens to:

| Source | How it works |
|---|---|
| **Music.app** | Polls via AppleScript every 2 seconds. Full tanda counting and playlist look-ahead. |
| **Swinsian** | Real-time push notifications. Tanda position shown; total track count unavailable. |
| **Embrace** | Real-time notifications + AppleScript polling. Full tanda counting. |
| **Built-in Player** | TangoDisplay plays audio directly. Build your setlist in the Setlist tab. |

### Built-in Player Settings

These options appear only when **Built-in Player** is selected.

**Main output** — the audio device to use for playback. Defaults to the macOS system output.

**Cortina fade** — duration of the volume fade used by Fade & Stop and Fade & Continue (1–15 seconds, in 0.5-second steps). Default: 5 seconds.

**Duplicate track protection** — when enabled, dropping a track that already exists in the setlist shows a confirmation alert before adding it. Includes a **Remember for this session** checkbox that silences the prompt for the rest of the session (until the setlist is cleared). Off by default.

**Auto-gap** — when enabled, TangoDisplay analyses silence at track boundaries and pads each transition with a silent preroll so the gap always meets the minimum. Only silence is added — existing gaps are never shortened.

**Minimum gap** — the target gap duration in seconds (0.5–5 s, in 0.5-second steps). Default: 4 seconds. Visible only when Auto-gap is enabled.

**Skip gap before first track** — when on (default), the first track in the setlist starts immediately with no silence preroll. The gap applies only between consecutive tracks.

**Auto-fade all cortinas** — when enabled, TangoDisplay automatically fades out cortinas and advances to the next track at the configured play time. Requires cortina detection to be set up via Cortina Rules.

**Cortina play time** — how many seconds of a cortina should play before the auto-fade begins (5–120 s, in 1-second steps). Default: 30 seconds. Visible only when Auto-fade is enabled. For cortinas shorter than play time + fade duration, the fade starts earlier so it always completes cleanly.

**Mark as played** — controls when a track receives its played stamp:

| Option | Behaviour |
|---|---|
| **After song ends** | The track is marked only when it plays all the way to completion |
| **After…** | The track is marked after a set number of seconds of playback (1–30 seconds). A marker line on the seek bar shows the threshold. Once marked, pressing play again skips to the next queued track. |

### ReplayGain Settings

**ReplayGain mode** — Off, Track, Album, or Auto (recommended). Auto uses embedded tags when present and analyses the file against the target loudness when absent.

**Prevent clipping** — caps the output at 0 dBFS. Active for Track, Album, and Auto modes.

**Preamp** — global gain offset on top of ReplayGain (−12 to +6 dB). Active for Track, Album, and Auto modes.

**Target Loudness** — the LUFS target used when Auto mode analyses a file (−23 to −14 LUFS). Active in Auto mode only.

### Track Info

Toggles for which fields appear in setlist rows (visible only with Built-in Player selected):

| Field | Default | Notes |
|---|---|---|
| Title | Always on | Cannot be hidden |
| Artist | Always on | Cannot be hidden |
| Genre | Always on | Cannot be hidden |
| Year | On | |
| Time | On | Shows duration and current position |
| Comments | Off | |
| Album Artist | Off | |

### Genre Colours

Assign custom colours to genre tags for upcoming (unplayed) tracks — giving a clear visual map of the tanda structure ahead.

**Enable/disable:** Toggle **Genre tag colours** in **Settings › Player › Genre Colours**.

**Adding a rule:**

1. Type a keyword in the text field (e.g. `tango`)
2. Pick a colour with the colour picker
3. Click **Add**

Keywords are case-insensitive and match anywhere in the genre name — `tango` matches `Tango`, `Argentine Tango`, `Tango Nuevo`, etc.

**Colour priority:**

| Track state | Genre tag colour |
|---|---|
| Playing | Green (always) |
| Paused (armed) | Orange (always) |
| Next to play | Accent blue (always) |
| Already played | Grey (always) |
| Upcoming / queued — keyword match | Your custom colour |
| Upcoming / queued — no match | Grey |

Custom colours apply only to tracks that have not yet been played and are not currently playing — the tanda structure is visible at a glance without interfering with standard playback indicators.

To remove a custom colour, click the **trash** icon next to the rule. The genre tag reverts to standard grey for upcoming tracks.

### Track Info Transformations

The **Advanced** tab in Settings lets you apply optional regex-based rules to reformat how Artist, Title, Year, Album Artist, and Comments are displayed on the dancer screen — without modifying the original music tags. See [Advanced Settings](Advanced-Settings) for full details and examples.
