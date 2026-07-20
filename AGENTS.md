# SOUNDWAVE / Ultrasonic PHY Layer - Agent Guidelines & Workflow Rules

This document defines the standard operating procedures and development workflow for AI coding agents working on the SOUNDWAVE codebase.

---

## 1. Development & Issue Workflow

When picking up or assigned an issue, follow this systematic workflow:

1. **Issue Discovery & Selection**:
   - Check open GitHub issues using `gh issue list`.
   - Pick the next sequential sub-issue in the DSP Core or UI roadmap.

2. **Branching Naming Convention**:
   - Always create a separate feature branch for each issue:
     ```bash
     git checkout -b feat/<topic>-issue-<issue_number>
     ```

3. **Implementation Standards**:
   - Refer to mathematical equations in `docs/MATHEMATICAL_MODEL.md`.
   - Ensure clean C99 code, pre-computed lookup tables for field operations, and zero memory leaks (ASan/UBSan clean).
   - Preserve comments, existing header signatures, and module contracts.

4. **Testing & Build Verification**:
   - Always add comprehensive unit tests in `native/tests/test_<module>.c`.
   - Validate build and run all test targets via CMake & CTest:
     ```bash
     mkdir -p build && cd build && cmake .. && make && ctest --output-on-failure
     ```
   - Ensure 100% of tests pass before committing.

5. **Commit, Push, Issue Closure & Pull Request**:
   - Use conventional commit format: `feat(<scope>): <description> (#<issue_number>)`.
   - Push branch to origin: `git push -u origin <branch-name>`.
   - Close resolved GitHub issue: `gh issue close <issue_number> --comment "..."`.
   - Create Pull Request automatically via GitHub CLI:
     ```bash
     gh pr create --title "feat(<scope>): <description> (#<issue_number>)" --body "..."
     ```

---

## 2. Codebase Structure

- `native/include/soundwave/`: C header definitions for DSP modules.
- `native/src/`: Core implementation files (`crc`, `rs`, `css`, `ofdm`, `sync`, `cfo`, `chanest`, `equalizer`, `audio`, `packet`, `api`).
- `native/tests/`: CTest unit test executables.
- `docs/`: Technical specifications, mathematical formulas, PRD, and roadmap.

---

## 3. Memory Persistence (mem0 MCP)

- Every agent working on this codebase MUST persist significant changes, feature completions, bug fixes, design decisions, and PR links to the `mem0` memory server using `add_memory`.
- At the start of a task or session, agents should query `mem0` via `search_memories` or `get_memories` to retrieve relevant project context, past decisions, and guidelines.
