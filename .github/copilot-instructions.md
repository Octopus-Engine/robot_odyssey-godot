# Copilot Instructions

## Repository Overview

This is a **fork of Godot Engine 4.5** that embeds a custom real-time strategy (RTS) simulation engine via the `modules/godoctopus2` module. The game project (GDScript/scenes) lives in a **separate repository** (`robot_odyssey-godoctopus`); this repo only contains the engine.

> **Important:** Do not modify any Godot engine code outside of `modules/godoctopus2/`. All game-specific changes belong in that directory.

### Submodule Structure

`modules/godoctopus2` is itself a Git submodule (url: `robot_odyssey-godoctopus`) with three nested submodules:

| Path | Description |
|---|---|
| `modules/godoctopus2/src/octopus2` | C++ RTS simulation engine (ECS via flecs, fixed-point arithmetic, pathfinding, combat) |
| `modules/godoctopus2/src/nwfc` | Constraint programming solver for procedural generation |
| `modules/godoctopus2/smart_list` | Utility data structure library |

Clone with:
```bash
git clone --recurse-submodules <repo-url>
```

---

## Build

The engine uses **SCons** (Python-based build system).

### Linux

```bash
# Build the editor (debug)
scons platform=linuxbsd target=editor debug=yes debug_symbols=yes

# Export template (release)
scons platform=linuxbsd target=template_release
```

### Windows

```bat
scons target=editor
```

The output binary lands in `bin/`. The VS Code launch config targets `bin/godoctopus2.exe`.

### Running Godot tests

**Linux:**
```bash
./bin/godot.linuxbsd.editor.x86_64 --headless --test --force-colors
```

**Windows:**
```bat
bin\godot.windows.editor.x86_64.exe --headless --test --force-colors
```

### octopus2 (RTS engine) — standalone tests

The `octopus2` submodule has its own CMake+GTest build (run from `modules/godoctopus2/src/octopus2/`):

**Linux:**
```bash
cmake --build builds/Debug --parallel
./builds/Debug/src/octopus/test/unit_tests                              # all tests
./builds/Debug/src/octopus/test/unit_tests --gtest_filter=SomeTest.*   # single suite
```

**Windows:**
```bat
cmake --build builds\Debug --parallel
builds\Debug\src\octopus\test\unit_tests.exe
builds\Debug\src\octopus\test\unit_tests.exe --gtest_filter=SomeTest.*
```

### nwfc — standalone tests

Run from `modules/godoctopus2/src/nwfc/`. Dependencies managed via Conan 2.

**Linux:**
```bash
source ~/venv/bin/activate   # activate Python venv with conan installed
conan install . --build=missing -of builds/Debug -s build_type=Debug -if builds/Debug/
cmake ../.. -G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=conan_toolchain.cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build . --parallel
./builds/Debug/src/nwfc/test/unit_tests                                     # all
./builds/Debug/src/nwfc/test/unit_tests --gtest_filter=BitsetDomainTest.*   # single
```

**Windows:**
```bat
conan install . --build=missing -of builds\Debug -s build_type=Debug -if builds\Debug\
cmake ..\.. -G "Visual Studio 17 2022" -DCMAKE_TOOLCHAIN_FILE=conan_toolchain.cmake
cmake --build builds\Debug --config Debug
builds\Debug\src\nwfc\test\unit_tests.exe --gtest_filter=BitsetDomainTest.*
```

---

## Architecture

### Godot engine layer (`core/`, `scene/`, `editor/`, `servers/`, etc.)
Standard upstream Godot 4 source. Avoid modifying unless fixing an engine-level bug.

### How godoctopus2 is integrated into Godot

- `modules/godoctopus2/config.py` — declares the module to SCons (always enabled)
- `modules/godoctopus2/SCsub` — lists all C/C++ sources, include paths, and compiles everything into `env.modules_sources`
- `modules/godoctopus2/register_types.cpp` — calls `ClassDB::register_class<>()` for every exposed Godot node at `MODULE_INITIALIZATION_LEVEL_SCENE`

All Godot-facing classes are in the `godot` namespace. The module exposes:
- `GameNode` — top-level simulation controller (runs a dedicated thread at 50 Hz)
- `ActionNode` — queues game actions (spawn units, modify runes) thread-safely
- `CommandNode` — sends player commands (move, attack) into the input queue
- `LevelNode` — abstract base; subclass in GDScript/C++ and pass to `GameNode` for level setup
- `NotWaveFunctionCollapseNode` — GDScript API wrapping the nwfc solver
- VAT/mesh classes (`VatLibrary`, `SmartMMeshLibrary`, etc.) — vertex animation texture rendering

### Directory structure

```
modules/godoctopus2/
├── src/
│   ├── godoctopus/        # Godot-facing C++ nodes and resources
│   │   ├── game/          # GameNode, LevelNode, prefabs (UnitPrefab)
│   │   ├── command/       # CommandNode — issues move/attack/cast commands
│   │   ├── action/        # ActionNode — spawns units, modifies runes (thread-safe queue)
│   │   ├── info/          # InfoNode — queries entity stats from simulation
│   │   ├── entity_group/  # EntityGroup (Resource wrapping flecs::entity vector)
│   │   ├── display/       # VAT & particle rendering nodes
│   │   ├── pickable/      # Entity selection / picking
│   │   ├── health_bar/    # HUD health display
│   │   ├── nwfc/          # Procedural generation (nwfc constraint solver)
│   │   └── trigger_module/
│   ├── vat/               # Vertex Animation Texture system (GPU-baked unit anims)
│   │   ├── VatLibrary     # manages VAT tracks + MultiMesh instances
│   │   └── SmartMMeshLibrary
│   ├── octopus2/          # octopus2 RTS simulation engine (C++ + Flecs ECS)
│   │   └── src/octopus/   # core simulation: world, commands, systems
│   ├── godot_tools.h      # shared macros for Godot binding (see Conventions)
│   └── octopus_types.h    # custom_variant, custom_step_manager, TICK_RATE
```

