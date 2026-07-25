import 'dart:convert';
import 'package:flutter/services.dart';

class LocoTypeUtil {
  static final LocoTypeUtil _instance = LocoTypeUtil._internal();
  factory LocoTypeUtil() => _instance;
  LocoTypeUtil._internal();

  final Map<String, String> _locoTypeMap = {};
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final csvData = await rootBundle.loadString('assets/loco_type_info.csv');
      final lines = const LineSplitter().convert(csvData);
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        final parts = trimmedLine.split(',');
        if (parts.length >= 2) {
          final code = parts[0].trim();
          final type = parts[1].trim();
          if (code.isNotEmpty && type.isNotEmpty) {
            _locoTypeMap[code] = type;
          }
        }
      }
    // ignore: empty_catches
    } catch (e) {}
    _isInitialized = true;
  }

  String? getLocoTypeByCode(String code) {
    if (!_isInitialized || code.isEmpty) return null;

    if (_locoTypeMap.containsKey(code)) {
      return _locoTypeMap[code];
    }

    if (code.length >= 4) {
      final prefix3 = code.substring(0, 3);
      return _locoTypeMap[prefix3];
    }

    return null;
  }

  String? getLocoTypeByLocoNumber(String locoNumber) {
    if (!_isInitialized) return null;

    final cleaned = locoNumber.trim().replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    if (cleaned.isEmpty || cleaned == '<NUL>') return null;
    if (cleaned.length < 3) return null;

    if (cleaned.length >= 4) {
      final longCode = cleaned.substring(0, 4);
      final result = getLocoTypeByCode(longCode);
      if (result != null) return result;
    }

    final prefix = cleaned.substring(0, 3);
    return getLocoTypeByCode(prefix);
  }

  Map<String, String> getAllMappings() {
    return Map.from(_locoTypeMap);
  }

  bool get isInitialized => _isInitialized;

  int get mappingCount => _locoTypeMap.length;
}
