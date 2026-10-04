import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/api_client.dart';

// ─── Model ───────────────────────────────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;

  const ChatMessage({required this.text, required this.isUser});
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class ChatNotifier extends StateNotifier<ChatState> {
  final int documentId;

  ChatNotifier(this.documentId) : super(const ChatState());

  Future<void> sendMessage(String question) async {
    if (question.trim().isEmpty) return;

    // Append the user's message immediately
    final userMessage = ChatMessage(text: question.trim(), isUser: true);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      clearError: true,
    );

    try {
      final response = await ApiClient.post('/chat/', {
        'document_id': documentId,
        'question': question.trim(),
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final answer = (data['answer'] as String?) ?? 'No answer returned.';
        final aiMessage = ChatMessage(text: answer, isUser: false);
        state = state.copyWith(
          messages: [...state.messages, aiMessage],
          isLoading: false,
        );
      } else {
        String errorMsg = 'Error ${response.statusCode}';
        try {
          final errData = jsonDecode(response.body);
          if (errData is Map && errData.containsKey('error')) {
            errorMsg = errData['error'];
          }
        } catch (_) {}

        // Show error as an AI message so the user sees it in context
        final errorMessage = ChatMessage(
          text: '⚠️ $errorMsg',
          isUser: false,
        );
        state = state.copyWith(
          messages: [...state.messages, errorMessage],
          isLoading: false,
          error: errorMsg,
        );
      }
    } catch (e) {
      final errorMessage = ChatMessage(
        text: '⚠️ Connection error: ${e.toString()}',
        isUser: false,
      );
      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void clearHistory() {
    state = const ChatState();
  }
}

// ─── Provider factory ─────────────────────────────────────────────────────────

/// A per-document chat provider. Each document gets its own chat state so
/// messages from different PDFs don't mix.
final chatProviderFamily =
    StateNotifierProvider.family<ChatNotifier, ChatState, int>(
  (ref, documentId) => ChatNotifier(documentId),
);
