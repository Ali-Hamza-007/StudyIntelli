import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

const _activeUsernameKey = 'active_username';
const _studyMaterialsCachePrefix = 'study_materials_cache_';

class StudyState {
  final bool isLoading;
  final List<dynamic> materials;
  final String? error;

  StudyState({this.isLoading = false, this.materials = const [], this.error});

  StudyState copyWith({
    bool? isLoading,
    List<dynamic>? materials,
    String? error,
    bool clearError = false,
  }) {
    return StudyState(
      isLoading: isLoading ?? this.isLoading,
      materials: materials ?? this.materials,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class StudyNotifier extends StateNotifier<StudyState> {
  StudyNotifier() : super(StudyState());

  Future<String?> _getCacheKey() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token != null) {
      try {
        final payload = token.split('.')[1];
        final claims =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(payload))),
                )
                as Map<String, dynamic>;
        final userId = claims['user_id'] ?? claims['sub'];
        if (userId != null) return '${_studyMaterialsCachePrefix}user_$userId';
      } catch (_) {}
    }

    final username = prefs.getString(_activeUsernameKey);
    if (username == null || username.isEmpty) return null;
    return '$_studyMaterialsCachePrefix$username';
  }

  Future<void> _cacheMaterials(List<dynamic> materials) async {
    try {
      final cacheKey = await _getCacheKey();
      if (cacheKey == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(materials));
    } catch (_) {}
  }

  Future<List<dynamic>?> _readCachedMaterials() async {
    try {
      final cacheKey = await _getCacheKey();
      if (cacheKey == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached == null) return null;
      final decoded = jsonDecode(cached);
      return decoded is List ? List<dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getPendingDeletesKey() async {
    final cacheKey = await _getCacheKey();
    return cacheKey == null ? null : '${cacheKey}_pending_deletes';
  }

  Future<List<dynamic>> _readPendingDeletes() async {
    try {
      final key = await _getPendingDeletesKey();
      if (key == null) return [];
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString(key) ?? '[]');
      return decoded is List ? List<dynamic>.from(decoded) : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writePendingDeletes(List<dynamic> ids) async {
    try {
      final key = await _getPendingDeletesKey();
      if (key == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(ids));
    } catch (_) {}
  }

  Future<void> _queuePendingDelete(dynamic id) async {
    final pending = await _readPendingDeletes();
    if (!pending.contains(id)) pending.add(id);
    await _writePendingDeletes(pending);
    await _cacheMaterials(state.materials);
  }

  Future<List<dynamic>> _applyPendingDeletes(List<dynamic> materials) async {
    final pending = await _readPendingDeletes();
    if (pending.isEmpty) return materials;

    final remaining = List<dynamic>.from(pending);
    for (final id in pending) {
      try {
        final response = await ApiClient.delete('/delete-material/$id/');
        if (response.statusCode == 200 ||
            response.statusCode == 204 ||
            response.statusCode == 404) {
          remaining.remove(id);
        }
      } catch (_) {}
    }
    await _writePendingDeletes(remaining);
    return materials
        .where((material) => !pending.contains(material['id']))
        .toList();
  }

  Future<bool> _restoreCachedMaterials() async {
    final cached = await _readCachedMaterials();
    if (cached == null) return false;
    state = state.copyWith(
      isLoading: false,
      materials: cached,
      clearError: true,
    );
    return true;
  }

  Future<void> fetchMaterials() async {
    final cached = await _readCachedMaterials();
    if (cached != null) {
      state = state.copyWith(materials: cached);
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ApiClient.get('/get-materials/');
      if (response.statusCode == 200) {
        // GET /get-materials/ now returns StudyMaterialDetailSerializer which
        // includes a fully-nested `document` object (not just an integer FK).
        // Each item shape: { "id":..., "document": {...}, "mcqs": [...], ... }
        final data = jsonDecode(response.body) as List;
        final visibleMaterials = await _applyPendingDeletes(data);
        state = state.copyWith(isLoading: false, materials: visibleMaterials);
        await _cacheMaterials(visibleMaterials);
      } else if (response.statusCode == 401) {
        state = state.copyWith(
          isLoading: false,
          error: 'Session expired. Please log in again.',
        );
      } else {
        final restored =
            response.statusCode >= 500 && await _restoreCachedMaterials();
        if (!restored) {
          state = state.copyWith(
            isLoading: false,
            error: 'Failed to fetch materials (${response.statusCode})',
          );
        }
      }
    } catch (e) {
      final restored = await _restoreCachedMaterials();
      if (!restored) {
        String errorMessage = 'Something went wrong. Please check your connection.';
        final eStr = e.toString().toLowerCase();
        if (eStr.contains('clientexception') || eStr.contains('socketexception') || eStr.contains('connection refused') || eStr.contains('network is unreachable')) {
          errorMessage = 'Backend is unavailable. Please try again later.';
        }
        state = state.copyWith(isLoading: false, error: errorMessage);
      }
    }
  }

  Future<bool> uploadDocument({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ApiClient.uploadFile(
        '/upload-pdf/',
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
      );

      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;

        // Upload response shape: { "document": {...}, "materials": {...} }
        // We combine them into a single flat object matching the list endpoint
        // shape so the UI can handle both upload and list items uniformly.
        //
        // The list endpoint (GET /get-materials/) returns items in the shape:
        //   { "id": <material_id>, "document": { <full document object> },
        //     "mcqs": [...], "short_questions": [...], ... }
        //
        // The upload endpoint (POST /upload-pdf/) returns:
        //   { "document": { <full document object> },
        //     "materials": { "id": ..., "mcqs": [...], ... } }
        //
        // We merge them here so ResultScreen gets the same consistent shape.
        final documentData = data['document'] as Map<String, dynamic>?;
        final materialsData = data['materials'] as Map<String, dynamic>?;

        if (documentData != null && materialsData != null) {
          // Build a unified item matching the list endpoint shape
          final unifiedItem = <String, dynamic>{
            ...materialsData,
            'document': documentData,
          };
          state = state.copyWith(
            isLoading: false,
            materials: [unifiedItem, ...state.materials],
          );
          await _cacheMaterials(state.materials);
        } else {
          // Fallback: store whatever the server returned
          state = state.copyWith(
            isLoading: false,
            materials: [data, ...state.materials],
          );
          await _cacheMaterials(state.materials);
        }
        return true;
      } else {
        String errorMsg = 'Upload failed (${response.statusCode})';
        try {
          final errData = jsonDecode(responseBody);
          if (errData is Map && errData.containsKey('error')) {
            errorMsg = errData['error'];
          }
        } catch (_) {}
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      String errorMessage = 'Something went wrong. Please check your connection.';
      final eStr = e.toString().toLowerCase();
      if (eStr.contains('clientexception') || eStr.contains('socketexception') || eStr.contains('connection refused') || eStr.contains('network is unreachable')) {
        errorMessage = 'Backend is unavailable. Please try again later.';
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    }
  }

  /// Optimistic delete: removes the item from state immediately, then calls
  /// the API. Rolls back with an error message if the API call fails.
  Future<bool> deleteMaterial(dynamic id) async {
    final previousMaterials = List<dynamic>.from(state.materials);
    final optimisticMaterials = state.materials
        .where((m) => m['id'] != id)
        .toList();

    state = state.copyWith(materials: optimisticMaterials, clearError: true);

    try {
      final response = await ApiClient.delete('/delete-material/$id/');

      if (response.statusCode == 200 || response.statusCode == 204) {
        await _cacheMaterials(state.materials);
        return true;
      } else if (response.statusCode == 401) {
        state = state.copyWith(
          materials: previousMaterials,
          error: 'Session expired. Please log in again.',
        );
        return false;
      } else if (response.statusCode >= 500) {
        await _queuePendingDelete(id);
        return true;
      } else {
        state = state.copyWith(
          materials: previousMaterials,
          error: 'Failed to delete (${response.statusCode})',
        );
        return false;
      }
    } catch (e) {
      await _queuePendingDelete(id);
      return true;
    }
  }
}

final studyProvider = StateNotifierProvider<StudyNotifier, StudyState>((ref) {
  return StudyNotifier();
});
