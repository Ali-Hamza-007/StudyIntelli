import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ResultScreen
// Displays all generated study materials in a tabbed layout.
// Also exposes a floating "Ask AI" button that opens a RAG chat bottom sheet.
// ─────────────────────────────────────────────────────────────────────────────

class ResultScreen extends ConsumerWidget {
  /// The unified material map.  Shape (same for both upload and list responses):
  ///   {
  ///     "id": <material_id>,
  ///     "document": { "id": ..., "title": ..., "file": ... },
  ///     "important_questions": [...],
  ///     "mcqs": [...],
  ///     "short_questions": [...],
  ///     "long_questions": [...],
  ///     "fill_in_the_blanks": [...],
  ///   }
  final Map<String, dynamic> material;

  const ResultScreen({Key? key, required this.material}) : super(key: key);

  // Extract document ID robustly from either a nested Map or a raw int.
  int? _documentId() {
    final doc = material['document'];
    if (doc is Map) return doc['id'] as int?;
    if (doc is int) return doc;
    return null;
  }

  String _documentTitle() {
    final doc = material['document'];
    if (doc is Map) {
      return (doc['title'] as String?)?.isNotEmpty == true
          ? doc['title'] as String
          : 'Study Material';
    }
    return 'Study Material';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importantQuestions = List<dynamic>.from(
      material['important_questions'] ?? [],
    );
    final mcqs = List<dynamic>.from(material['mcqs'] ?? []);
    final fillInTheBlanks = List<dynamic>.from(
      material['fill_in_the_blanks'] ?? [],
    );
    final shortQuestions = List<dynamic>.from(
      material['short_questions'] ?? [],
    );
    final longQuestions = List<dynamic>.from(material['long_questions'] ?? []);

    // Build tabs only for non-empty sections
    final tabs = <_TabEntry>[];
    if (importantQuestions.isNotEmpty) {
      tabs.add(
        _TabEntry(
          label: 'Important',
          icon: Icons.star_rounded,
          color: const Color(0xFFE8A838),
          child: _ImportantQList(questions: importantQuestions),
        ),
      );
    }
    if (mcqs.isNotEmpty) {
      tabs.add(
        _TabEntry(
          label: 'MCQs',
          icon: Icons.quiz_rounded,
          color: const Color(0xFF58C4DC),
          child: _MCQList(mcqs: mcqs),
        ),
      );
    }
    if (shortQuestions.isNotEmpty) {
      tabs.add(
        _TabEntry(
          label: 'Short Q',
          icon: Icons.short_text_rounded,
          color: const Color(0xFF7C5CBF),
          child: _QAList(
            items: shortQuestions,
            questionKey: 'question',
            answerKey: 'answer',
          ),
        ),
      );
    }
    if (longQuestions.isNotEmpty) {
      tabs.add(
        _TabEntry(
          label: 'Long Q',
          icon: Icons.article_rounded,
          color: const Color(0xFF4CAF50),
          child: _QAList(
            items: longQuestions,
            questionKey: 'question',
            answerKey: 'answer',
            isLong: true,
          ),
        ),
      );
    }
    if (fillInTheBlanks.isNotEmpty) {
      tabs.add(
        _TabEntry(
          label: 'Fill Blanks',
          icon: Icons.edit_rounded,
          color: const Color(0xFFE57373),
          child: _FIBList(items: fillInTheBlanks),
        ),
      );
    }

    final docId = _documentId();

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Study Materials')),
        floatingActionButton: docId != null
            ? _ChatFAB(documentId: docId, documentTitle: _documentTitle())
            : null,
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF9E99B8),
                  size: 56,
                ),
                SizedBox(height: 16),
                Text(
                  'No questions were generated.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'The PDF may have been too short or image-based.\n'
                  'You can still use the AI chat to ask questions about the content.',
                  style: TextStyle(color: Color(0xFF9E99B8), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: const Color(0xFF13111F),
        appBar: AppBar(
          title: Text(
            _documentTitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: const Color(0xFF1E1B2E),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: tabs
                    .map(
                      (t) => Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.icon, size: 15, color: t.color),
                            const SizedBox(width: 6),
                            Text(t.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        body: TabBarView(children: tabs.map((t) => t.child).toList()),
        // RAG Chat floating action button — only shown if we have a document id
        floatingActionButton: docId != null
            ? _ChatFAB(documentId: docId, documentTitle: _documentTitle())
            : null,
      ),
    );
  }
}

// ─── Chat FAB ────────────────────────────────────────────────────────────────

class _ChatFAB extends StatelessWidget {
  final int documentId;
  final String documentTitle;

  const _ChatFAB({required this.documentId, required this.documentTitle});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _openChat(context),
      icon: const Icon(Icons.chat_bubble_outline_rounded),
      label: const Text(
        'Ask AI',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      backgroundColor: const Color(0xFF58C4DC),
      foregroundColor: const Color(0xFF13111F),
    );
  }

  void _openChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatBottomSheet(
        documentId: documentId,
        documentTitle: documentTitle,
      ),
    );
  }
}

// ─── Chat Bottom Sheet ────────────────────────────────────────────────────────

