import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class GlobalAudioPlayer extends ChangeNotifier {
  static final GlobalAudioPlayer _instance = GlobalAudioPlayer._internal();
  factory GlobalAudioPlayer() => _instance;

  GlobalAudioPlayer._internal() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _player.onPositionChanged.listen((p) {
      _position = p;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      notifyListeners();
    });
  }

  final AudioPlayer _player = AudioPlayer();
  String? _activeUrl;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = false;

  String? get activeUrl => _activeUrl;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  bool get isLoading => _isLoading;

  Future<void> play(String url) async {
    if (_activeUrl == url) {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.resume();
      }
      return;
    }

    _isLoading = true;
    _activeUrl = url;
    _isPlaying = false;
    _duration = Duration.zero;
    _position = Duration.zero;
    notifyListeners();

    try {
      await _player.stop();
      final localPath = await _getLocalFilePath(url);
      if (localPath != null && await File(localPath).exists()) {
        await _player.play(DeviceFileSource(localPath));
      } else {
        // Stream directly but trigger background cache download
        await _player.play(UrlSource(url));
        if (localPath != null) {
          _cacheFileInBackground(url, localPath);
        }
      }
    } catch (e) {
      debugPrint("Error playing audio: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
  }

  Future<void> stop() async {
    await _player.stop();
    _activeUrl = null;
    _isPlaying = false;
    notifyListeners();
  }

  Future<String?> _getLocalFilePath(String url) async {
    try {
      final directory = await getTemporaryDirectory();
      // Use clean filename from the url
      final fileName = url.split('/').last.split('?').first;
      if (fileName.isEmpty) return null;
      return '${directory.path}/voice_note_$fileName';
    } catch (_) {
      return null;
    }
  }

  void _cacheFileInBackground(String url, String localPath) async {
    try {
      final dio = Dio();
      await dio.download(url, localPath);
    } catch (e) {
      debugPrint("Error caching audio file in background: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
