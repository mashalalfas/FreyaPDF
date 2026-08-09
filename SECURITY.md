# Security Policy

Feya PDF is an offline, privacy-first PDF reader. It stores encrypted documents
and secrets (encryption passphrases, app-lock PIN, remembered PDF passwords),
so security is a priority.

## Reporting a vulnerability

**Please report vulnerabilities privately — do not open a public issue.**

- Email: <feya.security@example.com>
- Subject prefix: `[FeyaPDF Security]`

Please include:

- The affected version (from **Settings → About → Commit** or `version` in `pubspec.yaml`)
- A description of the issue and steps to reproduce
- Any relevant logs or screenshots (without real user data)
- Your suggested fix, if you have one

You should receive a response within **7 days**. Please allow time for a fix
before public disclosure.

## Security principles

- **No data collection.** The app has no analytics, no accounts, and no
  backend. Your files never leave the device.
- **Secrets live only in platform secure storage** (`flutter_secure_storage`),
  never in `SharedPreferences`, backups, logs, or exported settings.
- **Encryption at rest.** `.pdf.enc` files use AES-256-GCM with PBKDF2-derived
  keys.
- **Memory safety.** Large documents are processed with bounded memory; the PDF
  viewer and search never load an entire document into the main isolate.

## Supported versions

| Version | Status |
|---|---|
| 1.2.x | Supported — apply fixes |
| < 1.2 | Not supported |

## Scope

In scope: the Feya PDF Android app and its handling of encrypted files,
passphrases, PIN/biometric auth, and remembered PDF passwords.

Out of scope: third-party dependencies (report those to their respective
maintainers), and issues caused by modified/unofficial builds.