### Data flow

```
GDScript/Godot → CommandNode/ActionNode
                     ↓ (thread-safe queue)
              octopus::Input<custom_variant>
                     ↓
              octopus::WorldContext  (simulation tick, TICK_RATE = 50 Hz)
                     ↓
              Flecs ECS world  ←→  GameNode._process() reads state
                     ↓
              VatLibrary / SmartMMeshLibrary  →  GPU rendering
```

`GameNode` owns the `WorldContext` and drives the simulation. `LevelNode` subclasses define per-level setup. `UnitPrefab` resources define unit stats in the Godot editor.

### GameNode threading model

`GameNode` runs the ECS world (`flecs::world`) on a background thread at `TICK_RATE = 50` Hz (20 ms steps). Godot's `_process` increments an atomic tick counter; the background thread consumes it. All cross-thread data access is protected by `_progress_mutex`. Never call `ecs.progress()` from the main thread.

### Include paths (godoctopus2 C++ code)

| Prefix | Maps to |
|---|---|
| `octopus/...` | `modules/godoctopus2/src/octopus2/src/octopus/src/octopus/` |
| `flecs.h` | `modules/godoctopus2/src/octopus2/src/octopus/src/flecs/` |
| `nwfc/...` (constraint solver) | `modules/godoctopus2/src/nwfc/src/nwfc/src/` |
| `godoctopus/...` | `modules/godoctopus2/src/godoctopus/` |
| `vat/...` | `modules/godoctopus2/src/vat/` |

---

## Key Conventions

### No floating-point, no exceptions (octopus2 / nwfc)

- **Never use `float`, `double`, or floating-point literals** inside `src/octopus2` or `src/nwfc`. All arithmetic must use `octopus::Fixed` or integer types (`int64_t`, etc.) to guarantee deterministic simulation across hardware.
- The codebase must build with `-fno-exceptions`. Use `assert()` for programmer errors, not `throw`.

### All classes in `namespace godot {}`

### Header guards: `#pragma once` (not `#ifndef` guards)

### Godot class registration pattern

```cpp
class MyNode : public Node {
    GDCLASS(MyNode, Node)
public:
    static void _bind_methods(); // registers methods & properties
};
```

### Macros from `godot_tools.h`

| Macro | Purpose |
|---|---|
| `SET_GET_NODE_PATH(Type, var_name)` | Declares `NodePath` + pointer + getter/setter |
| `INIT_NODE_PATH(Type, var_name)` | Resolves the node path in `init_nodes()` |
| `BIND_NODE_PATH(ClassName, Type, var_name)` | Registers it with `ClassDB` |
| `SET_GET_PARAM(type, name)` | Property with getter/setter (no default) |
| `SET_GET_PARAM_DEF(type, name, default)` | Property with getter/setter + default |
| `ADD_SIMPLE_PROP(ClassName, VariantType, name)` | Binds + exposes a primitive property |
| `ADD_OBJECT_PROP(ClassName, Type, name)` | Binds + exposes a Resource property |
| `ADD_ARRAY_OBJECT_PROP(ClassName, Type, name)` | Binds + exposes a typed array property |

Node path fields are resolved by calling `init_nodes()` (typically from `_ready` or explicit setup).

### Numeric stats use x10 integers

Stats that could be floats are stored as integers multiplied by 10 to avoid floating-point precision issues (e.g., `damage_x10`, `special_x10`, `windup_x10`).

### Thread safety

The simulation runs on a background thread. Nodes that bridge the two threads (e.g., `ActionNode`, `InfoNode`) use `std::mutex _mutex` and `std::lock_guard<std::mutex>` for all cross-thread data access.

### `EntityGroup`

A `Resource` (not a `Node`) wrapping `std::vector<flecs::entity>`. Passed between GDScript and C++ to refer to groups of simulation entities. Call `remove_dead_entities()` before use if the group may be stale.

### `custom_variant` (in `octopus_types.h`)

`custom_variant` is a `std::variant` of all supported command types; `custom_queue` is `CommandQueue<custom_variant>`:
```cpp
typedef std::variant<NoOpCommand, MoveCommand, AttackCommand, CastCommand, SetRallyPointCommand> custom_variant;
```
When adding a new command type, update this typedef, all variant visitors, and the `advanced_components_support<>` call in `GameNode::init_world`.

### `UnitPrefab` resources

Define all unit stats in the Godot editor via `UnitPrefab` resources. These are referenced by name (String) when spawning units via `ActionNode::spawn_units(prefab_name, ...)`.

### Commit messages

Follow the Conventional Commits format (e.g., `feat:`, `fix:`, `refactor:`). Create feature branches from `main`.

### Submodule code style

- The nwfc codebase uses the intentional typo `explaination` (not `explanation`) — keep this spelling for consistency

---

## Adding a new Godot node to the module

1. Create `src/godoctopus/<area>/MyNode.h` and `.cpp` in the `godot` namespace
2. Use `GDCLASS(MyNode, BaseClass)` and define `static void _bind_methods()`
3. Add the `.cpp` to `godoctopus2_sources` in `modules/godoctopus2/SCsub`
4. `#include` the header in `register_types.cpp` and call `ClassDB::register_class<godot::MyNode>()`

## Workflow tips

- Make sure to build using the debug build command to validate your changes.