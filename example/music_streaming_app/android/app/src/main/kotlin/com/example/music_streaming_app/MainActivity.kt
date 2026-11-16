package com.example.music_streaming_app

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (not plain FlutterActivity) is required so the
// Android media session / notification can reopen the app correctly.
class MainActivity : AudioServiceActivity()
