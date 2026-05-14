import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:twilio_programmable_video/twilio_programmable_video.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/chat/call_service.dart';
import '../../services/chat/socket_service.dart';
import '../../services/auth_service.dart';

class CallOverlayManager {
  static OverlayEntry? _overlayEntry;
  static bool get isCalling => _overlayEntry != null;

  static void show(BuildContext context, String name, String avatar, String receiverId) {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) =>
          CallOverlay(name: name, avatar: avatar, receiverId: receiverId, onEnd: () => hide()),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class CallOverlay extends StatefulWidget {
  final String name;
  final String avatar;
  final String receiverId;
  final VoidCallback onEnd;

  const CallOverlay({
    super.key,
    required this.name,
    required this.avatar,
    required this.receiverId,
    required this.onEnd,
  });

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final SocketService _socketService = SocketService();
  final AuthService _authService = AuthService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isMinimized = false;
  bool _isSpeakerOn = false;
  bool _isMuted = false;
  Offset _minimizedPosition = const Offset(20, 100);

  String _status = 'Calling...';
  String? _callId;
  String? _roomName;
  String? _token;
  bool _isActive = false;

  // ── Twilio Video ────────────────────────────────────────────────────────
  Room? _room;
  LocalAudioTrack? _localAudioTrack;
  String? _remoteUserId; // receiver's userId — set after call:initiate

  // ── Timer ────────────────────────────────────────────────────────────────
  Timer? _callTimer;
  int _elapsedSeconds = 0;

  // ── Avatar pulse animation ───────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _playDialingTone();
    _initiateCall();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _socketService.off('call:answered');
    _socketService.off('call:rejected');
    _socketService.off('call:ended');
    _socketService.off('call:error');
    _socketService.off('webrtc:answer');
    _socketService.off('webrtc:ice');
    _stopTimer();
    _audioPlayer.dispose();
    _pulseController.dispose();
    _localAudioTrack = null;
    _room?.disconnect();
    super.dispose();
  }

  // ── Twilio Call helpers ──────────────────────────────────────────────────
  Future<void> _startTwilioCall({required String token, required String roomName}) async {
    try {
      print('Connecting to Twilio Room: $roomName');
      _stopSounds(); // Redundant stop to be safe
      // Create local audio track
      _localAudioTrack = LocalAudioTrack(true, 'microphone');

      _room = await TwilioProgrammableVideo.connect(
        ConnectOptions(
          token,
          roomName: roomName,
          audioTracks: [_localAudioTrack!],
          enableNetworkQuality: true,
          enableDominantSpeaker: true,
        ),
      );

      await TwilioProgrammableVideo.setSpeakerphoneOn(true);
      print('Twilio (Caller): Connected and speakerphone enabled');
      print('Connected to room: ${_room?.sid}');

      // Listen for remote audio
      _room?.onParticipantConnected.listen((event) {
        _handleParticipant(event.remoteParticipant);
      });

      // Handle existing participants
      for (var p in _room?.remoteParticipants ?? []) {
        _handleParticipant(p);
      }

      _room?.onDisconnected.listen((event) {
        print('Disconnected from room');
        _endCall();
      });

      // Set initial speaker state
      webrtc.Helper.setSpeakerphoneOn(_isSpeakerOn);

    } catch (e) {
      debugPrint('Twilio error: $e');
    }
  }

  void _handleParticipant(RemoteParticipant participant) {
    // Handle existing tracks
    for (var pub in participant.remoteAudioTracks) {
      if (pub.remoteAudioTrack != null) {
        print('🔊 Existing audio track found from ${participant.identity}');
        pub.remoteAudioTrack?.enablePlayback(true);
      }
    }

    // Listen for new tracks
    participant.onAudioTrackSubscribed.listen((event) {
      print('🔊 Subscribed to new audio track from ${participant.identity}');
      event.remoteAudioTrack.enablePlayback(true);
    });
  }

