/// 三个主页面（看板 / 功能 / 设置）共用的 AppBar 标题。
///
/// 形如「掌上砚园·看板」：前半「掌上砚园」加粗，后半是当前页面名，
/// 常规字重。拆成两个 Text 是为了让 `find.text('掌上砚园')` 仍可命中。
library;

import 'package:flutter/material.dart';

/// 品牌标题。
class AppBarBrandTitle extends StatelessWidget {
  const AppBarBrandTitle(this.page, {super.key});

  /// 当前页面名，如「看板」「功能」「设置」。
  final String page;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '掌上砚园',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          '·$page',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
