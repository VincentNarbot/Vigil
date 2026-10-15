# Vigil

A tiny macOS menu bar app that keeps your Mac awake **while the screen stays locked**.

Most keep-awake apps hold the display on, which means you can't lock and walk away. Vigil only prevents *system* sleep by default, so the display can turn off and the screen can lock while long-running jobs, coding agents, builds, downloads or remote sessions keep going. You can't use the Mac, but your agents can.

## Features

- **Keep Mac Awake (screen can lock)**: prevents idle system sleep, allows display sleep and screen lock (default)
- **Keep Mac and Display Awake**: classic caffeinate-style behavior
- **Only When on Power Adapter**: pauses automatically on battery (on by default)
- **Stay Awake With Lid Closed**: toggles `pmset disablesleep` (asks for an admin password; runs warmer, so keep the Mac on a hard surface)
- **Lock Screen Now**
- **Launch at Login**

One Swift file, no dependencies, no network access.

## Build

Requires macOS 13+ and the Xcode command line tools.

```sh
./build.sh
```

This builds `Vigil.app`, ad-hoc signs it, installs it to `~/Applications` and launches it.

## How it works

Vigil holds an IOKit power assertion: `PreventUserIdleSystemSleep` (or `PreventUserIdleDisplaySleep` in display mode). You can see it with:

```sh
pmset -g assertions | grep Vigil
```

Quitting Vigil releases the assertion immediately.

## License

MIT