class _ChatBottomSheet extends ConsumerStatefulWidget {
  final int documentId;
  final String documentTitle;

  const _ChatBottomSheet({
    required this.documentId,
    required this.documentTitle,
  });

  @override
  ConsumerState<_ChatBottomSheet> createState() => _ChatBottomSheetState();
}

class _ChatBottomSheetState extends ConsumerState<_ChatBottomSheet> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(chatProviderFamily(widget.documentId).notifier).sendMessage(text);
    // Scroll to bottom after the frame renders with the new message
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProviderFamily(widget.documentId));
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Auto-scroll when new messages arrive
    if (chatState.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3555),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF58C4DC), Color(0xFF7C5CBF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Study Assistant',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          widget.documentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF9E99B8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF9E99B8),
                      size: 22,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFF2E2A45)),

            // ── Message list ─────────────────────────────────────────────────
            Expanded(
              child: chatState.messages.isEmpty
                  ? _ChatEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount:
                          chatState.messages.length +
                          (chatState.isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == chatState.messages.length &&
                            chatState.isLoading) {
                          return const _TypingIndicator();
                        }
                        return _MessageBubble(
                          message: chatState.messages[index],
                        );
                      },
                    ),
            ),

            // ── Input bar ─────────────────────────────────────────────────────
            SafeArea(
              bottom: true,
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1B2E),
                  border: Border(
                    top: BorderSide(color: Color(0xFF2E2A45), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Ask anything about this material…',
                          hintStyle: const TextStyle(
                            color: Color(0xFF6C6785),
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF2A2641),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF3A3555),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF3A3555),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF58C4DC),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: Material(
                        color: chatState.isLoading
                            ? const Color(0xFF3A3555)
                            : const Color(0xFF58C4DC),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: chatState.isLoading ? null : _sendMessage,
                          child: Container(
                            padding: const EdgeInsets.all(13),
                            child: Icon(
                              chatState.isLoading
                                  ? Icons.hourglass_top_rounded
                                  : Icons.send_rounded,
                              color: chatState.isLoading
                                  ? const Color(0xFF9E99B8)
                                  : const Color(0xFF13111F),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 6,
          bottom: 6,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [Color(0xFF7C5CBF), Color(0xFF58C4DC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isUser ? null : const Color(0xFF2A2641),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: const Color(0xFF3A3555)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const Icon(
                Icons.psychology_rounded,
                size: 14,
                color: Color(0xFF58C4DC),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFFE8E0FF),
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Typing Indicator ─────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2641),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: const Color(0xFF3A3555)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.psychology_rounded,
              size: 14,
              color: Color(0xFF58C4DC),
            ),
            const SizedBox(width: 8),
            ...List.generate(3, (i) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  final offset = ((_controller.value * 3) - i).clamp(0.0, 1.0);
                  final opacity = (offset < 0.5 ? offset * 2 : (1 - offset) * 2)
                      .clamp(0.3, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(88, 196, 220, opacity),
                      shape: BoxShape.circle,
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── Chat Empty State ─────────────────────────────────────────────────────────

class _ChatEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFF58C4DC), Color(0xFF7C5CBF)],
              ).createShader(b),
              child: const Icon(
                Icons.psychology_rounded,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ask anything about this PDF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The AI has read the entire document and can answer\n'
              'questions, explain concepts, or summarize sections.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9E99B8),
                fontSize: 13,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            // Suggestion chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: const [
                _SuggestionChip('Summarize this topic'),
                _SuggestionChip('What are the key points?'),
                _SuggestionChip('Explain with an example'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  const _SuggestionChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2641),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3A3555)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Color(0xFF9E99B8), fontSize: 12),
      ),
    );
  }
}

// ─── Tab entry helper ────────────────────────────────────────────────────────

class _TabEntry {
  final String label;
  final IconData icon;
  final Color color;
  final Widget child;

  const _TabEntry({
    required this.label,
    required this.icon,
    required this.color,
    required this.child,
  });
}

// ─── Important Questions ──────────────────────────────────────────────────────

class _ImportantQList extends StatelessWidget {
  final List<dynamic> questions;
  const _ImportantQList({required this.questions});

