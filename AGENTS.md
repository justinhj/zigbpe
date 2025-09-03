# Zigbpe Agent Instructions

This file provides instructions for AI agents working on this Zig codebase.

## Build, Lint, and Test Commands

- **Build:** `zig build`
- **Run:** `zig build run`
- **Test:** `zig build test`
- **Run a single test:** `zig build test --test-filter "your test name"`
- **Format/Lint:** `zig fmt .` (run from the root directory)

## Code Style Guidelines

- **Formatting:** All code must be formatted with `zig fmt`.
- **Imports:** Group standard library imports first, then third-party imports.
- **Types:** Add explicit types to all variable and function declarations.
- **Naming Conventions:**
  - `PascalCase` for types (structs, enums, unions).
  - `snake_case` for variables and functions.
  - `UPPER_SNAKE_CASE` for constants.
- **Error Handling:** Use `try` and `catch` for functions that can fail. Avoid returning nullable pointers for error conditions.
- **Comments:** Use `//` for single-line comments. Add comments to explain complex logic, not to restate what the code does.
