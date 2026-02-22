# DockKit Integration

## Overview

Controls a DockKit-compatible motorized phone stand (e.g., Insta360 Flow Pro) to give the avatar physical movement — nodding, looking around, and expressive gestures.

DockKit is **optional**. The app functions fully without a motorized stand.

## Requirements

- iPhone with DockKit support
- DockKit-compatible accessory (MFi certified)
- Active `AVCaptureSession` (DockKit requires camera access)
- `NSCameraUsageDescription` in Info.plist

## Control Methods

### 1. Built-in Gestures

DockKit provides pre-built animations:

| Gesture | Description |
|---------|-------------|
| `nod` / `yes` | Nod up and down |
| `shake` / `no` | Shake side to side |
| `wakeup` / `wake` | Wake-up motion |
| `kapow` | Impact-style motion |

### 2. Motion Presets

Custom velocity-based motion sequences defined in `DockKitManager`:

| Preset | Motion |
|--------|--------|
| `smallNod` | Quick nod down and back up |
| `lookLeft` | Glance left, return to center |
| `lookRight` | Glance right, return to center |
| `lookAround` | Look left then right |
| `thinking` | Slight tilt to one side |
| `excited` | Rapid nodding |
| `slowNodDown` | Slow downward tilt (dozing off) |
| `swaySinging` | Side-to-side sway (for singing/music) |

### 3. Raw Control

Direct DockKit API access for custom movements:

```json
// Rotation3D — set absolute angle (radians, EulerAngles XYZ)
{"pitch": 0, "yaw": 1.57, "roll": 0}

// Vector3D — alternative API
{"pitch": 0, "yaw": 1.57, "roll": 0, "mode": "v3"}

// Angular velocity — rotate at speed for duration
{"pitch": 0, "yaw": -1.5, "roll": 0, "mode": "velocity", "durationMs": 2100}
```

## System Tracking

DockKit has an auto-tracking feature that follows faces. This **must be disabled** before manual control:

1. `setSystemTrackingEnabled(false)` — before every velocity/orientation command
2. Execute motor command
3. `setSystemTrackingEnabled(true)` — after command completes

The app handles this automatically. If tracking is left enabled, it fights manual movements.

## Animation Guard

An `isAnimating` flag prevents concurrent motor commands. While animating:
- New motion/velocity/orientation commands are **skipped** (logged as "Already animating")
- Built-in gestures are also blocked

If `isAnimating` gets stuck (shouldn't happen, but edge case on app crash), restarting the app resets it.

## Axis Mapping

DockKit uses a coordinate system that may not match intuition:

```swift
// Rotation3D (EulerAngles, order: .xyz)
x: Angle2D = yaw   (left/right rotation)
y: Angle2D = pitch  (up/down tilt)
z: Angle2D = roll   (clockwise/counter-clockwise)

// Vector3D (for velocity)
x: pitch
y: yaw
z: roll (unused in motion presets)
```

Note: The mapping between the JSON fields (`pitch`, `yaw`, `roll`) and the DockKit API axes is handled in `DockKitManager.swift`. Check the code for the exact mapping.

## Sleep/Wake Integration

- **Sleep**: `suspendTracking()` disables system tracking (saves power)
- **Wake**: `resumeTracking()` re-enables system tracking
- Managed by `IdleSceneManager` during screen dimming
