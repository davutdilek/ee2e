import 'dart:convert';
import 'dart:typed_data';

/// base64url helper'lar (padding'siz wire format).
class B64u {
  const B64u._();

  static String encode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Uint8List decode(String value) {
    final padded = value + '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode(padded);
  }
}
