import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_model.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../services/backend_service.dart';
import '../services/connection_service.dart';
import '../services/background_service.dart';
import '../services/nearby_service.dart';
import '../theme.dart';
import '../utils/anonymous_identity.dart';
import 'chat_screen.dart';
import 'edit_profile_screen.dart'; // EditProfileContent

// ── Anonymous avatar colors ──────────────────────────────────────────────────

const _anonAvatarColors = [
  Color(0xFF5C6BC0), // indigo
  Color(0xFF7E57C2), // deep purple
  Color(0xFF26A69A), // teal
  Color(0xFFEF5350), // red
  Color(0xFFAB47BC), // purple
  Color(0xFF42A5F5), // blue
  Color(0xFF66BB6A), // green
  Color(0xFFFF7043), // deep orange
  Color(0xFF26C6DA), // cyan
  Color(0xFFEC407A), // pink
];

Color _anonColor(String connectionId) {
  final hash = connectionId.hashCode.abs();
  return _anonAvatarColors[hash % _anonAvatarColors.length];
}

// ── Card button modes ────────────────────────────────────────────────────────
enum CardButtonMode { none, connect, pending, accept }

// ── Dashboard screen ─────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final String? userPhotoUrl;
  final String displayName;
  final VoidCallback onSignOut;
  final NearbyService nearbyService;
  final ConnectionService connectionService;

  const DashboardScreen({
    super.key,
    this.userPhotoUrl,
    required this.displayName,
    required this.onSignOut,
    required this.nearbyService,
    required this.connectionService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTab = 0;
  bool _isScanning = false;
  bool _isTogglingBluetooth = false;
  bool _isDeleting = false;
  bool _isClearingData = false;
  bool _isSendingNotification = false;
  /// Connection IDs currently being accepted (for button loading state).
  final Set<String> _acceptingConnectionIds = {};

  NearbyService get _svc => widget.nearbyService;
  ConnectionService get _connSvc => widget.connectionService;
  String get _firstName => widget.displayName.split(' ').first;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    _connSvc.addListener(_onChanged);
    _startScanning();
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    _connSvc.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startScanning() async {
    if (_isTogglingBluetooth) return;
    setState(() => _isTogglingBluetooth = true);
    try {
      final granted = await _svc.requestPermissions();
      if (!granted) return;
      await _svc.startBoth();
      await BackgroundServiceManager.start();
      if (mounted) setState(() => _isScanning = true);
    } finally {
      if (mounted) setState(() => _isTogglingBluetooth = false);
    }
  }

  Future<void> _stopScanning() async {
    if (_isTogglingBluetooth) return;
    setState(() => _isTogglingBluetooth = true);
    try {
      await BackgroundServiceManager.stop();
      await _svc.stopAll();
      if (mounted) setState(() => _isScanning = false);
    } finally {
      if (mounted) setState(() => _isTogglingBluetooth = false);
    }
  }

  Future<void> _refreshDashboard() async {
    await _connSvc.refreshConnections();
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fresh Start'),
        content: const Text(
          'This will remove all your connections and chat history. Your profile will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClearingData = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('student_uid');

      if (uid == null || uid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No account found')));
          setState(() => _isClearingData = false);
        }
        return;
      }

      final success = await BackendService.clearUserData(uid);
      if (success) {
        widget.connectionService.clearLocalData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All connections and chats cleared')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to clear data')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isClearingData = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all associated data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('student_uid');

      if (uid == null || uid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No account found to delete')),
          );
          setState(() => _isDeleting = false);
        }
        return;
      }

      final success = await BackendService.deleteStudent(uid);
      if (success) {
        await prefs.remove('student_uid');
        widget.onSignOut();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete account')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _sendMockNotification() async {
    setState(() => _isSendingNotification = true);
    try {
      // 1. Inject demo connection card into Discover
      final connectionId = _connSvc.injectDemoConnection();

      // 2. Show a local notification mimicking a Gemini match alert
      const androidDetails = AndroidNotificationDetails(
        'nearby_alerts',
        'Nearby Alerts',
        channelDescription: 'Notifications when someone is nearby',
        importance: Importance.high,
        priority: Priority.high,
      );
      const notifDetails = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      );
      await FlutterLocalNotificationsPlugin().show(
        42,
        '\u{2728} Gemini found a match!',
        'An 88% skills match is nearby — someone with full-stack and AI experience that complements your profile.',
        notifDetails,
      );

      // 3. Switch to dashboard tab
      if (mounted) {
        setState(() => _selectedTab = 0);
      }

      // 4. After 5 seconds, promote to Request (peer accepts)
      Timer(const Duration(seconds: 5), () {
        if (mounted) {
          _connSvc.promoteDemoToRequest(connectionId);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingNotification = false);
    }
  }

  /// Real name from peer profile (used only when both accepted).
  String _realPeerName(ConnectionModel conn) {
    final peerUid = conn.otherUid(_connSvc.myUid ?? '');
    final profile = _connSvc.peerProfiles[peerUid];
    if (profile != null) {
      final identity = profile['identity'] as Map<String, dynamic>?;
      return identity?['full_name'] as String? ?? 'Unknown';
    }
    return 'Unknown';
  }

  /// Display name: anonymous until both accept, then real name.
  String _peerName(ConnectionModel conn) {
    if (conn.isComplete) return _realPeerName(conn);
    return anonymousName(conn.connectionId);
  }

  String _peerInitials(ConnectionModel conn) {
    if (!conn.isComplete) return anonymousEmoji(conn.connectionId);
    final name = _realPeerName(conn);
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  /// Whether to show emoji avatar (anonymous) vs initials.
  bool _isAnonymous(ConnectionModel conn) => !conn.isComplete;

  /// Get tags for a connection peer (focus areas, project stage, etc.)
  List<String> _peerTags(ConnectionModel conn) {
    final peerUid = conn.otherUid(_connSvc.myUid ?? '');
    final profile = _connSvc.peerProfiles[peerUid];
    if (profile == null) return [];
    final tags = <String>[];
    // Focus areas
    final focusAreas = profile['focus_areas'] as List?;
    if (focusAreas != null) {
      for (final f in focusAreas) {
        final s = f.toString();
        tags.add(_focusLabel(s));
      }
    }
    // Project stage
    final project = profile['project'] as Map<String, dynamic>?;
    if (project != null) {
      final stage = project['stage'] as String?;
      if (stage != null && stage.isNotEmpty) {
        tags.add(_stageLabel(stage));
      }
    }
    return tags;
  }

  static String _focusLabel(String raw) {
    switch (raw) {
      case 'startup': return 'Startup';
      case 'research': return 'Research';
      case 'side_project': return 'Side Project';
      case 'open_source': return 'Open Source';
      case 'looking': return 'Opportunities';
      default: return raw;
    }
  }

  static String _stageLabel(String raw) {
    switch (raw) {
      case 'idea': return 'Idea';
      case 'mvp': return 'MVP';
      case 'launched': return 'Launched';
      case 'scaling': return 'Scaling';
      default: return raw;
    }
  }

  String _connectionRoomId(ConnectionModel conn) {
    final uids = [conn.uid1, conn.uid2]..sort();
    return '${uids[0]}_${uids[1]}';
  }

  void _pushChatScreen(ConnectionModel conn) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerName: _peerName(conn),
          peerInitials: _peerInitials(conn),
          roomId: _connectionRoomId(conn),
          myUid: _connSvc.myUid ?? '',
          onAvatarTap: conn.isComplete
              ? () => _showFullProfileSheet(conn)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // Main content
          SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _selectedTab == 0
                  ? _buildDashboardContent(theme)
                  : _selectedTab == 1
                      ? _buildChatContent(theme)
                      : _selectedTab == 2
                          ? EditProfileContent(
                              key: const ValueKey('profile'),
                              userPhotoUrl: widget.userPhotoUrl,
                              displayName: widget.displayName,
                              onSignOut: widget.onSignOut,
                            )
                          : _buildDeveloperContent(),
            ),
          ),
          // Floating glass nav bar
          Positioned(
            left: 24,
            right: 24,
            bottom: bottomPadding + 16,
            child: _GlassNavBar(
              selectedIndex: _selectedTab,
              onTap: (index) => setState(() => _selectedTab = index),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dashboard tab ──────────────────────────────────────────────────────

  CardButtonMode _buttonModeFor(ConnectionModel conn) {
    final myUid = _connSvc.myUid ?? '';
    if (conn.isComplete) return CardButtonMode.none; // chat button shown separately
    if (conn.hasAccepted(myUid)) return CardButtonMode.pending;
    final otherUid = conn.otherUid(myUid);
    if (conn.hasAccepted(otherUid)) return CardButtonMode.accept;
    return CardButtonMode.connect;
  }

  Widget _buildConnectionSection(
    ThemeData theme,
    String title,
    List<ConnectionModel> connections, {
    CardButtonMode? overrideMode,
  }) {
    if (connections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding, 28, AppSpacing.screenPadding, 14,
          ),
          child: Row(
            children: [
              Text(
                title,
                style: GoogleFonts.sora(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${connections.length}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Divider(height: 1)),
            ],
          ),
        ),
        ...connections.map((conn) {
          final mode = overrideMode ?? _buttonModeFor(conn);
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 12,
            ),
            child: _ConnectionCard(
              conn: conn,
              peerName: _peerName(conn),
              peerInitials: _peerInitials(conn),
              myUid: _connSvc.myUid ?? '',
              isAnonymous: _isAnonymous(conn),
              buttonMode: mode,
              isLoading: _acceptingConnectionIds.contains(conn.connectionId),
              showChatButton: conn.isComplete,
              onTap: () => _showProfileSheet(conn),
              onAction: () async {
                setState(() => _acceptingConnectionIds.add(conn.connectionId));
                try {
                  await _connSvc.acceptConnection(conn.connectionId);
                } finally {
                  if (mounted) setState(() => _acceptingConnectionIds.remove(conn.connectionId));
                }
              },
              onChat: () => _pushChatScreen(conn),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDashboardContent(ThemeData theme) {
    final connected = _connSvc.connectedNearby;
    final incoming = _connSvc.incomingRequests;
    final discovered = _connSvc.discoveredMatches;
    final sent = _connSvc.sentRequests;
    // Combine discovered + sent into one "Discover" section
    final discoverList = [...discovered, ...sent];

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      color: AppColors.primary,
      child: ListView(
        key: const ValueKey('dashboard'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          // Welcome header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding, 28, AppSpacing.screenPadding, 0,
            ),
            child: Text(
              '\u{1F44B} Welcome back, $_firstName',
              style: theme.textTheme.headlineSmall?.copyWith(fontSize: 26),
            ),
          ),
          // Status banner
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, 20, AppSpacing.screenPadding, 0),
            child: _StatusBanner(
              message: _svc.statusMessage,
              isScanning: _isScanning,
              isToggling: _isTogglingBluetooth,
              onToggle: _isScanning ? _stopScanning : _startScanning,
            ),
          ),
          // ── Skeleton loader for BT-connected, API-loading peers ──
          if (_connSvc.loadingPeerUids.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding, 20, AppSpacing.screenPadding, 10,
              ),
              child: _SkeletonCard(),
            ),
          // ── Profile card sections ──
          _buildConnectionSection(theme, 'Connected', connected),
          _buildConnectionSection(theme, 'Requests', incoming, overrideMode: CardButtonMode.accept),
          _buildConnectionSection(theme, 'Discover', discoverList),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Profile bottom sheet (connection sheet) ─────────────────────────────

  void _showProfileSheet(ConnectionModel conn) {
    final myUid = _connSvc.myUid ?? '';
    final name = _peerName(conn);
    final initials = _peerInitials(conn);
    final summary = conn.summaryFor(myUid);
    final iAccepted = conn.hasAccepted(myUid);
    final isComplete = conn.isComplete;
    final isAnon = _isAnonymous(conn);
    final tags = _peerTags(conn);
    final avatarColor = isAnon
        ? _anonColor(conn.connectionId)
        : AppColors.surfaceLightBlue;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String buttonLabel;
        bool buttonEnabled;
        Color buttonColor;
        VoidCallback? buttonAction;
        final otherUid = conn.otherUid(myUid);
        final otherAccepted = conn.hasAccepted(otherUid);

        if (isComplete) {
          buttonLabel = 'Chat';
          buttonEnabled = true;
          buttonColor = AppColors.primary;
          buttonAction = () {
            Navigator.pop(ctx);
            _pushChatScreen(conn);
          };
        } else if (iAccepted) {
          buttonLabel = 'Pending';
          buttonEnabled = false;
          buttonColor = AppColors.inactive;
          buttonAction = null;
        } else if (otherAccepted) {
          // They connected first — show Accept
          buttonLabel = 'Accept';
          buttonEnabled = true;
          buttonColor = AppColors.primary;
          buttonAction = () async {
            Navigator.pop(ctx);
            setState(() => _acceptingConnectionIds.add(conn.connectionId));
            try {
              await _connSvc.acceptConnection(conn.connectionId);
            } finally {
              if (mounted) setState(() => _acceptingConnectionIds.remove(conn.connectionId));
            }
          };
        } else {
          // Neither connected — show Connect
          buttonLabel = 'Connect';
          buttonEnabled = true;
          buttonColor = AppColors.primary;
          buttonAction = () async {
            Navigator.pop(ctx);
            setState(() => _acceptingConnectionIds.add(conn.connectionId));
            try {
              await _connSvc.acceptConnection(conn.connectionId);
            } finally {
              if (mounted) setState(() => _acceptingConnectionIds.remove(conn.connectionId));
            }
          };
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surfaceGray,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar — tap to see full profile when revealed
              GestureDetector(
                onTap: isComplete ? () {
                  Navigator.pop(ctx);
                  _showFullProfileSheet(conn);
                } : null,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: isAnon ? 36 : 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Name
              Text(
                name,
                style: GoogleFonts.sora(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              // Tags instead of match percentage
              if (tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  )).toList(),
                )
              else
                Text(
                  '${conn.matchPercentage.toStringAsFixed(0)}% match',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              const SizedBox(height: 18),
              // Summary (from Gemini)
              if (summary != null && summary.isNotEmpty)
                Text(
                  summary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 28),
              // Action button
              SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeight,
                child: FilledButton(
                  onPressed: buttonEnabled ? buttonAction : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: buttonEnabled
                        ? AppColors.onPrimary
                        : AppColors.textTertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: Text(
                    buttonLabel,
                    style: GoogleFonts.sora(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Full profile sheet (all onboarding info) ────────────────────────────

  void _showFullProfileSheet(ConnectionModel conn) {
    final peerUid = conn.otherUid(_connSvc.myUid ?? '');
    final profile = _connSvc.peerProfiles[peerUid];
    if (profile == null) return;

    final identity = profile['identity'] as Map<String, dynamic>? ?? {};
    final name = identity['full_name'] as String? ?? 'Unknown';
    final university = identity['university'] as String? ?? '';
    final gradYear = identity['graduation_year'];
    final majors = (identity['major'] as List?)?.cast<String>() ?? [];
    final minors = (identity['minor'] as List?)?.cast<String>() ?? [];
    final focusAreas = (profile['focus_areas'] as List?)?.cast<String>() ?? [];
    final project = profile['project'] as Map<String, dynamic>? ?? {};
    final oneLiner = project['one_liner'] as String?;
    final stage = project['stage'] as String?;
    final industries = (project['industry'] as List?)?.cast<String>() ?? [];
    final skills = profile['skills'] as Map<String, dynamic>? ?? {};
    final possessed = (skills['possessed'] as List?)
        ?.map((s) => (s as Map<String, dynamic>)['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList() ?? [];
    final needed = (skills['needed'] as List?)
        ?.map((s) => (s as Map<String, dynamic>)['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList() ?? [];

    final initials = _peerInitials(conn);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceGray,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Avatar + Name
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLightBlue,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      name,
                      style: GoogleFonts.sora(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (university.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        '$university${gradYear != null ? ' \u2022 $gradYear' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Majors / Minors
                  if (majors.isNotEmpty)
                    _profileSection('Major', majors.join(', ')),
                  if (minors.isNotEmpty)
                    _profileSection('Minor', minors.join(', ')),
                  // Focus areas
                  if (focusAreas.isNotEmpty) ...[
                    _profileLabel('Focus'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: focusAreas.map((f) => _tagChip(_focusLabel(f))).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Project
                  if (oneLiner != null && oneLiner.isNotEmpty)
                    _profileSection('Project', oneLiner),
                  if (stage != null && stage.isNotEmpty)
                    _profileSection('Stage', _stageLabel(stage)),
                  if (industries.isNotEmpty) ...[
                    _profileLabel('Industry'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: industries.map((d) => _tagChip(d)).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Skills
                  if (possessed.isNotEmpty) ...[
                    _profileLabel('Skills'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: possessed.map((s) => _tagChip(s)).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (needed.isNotEmpty) ...[
                    _profileLabel('Looking for'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: needed.map((s) => _tagChip(s, accent: true)).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _profileSection(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileLabel(label),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
      ),
    );
  }

  Widget _tagChip(String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.surfaceLightBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: accent ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
    );
  }

  // ── Chat tab ─────────────────────────────────────────────────────────

  Widget _buildChatContent(ThemeData theme) {
    final acceptedConnections = _connSvc.allAccepted;

    return Column(
      key: const ValueKey('chat'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            24,
            AppSpacing.screenPadding,
            16,
          ),
          child: Text('Messages', style: theme.textTheme.headlineSmall?.copyWith(fontSize: 26)),
        ),
        Expanded(
          child: acceptedConnections.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No conversations yet',
                          style: GoogleFonts.sora(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Connect with people to start chatting',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshDashboard,
                  color: AppColors.primary,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
                    itemCount: acceptedConnections.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 0.5,
                      indent: AppSpacing.screenPadding + 56,
                    ),
                    itemBuilder: (context, index) {
                      final conn = acceptedConnections[index];
                      return _ChatListTile(
                        name: _peerName(conn),
                        initials: _peerInitials(conn),
                        summary: conn.summaryFor(_connSvc.myUid ?? ''),
                        onTap: () => _pushChatScreen(conn),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // Profile tab is now handled by EditProfileContent widget.

  // ── Developer tab ──────────────────────────────────────────────────────

  Widget _buildDeveloperContent() {
    return ListView(
      key: const ValueKey('developer'),
      padding: const EdgeInsets.only(top: 24, bottom: 120),
      children: [
        // ── Notifications section ──
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: Text(
            'Notifications',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: FilledButton.icon(
            onPressed: _isSendingNotification ? null : _sendMockNotification,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Start Demo'),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: Text(
            'Simulates a Gemini match notification and walks through the full connection lifecycle.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),

        const SizedBox(height: 32),

        // ── Data section ──
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: Text(
            'Data',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: FilledButton(
            onPressed: _isClearingData ? null : _clearData,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceLightBlue,
              foregroundColor: AppColors.textPrimary,
            ),
            child: _isClearingData
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  )
                : const Text('Fresh Start'),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: FilledButton(
            onPressed: _isDeleting ? null : _deleteAccount,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Delete Account'),
          ),
        ),
      ],
    );
  }
}

// ── Connection card ──────────────────────────────────────────────────────────

class _ConnectionCard extends StatelessWidget {
  final ConnectionModel conn;
  final String peerName;
  final String peerInitials;
  final String myUid;
  final bool isAnonymous;
  final CardButtonMode buttonMode;
  final bool isLoading;
  final bool showChatButton;
  final VoidCallback onTap;
  final Future<void> Function() onAction;
  final VoidCallback? onChat;

  const _ConnectionCard({
    required this.conn,
    required this.peerName,
    required this.peerInitials,
    required this.myUid,
    this.isAnonymous = false,
    required this.buttonMode,
    this.isLoading = false,
    required this.showChatButton,
    required this.onTap,
    required this.onAction,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final avatarColor = isAnonymous
        ? _anonColor(conn.connectionId)
        : AppColors.surfaceLightBlue;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceGray,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                peerInitials,
                style: TextStyle(
                  fontSize: isAnonymous ? 26 : 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName,
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${conn.matchPercentage.toStringAsFixed(0)}% match',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Action button (Connect / Pending / Accept)
            if (buttonMode == CardButtonMode.connect || buttonMode == CardButtonMode.accept) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: isLoading ? null : onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: isLoading ? AppColors.inactive : AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    buttonMode == CardButtonMode.accept ? 'Accept' : 'Connect',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isLoading ? AppColors.textTertiary : AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ] else if (buttonMode == CardButtonMode.pending) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.inactive,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Pending',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
            // Chat icon — only visible when connected
            if (showChatButton) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onChat,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    size: 20,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Chat list tile ───────────────────────────────────────────────────────

class _ChatListTile extends StatelessWidget {
  final String name;
  final String initials;
  final String? summary;
  final VoidCallback onTap;

  const _ChatListTile({
    required this.name,
    required this.initials,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = summary ?? 'Tap to start chatting';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: 16,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.surfaceLightBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glass morphism nav bar ────────────────────────────────────────────────

class _GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _GlassNavBar({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF797583).withValues(alpha: 0.18),
                const Color(0xFF363567).withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavBarItem(
                icon: Icons.explore_rounded,
                label: 'Discover',
                isSelected: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavBarItem(
                icon: Icons.chat_bubble_rounded,
                label: 'Chat',
                isSelected: selectedIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavBarItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                isSelected: selectedIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavBarItem(
                icon: Icons.code_rounded,
                label: 'Dev',
                isSelected: selectedIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        height: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton loading card ──────────────────────────────────────────────────

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceGray,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Avatar skeleton
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceLightBlue,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 130,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLightBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 90,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLightBlue.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isScanning;
  final bool isToggling;
  final VoidCallback onToggle;

  const _StatusBanner({
    required this.message,
    required this.isScanning,
    this.isToggling = false,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isScanning
        ? AppColors.primary.withValues(alpha: 0.08)
        : AppColors.surfaceGray;
    final borderColor = isScanning
        ? AppColors.primary.withValues(alpha: 0.2)
        : AppColors.border;

    // Semicircle colors: inner = lightest, outer = subtler
    final innerCircle = isScanning
        ? AppColors.primary.withValues(alpha: 0.10)
        : AppColors.surfaceLightBlue.withValues(alpha: 0.5);
    final outerCircle = isScanning
        ? AppColors.primary.withValues(alpha: 0.05)
        : AppColors.surfaceLightBlue.withValues(alpha: 0.25);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Concentric semicircles
            Positioned(
              bottom: -160,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 264,
                  height: 264,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: outerCircle,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -118,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: innerCircle,
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    isScanning
                        ? Icons.bluetooth_searching
                        : Icons.bluetooth_disabled,
                    size: 24,
                    color: isScanning
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      isScanning ? 'Live' : 'Idle',
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isScanning
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: isToggling ? null : onToggle,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isScanning
                            ? AppColors.primary
                            : AppColors.surfaceLightBlue,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        isScanning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                        color: isScanning
                            ? AppColors.onPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
