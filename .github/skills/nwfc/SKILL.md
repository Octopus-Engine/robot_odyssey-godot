---
name: nwfc
description: >
  Reference guide for the nwfc constraint-programming module and its Godot node
  NotWaveFunctionCollapseNode. Use this skill when the user asks to add constraints,
  pickers, or features to the nwfc module, or when writing GDScript that drives
  procedural generation via NotWaveFunctionCollapseNode.
---

# nwfc — Constraint-Programming Solver

> **Despite its name, this is NOT a Wave Function Collapse implementation.**
> It is a general constraint-programming solver used for procedural (grid) generation.
> The README states: *"This is not a wave function collapse lib but a constraint programming solver."*

---

## Module layout

```
modules/godoctopus2/src/nwfc/
├── src/nwfc/src/nwfc/src/
│   ├── variable/
│   │   ├── domain/
│   │   │   ├── BitsetDomain.hh / .cc   ← domain representation
│   │   │   └── Domain.hh               ← type alias (Domain = BitsetDomain)
│   │   └── layout/2d/
│   │       └── GridLayout.hh / .cc     ← 2D grid ↔ flat-index mapping
│   ├── constraint/
│   │   ├── Constraint.hh               ← abstract base
│   │   └── bitset/
│   │       ├── CompatibilityBitset.hh  ← pairwise value incompatibility
│   │       ├── CardinalityBitset.hh    ← min/max count of a value in a variable set
│   │       └── AllDifferentBitset.hh   ← all-different constraint
│   ├── pickers/
│   │   ├── variable/
│   │   │   ├── VariablePicker.hh           ← abstract: which variable to assign next
│   │   │   └── ValueOrientedVariablePicker.hh ← targets a specific value count
│   │   └── value/
│   │       ├── ValuePicker.hh              ← abstract: which value to assign
│   │       └── WeightBasedValuePicker.hh
│   ├── state/
│   │   └── State.hh / .cc              ← solver state + free functions
│   └── utils/log/Log.hh
└── src/nwfc/test/                       ← catch2 unit tests
```

Godot wrapper:
```
modules/godoctopus2/src/godoctopus/nwfc/
├── NotWaveFunctionCollapseNode.h
└── NotWaveFunctionCollapseNode.cpp
```

---

## Core C++ types (`namespace nwfc`)

### `BitsetDomain`
```cpp
struct BitsetDomain {
    std::vector<bool> bits;         // true = value still possible
    std::vector<std::size_t> explaination; // which variable caused each removal
    std::string id;
    std::size_t value;              // assigned value (if decided)
};
```
Key free functions: `remove_value`, `remove_all_but_value`, `assign_value`,
`is_value_in_domain`, `is_decided`, `is_empty`, `restore`, `get_assigned_value`.

`Domain` is just a type alias: `using Domain = BitsetDomain;`

---

### `State`
```cpp
struct State {
    std::vector<Domain> domains;                    // one per variable
    std::vector<bool>   assigned;
    std::vector<std::size_t> rank;                  // assignment order
    std::vector<std::size_t> affectation;
    std::vector<std::unique_ptr<Constraint>> constraints;
    std::list<StateMemento> mementos;               // backtracking stack
    mutable std::mt19937 generator;                 // seeded with 42 by default

    void init();  // call after populating domains
};
```
Solver free functions (all in `State.hh`):

| Function | Description |
|---|---|
| `progress(state, var, val)` | Assign `val` to `var`, propagate all constraints |
| `backtrack(state)` | Undo last assignment |
| `backjump(state)` | Undo to the assignment that caused the conflict |
| `progress_and_backtrack(state, var, val)` | Combined: progress then backtrack on failure |
| `greedy_pick_variable(state)` | Smallest domain first (MRV heuristic) |
| `greedy_pick_value(state, var)` | First available value |
| `random_pick_value(state, var)` | Uniformly random value from domain |
| `is_assigned(state, var)` | Returns whether variable is currently assigned |

---

### `Constraint` (abstract)
```cpp
struct Constraint {
    virtual void propagate(State &state, std::size_t variable_assigned) = 0;
};
```
Constraints are stored in `State::constraints`. `propagate` is called automatically
by `progress` after each assignment.

**Concrete constraints:**

| Class | Constructor / factory | What it does |
|---|---|---|
| `CompatibilityBitset` | `CompatibilityBitset(var, val, incompatibilities)` | When `var` is assigned `val`, removes incompatible values from listed other variables |
| `CardinalityBitset` | `CardinalityBitset::newLowerCardinality(vars, val, lb)` / `newUpperCardinality(vars, val, ub)` | Enforces min/max count of `val` across `vars` |
| `AllDifferentBitset` | — | All variables in the set must take different values |

`GridLayout::create_man_distance_incompatibilty_constraint(layout, distance, value, incompatibilities)`
is a factory that creates a set of `CompatibilityBitset*` for all pairs of cells
within a given Manhattan distance.

---

