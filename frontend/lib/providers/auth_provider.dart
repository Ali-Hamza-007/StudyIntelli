import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? error;

  AuthState({this.isLoading = false, this.isAuthenticated = false, this.error});

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState()) {
    checkAuth();
  }

  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token != null) {
      state = state.copyWith(isAuthenticated: true);
    }
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ApiClient.post('/auth/login/', {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', data['access']);
        await prefs.setString('refresh_token', data['refresh']);
        await prefs.setString('active_username', username);
        state = state.copyWith(isLoading: false, isAuthenticated: true);
        return true;
      } else {
        state = state.copyWith(isLoading: false, error: 'Invalid credentials');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> register(String username, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ApiClient.post('/auth/register/', {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 201) {
        return await login(username, password);
      } else {
        state = state.copyWith(isLoading: false, error: 'Registration failed');
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('active_username');
    state = state.copyWith(isAuthenticated: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
