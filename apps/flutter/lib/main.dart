import 'package:flutter/material.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  runApp(MusicApp(bootstrap: bootstrapStatus()));
}
