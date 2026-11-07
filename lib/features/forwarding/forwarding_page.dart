import 'package:flutter/material.dart';

import '../../widgets/page_scaffold.dart';

class ForwardingPage extends StatelessWidget {
  const ForwardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      title: '端口转发',
      child: EmptyState(
        icon: Icons.swap_horiz,
        title: '还没有转发规则',
        message: '支持本地、远程和动态（SOCKS）转发',
      ),
    );
  }
}
