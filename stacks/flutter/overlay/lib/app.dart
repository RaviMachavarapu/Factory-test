// __NAME__ — flutter stack pack overlay (REQ-303/304).
import 'package:flutter/material.dart';

class GreetingApp extends StatelessWidget {
  const GreetingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '__NAME__',
      home: Scaffold(
        body: Center(
          child: Text('Hello from __NAME__'),
        ),
      ),
    );
  }
}