  Color _priorityColor(String p) {
    switch (p.toLowerCase()) {
      case 'high':
        return const Color(0xFFE57373);
      case 'medium':
        return const Color(0xFFE8A838);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      itemBuilder: (_, i) {
        final q = questions[i];
        final priority = (q['priority'] ?? 'Low').toString();
        final color = _priorityColor(priority);
        return _BaseCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (q['question'] ?? '').toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Text(
                        priority,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── MCQ List ─────────────────────────────────────────────────────────────────

class _MCQList extends StatelessWidget {
  final List<dynamic> mcqs;
  const _MCQList({required this.mcqs});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: mcqs.length,
      itemBuilder: (_, i) => _MCQCard(mcq: mcqs[i], index: i),
    );
  }
}

class _MCQCard extends StatefulWidget {
  final dynamic mcq;
  final int index;
  const _MCQCard({required this.mcq, required this.index});

  @override
  State<_MCQCard> createState() => _MCQCardState();
}

class _MCQCardState extends State<_MCQCard> {
  String? _selected;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final options = List<dynamic>.from(widget.mcq['options'] ?? []);
    final correctAnswer = (widget.mcq['correct_answer'] ?? '').toString();

    return _BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF58C4DC).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Q${widget.index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF58C4DC),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  (widget.mcq['question'] ?? '').toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...options.map((opt) {
            final optStr = opt.toString();
            final isCorrect = optStr == correctAnswer;
            final isSelected = _selected == optStr;

            Color bgColor = const Color(0xFF2A2641);
            Color borderColor = const Color(0xFF3A3555);
            Color textColor = const Color(0xFFE8E0FF);

            if (_revealed) {
              if (isCorrect) {
                bgColor = const Color(0xFF4CAF50).withOpacity(0.15);
                borderColor = const Color(0xFF4CAF50);
                textColor = const Color(0xFF4CAF50);
              } else if (isSelected && !isCorrect) {
                bgColor = const Color(0xFFE57373).withOpacity(0.15);
                borderColor = const Color(0xFFE57373);
                textColor = const Color(0xFFE57373);
              }
            }

            return GestureDetector(
              onTap: _revealed
                  ? null
                  : () => setState(() => _selected = optStr),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected && !_revealed
                        ? const Color(0xFF7C5CBF)
                        : borderColor,
                    width: isSelected && !_revealed ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        optStr,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: isSelected || (isCorrect && _revealed)
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (_revealed && isCorrect)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF4CAF50),
                        size: 18,
                      ),
                    if (_revealed && isSelected && !isCorrect)
                      const Icon(
                        Icons.cancel_rounded,
                        color: Color(0xFFE57373),
                        size: 18,
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          if (!_revealed)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(
                  Icons.visibility_rounded,
                  size: 16,
                  color: Color(0xFF58C4DC),
                ),
                label: const Text(
                  'Show Answer',
                  style: TextStyle(color: Color(0xFF58C4DC), fontSize: 13),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF4CAF50).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF4CAF50),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Answer: $correctAnswer',
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
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

// ─── Short / Long Q&A List ────────────────────────────────────────────────────

class _QAList extends StatelessWidget {
  final List<dynamic> items;
  final String questionKey;
  final String answerKey;
  final bool isLong;

  const _QAList({
    required this.items,
    required this.questionKey,
    required this.answerKey,
    this.isLong = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _QACard(
        index: i,
        question: (items[i][questionKey] ?? '').toString(),
        answer: (items[i][answerKey] ?? '').toString(),
        isLong: isLong,
      ),
    );
  }
}

class _QACard extends StatefulWidget {
  final int index;
  final String question;
  final String answer;
  final bool isLong;

  const _QACard({
    required this.index,
    required this.question,
    required this.answer,
    required this.isLong,
  });

  @override
  State<_QACard> createState() => _QACardState();
}

class _QACardState extends State<_QACard> {
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isLong
        ? const Color(0xFF4CAF50)
        : const Color(0xFF7C5CBF);

    return _BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Q${widget.index + 1}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.question,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            firstChild: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showAnswer = true),
                icon: Icon(Icons.visibility_rounded, size: 16, color: color),
                label: Text(
                  'Show Answer',
                  style: TextStyle(color: color, fontSize: 13),
                ),
              ),
            ),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Text(
                widget.answer,
                style: TextStyle(
                  color: color == const Color(0xFF4CAF50)
                      ? const Color(0xFFA5D6A7)
                      : const Color(0xFFCEB8F0),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
            crossFadeState: _showAnswer
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
          ),
        ],
      ),
    );
  }
}

// ─── Fill in the Blanks ───────────────────────────────────────────────────────

class _FIBList extends StatelessWidget {
  final List<dynamic> items;
  const _FIBList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _FIBCard(index: i, item: items[i]),
    );
  }
}

class _FIBCard extends StatefulWidget {
  final int index;
  final dynamic item;
  const _FIBCard({required this.index, required this.item});

  @override
  State<_FIBCard> createState() => _FIBCardState();
}

class _FIBCardState extends State<_FIBCard> {
  bool _revealed = false;

  String _buildSentence(String sentence, String answer, bool reveal) {
    if (!reveal) return sentence;
    return sentence.replaceAll('____', '[$answer]');
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFE57373);
    final sentence = (widget.item['sentence'] ?? '').toString();
    final answer = (widget.item['answer'] ?? '').toString();

    return _BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${widget.index + 1}',
                    style: const TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _buildSentence(sentence, answer, _revealed),
                    key: ValueKey(_revealed),
                    style: TextStyle(
                      color: _revealed
                          ? const Color(0xFFFFAB91)
                          : const Color(0xFFE8E0FF),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_revealed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(
                  Icons.visibility_rounded,
                  size: 16,
                  color: color,
                ),
                label: const Text(
                  'Reveal Answer',
                  style: TextStyle(color: color, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Base card ────────────────────────────────────────────────────────────────

class _BaseCard extends StatelessWidget {
  final Widget child;
  const _BaseCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2641),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3555)),
      ),
      child: child,
    );
  }
}
