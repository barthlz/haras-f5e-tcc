import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use --dart-define no Flutter. NUNCA use service_role/secret key no Android.
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY '
              'antes de executar o aplicativo. Consulte o README.md.'),
        )),
      ),
    ));
    return;
  }

  await Supabase.initialize(url: url, publishableKey: key);
  runApp(const HarasApp());
}
