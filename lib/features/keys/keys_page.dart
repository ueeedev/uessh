import 'package:flutter/material.dart';

import '../../widgets/page_scaffold.dart';

class KeysPage extends StatelessWidget {
  const KeysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      title: '密钥',
      child: EmptyState(
        icon: Icons.key_outlined,
        title: '还没有密钥',
        message: '导入或生成 SSH 密钥，用于免密码登录',
      ),
    );
  }
}
