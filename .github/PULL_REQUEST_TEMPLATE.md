## Description

Provide a clear and concise summary of the changes introduced in this Pull Request.

Fixes # <!-- Issue Number -->
Parent EPIC: # <!-- EPIC Issue Number, e.g. #12, #13, #14 -->

---

## Type of Change

- [ ] `feat`: New feature or algorithm implementation
- [ ] `fix`: Bug fix or resolution of edge case
- [ ] `docs`: Documentation or code comment updates
- [ ] `refactor`: Code quality enhancement or refactoring without behavior change
- [ ] `test`: Unit, integration, or benchmark test addition/update
- [ ] `ci`: CI/CD pipeline or build system configuration change

---

## Technical Highlights & Implementation Details

- Key change 1
- Key change 2
- Memory & thread-safety considerations

---

## Verification & Testing Checklist

- [ ] **Native CTest Suite**: All tests pass (`ctest --output-on-failure` inside `build/`).
- [ ] **AddressSanitizer / UBSan**: No memory leaks or undefined behavior detected (`cmake -DSW_USE_SANITIZER=ON ../native`).
- [ ] **Flutter App & Tests**: All Dart unit/widget tests pass (`flutter test` inside `soundwave_app/`).
- [ ] **Code Formatting & Lints**: Code formatted cleanly (`dart format .`, `flutter analyze`).
- [ ] **Documentation**: Updated relevant developer docs in `docs/` and header Doxygen comments.

---

## Screenshots / Verification Output (If applicable)

```text
Include relevant test execution logs, benchmark metrics, or visual UI screenshots here.
```
