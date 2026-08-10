// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/build_info.dart';
import 'package:freya_pdf/features/settings/backup_provider.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/security/app_lock_service.dart';
import 'package:freya_pdf/features/encryption/widgets/passphrase_dialog.dart';
import 'package:freya_pdf/features/update/update_provider.dart';
import 'package:freya_pdf/features/update/widgets/update_dialog.dart';
import 'package:freya_pdf/features/security/pdf_password_storage.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final encryption = context.watch<EncryptionProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Account Section ──
          _SectionHeader('Account'),
          ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                settings.userProfile.name.isNotEmpty
                    ? settings.userProfile.name[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 20,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            title: Text(
              settings.userProfile.name.isEmpty
                  ? 'Set your name'
                  : settings.userProfile.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              settings.userProfile.email.isEmpty
                  ? 'Tap to edit profile'
                  : settings.userProfile.email,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showEditProfileDialog(context, settings),
          ),

          const SizedBox(height: 8),

          // ── Encryption Section ──
          _SectionHeader('Encryption'),
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('Passphrase'),
            subtitle: Text(
              encryption.hasPassphrase
                  ? '●●●●●●●●'
                  : 'Not set — files will not be encrypted',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showPassphraseDialog(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('Auto-encrypt new files'),
            subtitle: Text(
              'New PDF files are encrypted on import',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            value: settings.autoEncrypt,
            onChanged: (v) => settings.setAutoEncrypt(v),
          ),
          if (encryption.hasPassphrase)
            ListTile(
              leading: Icon(Icons.lock_open_rounded, color: colorScheme.error),
              title: Text(
                'Clear passphrase',
                style: TextStyle(color: colorScheme.error),
              ),
              subtitle: Text(
                'Lock all encrypted files until re-entered',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              onTap: () async {
                await encryption.clearPassphrase();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Passphrase cleared'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: const Text('Remembered PDF passwords'),
            subtitle: Text(
              'Clear passwords saved for external PDFs on this device',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            onTap: () => _clearRememberedPdfPasswords(context),
          ),

          const SizedBox(height: 8),

          // ── App Lock Section ──
          _SectionHeader('App Lock'),
          _AppLockTile(settings: settings),

          const SizedBox(height: 8),

          // ── Reader Section ──
          _SectionHeader('Reader'),
          SwitchListTile(
            secondary: const Icon(Icons.view_column_rounded),
            title: const Text('Continuous scroll'),
            subtitle: Text(
              'Scroll pages vertically instead of swiping one at a time',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            value: settings.continuousScroll,
            onChanged: (v) => settings.setContinuousScroll(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.grid_view_rounded),
            title: const Text('Show thumbnails'),
            subtitle: Text(
              'Show a thumbnail grid button while reading',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            value: settings.showThumbnails,
            onChanged: (v) => settings.setShowThumbnails(v),
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.dark_mode_rounded,
              color: settings.darkReadingMode ? colorScheme.primary : null,
            ),
            title: const Text('Dark reading mode'),
            subtitle: Text(
              'Invert PDF colors for comfortable reading in low light',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            value: settings.darkReadingMode,
            onChanged: (v) => settings.setDarkReadingMode(v),
          ),

          const SizedBox(height: 8),

          // ── Appearance Section ──
          _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(
              _themeModeLabel(settings.themeMode),
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showThemePicker(context, settings),
          ),

          const SizedBox(height: 8),

          // ── Backup & Restore Section ──
          _SectionHeader('Backup & Restore'),
          Consumer<BackupProvider>(
            builder: (ctx, backup, _) => ListTile(
              leading: const Icon(Icons.backup_rounded),
              title: const Text('Export backup'),
              subtitle: Text(
                backup.isExporting
                    ? 'Exporting…'
                    : 'Save all data as a JSON file',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              trailing: backup.isExporting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: backup.isExporting ? null : () => backup.exportBackup(ctx),
            ),
          ),
          Consumer<BackupProvider>(
            builder: (ctx, backup, _) => ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Import backup'),
              subtitle: Text(
                backup.isImporting
                    ? 'Restoring…'
                    : 'Restore data from a JSON file',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              trailing: backup.isImporting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: backup.isImporting ? null : () => backup.importBackup(ctx),
            ),
          ),

          const SizedBox(height: 8),

          // ── About Section ──
          _SectionHeader('About'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/logo/FREYA PDF.png',
                        width: 64,
                        height: 64,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Freya PDF',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A clean, fast, ad-free PDF reader',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Consumer<UpdateProvider>(
                  builder: (ctx, update, _) => ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Version'),
                    trailing: Text(
                      'v${update.currentVersion}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.tag_rounded),
                  title: const Text('Commit'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        BuildInfo.gitHash,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: BuildInfo.gitHash),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Commit hash copied'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                _UpdateCheckTile(),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('Open source licenses'),
                  subtitle: Text(
                    'Includes MIT/Apache/BSD licensed works',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Freya PDF',
                    applicationVersion: context
                        .read<UpdateProvider>()
                        .currentVersion,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _clearRememberedPdfPasswords(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear remembered PDF passwords?'),
        content: const Text(
          'Passwords saved for external PDFs will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await PdfPasswordStorage().clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Remembered PDF passwords cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _showThemePicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  ctx,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Theme',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            _themeOption(
              ctx,
              settings,
              ThemeMode.system,
              Icons.brightness_auto_rounded,
              'System',
            ),
            _themeOption(
              ctx,
              settings,
              ThemeMode.light,
              Icons.light_mode_rounded,
              'Light',
            ),
            _themeOption(
              ctx,
              settings,
              ThemeMode.dark,
              Icons.dark_mode_rounded,
              'Dark',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(
    BuildContext context,
    SettingsProvider settings,
    ThemeMode mode,
    IconData icon,
    String label,
  ) {
    final isActive = settings.themeMode == mode;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: isActive ? colorScheme.primary : null),
      title: Text(label),
      trailing: isActive
          ? Icon(Icons.check_rounded, color: colorScheme.primary)
          : null,
      onTap: () {
        settings.setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  void _showEditProfileDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => _EditProfileDialog(settings: settings),
    );
  }
}

/// Stateful dialog that owns its TextEditingControllers so they're
/// disposed when the dialog closes. Fixes a memory leak where controllers
/// were created in a stateless helper and never released.
class _EditProfileDialog extends StatefulWidget {
  final SettingsProvider settings;

  const _EditProfileDialog({required this.settings});

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.settings.userProfile.name,
    );
    _emailController = TextEditingController(
      text: widget.settings.userProfile.email,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit Profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.settings.updateUserProfile(
              widget.settings.userProfile.copyWith(
                name: _nameController.text,
                email: _emailController.text,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// App Lock settings tile: PIN setup, change, toggle, biometric toggle.
class _AppLockTile extends StatefulWidget {
  final SettingsProvider settings;

  const _AppLockTile({required this.settings});

  @override
  State<_AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<_AppLockTile> {
  final AppLockService _lockService = AppLockService();
  bool _hasPin = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final hasPin = await _lockService.hasPin();
    final bioAvail = await _lockService.isBiometricAvailable();
    final bioEnabled = await _lockService.getBiometricEnabled();
    if (mounted) {
      setState(() {
        _hasPin = hasPin;
        _biometricAvailable = bioAvail;
        _biometricEnabled = bioEnabled;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      children: [
        // App lock toggle
        SwitchListTile(
          secondary: Icon(
            widget.settings.appLockEnabled
                ? Icons.lock_rounded
                : Icons.lock_open_rounded,
          ),
          title: const Text('App lock'),
          subtitle: Text(
            _hasPin
                ? 'Lock the app behind a PIN or biometric'
                : 'Set up a PIN first',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          value: widget.settings.appLockEnabled && _hasPin,
          onChanged: _hasPin
              ? (v) => widget.settings.setAppLockEnabled(v)
              : null,
        ),

        // Set / change PIN
        ListTile(
          leading: Icon(_hasPin ? Icons.lock_reset_rounded : Icons.pin_rounded),
          title: Text(_hasPin ? 'Change PIN' : 'Set PIN'),
          subtitle: Text(
            _hasPin
                ? 'Change your app unlock PIN'
                : 'Create a PIN to lock the app',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            // Changing an existing PIN must first verify the current PIN (or
            // biometric) so a bystander with a few seconds of access cannot
            // silently reset the lock. Setting a brand-new PIN (no PIN exists)
            // requires no re-authentication.
            if (_hasPin && !await _requireCurrentPin(context)) return;
            if (!context.mounted) return;
            _showPinSetupDialog(context);
          },
        ),

        // Biometric toggle (only if available and PIN is set)
        if (_biometricAvailable && _hasPin)
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('Unlock with biometrics'),
            subtitle: Text(
              _biometricEnabled
                  ? 'Fingerprint or face unlock enabled'
                  : 'Use fingerprint or face to unlock',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            value: _biometricEnabled,
            onChanged: (v) async {
              await _lockService.setBiometricEnabled(v);
              setState(() => _biometricEnabled = v);
            },
          ),

        // Clear PIN (only if set)
        if (_hasPin)
          ListTile(
            leading: Icon(
              Icons.delete_forever_rounded,
              color: colorScheme.error,
            ),
            title: Text(
              'Remove PIN',
              style: TextStyle(color: colorScheme.error),
            ),
            subtitle: Text(
              'Disable app lock and clear stored PIN',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            onTap: () => _confirmRemovePin(context),
          ),
      ],
    );
  }

  /// Require the user to prove they know the current PIN (falling back to
  /// biometrics if enabled) before a destructive lock operation. Returns true
  /// when re-authentication succeeds.
  Future<bool> _requireCurrentPin(BuildContext context) async {
    final controller = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Enter current PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Confirm your current PIN to continue.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Current PIN',
                  errorText: error,
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) async {
                  setDialogState(() => error = null);
                  final verified =
                      await _lockService.confirmCurrentPin(controller.text);
                  if (verified && ctx.mounted) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDialogState(() => error = 'Incorrect PIN');
                    controller.clear();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            if (_biometricAvailable)
              TextButton(
                onPressed: () async {
                  final bioOk =
                      await _lockService.authenticateWithBiometrics();
                  if (bioOk && ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Use biometrics'),
              ),
            FilledButton(
              onPressed: () async {
                setDialogState(() => error = null);
                final verified =
                    await _lockService.confirmCurrentPin(controller.text);
                if (verified && ctx.mounted) {
                  Navigator.pop(ctx, true);
                } else {
                  setDialogState(() => error = 'Incorrect PIN');
                  controller.clear();
                }
              },
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  void _showPinSetupDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    String pin = '';
    String confirmPin = '';
    bool step2 = false;
    String? step2Error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(step2 ? 'Confirm PIN' : 'Set PIN'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step2
                        ? 'Enter your PIN again to confirm'
                        : 'Enter a 4-6 digit PIN',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Pin dots display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      step2 ? confirmPin.length : pin.length,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (step2Error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      step2Error!,
                      style: TextStyle(color: colorScheme.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Inline keypad
                  _PinSetupKeypad(
                    onDigit: (d) {
                      setDialogState(() {
                        if (!step2) {
                          if (pin.length < 6) {
                            pin += String.fromCharCode(48 + d);
                          }
                          if (pin.length >= 4 && pin.length <= 6) {
                            // Auto-proceed to confirm if user stops
                          }
                        } else {
                          if (confirmPin.length < 6) {
                            confirmPin += String.fromCharCode(48 + d);
                          }
                        }
                        step2Error = null;
                      });
                    },
                    onDelete: () {
                      setDialogState(() {
                        if (!step2) {
                          if (pin.isNotEmpty) {
                            pin = pin.substring(0, pin.length - 1);
                          }
                        } else {
                          if (confirmPin.isNotEmpty) {
                            confirmPin = confirmPin.substring(
                              0,
                              confirmPin.length - 1,
                            );
                          }
                        }
                      });
                    },
                    canDelete:
                        (!step2 && pin.isNotEmpty) ||
                        (step2 && confirmPin.isNotEmpty),
                    colorScheme: colorScheme,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                if (!step2 && pin.length >= 4)
                  FilledButton(
                    onPressed: () {
                      setDialogState(() {
                        step2 = true;
                      });
                    },
                    child: const Text('Continue'),
                  ),
                if (step2 && confirmPin.length >= 4)
                  FilledButton(
                    onPressed: () async {
                      if (pin == confirmPin) {
                        await _lockService.setPin(pin);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          final messenger = ScaffoldMessenger.of(context);
                          await widget.settings.setAppLockEnabled(true);
                          _loadState();
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('PIN set successfully'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        }
                      } else {
                        setDialogState(() {
                          step2Error = 'PINs do not match';
                          confirmPin = '';
                        });
                      }
                    },
                    child: const Text('Confirm'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRemovePin(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    // Must verify the current PIN (or biometric) first so the lock cannot be
    // silently disabled in an unlocked session by a bystander.
    if (!await _requireCurrentPin(context)) return;
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove PIN?'),
        content: const Text(
          'This will disable app lock and delete your stored PIN. '
          'You will need to set a new PIN to lock the app again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () async {
              await _lockService.clearPin();
              await widget.settings.setAppLockEnabled(false);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                final messenger = ScaffoldMessenger.of(context);
                _loadState();
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text('PIN removed'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

/// Small inline keypad used in the PIN setup dialog.
class _PinSetupKeypad extends StatelessWidget {
  final void Function(int digit) onDigit;
  final VoidCallback onDelete;
  final bool canDelete;
  final ColorScheme colorScheme;

  const _PinSetupKeypad({
    required this.onDigit,
    required this.onDelete,
    required this.canDelete,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row
                  .map((d) => _SetupKey(label: '$d', onTap: () => onDigit(d)))
                  .toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 60),
            _SetupKey(label: '0', onTap: () => onDigit(0)),
            _SetupKey(
              icon: Icons.backspace_outlined,
              onTap: canDelete ? onDelete : null,
              disabled: !canDelete,
            ),
          ],
        ),
      ],
    );
  }
}

class _SetupKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool disabled;

  const _SetupKey({this.label, this.icon, this.onTap, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = disabled
        ? colorScheme.onSurface.withValues(alpha: 0.15)
        : colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: disabled ? null : onTap,
          child: Container(
            width: 60,
            height: 52,
            alignment: Alignment.center,
            child: label != null
                ? Text(
                    label!,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  )
                : Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}

class _UpdateCheckTile extends StatefulWidget {
  const _UpdateCheckTile();

  @override
  State<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<_UpdateCheckTile> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final update = context.watch<UpdateProvider>();

    return ListTile(
      leading: Icon(
        Icons.system_update_rounded,
        color: _checking ? colorScheme.primary : null,
      ),
      title: const Text('Check for updates'),
      subtitle: Text(
        _checking ? 'Checking…' : 'See if a newer version is available',
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
      ),
      trailing: _checking
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : const Icon(Icons.chevron_right_rounded),
      onTap: _checking
          ? null
          : () async {
              setState(() => _checking = true);
              final messenger = ScaffoldMessenger.of(context);
              await update.checkForUpdate();
              if (!mounted) return;
              setState(() => _checking = false);

              switch (update.state) {
                case UpdateState.updateAvailable:
                  // ignore: use_build_context_synchronously
                  showUpdateDialog(context);
                  break;
                case UpdateState.upToDate:
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'You\'re up to date (v${update.currentVersion})',
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                  break;
                case UpdateState.noInternet:
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('No internet connection'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                  break;
                default:
                  if (update.errorMessage != null) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(update.errorMessage!),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }
              }
            },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
