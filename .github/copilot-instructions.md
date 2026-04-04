# Godot Engine – Robot Odyssey fork (godoctopus2)

This is a custom fork of **Godot Engine 4.5.2-rc** that bundles the `godoctopus2` module — an RTS simulation engine (octopus2 + Flecs ECS) integrated with Godot as the renderer and editor. Most new game-logic code lives in `modules/godoctopus2/`.

---

## Build

Build with `scons platform=linuxbsd target=editor debug=yes debug_symbols=yes` exclusively to avoid very long build times.

The built editor binary is expected at:
```
~/dev/robot_odyssey-godot/bin/godot.linuxbsd.editor.x86_64
```

### Export & run scripts (in `scripts/`)

```bash
scripts/export_release_linux.sh   # export release build for Linux
scripts/export_debug.sh           # export debug build
scripts/launch_game.sh            # launch the exported binary
scripts/open_codes.sh             # open VS Code for the module source dirs
```

---

## Linting (Python build scripts only)

```bash
# Lint/format Python files (SConstruct, SCsub, misc scripts)
ruff check .
ruff format .

# Type-check
mypy .

# Spell-check
codespell
```

Config for all three tools is in `pyproject.toml`. `thirdparty/` is excluded everywhere.

---

## Architecture

### Godot engine layer (`core/`, `scene/`, `editor/`, `servers/`, etc.)
Standard upstream Godot 4 source. Avoid modifying unless fixing an engine-level bug.

### `modules/godoctopus2/` — the game module
This is where all Robot Odyssey game logic lives. It bridges Godot nodes with the **octopus2** RTS simulation engine.

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
│   │   ├── nwfc/          # Procedural generation (wave function collapse)
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

---

## Key conventions in `modules/godoctopus2/`

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
The command type is:
```cpp
typedef std::variant<NoOpCommand, MoveCommand, AttackCommand, CastCommand, SetRallyPointCommand> custom_variant;
```
Add new command types here and update all variant visitors.

### `UnitPrefab` resources
Define all unit stats in the Godot editor via `UnitPrefab` resources. These are referenced by name (String) when spawning units via `ActionNode::spawn_units(prefab_name, ...)`.

## Workflow tips

- Make sure to build using the debug build command to validate your changes.
