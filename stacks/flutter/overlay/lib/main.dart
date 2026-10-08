// __NAME__ — flutter stack pack overlay (REQ-303/304).
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // REQ-390: a smoke run under SPECFLOW_SMOKE=1 starts up and exits 0
  // without waiting on a window event loop, so the release gate can prove
  // the built app launches.
  if (Platform.environment['SPECFLOW_SMOKE'] == '1') {
    exit(0);
  }
  runApp(const GreetingApp());
}
