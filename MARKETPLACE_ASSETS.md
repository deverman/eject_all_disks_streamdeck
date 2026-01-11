# Marketplace Submission Assets

This document contains all the marketing copy and image specifications needed to submit the Eject All Disks plugin to the Elgato Marketplace.

---

## Product Information

### Basic Details

| Field | Value |
|-------|-------|
| **Product Name** | Eject All Disks |
| **Author** | Brent Deverman |
| **Version** | 3.0.0 |
| **Price** | $1.00 USD |
| **Category** | Utilities / System |
| **Platform** | macOS 13+ |
| **Stream Deck Version** | 6.4+ |

### URLs

| Field | URL |
|-------|-----|
| **Homepage** | https://github.com/deverman/eject_all_disks_streamdeck |
| **Support** | https://github.com/deverman/eject_all_disks_streamdeck/issues |
| **Documentation** | https://github.com/deverman/eject_all_disks_streamdeck#readme |

---

## Product Description

### Short Description (for previews)

```
Safely eject all external drives with a single button press. Fast, native, and reliable.
```

### Full Description

```
Eject All Disks - One-Button Disk Ejection for macOS

Tired of hunting through Finder to eject your drives? With Eject All Disks,
safely remove all external drives with a single Stream Deck button press.

WHY EJECT ALL DISKS?

✓ FAST — Uses native macOS APIs for ~6x faster ejection than diskutil
✓ SIMPLE — One button ejects everything. No menus, no hunting, no dragging to trash
✓ SMART — Shows real-time disk count so you always know what's connected
✓ RELIABLE — Detailed error messages tell you exactly what went wrong

FEATURES

• Real-time disk count displayed on button (updates every 3 seconds)
• Visual feedback during ejection (Ejecting... → Ejected!)
• Intelligent error handling:
  - "In Use" when apps are blocking ejection
  - "Grant Access" when permissions are needed
  - "1 of 3 Failed" for partial failures
• Privacy-focused: Never logs your volume names
• Pure Swift implementation with zero dependencies

PERFECT FOR

• Content creators managing camera cards and SSDs
• Video editors working with multiple scratch disks
• Photographers importing from multiple memory cards
• Musicians with sample libraries on external drives
• Anyone who's tired of the eject dance

REQUIREMENTS

• macOS 13 (Ventura) or later
• Stream Deck 6.4 or later
• Full Disk Access permission (one-time setup)

QUICK SETUP

1. Install the plugin
2. Drag "Eject All Disks" to your Stream Deck
3. Grant Full Disk Access when prompted (System Settings → Privacy & Security)
4. Press the button to eject all drives!

The button shows your current disk count (e.g., "2 Disks") and updates
automatically as drives are connected or removed.

---

Built with ❤️ by Brent Deverman
Native Swift • No Node.js • No Shell Scripts • Just Fast
```

### Feature Bullets (for gallery images)

```
• One button ejects all drives
• 6x faster than diskutil
• Real-time disk count
• Smart error messages
• Privacy-focused logging
• Pure Swift performance
```

---

## Release Notes

### Version 3.0.0

```
Complete rewrite as native Swift plugin

NEW:
• Pure Swift implementation (no Node.js or shell scripts)
• ~6x faster ejection using native DiskArbitration framework
• Real-time disk count updates every 3 seconds
• Intelligent error messages (In Use, Grant Access, Timeout, etc.)
• Network volume filtering (won't try to eject SMB/AFP mounts)
• 30-second timeout prevents indefinite hangs

IMPROVED:
• Privacy-focused: Volume names never logged
• System volume protection using macOS APIs (not hardcoded names)
• Cleaner UI states (shows "No Disks" when nothing connected)

FIXED:
• No longer attempts to eject network drives
• Proper handling of APFS container volumes
```

---

## Required Images

### 1. Marketplace Icon (288 × 288 px)

**Filename:** `marketplace-icon.png`

