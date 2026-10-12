# Contributing to SnappySnag Flutter SDK

Thank you for your interest in contributing to SnappySnag! We welcome bug fixes, documentation improvements, feature enhancements, and community feedback.

---

## Code of Conduct

We are committed to providing a welcoming, inclusive, and harassment-free environment for everyone. Please be respectful and constructive in all interactions.

---

## How to Contribute

### 1. Reporting Bugs & Suggesting Features
- Before creating a new issue, search existing [Issues](https://github.com/snappysnag/snappy_snag_flutter/issues) to see if it has already been reported.
- To file a bug, use the **Bug Report** template and include steps to reproduce, device/OS details, and Flutter versions.
- To propose an enhancement, use the **Feature Request** template and explain the motivation and proposed design.

### 2. Security Vulnerabilities
- If you discover a security-sensitive issue or vulnerability, **please do not open a public issue**.
- Follow our responsible disclosure guidelines outlined in [SECURITY.md](SECURITY.md) or email us directly at **security@snappysnag.com**.

### 3. Submitting Pull Requests (PR)
1. **Fork** the repository and create a new feature/fix branch:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. **Install dependencies**:
   ```bash
   flutter pub get
   ```
3. **Write tests**:
   - Make sure any new functionality or bug fix is accompanied by unit or widget tests under `test/`.
4. **Ensure quality checks pass**:
   ```bash
   flutter analyze
   flutter test
   ```
5. **Commit your changes**:
   - Use clear, descriptive commit messages.
6. **Open a Pull Request**:
   - Provide a clear summary of your changes, reference any related issue numbers (e.g. `Fixes #12`), and confirm that CI passes.

---

## Coding Guidelines

- Adhere to official Dart style conventions (`flutter analyze` should yield 0 warnings/errors).
- Protect user privacy and data security: ensure no PII or sensitive developer keys are inadvertently captured or logged.
- Keep the SDK lightweight, performant, and backwards-compatible with supported Flutter/Dart versions.

Thank you for helping make SnappySnag better!
