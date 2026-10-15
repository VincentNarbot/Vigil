# Vigil

**Keep your AI agents running locally, with your Mac locked.**

Coding agents (Claude Code, Codex, Cursor and friends) run on your Mac. You can drive them from your phone, but only while the Mac is awake. Lock the screen and walk away, and macOS soon puts the Mac to sleep, which stops every agent and drops your remote connection.

Vigil is a tiny menu bar app that fixes exactly that. It keeps the Mac itself awake but lets the display turn off and the screen lock. Anyone sitting at your desk sees only a locked screen, while your agents keep working and stay reachable from your phone.

Most keep-awake apps hold the display on instead, which means you can't lock and leave.

## Menu

- **Keep Mac Awake while Locked**: the screen can turn off and lock (default).
- **Keep Display On**: the screen stays on too.
- **Keep Awake For**: indefinitely, or 15 minutes to 8 hours. Timed sessions show a countdown next to the icon.
- **Turn Off**, **Lock Screen**, **Launch at Login**

Vigil only holds the Mac awake on the power adapter; on battery it pauses and the cup icon turns empty.

One Swift file, no dependencies, no network access.

Want it to keep running with the lid closed and no external display? Run `sudo pmset -a disablesleep 1` (undo with `0`). It runs warmer, so keep the Mac on a hard surface.

## Build

Requires macOS 14.4+ and the Xcode command line tools.

```sh
./build.sh
```

This builds `Vigil.app`, ad-hoc signs it, installs it to `~/Applications` and launches it.

## How it works

Vigil holds an IOKit `PreventUserIdleSystemSleep` power assertion (`PreventUserIdleDisplaySleep` with Keep Display On). You can see it with:

```sh
pmset -g assertions | grep Vigil
```

Quitting Vigil releases the assertion immediately.

## License

MIT
