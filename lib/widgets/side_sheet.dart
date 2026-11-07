import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Opens a Material 3 modal side sheet that slides in from the right.
Future<T?> showSideSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 440,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: scheme.scrim.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, _) {
      final maxWidth = MediaQuery.sizeOf(context).width - 56;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: math.min(width, maxWidth),
          height: double.infinity,
          child: builder(context),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      ),
      child: child,
    ),
  );
}

/// Side sheet frame: title bar with close button, scrolling body,
/// and a bottom action row.
///
/// Every way of closing (close button, scrim, Esc, or an action calling
/// `Navigator.maybePop`) asks for confirmation while [hasUnsavedChanges]
/// is true. Use `Navigator.pop` to close without asking, e.g. after saving.
class SideSheet extends StatelessWidget {
  const SideSheet({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.hasUnsavedChanges = false,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool hasUnsavedChanges;

  Future<void> _confirmDiscard(BuildContext context) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.edit_off_outlined),
        title: const Text('放弃未保存的修改？'),
        content: const Text('关闭后，刚才填写的内容不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (discard == true && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard(context);
      },
      child: _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ],
            ),
          ),
          Expanded(child: body),
          if (actions.isNotEmpty) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
