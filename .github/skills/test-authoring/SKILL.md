---
name: test-authoring
description: >
  Step-by-step guide for writing tests for new runes, skills, and gameplay features in the godoctopus2 module. Use this skill when authoring tests gameplay behaviors.
---
# Skill: Godoctopus2 Test Authoring

## Overview
Step-by-step guide for writing tests for new runes, skills, and gameplay features in the godoctopus2 module. Use this skill when authoring tests for rune effects, stat modifications, and conditional gameplay behaviors.

## Reference Test
- **Primary Example**: `test_gamenode_conditional_armor_buff_low_life_tier1`
  - Location: `modules/godoctopus2/src/testing/ConditionalLowLifeBuffRunes.test.cpp:38-81`
  - Registration: `modules/godoctopus2/tests/test_gamenode_basic.h:40-42`

---

## Part 1: Test Infrastructure Setup

### 1.1 Create Test Files

Create two files in `modules/godoctopus2/src/testing/`:

**`YourFeature.test.h`:**
```cpp
#pragma once

void test_gamenode_your_feature();
void test_gamenode_your_feature_edge_case();  // Add more as needed
```

**`YourFeature.test.cpp`:**
- Include Godot headers and test framework
- Define `GameNodeTestContextWithCustomPrefab` struct (copy from existing test files)
- Implement all test functions

### 1.2 GameNodeTestContextWithCustomPrefab Helper Struct

This struct is the foundation for all tests. Copy this into your `.cpp` file:

```cpp
struct GameNodeTestContextWithCustomPrefab {
    godot::GameNode *game_node = nullptr;
    godot::ActionNode *action_node = nullptr;
    godot::InfoProxyNode *proxy_node = nullptr;

    GameNodeTestContextWithCustomPrefab(Ref<godot::UnitPrefab> custom_prefab) {
        game_node = memnew(godot::GameNode);
        game_node->set_name("GameNode");
        game_node->get_unit_prefabs().push_back(custom_prefab);

        action_node = memnew(godot::ActionNode);
        action_node->set_ref_game_node(NodePath("/root/GameNode"));
        game_node->add_child(action_node);

        proxy_node = memnew(godot::InfoProxyNode);
        proxy_node->set_ref_game_node(NodePath("/root/GameNode"));
        proxy_node->set_refresh_tick(1);
        game_node->add_child(proxy_node);

        SceneTree::get_singleton()->get_root()->add_child(game_node);
        game_node->init_from_level(Dictionary());
    }

    ~GameNodeTestContextWithCustomPrefab() {}
};
```

---

## Part 2: Writing a Test Function

### 2.1 Create UnitPrefab (Base Stats)

```cpp
void test_gamenode_my_rune() {
    auto prefab = Ref<godot::UnitPrefab>(memnew(godot::UnitPrefab));
    prefab->set_prefab_name("testunit");
    prefab->set_hitpoint(100);          // Max HP
    prefab->set_armor(0);               // Base armor
    prefab->set_damage_x10(50);         // Damage (x10 format: 5.0)
    prefab->set_reload_x10(100);        // Reload (x10 format: 10.0)
    prefab->set_range_x10(30);          // Range (x10 format: 3.0)
    prefab->set_special_x10(100);       // Special stat (used for rune scaling)
    prefab->set_windup_x10(5);          // Attack windup
    // ... set any other relevant stats
```

**Key Stats (x10 Format):**
- `set_*_x10()` — All float-like stats use integer x10 format for determinism
- `set_prefab_name()` — Used when spawning with `spawn_units_in_group(name, ...)`
- `set_attack_enabled()` — Set to `false` if unit shouldn't auto-attack

### 2.2 Setup Test Context

```cpp
    GameNodeTestContextWithCustomPrefab context(prefab);
    StringName unit_name = "testunit";
```

### 2.3 Spawn Unit(s)

