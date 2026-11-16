import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/audio_handler.dart';
import 'services/download_service.dart';
import 'services/yt_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Route audio to the music stream and handle headphone unplug / calls.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  final ytService = YtService();
  final downloadService = DownloadService(ytService: ytService);
  await downloadService.load();

  // Starts the background isolate/service that owns the media notification
  // and lock-screen controls. MusicAudioHandler is created once, here.
  final audioHandler = await AudioService.init<MusicAudioHandler>(
    builder: () => MusicAudioHandler(ytService: ytService),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_streaming_app.audio',
      androidNotificationChannelName: 'Wave Music playback',
      androidNotificationChannelDescription:
          'Controls for music playing in the background',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );

  runApp(
    MusicApp(
      ytService: ytService,
      audioHandler: audioHandler,
      downloadService: downloadService,
    ),
  );
}

class MusicApp extends StatelessWidget {
  const MusicApp({
    super.key,
    required this.ytService,
    required this.audioHandler,
    required this.downloadService,
  });

  final YtService ytService;
  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wave Music',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeScreen(
        ytService: ytService,
        audioHandler: audioHandler,
        downloadService: downloadService,
      ),
    );
  }
}
