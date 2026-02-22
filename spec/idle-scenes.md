# Idle Scene System

## Overview

Automatic idle animations triggered by inactivity time, time-of-day, and external events (music playback). Includes burn-in protection via screen dimming.

## Idle Scenes

| Scene | Trigger | Expression | Motion | Duration |
|-------|---------|-----------|--------|----------|
| `sleeping` | 3+ min idle | `sleepy` → `sleeping` | `slowNodDown` | 5 min max |
| `thinking` | 5+ min idle | `thinking` | `thinking` | 45 sec max |
| `snack` | 8+ min idle (or 15:00) | `idle_snack` | — | 90 sec max |
| `bored` | 15+ min idle | `idle_bored` | `lookAround` | 2 min max |
| `singing` | Music playing | `idle_singing` | `swaySinging` | 60 sec max |
| `greeting` | 7-9h / 12-13h / 17-19h | `greeting` | `smallNod` | 30 sec max |

## Screen Dimming (Burn-in Protection)

| Time | Dim After |
|------|-----------|
| Daytime (7:00–23:00) | 30 minutes idle |
| Night (23:00–7:00) | 2 minutes idle |

When dimmed:
- Screen brightness → 0.01
- Camera session stopped
- DockKit tracking suspended
- Expression set to `sleeping`
- Auto-blink disabled

## Wake Triggers

Any of these wakes from idle/dimmed state:
- Screen tap
- Any WebSocket command (except `silent_debug`)
- `force_wake` command
- Voice input wake word detection

## Evaluation Loop

`IdleSceneManager` runs a timer every **15 seconds** that:
1. Checks screen dim threshold
2. Manages scene duration limits
3. Evaluates time-of-day greetings (once per hour)
4. Probabilistically selects idle scenes based on idle duration

Scene transitions are randomized (using `Int.random`) to feel more natural and avoid predictable patterns.