**Design Concept:**
- Eject symbol (⏏) as the focal point
- Clean, modern design
- Works well at small sizes
- Color scheme:
  - Background: Dark gradient (#1a1a2e to #16213e)
  - Icon: White or accent color (#4ecca3 teal or #e94560 coral)
- No text (icon only)

**Visual Description:**
```
┌────────────────────────┐
│                        │
│         ┌───┐          │
│         │   │          │
│         │ ▲ │          │
│         │   │          │
│         └───┘          │
│        ═══════         │
│                        │
│   Dark gradient bg     │
│   White eject symbol   │
│                        │
└────────────────────────┘
```

### 2. Thumbnail (1920 × 960 px)

**Filename:** `thumbnail.png`

**Design Concept:**
- Stream Deck device showing the plugin button
- Product name prominently displayed
- Clean, professional look
- Dark theme to match Stream Deck aesthetic

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   ┌─────────────────┐                                           │
│   │  [Stream Deck]  │        EJECT ALL DISKS                    │
│   │   ┌───┬───┬───┐ │                                           │
│   │   │   │ 2 │   │ │        One button. All drives.            │
│   │   │   │Dsk│   │ │        Instant ejection.                  │
│   │   ├───┼───┼───┤ │                                           │
│   │   │   │   │   │ │        ✓ 6x faster than diskutil          │
│   │   │   │   │   │ │        ✓ Real-time disk count             │
│   │   └───┴───┴───┘ │        ✓ Smart error messages             │
│   └─────────────────┘                                           │
│                                                                 │
│   Dark gradient background (#0f0f1a to #1a1a2e)                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Gallery Image 1: Button States (1920 × 960 px)

**Filename:** `gallery-1-states.png`

**Design Concept:**
Show all button states side by side

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│              BUTTON STATES                                      │
│                                                                 │
│   ┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐          │
│   │  2  │    │ No  │    │Eject│    │Eject│    │ In  │          │
│   │Disks│    │Disks│    │ing..│    │ed!  │    │ Use │          │
│   │ ⏏  │    │ ⏏  │    │ ⟳  │    │ ✓  │    │ ✕  │          │
│   └─────┘    └─────┘    └─────┘    └─────┘    └─────┘          │
│    Ready    No Disks   Ejecting   Success     Error            │
│                                                                 │
│   See exactly what's happening at a glance                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4. Gallery Image 2: Speed Comparison (1920 × 960 px)

**Filename:** `gallery-2-speed.png`

**Design Concept:**
Visual comparison showing speed advantage

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│              6X FASTER EJECTION                                 │
│                                                                 │
│   Traditional (diskutil)                                        │
│   ████████████████████████████████████████░░░░░░  ~600ms        │
│                                                                 │
│   Eject All Disks (native)                                      │
│   ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ~100ms        │
│                                                                 │
│   Uses macOS DiskArbitration framework directly                 │
│   No subprocess spawning • No shell overhead                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Gallery Image 3: Error Handling (1920 × 960 px)

**Filename:** `gallery-3-errors.png`

**Design Concept:**
Show intelligent error messages

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│              SMART ERROR MESSAGES                               │
│                                                                 │
│   ┌─────┐  "In Use"                                             │
│   │ In  │  → An app is using the disk. Close it and retry.     │
│   │ Use │                                                       │
│   └─────┘                                                       │
│                                                                 │
│   ┌─────┐  "Grant Access"                                       │
│   │Grant│  → Full Disk Access needed. One-time setup.          │
│   │Acces│                                                       │
│   └─────┘                                                       │
│                                                                 │
│   ┌─────┐  "1 of 3 Failed"                                      │
│   │1of3 │  → Partial success. Shows exactly what happened.     │
│   │Fail │                                                       │
│   └─────┘                                                       │
│                                                                 │
│   No more guessing why ejection failed                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6. Gallery Image 4: Use Cases (1920 × 960 px)

**Filename:** `gallery-4-usecases.png`

**Design Concept:**
Show target audiences with icons

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│              PERFECT FOR                                        │
│                                                                 │
│   🎬 Video Editors        📸 Photographers                      │
│   Multiple scratch        Camera cards &                        │
│   disks & proxies         memory cards                          │
│                                                                 │
│   🎵 Musicians            💻 Developers                         │
│   Sample libraries        External build                        │
│   & project drives        drives & backups                      │
│                                                                 │
│   🎮 Streamers            👨‍💼 Professionals                      │
│   Game capture            Any workflow with                     │
│   drives & assets         external storage                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 7. Gallery Image 5: Setup (1920 × 960 px)

**Filename:** `gallery-5-setup.png`

**Design Concept:**
Simple 3-step setup process

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│              EASY SETUP                                         │
│                                                                 │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │     1       │    │     2       │    │     3       │        │
│   │   Install   │ →  │    Drag     │ →  │   Grant     │        │
│   │   Plugin    │    │  to Deck    │    │   Access    │        │
│   └─────────────┘    └─────────────┘    └─────────────┘        │
│                                                                 │
│   Download from      Add "Eject All     One-time Full          │
│   Marketplace        Disks" action      Disk Access            │
│                                                                 │
│               Ready in under 60 seconds!                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Image Creation Checklist

```
☐ marketplace-icon.png (288 × 288 px)
☐ thumbnail.png (1920 × 960 px)
☐ gallery-1-states.png (1920 × 960 px)
☐ gallery-2-speed.png (1920 × 960 px)
☐ gallery-3-errors.png (1920 × 960 px)
☐ gallery-4-usecases.png (1920 × 960 px) [optional]
☐ gallery-5-setup.png (1920 × 960 px) [optional]
```

**Minimum Required:** Icon + Thumbnail + 3 Gallery Images

---

## Design Guidelines

### Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Background Dark | #0f0f1a | Primary background |
| Background Mid | #1a1a2e | Secondary background |
| Background Light | #16213e | Accents |
| Primary Accent | #4ecca3 | Success, highlights |
| Secondary Accent | #e94560 | Errors, attention |
| Text Primary | #ffffff | Headings |
| Text Secondary | #a0a0a0 | Body text |

### Typography

- **Headings:** SF Pro Display Bold (or similar sans-serif)
- **Body:** SF Pro Text Regular
- **Monospace:** SF Mono (for technical details)

### Style Notes

- Dark theme to match Stream Deck aesthetic
- Clean, minimal design
- Generous whitespace
- No busy backgrounds or gradients
- Icons should be simple and recognizable at small sizes

---

## Alt Text for Accessibility

### Thumbnail
```
Eject All Disks Stream Deck plugin showing a button with "2 Disks"
displayed. Text reads: One button. All drives. Instant ejection.
```

### Gallery Image 1
```
Five Stream Deck buttons showing different states: Ready with disk count,
No Disks, Ejecting animation, Success checkmark, and Error with In Use message.
```

### Gallery Image 2
```
Speed comparison bar chart showing Eject All Disks is 6 times faster
than traditional diskutil commands.
```

### Gallery Image 3
```
Three error message examples: In Use when an app blocks ejection,
Grant Access for permissions, and partial failure showing 1 of 3 Failed.
```

---

## Submission Checklist

### Before Creating Images

```
☐ Review Elgato's image guidelines
☐ Prepare screenshots of actual plugin
☐ Gather Stream Deck device photos (or use official media kit)
☐ Create consistent design template
```

### Before Submitting

```
☐ All images are PNG format
☐ All images meet exact size requirements
☐ Alt text written for each image
☐ No copyrighted material used
☐ No external links in images
☐ Product name visible in thumbnail
☐ Images tell a cohesive story
```

---

## Notes for Image Creation

If creating images yourself:
1. Use Figma, Sketch, or Photoshop
2. Export at exact dimensions (no scaling)
3. Use PNG-24 for best quality
4. Test images at small preview sizes

If hiring a designer:
1. Share this document as a brief
2. Provide the actual button SVGs from the plugin
3. Request layered source files (PSD/Figma)
4. Get both light and dark versions

---

*Last Updated: 2026-01-11*
