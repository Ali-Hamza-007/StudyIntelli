import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Key used to persist the last-working backend host.
const _kBackendHostKey = 'backend_host';

/// Port the Django dev-server listens on.
const _kBackendPort = 8000;

/// UDP discovery port matching backend/api/apps.py beacon.
const _kUdpDiscoveryPort = 8888;

/// Known PC IP on current local network — checked with highest priority.
const _kKnownDevHost = '10.228.18.137';

/// Common IPs the PC gets when the phone provides USB tethering.
const _kUsbTetheringGateways = ['192.168.42.129', '192.168.42.73'];

class ApiClient {
  static String? _resolvedBaseUrl;
  static Completer<String>? _discoveryCompleter;
  static int _consecutiveErrors = 0;
  static const _kMaxErrorsBeforeInvalidate = 3;

  // ─── Base URL Resolvers ───────────────────────────────────────────────────

  /// Asynchronously returns the base URL.
  /// If not yet discovered, runs discovery. If discovery is already in progress,
  /// awaits the current discovery attempt.
  static Future<String> get baseUrl async {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;

    if (kIsWeb) {
      _resolvedBaseUrl = 'http://127.0.0.1:$_kBackendPort/api';
      return _resolvedBaseUrl!;
    }

    if (_discoveryCompleter != null && !_discoveryCompleter!.isCompleted) {
      return _discoveryCompleter!.future;
    }

    _discoveryCompleter = Completer<String>();
    try {
      final host = await _discoverBackendUrl();
      _resolvedBaseUrl = 'http://$host:$_kBackendPort/api';
      _discoveryCompleter!.complete(_resolvedBaseUrl!);
    } catch (_) {
      final fallback = _getSafeFallbackHost();
      _resolvedBaseUrl = 'http://$fallback:$_kBackendPort/api';
      if (!_discoveryCompleter!.isCompleted) {
        _discoveryCompleter!.complete(_resolvedBaseUrl!);
      }
    }
    return _resolvedBaseUrl!;
  }

  /// Synchronous snapshot — returns the resolved URL or a platform-safe fallback.
  static String get baseUrlSync {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;
    if (kIsWeb) return 'http://127.0.0.1:$_kBackendPort/api';
    return 'http://${_getSafeFallbackHost()}:$_kBackendPort/api';
  }

  /// Clear cached URL so next call re-probes the network.
  static void invalidate() {
    _resolvedBaseUrl = null;
    _discoveryCompleter = null;
  }

