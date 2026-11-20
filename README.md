# mtts

**mtts** (mouth to text) is a macOS prototype that tests whether the head-tracking motion sensor in **Powerbeats Pro 2** can turn **silently mouthed words into text**. It also lets you control your Mac with head gestures: turn your head to switch tabs, or click with a motion you train yourself.

When you mouth a word, your jaw moves, and the jaw joint sits right in front of the ear canal. So the earbuds move a tiny amount. mtts reads that motion through `CMHeadphoneMotionManager`, learns what each of your words looks like, and matches new ones against them. There's no language model: it's a small-vocabulary template matcher plus a statistical test that tells you whether the signal is real.

## Headphones

Built and tuned for **Powerbeats Pro 2** (model A3157, A3158 or A3160). It works with any headphones that have spatial-audio head tracking. Pick between them from the device menu at the top of the sidebar.

| Works (head tracking) | Doesn't (no head-tracking sensor) |
|---|---|
| Powerbeats Pro 2, Powerbeats Fit, Beats Fit Pro, Beats Studio Pro, Beats Solo 4 | Powerbeats Pro (2019), Beats Studio Buds / Buds+, Beats Solo Buds, Solo Pro, Flex |
| AirPods Pro / Pro 2 / Pro 3, AirPods 4, AirPods (3rd gen), AirPods Max / Max 2 | AirPods (1st and 2nd gen) |

iOS and macOS call both Powerbeats generations "Powerbeats Pro". mtts reads the Bluetooth product ID to tell them apart (`0x201D` is Powerbeats Pro 2). Apple doesn't publish a supported-models list for the motion API. The table follows each model's head-tracking support, and the Live screen shows whether motion is actually streaming.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools: `xcode-select --install`. Xcode itself isn't needed.
- No third-party dependencies

## Build & run

```sh
git clone https://github.com/ryunzz/mtts.git
cd mtts
scripts/build-app.sh          # builds and ad-hoc signs build/mtts.app
open build/mtts.app
scripts/test.sh               # unit tests (Swift Testing)
```

On first launch:
1. Pair your Powerbeats Pro 2 with the Mac.
2. Choose them as the sound output from the sidebar device menu or Control Center.
3. Click **Allow** for Motion. The microphone and speech prompts appear only if you start the mic.

The app is ad-hoc signed, so macOS treats each rebuild as a new app and asks for Motion permission again. To keep the grant across rebuilds, sign with your own identity: `SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh`.

To run it on another Mac, either clone and build there, or copy `build/mtts.app` across (Apple silicon only). It isn't notarized, so the first time macOS blocks it: go to System Settings › Privacy & Security and click **Open Anyway**.

## Choosing headphones

Head motion always comes from whichever headphones are the Mac's **sound output**; the motion API has no device picker of its own. The sidebar's device menu:

- lists every output with its detected model, and marks models without head tracking. Choosing one makes it the Mac's output.
- shows paired headphones that aren't connected.
- has **Treat As**, which pins the model by hand when automatic detection doesn't recognize it.

Training takes are stored per headphone model. Takes recorded with AirPods are never matched against your Powerbeats, and the other way around.

## Screens

| Screen | What it does |
|---|---|
| **Live** | Everything the headphones send, as it arrives. A 3D head that mirrors yours (with **Recenter**), a gyroscope scope in °/s, an accelerometer scope in milli-g, and a trail of where you're looking. Above them: the model, firmware, battery (left, right, case), sample rate, jitter, latency, dropped samples and how long the stream has run. **Freeze** in the toolbar holds every plot still. The microphone input and session recorder sit at the bottom. |
| **Train** | Pick a word, hold **Space**, mouth it, release. Each take is stored as a template; aim for 10 per word. **Signal Check** runs leave-one-out classification and a 500× shuffled-label test, then shows accuracy against chance, a p-value and a confusion matrix. The channel checkboxes let you test which motion channels carry the signal. |
| **Decode** | Motion to text. Hold Space, or use auto-detect after calibrating the noise floor. Each segment is matched against your takes and added to the transcript. A live mic transcript runs alongside it for comparison. |

## Head gestures

