import 'package:flutter/material.dart';

import 'welcome_screen.dart';

class InterestsScreen extends StatelessWidget {
  const InterestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WelcomeScreen(initialStep: 3);
  }
}
