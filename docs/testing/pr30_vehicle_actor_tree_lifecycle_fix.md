# PR #30 VehicleActor lifecycle regression check

This regression check covers the Godot error:

```text
Condition "!is_inside_tree()" is true. Returning: Transform3D()
```

## Cause

`VehicleActor.configure()` builds detached candidate actors during vehicle batch preparation. Calling `sync_from_state()` at that time attempted to assign `global_position` and `global_basis` before the actor entered the scene tree.

## Fix

- `VehicleActor.sync_from_state()` returns without touching global transforms while detached.
- `VehicleActor._ready()` applies the pending runtime transform after tree entry.
- `Scene01VehicleManager` keeps its post-attachment synchronization, which remains valid for actors attached to an active tree.

## Verification

Run:

```powershell
godot --headless --path . --script res://tests/vehicles/vehicle_actor_tree_lifecycle_smoke_test.gd
godot --headless --path . --script res://tests/scene_01/scene_01_vehicle_smoke_test.gd
godot --headless --path . --script res://tests/scene_01/vehicle_batch_preparation_smoke_test.gd
godot --headless --path . --script res://tests/scene_01/scene_01_grid_smoke_test.gd
godot --headless --path . --script res://tests/scene_01/scene_01_field_interaction_smoke_test.gd
```

Expected: the tests reach their success markers and no `!is_inside_tree()` / `get_global_transform` errors appear.