Both gestures come from the same headphone motion stream (gyroscope, accelerometer and attitude). They send events to whatever app is in front, so macOS asks for **Accessibility** access the first time (System Settings › Privacy & Security › Accessibility).

- **Head Shortcuts** (Live screen): face forward and click **Recenter**, then turn your head past the trigger angle (25° by default). A left turn sends *previous* and a right turn sends *next*: tabs (⌃⇧⇥ / ⌃⇥), desktops (⌃← / ⌃→) or arrow keys for slides. Each turn fires once. Face center again (within 5°) to re-arm. Shortcuts pause while you're recording a take.
- **Gesture Click** (Live screen): record your own click motion on **Train › Gestures › Click gesture**, for example opening your mouth wide. Hold Space, do the motion, release, and repeat 5–8 times; at least 3 takes are needed. Back on Live, the match meter fills as the stream gets close to your takes. Turn the card on to left-click wherever the cursor is. Raise **Sensitivity** if it misses and lower it if it clicks by accident. Fast head turns are ignored, so looking around doesn't click.

## Before a demo

1. Put the Powerbeats in the way you'll wear them on stage. Re-seating shifts the signal.
2. On **Train**, record about 10 takes for each of 3–5 words. That takes roughly 5–10 minutes.
3. Run **Signal Check** and confirm p < 0.05.
4. On **Decode**, either use **Hold Space**, or pick **Auto-detect** and click **Calibrate Noise Floor** while holding still for 2 seconds.

## How decoding works

1. **Segmentation** (`CaptureController`): a Space-hold, or an energy trigger above a calibrated noise floor, with pre-roll and hangover.
2. **Features** (`MotionFeatures`): per frame, user acceleration (3), rotation rate (3) and attitude change since the segment started (3). Each channel is mean-centered, and quiet lead-in and lead-out frames are trimmed.
3. **Matching** (`DTW`, `TemplateClassifier`): channels are z-scaled across the training set. Matching is 1-nearest-neighbour per word using dynamic time warping with a Sakoe–Chiba band, so a word said faster or slower still matches. A segment is rejected if the best distance is above *max distance* or the margin to the runner-up is below *min confidence*.
4. **Is it real?** (`Evaluation`): leave-one-out accuracy is compared with the same procedure run on shuffled labels. If p < 0.05, the motion distinguishes your words better than chance.

Headphone detection (`HeadphoneDeviceMonitor`, `BluetoothInventory`, `HeadphoneModel`) works like this:
- It finds the current Core Audio output.
- It matches that output to its Bluetooth device by MAC address, using `system_profiler SPBluetoothDataType -json`.
- It looks up the model from the product ID.

A model is only used as the key for training takes once the Bluetooth lookup has confirmed it. A failed or early lookup therefore can't hide your takes.

## Experiment protocol

Click **Record Session** in the toolbar, or use the Live screen. Recordings go to `~/Documents/mtts/Sessions/<timestamp>-<condition>/`:

- `motion.csv`: every motion sample. `t` is seconds from session start.
- `audio.caf`: microphone audio, if the mic is running.
- `events.csv`: every Space-held segment, with its label or prediction.
- `meta.json`: condition, prompt, and the audio start offset for aligning audio with motion.

A useful comparison: the same 5-word script under **Normal speech**, **Whisper** and **Silent mouthing**, 10 reps each. Then compare Signal Check results across channel sets.

The training set is stored at `~/Library/Application Support/mtts/dataset.json`.

The app used to be called Beatvox. On first launch, mtts moves a Beatvox training set and headphone choices over. Older recordings stay in `~/Documents/Beatvox/Sessions`.

## Known limits

- Headphone motion is pre-processed and low-rate (about 25 Hz). The Powerbeats speech accelerometer and heart-rate sensor aren't exposed to apps, so this measures jaw and head movement, not vocal vibration.
- Takes are specific to one person, one session and one fit.
- Choosing the Powerbeats as the mic input switches them to the Bluetooth headset (HFP) profile.

## Credits

Based on [Subvox](https://github.com/joeblau/subvox) by Joe Blau (MIT), retargeted at Powerbeats Pro 2, with headphone detection and switching, per-device training sets, a redesigned interface, and a SwiftPM build that needs no Xcode.
