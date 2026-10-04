import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/study_provider.dart';
import '../providers/auth_provider.dart';
import '../core/api_client.dart';
import 'auth_screen.dart';
import 'result_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fabAnimController;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(studyProvider.notifier).fetchMaterials();
    });
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: isError
                  ? const Color(0xFFE57373)
                  : const Color(0xFF58C4DC),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2A2641),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;

    final Uint8List? fileBytes = file.bytes;
    final String? filePath = kIsWeb ? null : file.path;

    if (fileBytes == null && filePath == null) return;

    if (!mounted) return;

    final success = await ref
        .read(studyProvider.notifier)
        .uploadDocument(
          filePath: filePath,
          fileBytes: fileBytes,
          fileName: file.name,
        );

    if (mounted) {
      if (success) {
        _showSnack('Questions generated successfully!');
      } else {
        final errorMsg = ref.read(studyProvider).error;
        if (errorMsg != null) {
          _showSnack(errorMsg, isError: true);
        }
      }
    }
  }

  Future<void> _confirmAndDelete(dynamic id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2A2641),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete study set?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete "$title" and all its questions.',
          style: const TextStyle(color: Color(0xFF9E99B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF9E99B8)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFFE57373),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticFeedback.mediumImpact();

    final success = await ref.read(studyProvider.notifier).deleteMaterial(id);

    if (!mounted) return;

    final errorMsg = ref.read(studyProvider).error;

    _showSnack(
      success ? 'Study set deleted.' : (errorMsg ?? 'Failed to delete.'),
      isError: !success,
    );
  }

  Future<void> _openPdf(String fileUrl, String label) async {
    HapticFeedback.selectionClick();
    final resolvedUrl = ApiClient.resolveMediaUrl(fileUrl);
    final uri = Uri.tryParse(resolvedUrl);

    if (uri == null) {
      _showSnack('Invalid file link for "$label".', isError: true);
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showSnack('Could not open "$label".', isError: true);
      }
    } catch (_) {
      _showSnack('Could not open "$label".', isError: true);
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final studyState = ref.watch(studyProvider);

    final totalQuestions = studyState.materials.fold<int>(0, (sum, m) {
      final mcq = (m['mcqs'] as List?)?.length ?? 0;
      final sq = (m['short_questions'] as List?)?.length ?? 0;
      final lq = (m['long_questions'] as List?)?.length ?? 0;
      final fib = (m['fill_in_the_blanks'] as List?)?.length ?? 0;
      final iq = (m['important_questions'] as List?)?.length ?? 0;
      return sum + mcq + sq + lq + fib + iq;
    });

    return Scaffold(
      body: RefreshIndicator(
        color: const Color(0xFF7C5CBF),
        backgroundColor: const Color(0xFF2A2641),
        onRefresh: () => ref.read(studyProvider.notifier).fetchMaterials(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 120,
              backgroundColor: const Color(0xFF1E1B2E),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                title: const Text(
                  'StudyIntelli',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E1B2E), Color(0xFF2A2050)],
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        left: 6,
                        bottom: 4,
                        child: Opacity(
                          opacity: 0.14,
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF7C5CBF), Color(0xFF58C4DC)],
                            ).createShader(bounds),
                            child: const Icon(
                              Icons.auto_stories_rounded,
                              size: 96,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _LogoutButton(
                    onPressed: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const AuthScreen()),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),

            if (!studyState.isLoading && studyState.materials.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _StatsBanner(
                    count: studyState.materials.length,
                    totalQuestions: totalQuestions,
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                child: Row(
                  children: [
                    Text(
                      studyState.isLoading
                          ? (studyState.materials.isEmpty ? 'Loading your study sets…' : 'Processing…')
                          : 'Your study sets',
                      style: const TextStyle(
                        color: Color(0xFF9E99B8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                    if (!studyState.isLoading &&
                        studyState.materials.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2641),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF3A3555)),
                        ),
                        child: Text(
                          '${studyState.materials.length}',
                          style: const TextStyle(
                            color: Color(0xFF58C4DC),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            if (studyState.isLoading && studyState.materials.isEmpty)
              const SliverFillRemaining(child: _LoadingView())
            else if (studyState.error != null && studyState.materials.isEmpty)
              SliverFillRemaining(
                child: _ErrorView(
                  error: studyState.error!,
                  onRetry: () =>
                      ref.read(studyProvider.notifier).fetchMaterials(),
                ),
              )
            else if (studyState.materials.isEmpty)
              const SliverFillRemaining(child: _EmptyView())
            else
              SliverPadding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 110,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final material = studyState.materials[index];
                    print(
                      'Material at index $index: $material',
                    ); // Debugging line

                    final docData = material['document'];
                    final date = _formatDate(material['created_at']);
                    final id = material['id'];

                    final pdfFileUrl = docData is Map && docData['file'] != null
                        ? docData['file'].toString()
                        : null;

                    // Extract actual PDF name from URL or available backend fields
                    String extractedName = '';
                    if (pdfFileUrl != null && pdfFileUrl.isNotEmpty) {
                      extractedName = Uri.decodeComponent(
                        pdfFileUrl.split('/').last.split('?').first,
                      );
                    } else if (docData is Map) {
                      extractedName =
                          (docData['filename'] ??
                                  docData['original_name'] ??
                                  docData['name'] ??
                                  docData['title'] ??
                                  '')
                              .toString();
                    }

                    // Fallback to generic only if extraction yields no valid string
                    final String actualPdfName = extractedName.trim().isNotEmpty
                        ? extractedName
                        : 'Study Material';

                    final title = actualPdfName;
                    final pdfFileName = actualPdfName;

                    final mcqCount = (material['mcqs'] as List?)?.length ?? 0;
                    final sqCount =
                        (material['short_questions'] as List?)?.length ?? 0;
                    final lqCount =
                        (material['long_questions'] as List?)?.length ?? 0;
                    final fibCount =
                        (material['fill_in_the_blanks'] as List?)?.length ?? 0;
                    final iqCount =
                        (material['important_questions'] as List?)?.length ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StaggeredEntrance(
                        index: index,
                        child: _MaterialCard(
                          title: title,
                          date: date,
                          pdfFileName: pdfFileName,
                          pdfFileUrl: pdfFileUrl,
                          mcqCount: mcqCount,
                          sqCount: sqCount,
                          lqCount: lqCount,
                          fibCount: fibCount,
                          iqCount: iqCount,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ResultScreen(material: material),
                            ),
                          ),
                          onDelete: () => _confirmAndDelete(id, title),
                          onOpenPdf: pdfFileUrl == null
                              ? null
                              : () => _openPdf(pdfFileUrl, pdfFileName),
                        ),
                      ),
                    );
                  }, childCount: studyState.materials.length),
                ),
              ),
          ],
        ),
      ),

      floatingActionButton: ScaleTransition(
        scale: _fabAnimController,
        child: FloatingActionButton.extended(
          onPressed: studyState.isLoading ? null : _pickAndUpload,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text(
            'Upload PDF',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: studyState.isLoading
              ? const Color(0xFF3A3555)
              : const Color(0xFF7C5CBF),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _LogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Logout',
      child: Material(
        color: const Color(0xFF2A2641),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A3555)),
            ),
            child: const Icon(
              Icons.logout_rounded,
              size: 19,
              color: Color(0xFF9E99B8),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredEntrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + (index.clamp(0, 10) * 55)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 20),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _StatsBanner extends StatelessWidget {
  final int count;
  final int totalQuestions;
  const _StatsBanner({required this.count, required this.totalQuestions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C5CBF), Color(0xFF4E6BAA)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CBF).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.library_books_rounded,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count Study Set${count == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap any set to start studying',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: Colors.white24,
            margin: const EdgeInsets.symmetric(horizontal: 14),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$totalQuestions',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'questions',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final String title;
  final String date;
  final String pdfFileName;
  final String? pdfFileUrl;
  final int mcqCount, sqCount, lqCount, fibCount, iqCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onOpenPdf;

  const _MaterialCard({
    required this.title,
    required this.date,
    required this.pdfFileName,
    required this.pdfFileUrl,
    required this.mcqCount,
    required this.sqCount,
    required this.lqCount,
    required this.fibCount,
    required this.iqCount,
    required this.onTap,
    required this.onDelete,
    required this.onOpenPdf,
  });

  @override
  Widget build(BuildContext context) {
    final hasPdf = pdfFileUrl != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C5CBF), Color(0xFF58C4DC)],
                      ),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          date,
                          style: const TextStyle(
                            color: Color(0xFF9E99B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: Color(0xFFE57373),
                        ),
                        tooltip: 'Delete',
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: onDelete,
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: Color(0xFF9E99B8),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Material(
                color: const Color(0xFF231F38),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onOpenPdf,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_rounded,
                          size: 15,
                          color: hasPdf
                              ? const Color(0xFF58C4DC)
                              : const Color(0xFF6C6785),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pdfFileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasPdf
                                  ? Colors.white
                                  : const Color(0xFF6C6785),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          hasPdf
                              ? Icons.open_in_new_rounded
                              : Icons.link_off_rounded,
                          size: 14,
                          color: hasPdf
                              ? const Color(0xFF9E99B8)
                              : const Color(0xFF6C6785),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (iqCount > 0)
                    _Chip(
                      icon: Icons.star_rounded,
                      label: '$iqCount Important',
                      color: const Color(0xFFE8A838),
                    ),
                  if (mcqCount > 0)
                    _Chip(
                      icon: Icons.quiz_rounded,
                      label: '$mcqCount MCQs',
                      color: const Color(0xFF58C4DC),
                    ),
                  if (sqCount > 0)
                    _Chip(
                      icon: Icons.short_text_rounded,
                      label: '$sqCount Short Q',
                      color: const Color(0xFF7C5CBF),
                    ),
                  if (lqCount > 0)
                    _Chip(
                      icon: Icons.article_rounded,
                      label: '$lqCount Long Q',
                      color: const Color(0xFF4CAF50),
                    ),
                  if (fibCount > 0)
                    _Chip(
                      icon: Icons.edit_rounded,
                      label: '$fibCount Fill Blanks',
                      color: const Color(0xFFE57373),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatefulWidget {
  const _LoadingView();

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + (_pulseController.value * 0.08);
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: const Color(0xFF2A2641),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C5CBF).withOpacity(0.3),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF7C5CBF),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Generating study materials…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This may take 15–30 seconds.',
            style: TextStyle(color: Color(0xFF9E99B8), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFE57373),
              size: 56,
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9E99B8), fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CBF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFF7C5CBF), Color(0xFF58C4DC)],
            ).createShader(b),
            child: const Icon(
              Icons.upload_file_rounded,
              size: 80,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No study sets yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Upload a PDF and StudyIntelli will\nautomatically generate exam questions for you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF9E99B8),
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2641),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A3555)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_downward_rounded,
                  color: Color(0xFF7C5CBF),
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'Tap "Upload PDF" below to get started',
                  style: TextStyle(color: Color(0xFF9E99B8), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
