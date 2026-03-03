import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/backend_service.dart';
import '../theme.dart';

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    required this.isMe,
    required this.timestamp,
  });
}

class ChatScreen extends StatefulWidget {
  final String peerName;
  final String peerInitials;
  final String roomId;
  final String myUid;
  final VoidCallback? onAvatarTap;

  const ChatScreen({
    super.key,
    required this.peerName,
    required this.peerInitials,
    required this.roomId,
    required this.myUid,
    this.onAvatarTap,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Poll for new messages every 5 seconds
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMessages(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final data = await BackendService.getChatMessages(widget.roomId);

    // If no server data and this is the mock Alex Chen room, inject mock chat
    if ((data == null || (data['messages'] as List?)?.isEmpty == true) &&
        widget.roomId.contains('mock_user_alex_001')) {
      if (_messages.isEmpty && mounted) {
        final now = DateTime.now();
        setState(() {
          _messages.addAll([
            ChatMessage(
              text: 'Hey! I saw we matched — your ML background is exactly what I need for the study assistant.',
              isMe: false,
              timestamp: now.subtract(const Duration(hours: 2, minutes: 15)),
            ),
            ChatMessage(
              text: 'Thanks! Yeah the project sounds really cool. What stack are you using for the frontend?',
              isMe: true,
              timestamp: now.subtract(const Duration(hours: 2, minutes: 10)),
            ),
            ChatMessage(
              text: 'React + TypeScript with Figma for design. The backend is where I need help though — thinking Python + FastAPI?',
              isMe: false,
              timestamp: now.subtract(const Duration(hours: 2, minutes: 5)),
            ),
            ChatMessage(
              text: 'That would work great with a ML pipeline. Want to grab coffee this week and sketch it out?',
              isMe: true,
              timestamp: now.subtract(const Duration(hours: 1, minutes: 58)),
            ),
          ]);
          _isLoading = false;
        });
        _scrollToBottom();
      }
      return;
    }

    // Mock chat for demo Gemini connection (Riley Kim)
    if ((data == null || (data['messages'] as List?)?.isEmpty == true) &&
        widget.roomId.contains('demo_gemini_peer')) {
      if (_messages.isEmpty && mounted) {
        final now = DateTime.now();
        setState(() {
          _messages.addAll([
            ChatMessage(
              text: 'Hey! Really cool that we matched — I\'ve been looking for someone with your design skills.',
              isMe: false,
              timestamp: now.subtract(const Duration(minutes: 12)),
            ),
            ChatMessage(
              text: 'Likewise! Your AI experience is exactly what my project needs. What are you working on?',
              isMe: true,
              timestamp: now.subtract(const Duration(minutes: 10)),
            ),
            ChatMessage(
              text: 'Building a campus networking tool that uses ML to suggest collaborators. Kind of meta that it connected us, haha.',
              isMe: false,
              timestamp: now.subtract(const Duration(minutes: 8)),
            ),
            ChatMessage(
              text: 'Ha, love that. I\'d be down to help with the mobile UI — want to meet at Coupa Cafe tomorrow?',
              isMe: true,
              timestamp: now.subtract(const Duration(minutes: 5)),
            ),
          ]);
          _isLoading = false;
        });
        _scrollToBottom();
      }
      return;
    }

    if (data == null || !mounted) return;

    final messageList = data['messages'] as List? ?? [];
    final newMessages = messageList.map((m) {
      return ChatMessage(
        text: m['content'] as String,
        isMe: m['sender_uid'] == widget.myUid,
        timestamp: DateTime.parse(m['timestamp'] as String),
      );
    }).toList();

    if (mounted) {
      final hadMessages = _messages.isNotEmpty;
      final newCount = newMessages.length;
      setState(() {
        _messages.clear();
        _messages.addAll(newMessages);
        _isLoading = false;
      });
      // Auto-scroll if new messages arrived
      if (!hadMessages || newCount > _messages.length) {
        _scrollToBottom();
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    // Optimistically add the message
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isMe: true,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();

    // Send to backend
    await BackendService.sendChatMessage(widget.roomId, widget.myUid, text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Top bar ──
            _ChatTopBar(
              name: widget.peerName,
              initials: widget.peerInitials,
              onBack: () => Navigator.pop(context),
              onAvatarTap: widget.onAvatarTap,
            ),
            const Divider(height: 0.5),
            // ── Messages ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'No messages yet. Say hi!',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return _ChatBubble(message: msg);
                          },
                        ),
            ),
            // ── Input bar ──
            _ChatInputBar(
              controller: _controller,
              onSend: _sendMessage,
              bottomPadding: bottomPadding,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

class _ChatTopBar extends StatelessWidget {
  final String name;
  final String initials;
  final VoidCallback onBack;
  final VoidCallback? onAvatarTap;

  const _ChatTopBar({
    required this.name,
    required this.initials,
    required this.onBack,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          // Avatar
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLightBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat bubble ──────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : AppColors.surfaceMediumBlue,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  message.text,
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: isMe ? AppColors.onPrimary : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? AppColors.onPrimary.withValues(alpha: 0.5)
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Input bar ────────────────────────────────────────────────────────────────

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final double bottomPadding;

  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding + 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Text field
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceGray,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onSend(),
                style: GoogleFonts.sora(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.sora(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Send button
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
