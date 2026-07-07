# Privacy Policy — Feya PDF

**Last updated:** 7 July 2026
**Effective date:** 7 July 2026

> **The short version.** Feya PDF does not collect, store, transmit, sell, or share your personal data. All your PDFs, encryption keys, app-lock credentials, annotations, tags, and reading activity stay on your device. The only outbound network call the App can make is an optional, unauthenticated check of a public GitHub Releases API endpoint — and only in builds distributed outside the Google Play Store.

---

## 1. About the App and the Developer

**Feya PDF** (the "**App**") is a free, open-source PDF reader for Android. The App provides local PDF viewing, annotation, tagging, search, and optional on-device encryption of PDF files. The App does not require a user account, does not run a backend, and does not sync your data to any cloud.

The App is developed and maintained by:

- **Mashal Alfas** (the "**Developer**", "**we**", "**us**")
- **Repository:** <https://github.com/mashalalfas/FeyaPDF>
- **Landing page:** <https://mashalalfas.github.io/FeyaPDF/>
- **Contact (issues only):** <https://github.com/mashalalfas/FeyaPDF/issues>

This Privacy Policy explains what information the App does and does not handle. We have written it in plain language because privacy disclosures should be readable.

---

## 2. Information We Do **Not** Collect

The App **does not** collect, store, transmit, sell, rent, or share any of the following:

- ❌ **User accounts** — there is no sign-up, login, profile, password, or account of any kind.
- ❌ **Personal identifiers** — no name, email, phone number, postal address, date of birth, or contact list.
- ❌ **Device identifiers** — no IMEI, IMSI, Android ID, advertising ID (GAID), MAC address, IP-based device fingerprint, or hardware serial.
- ❌ **Usage analytics** — no Firebase Analytics, Google Analytics, Mixpanel, Amplitude, Flurry, or any other analytics SDK.
- ❌ **Crash or error reports** — no Firebase Crashlytics, Sentry, Bugsnag, or similar. (See Section 8 for the current version and how future changes would be handled.)
- ❌ **PDF content or metadata** — the App does not read, scan, fingerprint, classify, summarise, translate, or transmit the contents or metadata of your PDF files.
- ❌ **Annotations, highlights, tags, or reading history** — these are stored only in app-private local storage.
- ❌ **Location data** — no GPS, no IP-based geolocation lookup, no coarse location.
- ❌ **Cookies or trackers** — the App is not a web browser and does not use cookies or third-party trackers.
- ❌ **Biometric data** — biometric authentication is performed **locally** by Android's `BiometricPrompt` API. Fingerprint, face, or iris data never leaves your device and is not accessible to the App, the Developer, or any third party.
- ❌ **Advertising identifiers** — the App does not serve ads, does not personalise content, and does not read the Google Advertising ID.
- ❌ **In-app purchases or payment data** — the App is free and contains no purchases; no payment SDK is included.

---

## 3. What Is Stored on Your Device

The App stores the following data **exclusively in app-private storage on your device**. None of it is transmitted to the Developer or to any third party.

| Data | Storage location | Purpose |
|------|------------------|---------|
| Encrypted PDF files (`.pdf.enc`) | App-private directory | Encrypted document storage |
| Wrapped decryption keys | Android Keystore (via `flutter_secure_storage`) | Decrypt your documents |
| PIN hash & biometric-unlock passphrase | Android Keystore (via `flutter_secure_storage`) | App lock |
| App settings (theme, sort order, update channel, etc.) | `SharedPreferences` | Personalisation |
| Recent-files list, tags, colour labels | App-local database / JSON files | Reading experience |
| Highlights, per-document view state (last page, etc.) | App-local database | Resume reading and re-find highlights |
| Self-update downloaded APKs (transient) | App cache | Installation before `REQUEST_INSTALL_PACKAGES` flow |

**The App explicitly opts out of OS-level data extraction.** The Android manifest sets `android:allowBackup="false"` and the App's backup and data-extraction rule files are empty. **Your on-device data is not included in Google Drive auto-backups, device-to-device transfer, or any other Android-level data-movement flow.** This is a deliberate privacy choice.

You can erase all on-device data at any time by **uninstalling the App**, or by clearing its data from Android Settings → Apps → Feya PDF → Storage → Clear data.

---

## 4. Encryption and Key Handling

The App's encryption feature is **end-to-end and on-device**:

