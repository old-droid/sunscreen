# ☀️ Sunscreen

A beautiful terminal TUI Pomodoro-style screen-time limiter for Linux.

## Features

- **2-hour daily quota** — after 2 hours of screen time, your desktop freezes
- **5-minute breaks every 30 minutes** — forces you to step away
- **Beautiful TUI** — color-coded progress bars, session timer, daily stats
- **X11 & Wayland support** — freezes your desktop when rules are violated
- **Persistent state** — survives crashes, resets daily

## Rules

| Rule | Behavior |
|------|----------|
| Every 30 min | 5-minute mandatory break (desktop frozen) |
| 2 hours/day quota | Desktop frozen for rest of the day |
| After break | Session counter resets, you get another 30 min |

## Installation

```bash
git clone https://github.com/yourname/sunscreen.git
cd sunscreen
chmod +x install.sh
./install.sh
```

This installs:
- `~/.local/bin/sunscreen` — main script
- `~/.config/systemd/user/sunscreen.service` — auto-start on boot
- Adds `~/.local/bin` to PATH

Or run directly:

```bash
chmod +x sunscreen.sh
./sunscreen.sh
```

### Service Commands

```bash
systemctl --user status sunscreen   # Check status
systemctl --user stop sunscreen     # Stop
systemctl --user start sunscreen    # Start
systemctl --user restart sunscreen  # Restart
```

## Usage

```bash
sunscreen
```

### Controls (TUI Mode)

| Key | Action |
|-----|--------|
| `q` | Quit |
| `r` | Reset today's progress |
| `Ctrl+C` | Exit (freeze persists if quota reached) |

### Modes

- **TUI** (`sunscreen`): Interactive dashboard showing timers and stats
- **Daemon** (`sunscreen --daemon`): Background service, auto-starts on boot

## Requirements

- Linux (X11 or Wayland)
- `xdotool` (X11 freeze)
- `wtype` (Wayland, optional)
- Bash 4+

## State Files

All data stored in `~/.sunscreen/`:

- `date` — current date (used for daily reset)
- `accumulated` — total seconds used today
- `session_start` — current session start epoch
- `break_end` — break end epoch
- `frozen_today` — whether frozen for the day

## License

MIT
