import 'package:flutter/material.dart';

import '../theme/staff_theme.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking staff access…', style: TextStyle(color: StaffColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
