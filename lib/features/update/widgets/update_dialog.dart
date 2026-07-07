import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../update_provider.dart';

/// Shows the auto-update dialog. Call from anywhere with BuildContext.
void showUpdateDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<UpdateProvider>(),
      child: const _UpdateDialog(),
    ),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          const Text('Update Available'),
        ],
      ),
      content: _buildContent(context, provider, colorScheme),
      actions: _buildActions(context, provider, colorScheme),
    );
  }

  Widget _buildContent(
    BuildContext context,
    UpdateProvider provider,
    ColorScheme colorScheme,
  ) {
    final release = provider.release;
    final newVersion = release?.version ?? '…';

    switch (provider.state) {
      case UpdateState.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloading v$newVersion…',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: provider.downloadProgress,
                minHeight: 8,
                backgroundColor:
                    colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.downloadProgress != null
                  ? '${(provider.downloadProgress! * 100).toStringAsFixed(0)}%'
                  : 'Preparing…',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      case UpdateState.downloaded:
        return Text(
          'v$newVersion downloaded successfully. '
          'Tap Install to update.',
        );

      case UpdateState.error:
        return Text(
          provider.errorMessage ?? 'Something went wrong.',
          style: TextStyle(color: colorScheme.error),
        );

      default:
        // updateAvailable
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of Feya PDF is available: v$newVersion',
              style: const TextStyle(fontSize: 14),
            ),
            if (release != null && release.body.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Text(
                    release.body,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
    }
  }

  List<Widget> _buildActions(
    BuildContext context,
    UpdateProvider provider,
    ColorScheme colorScheme,
  ) {
    switch (provider.state) {
      case UpdateState.downloading:
        return [
          TextButton(
            onPressed: () {
              provider.cancelDownload();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ];

      case UpdateState.downloaded:
        return [
          TextButton(
            onPressed: () {
              provider.reset();
              Navigator.pop(context);
            },
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              provider.installUpdate();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.install_mobile_rounded),
            label: const Text('Install'),
          ),
        ];

      case UpdateState.error:
        return [
          TextButton(
            onPressed: () {
              provider.reset();
              Navigator.pop(context);
            },
            child: const Text('Dismiss'),
          ),
        ];

      default:
        return [
          TextButton(
            onPressed: () {
              provider.reset();
              Navigator.pop(context);
            },
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () => provider.downloadUpdate(),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download'),
          ),
        ];
    }
  }
}
