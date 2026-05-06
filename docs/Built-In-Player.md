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
| Genre tag | Colour-coded: green = playing, orange = paused, blue = next to play, grey = queued/played |
| Year | Optional — toggle in Player Settings |
| Duration | Optional — toggle in Player Settings |
| Comments / Album Artist | Optional — toggle in Player Settings |
| Stop marker | Small stop icon when "Stop After This Track" is set |

The setlist persists across app restarts — it is saved automatically to Application Support.

---

## Player Controls

The player controls sit above the track list.

> **Screenshot placeholder:** player controls area showing transport, seek bar, fade buttons, volume, eye button, and artwork

Working left to right:

- **Eye button** — scrolls the track list to highlight the currently playing track
- **Track info** — title and artist of the current track
- **Seek bar** — drag to jump to any position in the track. When "After…" mark-as-played timing is active, a small vertical marker line shows the threshold position
- **Time display** — elapsed and remaining time
- **Volume slider** — master volume for the built-in player (0–100%)
- **Transport button** — large central play/stop button (see states below)
- **Fade buttons** — Fade & Stop and Fade & Continue (see below)
- **Album artwork** — extracted from the audio file, shown top-right (70×70, rounded)

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

- **Total duration** — the combined length of all remaining unplayed tracks
- **Estimated end time** — a projected clock time when the setlist will finish, calculated from the current elapsed position, all remaining queued tracks, and any stop-after marker (e.g. "Ends ~23:45")

---

## Export to Apple Music

Click **Export to Apple Music** in the toolbar to create a new Apple Music playlist containing all tracks in the current setlist. The playlist is named with the current date and time.

> **Note:** Export to Apple Music requires the **Automation › Music** permission. macOS will prompt for this on first use.

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

**Mark as played** — controls when a track receives its played stamp:

| Option | Behaviour |
|---|---|
| **After song ends** | The track is marked only when it plays all the way to completion |
| **After…** | The track is marked after a set number of seconds of playback (1–30 seconds). A marker line on the seek bar shows the threshold. Once marked, pressing play again skips to the next queued track. |

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