- **Algorithm:** **AES-256-GCM** (authenticated encryption with associated data), 96-bit random IV per file, 128-bit authentication tag.
- **Key derivation:** **PBKDF2** with a per-file random salt and a high iteration count, deriving a 256-bit key from your PIN.
- **Key storage:** Wrapped keys are stored in the **Android Keystore** (hardware-backed where the device supports it, e.g. StrongBox or TEE) via `flutter_secure_storage`. Plaintext keys exist only briefly in memory while decrypting a document.
- **Key transmission:** **None.** Decryption keys are never sent to the Developer or to any third party.
- **Plaintext handling:** Decrypted PDF bytes are held in memory only for the duration of the current view and are not written to public or shared storage.

Because the Developer has no access to your keys or your PIN, **we cannot decrypt your documents, recover your PIN, or restore access to your files.** Loss of your PIN, or of access to the Android Keystore (e.g. factory reset, lost device, biometric re-enrolment), means **permanent loss of access to encrypted content**. Please make your own backups of important files.

---

## 5. Permissions Requested by the App

The App requests the following Android permissions. Each is the **minimum necessary** to provide a feature, and **no permission is used for behavioural advertising, profiling, or data collection**.

| Permission | Why it is needed | Required? |
|------------|------------------|-----------|
| `READ_EXTERNAL_STORAGE` (Android ≤ 12) | Access PDF files you select through the system file picker on legacy devices | Required only on Android ≤ 12 for opening files in shared storage |
| `WRITE_EXTERNAL_STORAGE` (Android ≤ 12) | Write files you explicitly export to a shared folder | Optional — only used if you save to a shared folder |
| `READ_MEDIA_*` (Android 13+) | Access PDF media in shared storage on modern Android | Granted implicitly via the Photo Picker / Storage Access Framework |
| `USE_BIOMETRIC` | Use fingerprint, face, or iris to unlock the App | **Optional** — only if you enable biometric app lock |
| `USE_FINGERPRINT` (legacy devices) | Legacy biometric API for older devices | **Optional** |
| `REQUEST_INSTALL_PACKAGES` | Install an APK update that you have explicitly chosen to download from GitHub Releases | **Optional** — only used in non-Play Store builds during a self-update |
| `INTERNET` | **(Debug/profile builds only.)** The release build's main manifest does **not** declare this permission. The optional GitHub update check is the only feature that would require it. | N/A in production releases |

The App uses the **Storage Access Framework (SAF)** as its primary way to open and save files, so it does **not** require broad storage permission on modern Android. No `CAMERA`, `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `READ_CONTACTS`, `READ_PHONE_STATE`, `READ_CALL_LOG`, `READ_SMS`, or `READ_CALENDAR` permission is requested.

---

## 6. Third-Party Services

The App contains **no third-party analytics, no advertising SDK, no crash reporter, and no social-login SDK.**

The **only** outbound network request the App can make is:

- **GitHub Releases API**
  - **Endpoint:** `https://api.github.com/repos/mashalalfas/FeyaPDF/releases/latest`
  - **Purpose:** Check whether a newer version is available for self-update
  - **Trigger:** Either (a) you tap "Check for updates" in Settings, or (b) an automatic check on app launch (configurable in Settings)
  - **Data sent:** A standard, **unauthenticated** HTTPS `GET` request. The request includes an `Accept` header set to `application/vnd.github+json` and an `X-GitHub-Api-Version` header. It does **not** include any user identifier, account token, device identifier, file content, or app-state data. GitHub (Microsoft Corporation) will observe your IP address as the source of the request, as is inherent in any internet request.
  - **Data received:** Public release metadata (version string, release notes, download URL, asset size).
  - **Retention:** Subject to GitHub's standard API logging and retention; we have no control over it.
  - **Availability:** **Disabled entirely in Google Play Store builds.** If you install Feya PDF from the Play Store, this network call is never made.

GitHub's privacy practices are governed by GitHub's own privacy statement, available at <https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement>. The Developer is not responsible for GitHub's data-handling practices.

---

## 7. Children's Privacy

The App is **not directed at children under the age of 13**, and the Developer does not knowingly collect personal information from children under 13 (or under the age defined as a "child" by the laws of your country, if that age is higher).

Because the App does not collect personal information from **anyone**, this commitment holds for all users. The App:

- contains no features aimed at children;
- contains no third-party advertising;
- contains no social, chat, or community features;
- does not ask the user to provide an age, name, email, or any other personal detail.

The App is not marketed or listed in any children's category on the Google Play Store. If you believe a child has provided personal information through the App, please open an issue at the contact link in Section 12 and the Developer will investigate — although, as stated, the App has no technical means to receive such information from a child.

