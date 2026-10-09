# Yamaha RM-TT

Group mute, per mic control and monitoring for Yamaha RM-TT tabletop microphones, from one plugin.
It talks to each mic directly over the RM Series remote control protocol (TCP 49280), one connection per mic.

Replaces the "Yamaha RM-TT" Text Controller user component, which did group mute only and had the mic
addresses typed into the script.

Written against Yamaha's "RM Series Remote Control Protocol Specifications" 3.0.0, which applies to RM-TT
firmware 3.0.0 and later.

## Install (no build needed)

Download `YamahaRMTT.qplug` from the latest entry on this repository's Releases page and put it in a
`Plugins\YamahaRMTT\` folder under the Q-SYS Designer folder your Designer uses. File > Preferences in Designer
shows which one that is: `Documents\QSC\Q-Sys Designer` by default, `OneDrive - Vivo Technologies\QSC\Q-Sys Designer`
on most Vivo laptops. Restart Q-SYS Designer; the plugin is listed under Plugins > User > Vivo.

## Properties

| Property | Range | What it changes |
|---|---|---|
| Number of Microphones | 1 to 16 | Rows on the Control and Setup pages, mic select buttons |
| Mic Mute Button | see below | What happens when someone presses the mute button on a mic |
| Audio Processing | Yes / No | Mic gain, echo cancellation, noise reduction, dereverberation, AGC, automix |
| Directivity | Yes / No | Pickup pattern, and on/off and angle for the four beams |
| Output Controls | Yes / No | Dante output faders, mutes, mute link, routing, output 2 processing |
| Output EQ | Yes / No | Six band EQ, on its own EQ page |
| LED Controls | Yes / No | Brightness, and the pattern and colors for muted and unmuted |
| Meters | Yes / No | AEC reference and output level meters for the selected mic |
| Clock Settings | Yes / No | Time zone, daylight saving and NTP on the Tools page |
| Command Line | Yes / No | A box to send any protocol command, and a List Parameters button |
| Heartbeat Seconds | 5 to 60 | How often an idle connection is kept alive |
| Identify Seconds | 1 to 60 | How long a mic flashes when Identify is pressed |

Mic Mute Button:

- **Mutes All Microphones**: pressing mute on any mic mutes or unmutes the whole group.
- **Mutes That Microphone**: only that mic changes, and Q-SYS follows it.
- **Overridden by Q-SYS**: the mic is put straight back to what Q-SYS last asked for.

## Setting up in a design

1. Setup page: type each mic's IP address. Model, firmware, serial number and unit ID fill in when it connects.
2. Control page: Mute All, Unmute All and the Muted toggle work on every mic; each row has its own mute.
3. Microphone, EQ and Tools pages work on one mic at a time. Pick it with the numbered buttons.
   Turn on Apply To All to send a change to every mic that is online.

## Mute behaviour

- The plugin holds the state each mic should be in and compares it with what the mic reports.
- A mute that is not confirmed is sent again every 2 seconds, 5 times, then the mic is marked as a fault.
- A mic that drops off the network and comes back is put back in the state the room was left in.
- Until something sets a mic's mute, the plugin takes the mic as it finds it.

## Connection

- Every Heartbeat Seconds the plugin asks each mic for its run mode, which the mic has to answer.
- A mic that has sent nothing for three heartbeats (30 seconds by default) is treated as gone: the connection is
  dropped and retried every 5 seconds. This is what catches a mic that loses power or its network port, because
  such a mic never closes the connection itself. Until then its Online LED stays on, so a lower Heartbeat Seconds
  means a faster Offline.
- A mute sent to a mic that has gone quiet is reported sooner, as Mute not confirmed, after the retries (10 seconds).

Status per mic: No IP address, Bad address, Offline, Starting (connected but not yet in normal run mode),
Updating firmware, Mute not confirmed, Alert, or OK. System Healthy is on only when no mic has a fault.

## What is covered

Everything the specification lists for the RM-TT:

| Area | How |
|---|---|
| System mute (`RM:MicMute/All`) | Control page |
| The other 27 parameters | Microphone and EQ pages, built from the `PARAMS` table |
| Level meters (`RM:AecRefPort`, `RM:OutputPort`) | Meters card |
| Device information, run mode, error status, alerts | Setup page and the Status column |
| Identify | Identify button on each row |
| Time zone, daylight saving, NTP | Clock card on the Tools page |
| Parameter and meter list (`prmnum`, `prminfo`, `mtrnum`, `mtrinfo`) | List Parameters button |
| Firmware update, provisioning import, normalized values, anything else | Command Line, typed by hand |

Presets (`ssrecall_ex`) are in the specification for the RM-CR only, so there are none here.

Firmware update and provisioning import have no button on purpose: they are one-off jobs that can take a mic
out of service, so they are only reachable by typing the command.

## Tested

1.0.0.2 was run in Designer against one RM-TT on firmware V3.0.1 on a live system (2026-10-09): it connected,
read the model, firmware, serial number and unit ID, and worked as expected in use.

Changes since then (the heartbeat that expects an answer, reconnecting a silent mic, Bad address, reading values
back after the mic refuses a change, and the Response box) have only been run against the simulated mic in `tests\`.
Pull a mic's network cable for a minute to confirm it goes Offline and comes back.

Not individually confirmed on a mic. Tick these off as they are checked:

- **More than one mic.** Group mute, the mic button modes and Apply To All need at least two.
- **Parameter addresses.** They are copied from the specification, including spellings such as
  `RM:Mic_Direcctl`. Press List Parameters and compare the debug window with the `PARAMS` table.
- **Meter channel count.** The specification does not say how many channels each meter has; two are drawn.
- **Output mute polarity.** The specification says 0 is muted for `RM:NeOut_Mute/Ch/On`, the reverse of the others.
- **Clock replies.** The reply format for the `RM:Get...` events is assumed to echo the event name and a quoted value,
  and the time zone table (0 to 32) is not in the specification.
- **Mic button notifications.** "Mutes All Microphones" relies on the mic sending `NOTIFY set RM:MicMute/All`
  when its button is pressed.
- **What the mic sends when it refuses a change.** The plugin expects a line starting `ERROR set`.

In Designer's dark theme the pages are shown with light and dark swapped (pale header, black cards). That is
Designer, not the plugin; the colors in `layout.lua` are the light-theme ones in `preview\`.

## Build

Needs Windows, VS Code and Git for Windows (the version step runs `sh`, which Git for Windows provides).

The folder must be named `YamahaRMTT`: the compiler names the `.qplug` after the folder.

Ctrl+Shift+B in VS Code, pick a version increment. The result is copied to
`Documents\QSC\Q-Sys Designer\Plugins\YamahaRMTT\`, and to the same folder under
`OneDrive - Vivo Technologies\QSC\Q-Sys Designer` when that exists.

| Pick | Use it for | 1.0.0.0 becomes |
|---|---|---|
| `ver_dev` | A work-in-progress build while testing | 1.0.0.1 |
| `ver_fix` | A bug fix that is ready to release | 1.0.1.0 |
| `ver_min` | A new feature | 1.1.0.0 |
| `ver_maj` | A change that breaks existing designs | 2.0.0.0 |
| `ver_none` | Compile without changing the version | 1.0.0.0 |

## Making a change

1. Pull `main`, then make a branch named for the change (`fix/meter-channels`, `feature/rm-cg`).
2. Edit the `.lua` files, never the `.qplug`: it is rebuilt from them and is not kept in Git.
3. Build with `ver_dev`, run the tests, and load the plugin in Designer.
4. Commit, push the branch and open a pull request. Someone else reviews and merges it.
5. If `info.lua` conflicts on `BuildVersion`, keep the higher number.

Never change `Id` in `info.lua`. Designer uses it to recognise the plugin in existing designs, so a new Id is a
different plugin.

To add or correct a parameter, edit its row in `PARAMS` in `plugin.lua`. The control, its place on the page,
the pins and the runtime all come from that row.

## Files

| File | Holds |
|---|---|
| `plugin.lua` | Skeleton, `SECTIONS`, `PARAMS` and `CLOCK_FIELDS` (every parameter and where it is drawn), shared helpers |
| `info.lua` | Name, Id and `BuildVersion` (the compiler updates the version) |
| `properties.lua`, `rectify_properties.lua` | The properties above |
| `controls.lua` | Group and per mic controls, then one control per parameter |
| `layout.lua` | Control, Microphone, EQ, Tools and Setup pages |
| `runtime.lua` | Connections, mute logic, parameter sync, meters, clock, parsing, status |
| `tests\` | A test that runs the compiled plugin in Lua 5.3 against simulated mics |
| `plugincompile\`, `.vscode\` | QSC's plugin compiler and the VS Code build task that runs it |
| `preview\` | Rough pictures of each page drawn from the layout code, not screenshots from Designer |

## Tests

    python tests\run_lua_test.py tests\rmtt_test.lua YamahaRMTT.qplug

Build first, so the `.qplug` exists. Needs Python with the `lupa` package (`pip install lupa`). It checks every
layout key against the control list for eight property combinations, then drives the runtime: connection and
start up, parameter display and sending, meters, clock, command line, group mute, the three mic button modes,
reconnection, retries and alerts. It does not replace loading the plugin in Designer.
