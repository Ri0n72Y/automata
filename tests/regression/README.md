# Regression suite

Tests in this directory run on every pull request and every push to `main`.

A test belongs here only when it protects a **confirmed regression**: behavior that was
already green/stable and was later broken again by work on another change.

Initial feature-development failures, acceptance walkthroughs, broad feature contracts,
and tests that only caught their own fixture/API drift belong in the manually triggered
Full Suite instead.

Current evidence:

- `scene_01_tray_reset_metadata_regression_test.gd`: Godot CI #396 caught stationary
  Transport tray interaction metadata disappearing after Reset during later UI/availability
  work; the production fix landed immediately afterward and CI #397 passed.
- `scene_01_move_readiness_side_effect_regression_test.gd`: Godot CI #400 caught later
  availability/readiness work corrupting the established MoveTo capability/lifecycle
  boundary; the follow-up readiness side-effect fix passed in CI #401.