  static String _getSafeFallbackHost() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // On Android physical device, 127.0.0.1 NEVER works. Fallback to known PC IP.
      return _kKnownDevHost;
    }
    return '127.0.0.1';
  }

  // ─── Initializer (called in main() before runApp) ─────────────────────────

  static Future<void> initBaseUrl() async {
    _resolvedBaseUrl = null;
    _discoveryCompleter = null;
    await baseUrl.timeout(
      const Duration(seconds: 4),
      onTimeout: () => baseUrlSync,
    );
  }

  // ─── Multi-Layer Dynamic Auto-Discovery ───────────────────────────────────

  static Future<String> _discoverBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();

    // Layer 0: ADB reverse — on Android, 127.0.0.1 works when `adb reverse`
    // is active (USB debugging). This is instant and the most reliable path.
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (await _isVerifiedBackend('127.0.0.1')) {
        await prefs.setString(_kBackendHostKey, '127.0.0.1');
        return '127.0.0.1';
      }
    }

    // Layer 1: Previously saved working host (0-50ms)
    final saved = prefs.getString(_kBackendHostKey);
    final skipLoopback = saved == '127.0.0.1' &&
        defaultTargetPlatform != TargetPlatform.android;
    if (saved != null && saved.isNotEmpty && !skipLoopback) {
      if (await _isVerifiedBackend(saved)) {
        return saved;
      }
    }

    // Layer 2: Known local dev host (fast 50ms check)
    if (await _isVerifiedBackend(_kKnownDevHost)) {
      await prefs.setString(_kBackendHostKey, _kKnownDevHost);
      return _kKnownDevHost;
    }

    // Layer 2b: USB tethering gateway IPs (phone hotspot → PC via USB)
    for (final gw in _kUsbTetheringGateways) {
      if (await _isVerifiedBackend(gw)) {
        await prefs.setString(_kBackendHostKey, gw);
        return gw;
      }
    }

    // Layer 2c: Detect gateway from the phone's own network interfaces
    final ifaceHost = await _detectGatewayFromInterfaces();
    if (ifaceHost != null && await _isVerifiedBackend(ifaceHost)) {
      await prefs.setString(_kBackendHostKey, ifaceHost);
      return ifaceHost;
    }

    // Layer 3: UDP Broadcast Beacon Discovery (instant 50-800ms)
    final udpHost = await _discoverViaUdp();
    if (udpHost != null && await _isVerifiedBackend(udpHost)) {
      await prefs.setString(_kBackendHostKey, udpHost);
      return udpHost;
    }

    // Layer 4: Android Emulator Alias
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (await _isVerifiedBackend('10.0.2.2')) {
        await prefs.setString(_kBackendHostKey, '10.0.2.2');
        return '10.0.2.2';
      }
    }

    // Layer 5: Dynamic Local Subnet Scan (batched, non-blocking)
    final scannedHost = await _scanLocalSubnets();
    if (scannedHost != null) {
      await prefs.setString(_kBackendHostKey, scannedHost);
      return scannedHost;
    }

    // Layer 6: Safe fallback
    return saved ?? _getSafeFallbackHost();
  }

  /// Listens for the backend UDP beacon on port 8888 or broadcasts a ping.
  static Future<String?> _discoverViaUdp() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _kUdpDiscoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      final completer = Completer<String?>();

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg != null) {
            final msg = utf8.decode(dg.data, allowMalformed: true);
            if (msg.contains('STUDYINTELLI') && !completer.isCompleted) {
              completer.complete(dg.address.address);
            }
          }
        }
      });

      // Broadcast a discovery ping to wake up the backend if it's waiting
      try {
        socket.send(
          utf8.encode('STUDYINTELLI_PING'),
          InternetAddress('255.255.255.255'),
          _kUdpDiscoveryPort,
        );
      } catch (_) {}

      return await completer.future.timeout(
        const Duration(milliseconds: 1000),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  /// Scans the device's actual subnet(s) in parallel chunks of 25 hosts.
  static Future<String?> _scanLocalSubnets() async {
    final subnets = <String>{};

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (_) {}

    // Ensure common local subnets are included as fallbacks
    subnets.add('10.228.18');
    subnets.add('192.168.1');
    subnets.add('192.168.0');
    subnets.add('192.168.43'); // Common Android Hotspot subnet
    subnets.add('192.168.42'); // Common USB tethering subnet

    for (final subnet in subnets) {
      // Priority targets: common gateways and router IPs
      final priorityTargets = [
        '$subnet.1',
        '$subnet.60',
        '$subnet.137',
        '$subnet.254',
        '$subnet.100',
        '$subnet.101',
      ];

      for (final host in priorityTargets) {
        if (await _isVerifiedBackend(host)) {
          return host;
        }
      }

      // Scan remaining hosts in chunks of 25
      final allHosts = <String>[];
      for (var i = 2; i <= 253; i++) {
        final host = '$subnet.$i';
        if (!priorityTargets.contains(host)) {
          allHosts.add(host);
        }
      }

      const chunkSize = 25;
      for (var i = 0; i < allHosts.length; i += chunkSize) {
        final chunk = allHosts.sublist(
          i,
          (i + chunkSize > allHosts.length) ? allHosts.length : i + chunkSize,
        );

        final results = await Future.wait(
          chunk.map((ip) async {
            final ok = await _fastSocketProbe(ip);
            return ok ? ip : null;
          }),
        );

        for (final candidate in results) {
          if (candidate != null && await _isVerifiedBackend(candidate)) {
            return candidate;
          }
        }
      }
    }

    return null;
  }

  /// Fast TCP socket check with short timeout.
  static Future<bool> _fastSocketProbe(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        _kBackendPort,
        timeout: const Duration(milliseconds: 400),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verifies that [host] is running our StudyIntelli Django backend.
  static Future<bool> _isVerifiedBackend(String host) async {
    try {
      // 1. Check TCP connection
      final socket = await Socket.connect(
        host,
        _kBackendPort,
        timeout: const Duration(milliseconds: 700),
      );
      socket.destroy();

      // 2. Fast HTTP check to Django auth endpoint
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 1000);
      try {
        final uri = Uri.parse('http://$host:$_kBackendPort/api/auth/login/');
        final request = await client.openUrl('OPTIONS', uri);
        final response = await request.close().timeout(
          const Duration(milliseconds: 1000),
        );
        // Django returns 200 for OPTIONS on TokenObtainPairView
        return response.statusCode == 200 || response.statusCode == 405;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return false;
    }
  }

  // ─── Media URL Helper ─────────────────────────────────────────────────────

  static String resolveMediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = _resolvedBaseUrl ?? baseUrlSync;
    final host =
        base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$host$normalizedPath';
  }

  // ─── Headers ──────────────────────────────────────────────────────────────

  static Future<Map<String, String>> getHeaders({
    bool isMultipart = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final headers = <String, String>{};
    if (!isMultipart) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  // ─── HTTP Methods with Self-Healing ───────────────────────────────────────

  static Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final url = await baseUrl;
      final headers = await getHeaders();
      final response = await http
          .post(
            Uri.parse('$url$endpoint'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      _consecutiveErrors = 0; // success — reset counter
      return response;
    } catch (e) {
      _handleNetworkError(e);
      rethrow;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    try {
      final url = await baseUrl;
      final headers = await getHeaders();
      final response = await http
          .get(Uri.parse('$url$endpoint'), headers: headers)
          .timeout(const Duration(seconds: 15));
      _consecutiveErrors = 0;
      return response;
    } catch (e) {
      _handleNetworkError(e);
      rethrow;
    }
  }

  static Future<http.Response> delete(String endpoint) async {
    try {
      final url = await baseUrl;
      final headers = await getHeaders();
      final response = await http
          .delete(Uri.parse('$url$endpoint'), headers: headers)
          .timeout(const Duration(seconds: 15));
      _consecutiveErrors = 0;
      return response;
    } catch (e) {
      _handleNetworkError(e);
      rethrow;
    }
  }

  static Future<http.StreamedResponse> uploadFile(
    String endpoint, {
    String? filePath,
    List<int>? fileBytes,
    required String fileName,
  }) async {
    try {
      final url = await baseUrl;
      final headers = await getHeaders(isMultipart: true);
      final request =
          http.MultipartRequest('POST', Uri.parse('$url$endpoint'));
      request.headers.addAll(headers);

      if (kIsWeb && fileBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
        );
      } else if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      } else {
        throw Exception('No file data provided');
      }

      request.fields['title'] = fileName;
      return await request.send();
    } catch (e) {
      _handleNetworkError(e);
      rethrow;
    }
  }

  static void _handleNetworkError(dynamic error) {
    if (!kIsWeb) {
      _consecutiveErrors++;
      // Only wipe cached URL after repeated failures, not on every transient error.
      // This prevents cascading re-discovery storms on flaky tethered connections.
      if (_consecutiveErrors >= _kMaxErrorsBeforeInvalidate) {
        invalidate();
        SharedPreferences.getInstance().then((prefs) {
          prefs.remove(_kBackendHostKey);
        });
        _consecutiveErrors = 0;
      }
    }
  }

  /// Detect the PC IP by looking at the phone's network interfaces.
  /// On USB tethering the phone gets an IP like 192.168.42.129 and the
  /// PC (gateway) is typically at .1 or the first host in the subnet.
  static Future<String?> _detectGatewayFromInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        // Look for USB tethering interfaces (rndis, usb, ncm, etc.)
        final nameLower = iface.name.toLowerCase();
        final isUsb = nameLower.contains('rndis') ||
            nameLower.contains('usb') ||
            nameLower.contains('ncm') ||
            nameLower.contains('rmnet');
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          // For USB tethering subnets, the PC is typically at .129 or .1
          final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
          if (isUsb || subnet == '192.168.42') {
            // The phone is one end; the PC is the other common host
            final phoneLastOctet = int.tryParse(parts[3]) ?? 0;
            final candidates = <String>[
              if (phoneLastOctet != 129) '$subnet.129',
              if (phoneLastOctet != 1) '$subnet.1',
              if (phoneLastOctet != 73) '$subnet.73',
            ];
            for (final candidate in candidates) {
              if (await _fastSocketProbe(candidate)) return candidate;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
