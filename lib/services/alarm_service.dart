import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AlarmStage { none, stage1, stage2, stage3 }

class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  AlarmStage _currentStage = AlarmStage.none;
  Timer? _vibrationTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  AlarmStage get currentStage => _currentStage;

  Future<void> triggerStage(AlarmStage stage) async {
    if (_currentStage == stage) return;
    _currentStage = stage;
    
    _vibrationTimer?.cancel();
    await _audioPlayer.stop();

    if (stage == AlarmStage.none) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString('custom_alarm_path');

    Source audioSource;
    if (customPath != null && File(customPath).existsSync()) {
      audioSource = DeviceFileSource(customPath);
    } else {
      String assetName = 'alarm1.mp3';
      if (stage == AlarmStage.stage2) assetName = 'alarm2.mp3';
      if (stage == AlarmStage.stage3) assetName = 'alarm3.mp3';
      audioSource = AssetSource(assetName);
    }

    if (stage == AlarmStage.stage1) {
      // Gentle reminder
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(audioSource, volume: 0.5);
      
      _vibrationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        HapticFeedback.lightImpact();
      });
    } else if (stage == AlarmStage.stage2) {
      // Escalate
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(audioSource, volume: 0.8);
      
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        HapticFeedback.mediumImpact();
      });
    } else if (stage == AlarmStage.stage3) {
      // Emergency (< 500m)
      WakelockPlus.enable();
      
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      // Force volume loud over system using audio_session ideally, but passing 1.0 here
      await _audioPlayer.play(audioSource, volume: 1.0);
      
      _vibrationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        HapticFeedback.heavyImpact();
      });
    }
  }

  void stopAlarm() {
    triggerStage(AlarmStage.none);
  }
}