### `GridLayout`
```cpp
struct GridLayout {
    std::size_t width, height;
    std::size_t get_index(x, y) const;  // (x,y) → flat index
    std::size_t get_x(index) const;
    std::size_t get_y(index) const;
    std::size_t size() const;           // width * height
};
```

---

### `VariablePicker` and `ValuePicker` (abstract)
```cpp
struct VariablePicker {
    virtual bool         is_done(State const &state)           = 0;
    virtual std::size_t  pick(State const &state)              = 0;
    virtual ValuePicker* get_value_picker()                    = 0;
};

struct ValuePicker {
    virtual std::size_t pick(State const &state, std::size_t var) = 0;
};
```

`ValueOrientedVariablePicker(count, value)` — active until `count` variables
are assigned `value`; picks a random unassigned variable that still has `value`
in its domain; pairs with `ConstantValuePicker(value)` which always assigns the
target value.

---

## Godot node: `NotWaveFunctionCollapseNode`

Extends `Node` (non-visual). All state lives in `std::unique_ptr<nwfc::State>` and
`std::unique_ptr<nwfc::GridLayout>` members.

### GDScript workflow

```gdscript
var nwfc = NotWaveFunctionCollapseNode.new()
add_child(nwfc)

# 1. Setup grid (must be called first)
nwfc.grid_setup(domain_size, grid_width, grid_height)
#   domain_size : number of distinct values (e.g. tile types)
#   grid_width  : columns
#   grid_height : rows

# 2. Optional: seed the RNG for deterministic output
nwfc.set_seed(42)

# 3. Add constraints (any combination)
nwfc.add_distance_constraint(distance, value, incompatible_values_array)
#   distance              : Manhattan distance threshold
#   value                 : trigger value index
#   incompatible_values_array : TypedArray[int] of values to exclude nearby

nwfc.add_lower_cardinality(variable_indices_array, value, lower_bound)
nwfc.add_upper_cardinality(variable_indices_array, value, upper_bound)

# NOTE: add_compatibility_constraint() is currently an unimplemented stub — do not use.

# 4. Optional: add pickers to bias generation
nwfc.add_value_oriented_variable_picker(target_count, value)

# 5. Advance the solver one step at a time (returns true when fully assigned)
while not nwfc.advance():
    pass

# 6. Read results row by row
for row in range(grid_height):
    var cells: Array = nwfc.get_row(row)
    # cells[col] == -1 means unassigned (only possible if advance() returned early)
    # cells[col] >= 0  is the assigned value index
```

### Method reference

| Method | Signature | Notes |
|---|---|---|
| `grid_setup` | `(domain_size: int, x: int, y: int)` | **Must be called first.** Resets all state. |
| `set_seed` | `(seed: int)` | Reseeds `mt19937`. Call before `advance()`. |
| `add_distance_constraint` | `(distance: int, value: int, incomp: Array[int])` | Manhattan-distance pairwise incompatibility |
| `add_lower_cardinality` | `(vars: Array[int], value: int, lb: int)` | At least `lb` of `vars` must be assigned `value` |
| `add_upper_cardinality` | `(vars: Array[int], value: int, ub: int)` | At most `ub` of `vars` may be assigned `value` |
| `add_compatibility_constraint` | `(variable, value, affected_var, affected_value)` | **STUB — unimplemented, does nothing** |
| `add_value_oriented_variable_picker` | `(count: int, value: int)` | Bias: assign `value` to `count` variables first |
| `has_pickers` | `() -> bool` | True if any picker is still active |
| `advance` | `() -> bool` | One solver step. Returns `true` when fully assigned. |
| `run` | `()` | **No-op stub.** |
| `get_row` | `(row: int) -> Array[int]` | Returns assigned values for one row (-1 = unassigned) |

---

## Adding a new constraint (C++ guide)

1. Create a new struct in `modules/godoctopus2/src/nwfc/src/nwfc/src/constraint/bitset/`:

```cpp
#pragma once
#include "constraint/Constraint.hh"
#include "state/State.hh"

namespace nwfc {

struct MyConstraint : public Constraint {
    // constructor parameters
    void propagate(State &state, std::size_t variable_assigned) override {
        // Use state.mementos.back() to record domain mutations for backtracking.
        // Call remove_value(domain, val, explaination_var) and push result
        // into memento.domain_mementos so backtrack() can undo it.
    }
};

} // namespace nwfc
```

2. Expose it via `NotWaveFunctionCollapseNode` if needed:
   - Add a method in `NotWaveFunctionCollapseNode.h`
   - Implement in `.cpp`, push with `state->constraints.emplace_back(new MyConstraint(...))`
   - Register with `ClassDB::bind_method` in `_bind_methods()`

---

## Adding a new variable/value picker (C++ guide)

- Subclass `VariablePicker` (and optionally `ValuePicker`).
- Implement `is_done`, `pick`, `get_value_picker`.
- Add an `add_*_picker` method to `NotWaveFunctionCollapseNode`.
- Push to `pickers` list: `pickers.push_back(std::make_unique<MyPicker>(...))`.
- Pickers are consumed front-to-back; `advance()` pops a picker when `is_done` returns true.