```cpp
    Ref<godot::EntityGroup> group = memnew(godot::EntityGroup);
    context.action_node->spawn_units_in_group(
        unit_name,          // Unit name (from prefab)
        Vector2(100, 100),  // Position
        0,                  // Team ID (0 or 1)
        1,                  // Count
        group               // Output group
    );
    context.game_node->tick();  // CRITICAL: Always tick after spawning
```

### 2.4 Apply Rune/Skill

```cpp
    context.action_node->mod_rune(
        "testunit",              // Unit name
        "MyRuneName",            // Rune class name (matches C++ class)
        0,                       // Rune slot index
        1,                       // Rune level
        true                     // true=add, false=remove
    );
    context.game_node->tick();  // CRITICAL: Always tick after mod_rune
```

### 2.5 Verify Effect (Read Stats)

```cpp
    double armor_value = Ref<godot::InfoProxyResource>(
        context.proxy_node->get_proxy_from_group(group)[0]
    )->get_armor();

    CHECK(armor_value == expected_value);
```

**Available Stat Methods:**
| Method | Returns | Format |
|--------|---------|--------|
| `get_armor()` | Armor value | integer |
| `get_damage()` | Damage (x10) | integer |
| `get_reload_time()` | Reload in seconds | double |
| `get_hp()` | Current hit points | double |
| `get_team()` | Team ID | integer (0 or 1) |

---

## Part 3: Testing Conditional Effects (e.g., Buffs at Low HP)

### Pattern for Conditional Runes

1. **Apply rune, verify effect is OFF at base state**
```cpp
    context.action_node->mod_rune("testunit", "ConditionalBuffRune", 0, 1, true);
    context.game_node->tick();

    double stat = Ref<godot::InfoProxyResource>(
        context.proxy_node->get_proxy_from_group(group)[0]
    )->get_armor();
    CHECK(stat == 0);  // Effect should be OFF initially
```

2. **Manually mutate ECS component to trigger condition**
```cpp
    // Trigger condition (e.g., set HP to 10% to activate "low life" buff)
    group->get_entities()[0].set<octopus::HitPoint>({10});
    context.game_node->tick();  // Let systems react
```

3. **Verify effect is ON**
```cpp
    stat = Ref<godot::InfoProxyResource>(
        context.proxy_node->get_proxy_from_group(group)[0]
    )->get_armor();
    CHECK(stat == expected_buffed_value);  // Effect should be ON
```

4. **Restore condition, verify effect is OFF again**
```cpp
    group->get_entities()[0].set<octopus::HitPoint>({100});  // Restore to high HP
    context.game_node->tick();

    stat = Ref<godot::InfoProxyResource>(
        context.proxy_node->get_proxy_from_group(group)[0]
    )->get_armor();
    CHECK(stat == 0);  // Effect should be OFF
```

### Direct Entity Component Mutation

For testing state-dependent runes, access flecs components directly:

```cpp
auto entities = group->get_entities();
entities[0].set<octopus::HitPoint>({new_hp_value});
entities[0].set<octopus::Armor>({new_armor_value});
entities[0].set<octopus::DamageX10>({new_damage_x10_value});
```

---

## Part 4: Test Registration

### 4.1 Add #include to test_gamenode_basic.h

Open `modules/godoctopus2/tests/test_gamenode_basic.h` and add:

```cpp
#include "testing/YourFeature.test.h"
```

### 4.2 Add TEST_CASE

Add a test case entry in the same file:

```cpp
TEST_CASE("[SceneTree][Node][Editor][godoctopus2] GameNode My Rune Feature") {
    test_gamenode_my_rune();
}
```

**Naming convention:** `[SceneTree][Node][Editor][godoctopus2] GameNode <Description>`

### 4.3 Update SCsub

Edit `modules/godoctopus2/SCsub` and add your `.cpp` to the `godoctopus2_sources` list:

```python
godoctopus2_sources = [
    # ... existing files ...
    "src/testing/YourFeature.test.cpp",
]
```

---

## Part 5: Running Tests

### Run All Tests
**Linux:**
```bash
./bin/godot.linuxbsd.editor.x86_64 --headless --test --force-colors
```

