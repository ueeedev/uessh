import 'package:flutter/material.dart';

import '../../widgets/page_scaffold.dart';
import '../../l10n/l10n.dart';

class ForwardingPage extends StatelessWidget {
  const ForwardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: context.l10n.forwardingTitle,
      child: EmptyState(
        icon: Icons.swap_horiz,
        title: context.l10n.noForwardsTitle,
        message: context.l10n.noForwardsMessage,
      ),
    );
  }
}
