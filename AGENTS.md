# Zigbpe Agent Instructions

This file provides instructions for AI agents working on this Zig codebase.

## Program purpose
This is a Zig implementation of the BPE algorithm for tokenizing text for an LLM.

## Zig info 
We require and use Zig version 0.14.1

Please bear in mind the version when checking online documentation and answering the users question.

## Build, Lint, and Test Commands

Note there are no tests yet.

- **Build:** `zig build`
- **Run:** `zig build run -- ./data/taylorswift.txt`
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
- **Error Handling:** Use `try` and `catch` for functions that can fail. Use `defer` for cleanup.
- **Memory Management:** Use allocators explicitly. Free memory with `defer` when appropriate.
- **Comptime:** Use `comptime` for compile-time operations and type-level programming.
- **Comments:** Use `//` for single-line comments. Add comments to explain complex logic, not to restate what the code does.
