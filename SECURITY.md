# Security Policy

## Supported Versions

We actively provide security patches, updates, and maintenance for the following versions of `snappy_snag`:

| Version | Supported          |
| ------- | ------------------ |
| 1.1.x   | :white_check_mark: |
| 1.0.x   | :white_check_mark: |
| < 1.0.0 | :x:                |

---

## On-Device Privacy & PII Protection Architecture

SnappySnag is engineered with a **zero-trust, privacy-first architecture** to guarantee that sensitive personal information never leaves the client device in plaintext:

1. **Automatic On-Device PII Masking (`findSensitiveFieldBounds`)**:
   - The Flutter SDK inspects active elements before transmission.
   - Any sensitive input fields (`TextField`, `EditableText`), profile avatars (`CircleAvatar`), and text matching regular expressions for **emails, phone numbers, credit card numbers, or postal codes** are automatically localized on the device.
   - Screen coordinates for sensitive areas can be blacked out or masked before sending.
2. **Widget Tree Traversal Safety**:
   - Passwords and confidential inputs are sanitized and never dumped in plaintext.
   - Framework internal classes (e.g., Flutter internal layout nodes) and application state stores (Provider, Riverpod internals) are filtered on-device to prevent state or token leakage.
3. **Local Storage Transparency**:
   - `SharedPreferences` is strictly limited to an anonymous random UUID for rate-limiting and a single temporary user-confirmed draft.
   - Sensitive credentials and auth tokens are **never** persisted to disk and reside exclusively in volatile app memory.
4. **Strict Write-Only Client API Key (Zero Read Surface)**:
   - Client SDK API keys (`snag_live_...`) operate on a strict **Write-Only (Publishable Key)** model.
   - The client API key has zero read (`SELECT`) permissions. Even if an application binary is reverse-engineered and the API key is extracted, no existing tickets, screenshots, or user feedback can ever be queried or retrieved from the server.
5. **Bundle ID & Package Name Verification**:
   - API keys are locked to your registered bundle identifier (e.g., `com.example.app`), neutralizing unauthorized submission attempts from third-party clients.

---

## Reporting a Vulnerability

We deeply appreciate the efforts of security researchers and developers in keeping our community and ecosystem safe.

If you discover a security vulnerability or privacy concern within the `snappy_snag` SDK, please **do NOT report it via public GitHub Issues**. Instead, follow these steps:

1. **Contact Us via Email**:
   - Send details to **[support@snappysnag.com](mailto:support@snappysnag.com)**.
   - Include a detailed description of the vulnerability, steps to reproduce, relevant code snippets, and your assessment of its severity.
2. **Response Timeline**:
   - **Initial Acknowledgment**: Within **48 hours**, we will acknowledge receipt of your report.
   - **Investigation & Assessment**: Within **5 business days**, our engineering team will provide a preliminary validation and status update.
   - **Remediation & Patch**: Once verified, we will develop a patch, test it across supported platforms, and publish a patch release via `pub.dev`.
3. **Coordinated Disclosure**:
   - We follow responsible disclosure guidelines. We ask that you give us adequate time to release a patch before disclosing details publicly.
