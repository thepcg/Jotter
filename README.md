# Jotter  
## A lightweight, context-aware to-do list for World of Warcraft

Jotter is a clean, minimalist to-do addon designed for players who like to plan what they are doing while they are doing it. It focuses on clarity, low visual noise, and staying out of your way until you need it.

At its core, Jotter lets you create simple, structured to-do items that are aware of where you are in the world. Tasks can be associated with specific zones, optional coordinates, and descriptive notes, making it ideal for quest planning, exploration goals, achievement tracking, profession routes, or simply remembering what you meant to do next.

---

## Key Features

### Zone-aware todos
Associate tasks with specific zones so your list stays relevant as you move through the world.

### Optional coordinates with waypoint creation
Add coordinates to a todo and click it to create an in-game waypoint, letting you move seamlessly from planning to action.

### Categories and grouping
Organize todos into categories that can be grouped, collapsed, and ordered for better focus and readability.

### Clean, resizable main window
A simple, distraction-free UI that can be resized and positioned to fit your layout.

### Lockable UI and combat-aware behavior
Lock the window in place and optionally hide or fade it while in combat so it never interferes when things get hectic.

### Minimalist configuration
Settings are designed to be straightforward and intentional, avoiding clutter and unnecessary complexity.

### Lightweight and performance-friendly
Jotter is built to do one thing well without heavy overhead or constant background processing.

---

## Philosophy

Jotter is not a quest helper or automation tool. It does not tell you how to play. Instead, it gives you a flexible space to track your own intentions, goals, and reminders in a way that feels natural inside the World of Warcraft UI.

If you like addons that respect your attention and adapt to your playstyle rather than forcing one on you, Jotter is built for you.

---

## Planned Features and Roadmap

Jotter is actively developed with a focus on intentional, player-driven tooling. The roadmap below outlines areas of planned expansion while maintaining the addon’s lightweight and non-intrusive design philosophy.

---

## Waypoint Integration and Navigation

Jotter already supports storing coordinates with a note. Planned enhancements will expand how those coordinates can be used in-game.

### Native Blizzard waypoint support
Create and manage Blizzard map waypoints directly from a Jotter note.

### TomTom integration (optional)
When TomTom is installed, Jotter will be able to create TomTom waypoints for notes with coordinates, offering enhanced navigation features without making TomTom a dependency.

### Smarter coordinate handling
Improved validation and normalization of coordinate input to reduce errors and improve reliability across zones and instances.

---

## Target-Associated Notes

Some reminders are about who, not where. Jotter will gain the ability to associate notes with specific targets.

### Player and NPC associations
Attach a Jotter note to an NPC, enemy, or player character.

### Context-aware reminders
Automatically surface relevant notes when you target the associated entity.

### Flexible identification
Support multiple identification methods where possible, such as name, creature ID, or GUID, to reduce ambiguity.

---

## Timers and Date-Based Reminders

Not all notes are location-based. Future updates will allow notes to reappear based on time.

### Countdown timers
Set short-duration reminders tied to a note, such as “check back in 10 minutes” or “respawn window.”

### Date and time reminders
Assign a specific date and time for a note to become active or highlighted.

### Non-intrusive alerts
Reminders will respect combat state and UI visibility settings to avoid disruptive popups.

---

## Importing and Exporting Notes

Sharing and portability are important, especially for alts, friends, or guilds.

### Export individual notes or collections
Copy notes as text or structured data for backup or sharing.

### Import support
Recreate notes from exported data, including categories, zones, and coordinates.

### Future-proof format
Exported data will be human-readable and versioned to support future changes without breaking old exports.

---

## Long-Term Direction

Jotter’s roadmap intentionally avoids turning it into a quest helper, guide, or automation addon. New features are evaluated based on three core principles:

- Player intent comes first  
- Minimal UI noise and overhead  
- Optional integrations, never hard dependencies  
