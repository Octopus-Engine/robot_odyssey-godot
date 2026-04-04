---
name: godot-node
description: >
  Step-by-step guide for adding a new C++ Godot Node class to the godoctopus2 module.
  Use this skill whenever the user asks to create a new Godot node, scene node, or Node2D
  in the godoctopus2 module of this repository.
---

# Adding a New Godot Node to godoctopus2

This skill covers the full process for creating a new C++ Godot node class inside the
`modules/godoctopus2` module. Follow every step in order and verify the build at the end.

---

## Step 1 — Determine the category and base class

- **Where does the node live?** Choose or create a subdirectory under
  `modules/godoctopus2/src/godoctopus/<category>/`.
  Examples: `triangulation/`, `game/`, `command/`, `pickable/`, `health_bar/`.
- **Which Godot base class?**
  - `Node2D` — for nodes that need 2D rendering (`_draw`, `queue_redraw`).
    Include: `"scene/2d/node_2d.h"`
  - `Node` — for non-visual nodes.
    Include: `"scene/main/node.h"`

---

## Step 2 — Create the header file

**Path:** `modules/godoctopus2/src/godoctopus/<category>/<ClassName>.h`

Template:

```cpp
#pragma once

#include "scene/2d/node_2d.h"          // or "scene/main/node.h" for non-visual

// Include any C++ engine headers needed, e.g.:
// #include "octopus/some/Header.hh"

namespace godot {

class ClassName : public Node2D {      // or Node
    GDCLASS(ClassName, Node2D)         // must match the class and its parent

    // ── Public GDScript-callable methods ────────────────────────────────────
    void some_method(Vector2 const &arg);
    int  some_query() const;

    static void _bind_methods();

protected:
    void _notification(int p_notification);

private:
    void _draw();                       // Only for Node2D nodes

    // Private helpers and data members
};

} // namespace godot
```

**Key rules:**
- Always wrap in `namespace godot {}`.
- `GDCLASS(ClassName, BaseClass)` must be the first line inside the class body.
- `_bind_methods()` must be `static void` and declared in the class.
- `_notification(int)` must be `protected`.
- `_draw()` is private and only needed for nodes that do custom rendering.

---

## Step 3 — Create the implementation file

**Path:** `modules/godoctopus2/src/godoctopus/<category>/<ClassName>.cpp`

Template:

```cpp
#include "ClassName.h"

namespace godot {

// ── Drawing (Node2D only) ────────────────────────────────────────────────────

void ClassName::_draw() {
    // Use inherited CanvasItem drawing methods:
    //   draw_line(Vector2 from, Vector2 to, Color color)
    //   draw_circle(Vector2 center, float radius, Color color)
    //   draw_polygon(PackedVector2Array points, PackedColorArray colors)
    //
    // Convert Fixed-point octopus coordinates to double for Godot:
    //   Vector2(some_fixed.to_double(), other_fixed.to_double())
}

// ── Public methods ───────────────────────────────────────────────────────────

void ClassName::some_method(Vector2 const &arg) {
    // ... implement ...
    queue_redraw();  // call after any state change that should update the display
}

int ClassName::some_query() const {
    return 0;
}

// ── Godot binding ────────────────────────────────────────────────────────────

void ClassName::_bind_methods() {
    ClassDB::bind_method(D_METHOD("some_method", "arg"), &ClassName::some_method);
    ClassDB::bind_method(D_METHOD("some_query"),         &ClassName::some_query);

    // For node-path properties use the SET_GET_NODE_PATH / BIND_NODE_PATH macros.
    // For simple typed properties use ADD_OBJECT_PROP or SET_GET_PARAM + explicit bindings.
}

void ClassName::_notification(int p_notification) {
    switch (p_notification) {
        case NOTIFICATION_DRAW: {
            _draw();          // Only needed for Node2D
        } break;
        case NOTIFICATION_READY: {
            set_process(false);  // Change to true if _process is needed
        } break;
        case NOTIFICATION_PROCESS: {
            // _process(get_process_delta_time());  // Uncomment if needed
        } break;
    }
}

} // namespace godot
```

**Key rules:**
- Every method that modifies visible state must call `queue_redraw()` at the end.
- `_notification` is the central dispatcher — do NOT override `_ready`, `_process`, or `_draw` as virtual functions; use `NOTIFICATION_*` constants instead.
- Fixed-point coordinates (`octopus::Fixed`) convert to `double` via `.to_double()`.

---

## Step 4 — Add the source file to the build system

**File:** `modules/godoctopus2/SCsub`

Find the `godoctopus2_sources` list and add the new `.cpp` file next to related files:

```python
godoctopus2_sources = [
    # ... existing entries ...
    "./src/godoctopus/<category>/ExistingNode.cpp",
    "./src/godoctopus/<category>/ClassName.cpp",   # ← add this line
    # ...
]
```

---

## Step 5 — Register the class with Godot

**File:** `modules/godoctopus2/register_types.cpp`

1. Add the include near the other `godoctopus` includes at the top:

```cpp
#include "godoctopus/<category>/ClassName.h"
```

2. Register the class inside `initialize_godoctopus2_module()`, in the `MODULE_INITIALIZATION_LEVEL_SCENE` block:

```cpp
ClassDB::register_class<godot::ClassName>();
```

Place it near other registrations of the same category for readability.

---

## Step 6 — Verify the build

Run the following from the repository root:

```bash
scons platform=linuxbsd target=editor debug=yes debug_symbols=yes
```

- A successful build confirms all headers, includes, and SCsub entries are correct.
- Fix any compiler errors before considering the task done.

---

## Quick-reference: conventions

| Topic | Convention |
|---|---|
| Godot wrapper namespace | `namespace godot {}` |
| Engine logic namespace | `namespace octopus {}` |
| Class macro | `GDCLASS(ClassName, BaseClass)` |
| Fixed-point → Godot | `Fixed::to_double()` → `double` → `Vector2(x, y)` |
| Trigger redraw | `queue_redraw()` after every state mutation |
| Node-path property | `SET_GET_NODE_PATH` in header, `BIND_NODE_PATH` in `_bind_methods` |
| Simple typed property | `SET_GET_PARAM` + `ADD_OBJECT_PROP` |
| Build command | `scons platform=linuxbsd target=editor` |
| Header extension | `.h` (not `.hpp`) for Godot wrapper files |
