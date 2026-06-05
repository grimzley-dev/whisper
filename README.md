# whisper

**whisper** is a lightweight, modular, zero-dependency utility addon for World of Warcraft. Built from the ground up for high performance and low memory footprint, it features a sleek, centralized configuration panel that allows you to easily toggle and customize only the features you need.

*Created for my guild, whisper on Sunstrider.*

## 🚀 Installation
1. Download the latest `whisper.zip` from the [Releases](https://github.com/YOUR-USERNAME/YOUR-REPO/releases) page.
2. Extract the folder into your `World of Warcraft\_retail_\Interface\AddOns\` directory.
3. Boot up the game and type `/shh` to open the control panel!

## ⚙️ Commands
* `/shh` - Opens the main configuration panel.
* `/shh enable <module>` - Enables a specific module.
* `/shh disable <module>` - Disables a specific module.
* `/shh test <module>` - Toggles the test mode for a module (e.g., `/shh test loot`).


---

## 🧩 Modules & Features

All modules can be dynamically enabled, disabled, and configured via the `/shh` panel without needing to reload your UI (unless specified).

### 🗝️ Keystones
Automatically tracks and displays the Mythic+ keystones for your entire party.
* **Teleport Integration:** Clickable dungeon icons that cast the respective portal spell if you have it learned (shows cooldowns on hover).
* **Reroll Reminder:** Displays a smooth, animated "Reroll Key?" golden text popup in the center of your screen when a Mythic+ dungeon is completed.
* **Customizable Display:** Choose between Default, Compact, or Transparent UI styles. Adjust X/Y offsets and choose whether the list grows upwards or downwards.

### 🎁 Loot Announcer
A beautiful visual notification system for party and raid loot drops.
* Displays the item icon, clickable item link, and the class-colored name of the player who received it.
* Optional sound alert when loot drops.
* Configurable X/Y positioning and display duration.
* Choose to see all group loot or only your own.

### ⚔️ Combat Texts
Stacked on-screen combat notifications inspired by AES/NUI.
* **Enter / Exit Combat** — flash messages when you enter or leave combat.
* **Low Durability** — persistent warning when equipped gear drops below 15% (hidden in combat).
* **Party Deaths** — class-colored death feed; multiple deaths can show at once.
* **Test mode** — preview all message types stacked, then drag the frame to set position.
* Configurable death line limit and burst protection during mass wipes.

### 👼 PI Helper (Power Infusion)
A must-have for Priests looking to perfectly time their Power Infusion.
* Select a priority target from the dropdown menu in the config panel (dynamically populates with your current group members).
* When your assigned target whispers you, a massive on-screen alert and sound effect will trigger.
* The alert automatically hides the moment you successfully cast Power Infusion on them.

### 🗺️ World Markers
Fast, keybind-driven world marker placement without reaching for the sidebar.
* **Custom Keybinds:** Set dedicated keys to Place and Clear markers.
* **Cyclical Mode:** Build a custom sequence of up to 8 markers. Pressing your keybind will drop them one by one in that exact order.
* **Static Mode:** Need to constantly drop a specific marker (e.g., Star)? Set it to Static to always drop your preferred shape.

### 🛠️ Utilities
A collection of micro-modules built for massive quality-of-life improvements.

* **Mail & Log:** * *Mass Mailing:* A powerful text-parsing interface. Paste lists in a `Name:Amount:Subject:Body` format to automatically queue and send mail with a progress bar and success summary.
  * *Mail Log:* A dedicated, searchable ledger that records all incoming and outgoing mail and gold transactions.
* **Quest Cleaner:** Automatically cleans up your objective tracker by quietly removing hidden, bugged, or backend quests from your watch list.
* **Mythic Frames:** (Requires ElvUI) Automatically tweaks ElvUI visibility settings to force standard Raid 1 frames to show when entering a Mythic Raid.
