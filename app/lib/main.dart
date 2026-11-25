import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/app_services.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  // Desktop: files given as arguments (e.g. "Open with UnRot") are imported on start.
  final files = args.where((a) => !a.startsWith('-')).toList();
  runApp(UnRotApp(services: services, initialFiles: files));
}
