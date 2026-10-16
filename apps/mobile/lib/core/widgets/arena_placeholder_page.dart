import 'package:flutter/material.dart';

import 'section_placeholder.dart';

/// A pushed page with a back-titled app bar and a centered placeholder — used
/// for destinations in the design that aren't built-out features yet.
class ArenaPlaceholderPage extends StatelessWidget {
  const ArenaPlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.construction_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SectionPlaceholder(icon: icon, title: title, subtitle: subtitle),
    );
  }
}
