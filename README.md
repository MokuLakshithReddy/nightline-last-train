# NIGHTLINE: LAST TRAIN

> **"Every stop is a risk. Every return is a reward."**

NIGHTLINE is a 1–6 player cooperative survival adventure on Roblox. A crew rides the last train through an abandoned city, explores dangerous stations for critical resources and mission objectives, evades a sound-hunting shadow entity known as **The Hollow**, and must make it back to the train before departure.

---

## Gameplay loop and code layout

~~~mermaid
flowchart TD
    A["Train hub and crew preparation"] --> B["Choose a station"]
    B --> C["Explore and find mission items"]
    C --> D["Complete objectives and evade The Hollow"]
    D --> E["Return to extraction"]
    E --> F["Board the train for the next trip"]
    F --> A
~~~

The code is organized as a Rojo-synced Luau project:
- Shared configuration, types, and utilities under ReplicatedStorage.
- Server-authoritative services and AI modules under ServerScriptService.
- Templates and world assets under ServerStorage.
- Client presentation controllers under StarterPlayerScripts.

This repository is the source project for Roblox Studio rather than a published game build. To inspect the place in Studio, use the Rojo workflow below. No verified in-game screenshots, released place link, or measured multiplayer performance results are currently included here.

**Why it matters:** modular server/client boundaries make it easier to iterate on cooperative mission logic while keeping gameplay validation on the server.

---
## 🛠️ Development Environment & Tooling

This project uses a modular, file-based Roblox development architecture powered by **Rojo** and **Luau**:

- **Engine:** Roblox Studio (Luau `--!strict`)
- **Sync & Project Tool:** Rojo 7.7.1
- **Linter & Static Analysis:** Selene 0.32.0 (Roblox standard)
- **VCS:** Git

---

## 🚀 Quick Setup & How to Run

### Option 1: Live Sync with Roblox Studio via Rojo
1. In the terminal, start the Rojo server:
   ```powershell
   .\bin\rojo.exe serve
   ```
2. Open **Roblox Studio** and open a blank Baseplate or existing place.
3. In Studio, click the **Rojo** plugin tab in the top bar and click **Connect** (default port `34872`).
4. All project files, scripts, services, and assets will live-sync instantly into your Studio DataModel.

### Option 2: Build a Standalone Roblox Place File (`.rbxl`)
Generate a self-contained `.rbxl` file that can be opened directly with double-click in Roblox Studio:
```powershell
.\bin\rojo.exe build -o Nightline.rbxl
```
Open `Nightline.rbxl` directly in Roblox Studio and press **F5 (Play)**.

---

## 🧪 Static Analysis & Linting
Run static analysis with Selene:
```powershell
.\bin\selene.exe src
```

---

## 📂 Project Structure

```text
NIGHTLINE/
├── bin/                          # Local developer CLI tool binaries (rojo, selene)
├── docs/                         # Engineering and architecture documentation
│   ├── ARCHITECTURE.md
│   ├── DEVELOPMENT_PROGRESS.md
│   ├── TESTING.md
│   └── KNOWN_ISSUES.md
├── default.project.json          # Rojo project definition
├── selene.toml                   # Luau linter rules
└── src/
    ├── ReplicatedStorage/
    │   └── Shared/
    │       ├── Config/           # Centralized balance and game configurations
    │       ├── Types/            # Luau type definitions
    │       └── Utils/            # Logger, Signal, and utility helpers
    ├── ServerScriptService/
    │   ├── Bootstrap.server.luau # Server initialization entry point
    │   ├── Services/             # Authoritative server services
    │   └── AI/                   # Monster AI and finite state machine
    ├── ServerStorage/
    │   └── Templates/            # Station and entity templates
    └── StarterPlayer/
        └── StarterPlayerScripts/
            ├── ClientBootstrap.client.luau # Client initialization entry point
            └── Controllers/                # Client-side presentation controllers
```

