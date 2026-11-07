import 'package:flutter/material.dart';

import '../../widgets/page_scaffold.dart';
import '../../l10n/l10n.dart';

class SnippetsPage extends StatelessWidget {
  const SnippetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: context.l10n.snippetsTitle,
      child: EmptyState(
        icon: Icons.code_outlined,
        title: context.l10n.noSnippetsTitle,
        message: context.l10n.noSnippetsMessage,
      ),
    );
  }
}
