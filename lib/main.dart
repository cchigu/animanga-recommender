import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/catalog_store.dart';
import 'services/library_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  await LibraryStore.instance.load();
  await CatalogStore.instance.load();
  runApp(const AnimangaApp());
  // Quietly refresh lists that are more than a few hours old, and build or
  // top up the catalog in the background.
  LibraryStore.instance.refreshIfStale();
  CatalogStore.instance.ensureFresh();
}

class AnimangaApp extends StatelessWidget {
  const AnimangaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Animanga Recommender',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
