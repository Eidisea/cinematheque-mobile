import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Page not found', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Go to dashboard')),
          ],
        ),
      ),
    );
  }
}
