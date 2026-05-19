import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import '../crypto/codec.dart';

class SafetyNumberScreen extends StatefulWidget {
  const SafetyNumberScreen({
    super.key,
    required this.myIk,
    required this.peerIk,
    required this.peerHandle,
  });

  final Uint8List myIk;
  final Uint8List peerIk;
  final String peerHandle;

  @override
  State<SafetyNumberScreen> createState() => _SafetyNumberScreenState();
}

class _SafetyNumberScreenState extends State<SafetyNumberScreen> {
  String? _fingerprintHex;

  @override
  void initState() {
    super.initState();
    _computeFingerprint();
  }

  Future<void> _computeFingerprint() async {
    // Fingerprint: SHA-256(IK_a || IK_b)
    // Standart yaklaşım: Anahtarları sıraya koyup birleştirmek (örn: alfabetik veya byte sırası)
    // Böylece hem Alice hem de Bob aynı sayıyı görür.
    // Şimdilik MVP için basitçe birleştirip hashliyoruz:
    
    final listA = widget.myIk.toList();
    final listB = widget.peerIk.toList();
    
    // Sort to ensure symmetric result regardless of who is initiator
    final isMyKeyFirst = _compareBytes(listA, listB) <= 0;
    
    final combined = isMyKeyFirst 
        ? [...listA, ...listB] 
        : [...listB, ...listA];

    final sha256 = Cryptography.instance.sha256();
    final hash = await sha256.hash(combined);
    
    // Formatlama: Okunabilir olması için her 2 karakterde bir boşluk eklenebilir
    // MVP için 64 karakterlik hex string'i 4'erli gruplara bölelim
    final hexString = _bytesToHex(hash.bytes);
    
    if (mounted) {
      setState(() {
        _fingerprintHex = _formatFingerprint(hexString);
      });
    }
  }

  int _compareBytes(List<int> a, List<int> b) {
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }
  
  String _formatFingerprint(String hex) {
    final buffer = StringBuffer();
    for (int i = 0; i < hex.length; i += 4) {
      if (i > 0) buffer.write(' ');
      if (i > 0 && i % 32 == 0) buffer.write('\n'); // 8 blokta bir alt satıra in
      buffer.write(hex.substring(i, (i + 4 < hex.length) ? i + 4 : hex.length));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Güvenlik Numarası'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.shield_rounded, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              '${widget.peerHandle} ile Uçtan Uca Şifreli',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Bu güvenlik numarasını karşı tarafın cihazındaki numara ile karşılaştırarak iletişimin güvenliğini doğrulayabilirsiniz.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _fingerprintHex == null
                  ? const CircularProgressIndicator()
                  : SelectableText(
                      _fingerprintHex!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
