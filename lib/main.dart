import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'track_habit_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'sync_service.dart';
import 'package:google_fonts/google_fonts.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SyncService().start();
  runApp(const HabitTrackerApp());
}

class HabitTrackerApp extends StatelessWidget {
  const HabitTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoLife Habit Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
        scaffoldBackgroundColor: Colors.lightGreen.shade100,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,         // AppBar fill colour
          foregroundColor: Colors.black,         // title & icon colour
          centerTitle: true,                     // centre the title
          elevation: 2,                          // shadow
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(100),
            ),
          ),
        ),
        cardTheme: CardTheme(
          color: Colors.lightGreen.shade50,                   // 卡片背景色
          elevation: 2,                                        // 投影高度
          margin: const EdgeInsets.symmetric(vertical: 8),     // 默认外边距
          shape: RoundedRectangleBorder(                       // 圆角
            borderRadius: BorderRadius.circular(35),
          ),
        ),
        textTheme: GoogleFonts.patrickHandTextTheme(
          Theme.of(context).textTheme,
        ).apply(
          fontSizeFactor: 1.3,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green, // button fill
            foregroundColor: Colors.black, // text/icon color
          ),
        ),
      ),

      navigatorKey: navigatorKey,
      home: const TrackHabitScreen(),
    );
  }
}

Future<void> seedTestData() async {
  await FirebaseFirestore.instance
      .collection('entries')
      .add({
    'habitTitle': 'Reduce Plastic',
    'date': Timestamp.now(),
    'value': 0.42,
  });
  print('⚡️ Seeded one test entry');
}



