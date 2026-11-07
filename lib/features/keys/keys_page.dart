import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/page_scaffold.dart';
import 'key_editor_sheet.dart';
import 'keys_providers.dart';
import 'ssh_key.dart';
import '../../l10n/l10n.dart';

/// Header buttons share the hosts page's height.
const _actionHeight = 44.0;

class KeysPage extends ConsumerWidget {
  const KeysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(keysProvider);
    return PageScaffold(
      title: context.l10n.navKeys,
      actions: [
        SizedBox(
          height: _actionHeight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => showKeyEditor(context),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.addKey),
          ),
        ),
      ],
      child: keys.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: context.l10n.loadKeysFailed,
          message: '$e',
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.key_outlined,
                title: context.l10n.noKeysTitle,
                message: context.l10n.noKeysMessage,
              )
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  mainAxisExtent: 80,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) => KeyCard(
                  sshKey: list[i],
                  onEdit: () => showKeyEditor(context, key: list[i]),
                ),
              ),
      ),
    );
  }
}

class KeyCard extends StatelessWidget {
  const KeyCard({super.key, required this.sshKey, required this.onEdit});

  final SshKey sshKey;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = sshKey.keyType?.replaceFirst('ssh-', '').toUpperCase();
    final fp = sshKey.fingerprint;
    final detail = [
      type ?? context.l10n.keyEncrypted,
      if (fp != null) '${fp.substring(0, fp.length.clamp(0, 22))}…',
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.tertiaryContainer,
                foregroundColor: scheme.onTertiaryContainer,
                child: const Icon(Icons.key),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sshKey.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.edit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
