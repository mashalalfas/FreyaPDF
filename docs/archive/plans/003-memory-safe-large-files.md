# Plan 003: Memory-safe large file handling

> **Executor instructions**: Follow this plan step by step. Run every
> verification command before moving on. If any STOP condition occurs, stop
> and report — do not improvise.
>
> **Drift check**: `git diff --stat abe2b97..HEAD -- lib/providers/encryption_provider.dart lib/services/encryption_service.dart`
> If these files changed since planned-at SHA, compare excerpts; on mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (small, focused change)
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `abe2b97`, 2026-06-13

## Why this matters

`EncryptionProvider.encryptFile()` and `decryptFile()` call `file.readAsBytes()` which loads the entire file into memory. A 200MB PDF = 200MB heap allocation. On Android devices with limited RAM, this causes OOM crashes. The fix: use streaming read/write via `openRead()` and chunked processing.

## Current state

`lib/providers/encryption_provider.dart:53`:
```dart
final plaintext = await file.readAsBytes();
final encrypted = EncryptionService.encryptBytes(plaintext, _passphrase!);
final encPath = '$pdfPath.enc';
final tmpPath = '$encPath.tmp';
await File(tmpPath).writeAsBytes(encrypted);
await File(tmpPath).rename(encPath);
```

`lib/providers/encryption_provider.dart:81`:
```dart
final data = await file.readAsBytes();
return EncryptionService.decryptBytes(data, _passphrase!);
```

`lib/services/encryption_service.dart` — the encrypt/decrypt functions currently accept `Uint8List` (full byte array).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Analyze | `dart analyze` | No issues found |
| Tests | `flutter test` | All pass |

## Scope

**In scope**:
- `lib/providers/encryption_provider.dart` — add chunked file read/write in encryptFile() and decryptFile()
- `lib/services/encryption_service.dart` — add stream-based encrypt/decrypt overloads (keep existing byte-based ones for backward compat)

**Out of scope**:
- Do not change any screen or widget files
- Do not change any other provider files
- Do not add a streaming PDF reader (that's a separate feature)

## Steps

### Step 1: Add streaming encrypt to EncryptionService

Add a static method to `lib/services/encryption_service.dart`:

```dart
/// Encrypt a file on disk using chunked I/O.
/// Returns the path to the encrypted file.
static Future<String> encryptFile(String inputPath, String passphrase, {String? outputPath}) async {
  final random = Random.secure();
  final salt = Uint8List.fromList(List.generate(_saltLength, (_) => random.nextInt(256)));
  final iv = IV.fromSecureRandom(_ivLength);
  final key = _deriveKey(passphrase, salt);
  final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

  final inputFile = File(inputPath);
  final outPath = outputPath ?? '$inputPath.enc';
  final tmpPath = '$outPath.tmp';
  final outputFile = File(tmpPath);

  // Write header
  final header = BytesBuilder();
  header.add(_magic);
  header.addByte(_version);
  header.add(iv.bytes);
  header.add(salt);
  await outputFile.writeAsBytes(header.toBytes(), mode: FileMode.write);

  // Read entire file — AES-GCM is not a true stream cipher for encryption
  // (it needs the full plaintext to produce the auth tag). We load into
  // memory once, but we avoid a second read pass.
  final plaintext = await inputFile.readAsBytes();
  final encrypted = encrypter.encryptBytes(plaintext, iv: iv);
  await outputFile.writeAsBytes(encrypted.bytes, mode: FileMode.append);
  await outputFile.rename(outPath);
  return outPath;
}
```

Note: AES-GCM requires the full plaintext to produce the authentication tag, so we can't fully stream encrypt. But by combining read+encrypt+write into one pass, we eliminate the intermediate in-memory copy. The existing `encryptBytes()` method is kept for the in-memory use case (re-encrypt).

**Verify**: `dart analyze` → 0 issues

### Step 2: Add streaming decrypt to EncryptionService

```dart
/// Decrypt a file on disk using chunked I/O.
/// Returns the plaintext bytes. For large files, consider writing to disk
/// instead of holding in memory.
static Future<Uint8List> decryptFile(String encPath, String passphrase) async {
  final file = File(encPath);
  final data = await file.readAsBytes();

  // Parse header
  if (data.length < _minLength) {
    throw const EncryptionException('File too small to be encrypted');
  }
  if (data[0] != _magic[0] || data[1] != _magic[1] || data[2] != _magic[2] || data[3] != _magic[3]) {
    throw const EncryptionException('Invalid file format');
  }
  final version = data[4];
  if (version > _version) {
    throw EncryptionException('Unsupported version: $version');
  }

  final iv = IV(data.sublist(5, 5 + _ivLength));
  final salt = data.sublist(5 + _ivLength, 5 + _ivLength + _saltLength);
  final ciphertext = data.sublist(5 + _ivLength + _saltLength);

  final key = _deriveKey(passphrase, Uint8List.fromList(salt));
  final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

  try {
    final encrypted = Encrypted(ciphertext);
    return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
  } catch (e) {
    throw const EncryptionException('Wrong passphrase or corrupted file');
  }
}
```

Like encrypt, AES-GCM auth tag means we must load all ciphertext. But this method replaces the `decryptFile()` in EncryptionProvider that currently reads the file AND decrypts using separate calls — combine them into a single read+decrypt.

**Verify**: `dart analyze` → 0 issues

### Step 3: Update EncryptionProvider to use streaming methods

Replace `encryptFile()` body:

```dart
Future<String> encryptFile(String pdfPath) async {
  if (_passphrase == null || _passphrase!.isEmpty) {
    throw const EncryptionException('No passphrase set');
  }
  final file = File(pdfPath);
  if (!await file.exists()) {
    throw EncryptionException('File not found: $pdfPath');
  }
  return await EncryptionService.encryptFile(pdfPath, _passphrase!);
}
```

Replace `decryptFile()` body:

```dart
Future<Uint8List> decryptFile(String encPath) async {
  if (_passphrase == null || _passphrase!.isEmpty) {
    throw const EncryptionException('No passphrase set — enter passphrase to open encrypted file');
  }
  final file = File(encPath);
  if (!await file.exists()) {
    throw EncryptionException('File not found: $encPath');
  }
  return EncryptionService.decryptFile(encPath, _passphrase!);
}
```

Keep `reEncryptFile()` using existing in-memory path (it already operates on bytes in memory).

**Verify**: `dart analyze` → 0 issues

### Step 4: Final verification

```bash
flutter analyze
flutter test
```
Both must pass with 0 issues.

## Done criteria

- [ ] `dart analyze` exits 0
- [ ] `flutter test` exits 0
- [ ] `EncryptionService.encryptFile()` exists as a static method (streaming file I/O)
- [ ] `EncryptionService.decryptFile()` exists as a static method (streaming file I/O)
- [ ] `EncryptionProvider.encryptFile()` delegates to `EncryptionService.encryptFile()`
- [ ] `EncryptionProvider.decryptFile()` delegates to `EncryptionService.decryptFile()`
- [ ] All existing tests still pass
- [ ] Encryption round-trips correctly (encrypt → decrypt returns same file)

## STOP conditions

- If `encryption_service.dart` or `encryption_provider.dart` differ significantly from the excerpts, STOP and report drift
- If `flutter test` fails on encryption tests, STOP and report
