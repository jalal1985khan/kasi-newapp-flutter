import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:twilio_programmable_video/twilio_programmable_video.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/chat/group_call_service.dart';
import '../../services/chat/socket_service.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Manager (show/hide)
// ─────────────────────────────────────────────────────────────────────────────
class GroupCallOverlayManager {
  static OverlayEntry? _entry;
  static bool get isActive => _entry != null;

  /// Show from the group chat page — host initiating
  static void showAsHost(
    BuildContext context, {
    required String groupId,
    required String groupName,
    required List<Map<String, dynamic>> members,
  }) {
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (_) => GroupCallOverlay(
        groupId: groupId,
        groupName: groupName,
        members: members,
        isHost: true,
        callId: null,
        roomName: null,
        hostName: null,
        hostImage: null,
        onEnd: hide,
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Incoming Group Call Manager (receiver side)
// ─────────────────────────────────────────────────────────────────────────────
class IncomingGroupCallOverlayManager {
  static OverlayEntry? _entry;

  static void showGlobal(
    OverlayState overlay, {
    required String callId,
    required String groupId,
    required String groupName,
    required String hostName,
    required String hostImage,
    required int memberCount,
  }) {
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (_) => GroupCallOverlay(
        groupId: groupId,
        groupName: groupName,
        members: const [],
        isHost: false,
        callId: callId,
        roomName: null,
        hostName: hostName,
        hostImage: hostImage,
        memberCount: memberCount,
        onEnd: hide,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_entry != null) overlay.insert(_entry!);
    });
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Group Call Overlay Widget
// ─────────────────────────────────────────────────────────────────────────────
class GroupCallOverlay extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<Map<String, dynamic>> members;
  final bool isHost;
  final String? callId;
  final String? roomName;
  final String? hostName;
  final String? hostImage;
  final int memberCount;
  final VoidCallback onEnd;

  const GroupCallOverlay({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.members,
    required this.isHost,
    required this.callId,
    required this.roomName,
    required this.hostName,
    required this.hostImage,
    this.memberCount = 2,
    required this.onEnd,
  });

  @override
  State<GroupCallOverlay> createState() => _GroupCallOverlayState();
}

class _GroupCallOverlayState extends State<GroupCallOverlay>
    with SingleTickerProviderStateMixin {
  final GroupCallService _groupCallService = GroupCallService();
  final SocketService _socketService = SocketService();
  final AuthService _authService = AuthService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Call state
  String _status = '';
  String? _callId;
  String? _roomName;
  bool _isActive = false;
  bool _isMuted = false;
  bool _isMinimized = false;
  Offset _minimizedPos = const Offset(20, 100);

  // Participants
  final List<String> _joinedNames = [];

  // Twilio
  Room? _room;
  LocalAudioTrack? _localAudioTrack;

  // Timer
  Timer? _callTimer;
  int _elapsed = 0;

  // Animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _setupSocketListeners();

    if (widget.isHost) {
      _status = 'Starting call...';
      _playDialingTone();
      _initiateAsHost();
    } else {
      _status = 'Incoming group call';
      _callId = widget.callId;
      _playRingtone();
    }
  }

  @override
  void dispose() {
    _socketService.off('group_call:participant_joined');
    _socketService.off('group_call:participant_left');
    _socketService.off('group_call:ended');
    _socketService.off('group_call:cancelled');
    _stopTimer();
    _stopSounds();
    _pulseCtrl.dispose();
    _audioPlayer.dispose();
    _localAudioTrack = null;
    _room?.disconnect();
    super.dispose();
  }

  // ── Sound ──────────────────────────────────────────────────────────────────
  Future<void> _playDialingTone() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource(
        'https://assets.mixkit.co/active_storage/sfx/2354/2354-preview.mp3',
      ));
    } catch (_) {}
  }

  Future<void> _playRingtone() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource(
        'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/phone-ringing.mp3',
      ));
    } catch (_) {}
  }

  Future<void> _stopSounds() async {
    try { await _audioPlayer.stop(); } catch (_) {}
  }

  Future<void> _playHangup() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(UrlSource(
        'https://satyanewbucket.lon1.cdn.digitaloceanspaces.com/flutter/phone-hang-up.mp3',
      ));
    } catch (_) {}
  }

  // ── Timer ──────────────────────────────────────────────────────────────────
  void _startTimer() {
    _callTimer?.cancel();
    _elapsed = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  void _stopTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  String get _timerLabel {
    final h = _elapsed ~/ 3600;
    final m = (_elapsed % 3600) ~/ 60;
    final s = _elapsed % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    }
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  // ── Socket listeners ───────────────────────────────────────────────────────
  void _setupSocketListeners() {
    _socketService.on('group_call:participant_joined', (data) {
      if (data['callId'] == _callId && mounted) {
        final name = data['userName']?.toString() ?? 'Member';
        setState(() {
          if (!_joinedNames.contains(name)) _joinedNames.add(name);
        });
      }
    });

    _socketService.on('group_call:participant_left', (data) {
      if (data['callId'] == _callId && mounted) {
        setState(() {});
      }
    });

    _socketService.on('group_call:ended', (data) {
      if (data['callId'] == _callId && mounted) {
        _endLocally();
      }
    });

    _socketService.on('group_call:cancelled', (data) {
      if (data['callId'] == _callId && mounted) {
        _endLocally(showHangup: false);
      }
    });
  }

  // ── Twilio ─────────────────────────────────────────────────────────────────
  Future<bool> _checkMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _connectToRoom(String token, String roomName) async {
    try {
      _stopSounds();
      _localAudioTrack = LocalAudioTrack(true, 'microphone');
      _room = await TwilioProgrammableVideo.connect(
        ConnectOptions(
          token,
          roomName: roomName,
          audioTracks: [_localAudioTrack!],
          enableDominantSpeaker: true,
        ),
      );
      await TwilioProgrammableVideo.setSpeakerphoneOn(_isSpeakerOn);

      // Existing participants
      for (var p in _room?.remoteParticipants ?? []) {
        _handleParticipant(p);
      }

      _room?.onParticipantConnected.listen((e) => _handleParticipant(e.remoteParticipant));
      _room?.onDisconnected.listen((_) => _endLocally());

      if (mounted) {
        setState(() {
          _isActive = true;
          _status = 'Connected';
        });
        _startTimer();
      }
    } catch (e) {
      debugPrint('[GroupCall] Twilio error: $e');
      if (mounted) {
        setState(() => _status = 'Connection failed');
        Future.delayed(const Duration(seconds: 2), _endLocally);
      }
    }
  }

  void _handleParticipant(RemoteParticipant p) {
    for (var pub in p.remoteAudioTracks) {
      pub.remoteAudioTrack?.enablePlayback(true);
    }
    p.onAudioTrackSubscribed.listen((e) => e.remoteAudioTrack.enablePlayback(true));
  }

  // ── Host flow ──────────────────────────────────────────────────────────────
  Future<void> _initiateAsHost() async {
    final hasPermission = await _checkMicPermission();
    if (!hasPermission) {
      if (mounted) setState(() => _status = 'Microphone permission denied');
      Future.delayed(const Duration(seconds: 2), widget.onEnd);
      return;
    }

    final response = await _groupCallService.getGroupCallToken(widget.groupId);
    if (!mounted) return;

    if (response['success'] == true) {
      _callId   = response['callId'];
      _roomName = response['roomName'];
      final String token = response['token'];

      final user = await _authService.getUser();
      final hostName  = user?['name'] ?? 'Host';
      final hostImage = AuthService.getProfileImage(user) ?? '';

      // Notify all members via socket
      _socketService.emit('group_call:initiate', {
        'callId':      _callId,
        'groupId':     widget.groupId,
        'groupName':   widget.groupName,
        'hostId':      user?['id'] ?? user?['_id'],
        'hostName':    hostName,
        'hostImage':   hostImage,
        'roomName':    _roomName,
        'memberCount': widget.members.length,
        'memberIds':   widget.members.map((m) => m['userId']).toList(),
      });

      setState(() => _status = 'Ringing members...');
      await _connectToRoom(token, _roomName!);
    } else {
      setState(() => _status = 'Failed: ${response['message']}');
      Future.delayed(const Duration(seconds: 3), widget.onEnd);
    }
  }

  // ── Member accept ──────────────────────────────────────────────────────────
  Future<void> _acceptCall() async {
    final hasPermission = await _checkMicPermission();
    if (!hasPermission) {
      _declineCall();
      return;
    }

    _stopSounds();
    setState(() => _status = 'Joining...');

    final response = await _groupCallService.joinGroupCall(_callId!);
    if (!mounted) return;

    if (response['success'] == true) {
      final user = await _authService.getUser();
      _socketService.emit('group_call:join', {
        'callId':    _callId,
        'groupId':   widget.groupId,
        'userId':    user?['id'] ?? user?['_id'],
        'userName':  user?['name'] ?? 'Member',
        'userImage': AuthService.getProfileImage(user) ?? '',
      });
      await _connectToRoom(response['token'], response['roomName']);
    } else {
      setState(() => _status = 'Failed to join call');
      Future.delayed(const Duration(seconds: 2), _endLocally);
    }
  }

  // ── Decline ────────────────────────────────────────────────────────────────
  void _declineCall() {
    _socketService.emit('group_call:decline', {
      'callId':  _callId,
      'groupId': widget.groupId,
    });
    if (_callId != null) {
      _groupCallService.endGroupCall(_callId!, decline: true);
    }
    _endLocally(showHangup: false);
  }

  // ── Leave / End ────────────────────────────────────────────────────────────
  void _leaveCall() {
    _socketService.emit('group_call:leave', {
      'callId':  _callId,
      'groupId': widget.groupId,
      'isHost':  widget.isHost,
    });
    if (_callId != null) {
      _groupCallService.endGroupCall(_callId!);
    }
    _endLocally();
  }

  void _endLocally({bool showHangup = true}) {
    _stopTimer();
    _stopSounds();
    if (showHangup) _playHangup();
    _localAudioTrack = null;
    _room?.disconnect();
    _room = null;
    Future.delayed(Duration(seconds: showHangup ? 2 : 0), widget.onEnd);
  }

  bool _isSpeakerOn = true; // Default to speakerphone

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    TwilioProgrammableVideo.setSpeakerphoneOn(_isSpeakerOn);
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localAudioTrack?.enable(!_isMuted);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isMinimized) return _buildMinimized();
    if (!widget.isHost && !_isActive) return _buildIncoming();
    return _buildActive();
  }

  // ── Incoming UI (receiver only) ─────────────────────────────────────────
  Widget _buildIncoming() {
    return Material(
      color: Colors.transparent,
      child: Container(
        color: const Color(0xCC000000),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing group icon
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.4), blurRadius: 24, spreadRadius: 4)],
                    ),
                    child: const Icon(Icons.groups, color: Colors.white, size: 48),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Incoming Group Call', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Text(
                  widget.groupName,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.hostName ?? "Host"} · ${widget.memberCount} members',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, decoration: TextDecoration.none),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _declineCall,
                        child: Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.red.withOpacity(0.4)),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.call_end, color: Colors.redAccent, size: 26),
                              SizedBox(height: 4),
                              Text('Decline', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: _acceptCall,
                        child: Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A884),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFF00A884).withOpacity(0.4), blurRadius: 16, spreadRadius: 2)],
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.call, color: Colors.white, size: 26),
                              SizedBox(height: 4),
                              Text('Join', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Active / Calling UI ─────────────────────────────────────────────────
  Widget _buildActive() {
    return Material(
      color: const Color(0xFF0D1B2A),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Group icon
                ScaleTransition(
                  scale: _isActive ? const AlwaysStoppedAnimation(1.0) : _pulseAnim,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 3),
                      boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)],
                    ),
                    child: const Icon(Icons.groups, color: Colors.white, size: 56),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.groupName,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                ),
                const SizedBox(height: 8),
                // Status / timer
                Text(
                  _isActive ? _timerLabel : _status,
                  style: TextStyle(
                    color: _isActive ? Colors.greenAccent : Colors.white70,
                    fontSize: _isActive ? 22 : 15,
                    fontWeight: _isActive ? FontWeight.bold : FontWeight.normal,
                    letterSpacing: _isActive ? 2.0 : 0,
                    decoration: TextDecoration.none,
                  ),
                ),
                // Participant chips
                if (_joinedNames.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: _joinedNames.take(6).map((name) => Chip(
                      label: Text(name, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      backgroundColor: Colors.white.withOpacity(0.12),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 56),
                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlBtn(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      color: _isMuted ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.15),
                      onTap: _toggleMute,
                    ),
                    _controlBtn(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      label: 'Speaker',
                      color: _isSpeakerOn ? Colors.greenAccent.withOpacity(0.3) : Colors.white.withOpacity(0.15),
                      onTap: _toggleSpeaker,
                    ),
                    _controlBtn(
                      icon: Icons.keyboard_arrow_down,
                      label: 'Minimize',
                      color: Colors.white.withOpacity(0.15),
                      onTap: () => setState(() => _isMinimized = true),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                GestureDetector(
                  onTap: _leaveCall,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 20, spreadRadius: 4)],
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

  // ── Minimized floating bubble ───────────────────────────────────────────
  Widget _buildMinimized() {
    return Positioned(
      left: _minimizedPos.dx,
      top: _minimizedPos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _minimizedPos = Offset(
              _minimizedPos.dx + details.delta.dx,
              _minimizedPos.dy + details.delta.dy,
            );
          });
        },
        onTap: () => setState(() => _isMinimized = false),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(30),
          color: const Color(0xFF00A884), // WhatsApp Green
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.groups, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  _isActive ? _timerLabel : _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlBtn({required IconData icon, required String label, required VoidCallback onTap, Color color = Colors.white24}) {
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
