import 'package:flutter/material.dart';

import '../../widgets/page_scaffold.dart';

class SnippetsPage extends StatelessWidget {
  const SnippetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      title: '代码片段',
      child: EmptyState(
        icon: Icons.code_outlined,
        title: '还没有代码片段',
        message: '保存常用命令，在终端里一键发送',
      ),
    );
  }
}