---

## 8. Crash Reporting and Future Telemetry

The current version of the App (**1.1.x** at the time of writing) does **not** include any crash reporting, error reporting, or usage telemetry.

If the Developer adds telemetry in a future version, this Privacy Policy will be updated **before** such a feature is enabled, the change will be documented in the release notes, and — if the telemetry involves any personal data — the feature will be **opt-in** or **anonymised** to the maximum extent technically possible.

---

## 9. Legal Bases (GDPR, UAE PDPL, CCPA, and Similar Frameworks)

Although the App does not collect personal data, the Developer lists the legal bases that would apply if any processing were to occur:

- **Performance of a contract** — to provide the App's core functionality (which requires no personal data from you).
- **Legitimate interests** — none are currently pursued via the App.
- **Consent** — not required for any current feature.
- **Legal obligation** — none.

If you are in the European Economic Area, the United Kingdom, the United Arab Emirates (under Federal Decree-Law No. 45 of 2021 on the Protection of Personal Data), the State of California (under the CCPA/CPRA), Brazil (under the LGPD), or any other jurisdiction with personal-data laws, **the App places no obligations on you and creates no compliance risks for you arising from your use of it**, because the Developer does not process your personal data through the App.

Data-subject rights (access, deletion, portability, objection, restriction, opt-out of sale or sharing) are moot in the absence of processing, but if you have any concern or request, please contact the Developer via the channel in Section 12.

---

## 10. International Data Transfers

Because the App does not collect or transmit your personal data, **there are no international data transfers of your personal data.**

The only outbound network call the App can make — the GitHub Releases API check — does not include personal data. The IP address that GitHub observes is governed by GitHub's privacy statement, not by this one.

---

## 11. Security

The Developer takes the security of the App seriously. Measures include:

- All app-private data is held in app-private storage, isolated from other apps by the Android sandbox.
- Encryption keys are held inside the **Android Keystore** (hardware-backed where available).
- `android:allowBackup="false"` and empty backup and data-extraction rules prevent OS-level leakage.
- The release Android manifest does **not** declare the `INTERNET` permission, and a `network_security_config.xml` is applied that disallows cleartext HTTP traffic.
- The repository is published for transparency so the community can audit the code.

No system is perfectly secure. The Developer makes no warranty of absolute security (see the EULA, Section 6). If you discover a security vulnerability, please report it privately through the GitHub issue tracker with the "**security**" label, or via the contact method in Section 12.

---

## 12. Changes to this Policy

The Developer may update this Privacy Policy from time to time. The "**Last updated**" date at the top of this document will reflect the most recent change. Material changes will, where reasonable, be communicated:

- In the release notes of the next App version, and
- Via a notice in the project repository at <https://github.com/mashalalfas/FeyaPDF>.

Continued use of the App after the effective date of a revised Privacy Policy indicates that you have read and accepted the updated policy. If you do not agree, please **uninstall the App** and stop using it.

A history of significant changes will be summarised at the bottom of this document.

---

## 13. Contact

This is a community-supported, open-source project. The best way to reach the Developer is via the public issue tracker. The Developer aims to respond to privacy-relevant issues within a reasonable time, but makes **no service-level commitment**.

- **Issue tracker / contact:** <https://github.com/mashalalfas/FeyaPDF/issues>
- **Repository:** <https://github.com/mashalalfas/FeyaPDF>
- **Landing page:** <https://mashalalfas.github.io/FeyaPDF/>
- **Creator:** Mashal Alfas

---

## 14. Effective Date and Version

This Privacy Policy is effective as of **7 July 2026** and applies to all versions of Feya PDF from **1.1.4** onwards. Earlier versions, if any, are covered by the Privacy Policy shipped with their respective release.

---

## 15. Plain-Language Summary

For anyone who just wants the gist:

- Feya PDF is a PDF reader that **keeps everything on your phone**.
- The Developer **does not run a server** that receives your data.
- The Developer **does not know who you are**, because you never tell the App.
- The Developer **cannot see your files**, because they never leave your device.
- Your **encryption keys never leave the Android Keystore**.
- The **only** network call the App can make is an optional check for updates on GitHub, and **even that is disabled in Play Store builds**.
- There is **no analytics, no advertising, no crash reporting, and no account** — in the current version or in any version you can verify by reading the open-source code.

If anything in this Privacy Policy is unclear, please open an issue and ask.

---

*This document is provided in English. Translations, if any, are for convenience only; in case of conflict, the English version prevails.*