  // ── Sound helpers ─────────────────────────────────────────────────────────
  Future<void> _playDialingTone() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource(
        'https://assets.mixkit.co/active_storage/sfx/2354/2354-preview.mp3',
      ));
    } catch (_) {}
  }

  Future<void> _playRingingTone() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource(
        'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/phone-ringing.mp3',
      ));
    } catch (_) {}
  }

  Future<void> _playHangupSound() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(UrlSource(
        'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/phone-hang-up.mp3',
      ));
    } catch (_) {}
  }

  Future<void> _stopSounds() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  // ── Timer helpers ─────────────────────────────────────────────────────────
  void _startTimer() {
    _callTimer?.cancel();
    _elapsedSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _stopTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  String get _timerLabel {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Socket ───────────────────────────────────────────────────────────────
  void _setupSocketListeners() {
    _socketService.on('call:answered', (data) {
      if (mounted) {
        _stopSounds();
        _startTimer();
        setState(() {
          _status = 'Connected';
          _isActive = true;
        });
        // Start WebRTC as the caller — we create the offer
        // Start Twilio call as the caller
        if (_token != null && _roomName != null) {
          _startTwilioCall(token: _token!, roomName: _roomName!);
        }
      }
    });

    _socketService.on('call:rejected', (data) {
      if (mounted) {
        _stopSounds();
        _stopTimer();
        setState(() => _status = 'Call Rejected');
        Future.delayed(const Duration(seconds: 2), widget.onEnd);
      }
    });

    _socketService.on('call:ended', (data) {
      if (mounted) {
        _stopSounds();
        _playHangupSound();
        _stopTimer();
        setState(() => _status = 'Call Ended');
        Future.delayed(const Duration(seconds: 3), widget.onEnd);
      }
    });

    _socketService.on('call:error', (data) {
      if (mounted) {
        _stopSounds();
        _stopTimer();
        setState(() => _status = 'Error: ${data['message']}');
        Future.delayed(const Duration(seconds: 3), widget.onEnd);
      }
    });
  }

  Future<bool> _checkPermissions() async {
    print('[DEBUG] Requesting microphone permission...');
    final status = await Permission.microphone.request();
    print('[DEBUG] Permission status: $status');
    return status.isGranted;
  }

  Future<void> _initiateCall() async {
    print('[DEBUG] Initiating call...');
    final hasPermission = await _checkPermissions();
    if (!hasPermission) {
      print('[DEBUG] Permission denied for microphone');
      if (mounted) {
        setState(() => _status = 'Permission denied');
        Future.delayed(const Duration(seconds: 2), widget.onEnd);
      }
      return;
    }

    print('[DEBUG] Fetching call token for receiver: ${widget.receiverId}');
    final response = await _callService.getCallToken(widget.receiverId);
    if (!mounted) return;

    if (response['success'] == true) {
      _callId = response['callId'];
      _roomName = response['roomName'];

      final user = await _authService.getUser();
      final callerName = user?['name'] ?? 'Admin';

      _remoteUserId = widget.receiverId; // store for WebRTC signaling
      _token = response['token'];
      _socketService.emit('call:initiate', {
        'callId': _callId,
        'receiverId': widget.receiverId,
        'callerName': callerName,
        'roomName': _roomName,
        'token': _token,
      });

      _playRingingTone();
      setState(() => _status = 'Ringing...');
    } else {
      _stopSounds();
      setState(() => _status = 'Call failed: ${response['message']}');
      Future.delayed(const Duration(seconds: 3), widget.onEnd);
    }
  }

  void _endCall() {
    _stopSounds();
    _playHangupSound();
    _stopTimer();
    if (_callId != null) {
      _socketService.emit('call:end', {
        'callId': _callId,
        'otherUserId': widget.receiverId,
      });
    }
    Future.delayed(const Duration(seconds: 3), widget.onEnd);
  }

  @override
  Widget build(BuildContext context) {
    if (_isMinimized) return _buildMinimized(context);
    return _buildFullScreen(context);
  }

  Widget _buildFullScreen(BuildContext context) {
    return Material(
      color: const Color(0xFF075E54).withOpacity(0.97),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Avatar with pulse animation
                ScaleTransition(
                  scale: _isActive ? const AlwaysStoppedAnimation(1.0) : _pulseAnim,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 4,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white24,
                      child: Text(
                        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                // Status / Timer
                Text(
                  _isActive ? _timerLabel : _status,
                  style: TextStyle(
                    color: _isActive ? Colors.greenAccent : Colors.white70,
                    fontSize: _isActive ? 22 : 16,
                    fontWeight: _isActive ? FontWeight.bold : FontWeight.normal,
                    decoration: TextDecoration.none,
                    letterSpacing: _isActive ? 2.0 : 0.0,
                  ),
                ),
                const SizedBox(height: 60),
                // Controls row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _callActionItem(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      color: _isMuted ? Colors.redAccent : Colors.white24,
                      onTap: _toggleMute,
                    ),
                    _callActionItem(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      label: 'Speaker',
                      color: _isSpeakerOn ? Colors.greenAccent.withOpacity(0.3) : Colors.white24,
                      onTap: _toggleSpeaker,
                    ),
                    _callActionItem(
                      icon: Icons.keyboard_arrow_down,
                      label: 'Minimize',
                      color: Colors.white24,
                      onTap: () => setState(() => _isMinimized = true),
                    ),
                  ],
                ),
                const SizedBox(height: 50),
                // End call button
                GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 36),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localAudioTrack?.enable(!_isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    webrtc.Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  Widget _buildMinimized(BuildContext context) {
    return Positioned(
      left: _minimizedPosition.dx,
      top: _minimizedPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() => _minimizedPosition += details.delta);
        },
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF075E54),
          child: Container(
            width: 130,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: InkWell(
                    onTap: () => setState(() => _isMinimized = false),
                    child: const Icon(Icons.open_in_full, color: Colors.white70, size: 16),
                  ),
                ),
                const SizedBox(height: 4),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white24,
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.name,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isActive ? _timerLabel : _status,
                  style: TextStyle(
                    color: _isActive ? Colors.greenAccent : Colors.white60,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _callActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white24,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.none),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// Incoming Call Overlay  (receiver side)
// ─────────────────────────────────────────────────────────────────────────────────

class IncomingCallOverlayManager {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required String callerName,
    required String callerId,
    required String callId,
    required String roomName,
  }) {
    showGlobal(
      Overlay.of(context),
      callerName: callerName,
      callerId: callerId,
      callId: callId,
      roomName: roomName,
    );
  }

  static void showGlobal(
    OverlayState overlay, {
    required String callerName,
    required String callerId,
    required String callId,
    required String roomName,
  }) {
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (_) => IncomingCallOverlay(
        callerName: callerName,
        callerId: callerId,
        callId: callId,
        roomName: roomName,
        onDismiss: hide,
      ),
    );
    
    // Ensure insertion happens after current frame to avoid "setState() or markNeedsBuild() called during build" crashes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_entry != null) {
        overlay.insert(_entry!);
      }
    });
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class IncomingCallOverlay extends StatefulWidget {
  final String callerName;
  final String callerId;
  final String callId;
  final String roomName;
  final VoidCallback onDismiss;

  const IncomingCallOverlay({
    super.key,
    required this.callerName,
    required this.callerId,
    required this.callId,
    required this.roomName,
    required this.onDismiss,
  });

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final SocketService _socketService = SocketService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  Room? _room;
  LocalAudioTrack? _localAudioTrack;
  bool _isMuted = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  bool _accepted = false;
  bool _isSpeakerOn = false;
  Timer? _callTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _playRingtone();

    // Auto-dismiss if caller ends
    _socketService.on('call:ended', (_) => _dismiss());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioPlayer.dispose();
    _callTimer?.cancel();
    _socketService.off('call:ended');
    _localAudioTrack = null;
    _room?.disconnect();
    super.dispose();
  }

  // ── Twilio Call helpers (Receiver) ───────────────────────────────────────
  Future<void> _startTwilioCall({required String token, required String roomName}) async {
    try {
      print('Receiver connecting to Twilio Room: $roomName');
      _stopSounds(); // Ensure ringing stops immediately
      // Create local audio track
      _localAudioTrack = LocalAudioTrack(true, 'microphone');

      _room = await TwilioProgrammableVideo.connect(
        ConnectOptions(
          token,
          roomName: roomName,
          audioTracks: [_localAudioTrack!],
        ),
      );
      
      await TwilioProgrammableVideo.setSpeakerphoneOn(true);
      debugPrint('Twilio (Receiver): Connected and speakerphone enabled');

      print('Receiver connected to room: ${_room?.sid}');

      // Listen for remote audio
      _room?.onParticipantConnected.listen((event) {
        _handleParticipant(event.remoteParticipant);
      });

      // Handle existing participants
      for (var p in _room?.remoteParticipants ?? []) {
        _handleParticipant(p);
      }

      _room?.onDisconnected.listen((event) {
        print('Room disconnected');
        _dismiss();
      });

      // Set initial speaker state
      webrtc.Helper.setSpeakerphoneOn(_isSpeakerOn);

    } catch (e) {
      debugPrint('Receiver Twilio error: $e');
    }
  }

  void _handleParticipant(RemoteParticipant participant) {
    // Handle existing tracks
    for (var pub in participant.remoteAudioTracks) {
      if (pub.remoteAudioTrack != null) {
        print('🔊 Existing audio track found from ${participant.identity}');
        pub.remoteAudioTrack?.enablePlayback(true);
      }
    }

    // Listen for new tracks
    participant.onAudioTrackSubscribed.listen((event) {
      print('🔊 Subscribed to new audio track from ${participant.identity}');
      event.remoteAudioTrack.enablePlayback(true);
    });
  }

  Future<void> _playRingtone() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource(
        'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/phone-ringing.mp3',
      ));
    } catch (_) {}
  }

  Future<void> _playHangupSound() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(UrlSource(
        'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/phone-hang-up.mp3',
      ));
    } catch (_) {}
  }

  Future<void> _stopSounds() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> _accept() async {
    print('[DEBUG] Accept button tapped');
    final hasPermission = await _checkPermissions();
    if (!hasPermission) {
      print('[DEBUG] Microphone permission denied on receiver side');
      _dismiss();
      return;
    }

    print('[DEBUG] Permission granted. Stopping ringtone...');
    _stopSounds();
    
    // 1. Fetch join token from backend
    print('[DEBUG] Fetching join token for callId: ${widget.callId}');
    final response = await _callService.joinCall(widget.callId);
    if (!response['success']) {
      debugPrint('Failed to join call: ${response['message']}');
      _dismiss();
      return;
    }

    // 2. Signal caller
    _socketService.emit('call:answer', {
      'callId': widget.callId,
      'callerId': widget.callerId,
      'roomName': response['roomName'],
    });

    setState(() => _accepted = true);
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    
    // 3. Connect to Twilio
    await _startTwilioCall(
      token: response['token'],
      roomName: response['roomName'],
    );
  }

  void _reject() {
    _stopSounds();
    _playHangupSound();
    _socketService.emit('call:reject', {
      'callId': widget.callId,
      'callerId': widget.callerId,
    });
    Future.delayed(const Duration(seconds: 3), widget.onDismiss);
  }

  Future<bool> _checkPermissions() async {
    print('[DEBUG-Receiver] Requesting microphone permission...');
    final status = await Permission.microphone.request();
    print('[DEBUG-Receiver] Permission status: $status');
    return status.isGranted;
  }

  void _dismiss() {
    _stopSounds();
    _playHangupSound();
    _callTimer?.cancel();
    Future.delayed(const Duration(seconds: 3), widget.onDismiss);
  }

  String get _timerLabel {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E).withOpacity(0.97),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _accepted ? const AlwaysStoppedAnimation(1.0) : _pulseAnim,
              child: Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 4),
                ),
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.blueAccent.withOpacity(0.3),
                  child: Text(
                    widget.callerName.isNotEmpty ? widget.callerName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.callerName,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
            ),
            const SizedBox(height: 8),
            Text(
              _accepted ? _timerLabel : 'Incoming Call...',
              style: TextStyle(
                color: _accepted ? Colors.greenAccent : Colors.white60,
                fontSize: _accepted ? 22 : 16,
                fontWeight: _accepted ? FontWeight.bold : FontWeight.normal,
                decoration: TextDecoration.none,
                letterSpacing: _accepted ? 2.0 : 0.0,
              ),
            ),
            const SizedBox(height: 60),
            if (!_accepted)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject
                  _callIconBtn(
                    icon: Icons.call_end,
                    color: Colors.red.shade600,
                    onTap: _reject,
                  ),
                  // Accept
                  _callIconBtn(
                    icon: Icons.call,
                    color: Colors.green.shade500,
                    onTap: _accept,
                  ),
                ],
              )
            else
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _callActionItem(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        color: _isMuted ? Colors.redAccent : Colors.white24,
                        onTap: _toggleMute,
                      ),
                      _callActionItem(
                        icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                        label: 'Speaker',
                        color: _isSpeakerOn ? Colors.greenAccent.withOpacity(0.3) : Colors.white24,
                        onTap: _toggleSpeaker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),
                  _callIconBtn(
                    icon: Icons.call_end,
                    color: Colors.red.shade600,
                    onTap: () {
                      _socketService.emit('call:end', {'callId': widget.callId, 'otherUserId': widget.callerId});
                      _dismiss();
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localAudioTrack?.enable(!_isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    webrtc.Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  Widget _callIconBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 20, spreadRadius: 4)],
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _callActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white24,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.none)),
      ],
    );
  }
}
