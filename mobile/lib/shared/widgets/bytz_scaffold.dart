import 'package:flutter/material.dart';

export 'bytz_state_panels.dart'
    show
        BytzEmptyState,
        BytzErrorPanel,
        BytzRouteErrorScreen,
        confirmSignOut,
        showLegalLinkError;

class BytzScaffold extends StatelessWidget {
  const BytzScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(child: body),
    );
  }
}

class BytzCard extends StatelessWidget {
  const BytzCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