**Windows:**
```cmd
bin\godot.windows.editor.x86_64.exe --headless --test --force-colors
```

### Run Specific Test
```bash
# Filter by test name
bin/godot.linuxbsd.editor.x86_64 --headless --test --force-colors 2>&1 | grep "My Rune"
```

### Rebuild Before Testing
```bash
# Linux
scons platform=linuxbsd target=editor debug=yes debug_symbols=yes tests=yes

# Windows
scons target=editor tests=yes
```

---

## Complete Example Test

```cpp
#include "tests/test_macros.h"
#include "scene/main/node.h"
#include "scene/main/window.h"
#include "godoctopus/game/GameNode.h"
#include "godoctopus/action/ActionNode.h"
#include "godoctopus/proxy/InfoProxyNode.h"
#include "testing/Example.test.h"

struct GameNodeTestContextWithCustomPrefab {
    // ... (copy from above or existing test file)
};

void test_gamenode_example_rune() {
    // 1. Create prefab
    auto prefab = Ref<godot::UnitPrefab>(memnew(godot::UnitPrefab));
    prefab->set_prefab_name("testunit");
    prefab->set_hitpoint(100);
    prefab->set_armor(0);

    // 2. Setup context
    GameNodeTestContextWithCustomPrefab context(prefab);

    // 3. Spawn unit
    Ref<godot::EntityGroup> group = memnew(godot::EntityGroup);
    context.action_node->spawn_units_in_group("testunit", Vector2(0, 0), 0, 1, group);
    context.game_node->tick();

    // 4. Apply rune
    context.action_node->mod_rune("testunit", "ExampleRune", 0, 1, true);
    context.game_node->tick();

    // 5. Verify effect
    double armor = Ref<godot::InfoProxyResource>(
        context.proxy_node->get_proxy_from_group(group)[0]
    )->get_armor();

    CHECK(armor == 5);  // Expected value
}
```

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Stats not updating after `mod_rune()` | Ensure `context.game_node->tick()` is called after rune application |
| InfoProxyNode returns stale data | Check `set_refresh_tick(1)` is set in context setup |
| Rune not found error | Verify rune class name matches registered C++ class exactly |
| Entity not in group | Check `spawn_units_in_group()` is called with output group reference |
| Test doesn't compile | Verify `.cpp` is added to `godoctopus2_sources` in SCsub |

---

## Advanced: Multi-Unit Testing

Testing rune interactions with multiple units:

```cpp
Ref<godot::EntityGroup> team0_group = memnew(godot::EntityGroup);
Ref<godot::EntityGroup> team1_group = memnew(godot::EntityGroup);

// Spawn team 0
context.action_node->spawn_units_in_group("unit", Vector2(100, 100), 0, 2, team0_group);

// Spawn team 1
context.action_node->spawn_units_in_group("unit", Vector2(110, 100), 1, 1, team1_group);

context.game_node->tick();

// Apply rune to team 0 unit
context.action_node->mod_rune("unit", "DamageBuff", 0, 1, true);
context.game_node->tick();

// Verify: team 0 has buff, team 1 doesn't
double team0_damage = Ref<godot::InfoProxyResource>(
    context.proxy_node->get_proxy_from_group(team0_group)[0]
)->get_damage();
double team1_damage = Ref<godot::InfoProxyResource>(
    context.proxy_node->get_proxy_from_group(team1_group)[0]
)->get_damage();

CHECK(team0_damage > team1_damage);
```

---

## Key Takeaways

1. **Always tick after state changes** — `context.game_node->tick()` after spawn, rune apply, or entity mutation
2. **Use x10 format for floats** — `set_reload_x10(100)` = 10.0 seconds
3. **Test conditionals in 3 phases** — verify OFF → apply condition → verify ON → restore → verify OFF
4. **Read stats via InfoProxyNode** — it bridges simulation to Godot thread safely
5. **Register in two places** — add `.h` include and `TEST_CASE` to test_gamenode_basic.h, add `.cpp` to SCsub

