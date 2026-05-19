import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/keys_api.dart';
import '../crypto/identity.dart';
import '../storage/secure_keys.dart';

/// Faz 2A — Kimlik & Bundle yönetim ekranı.
///
/// Bu ekran "yetişkin" mesajlaşma akışından bağımsız bir araç gibi davranır:
/// kullanıcı kimliğini üretir, sunucuya yükler, başkasının bundle'ını çekip
/// SPK signature'ını doğrular. Faz 2B'de bu adım X3DH'ye girdi olarak kullanılır.
class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key, required this.serverUrl});

  final String serverUrl;

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final _store = SecureKeyStore();
  late final _api = KeysApi(baseUrl: widget.serverUrl);
  final _handleCtrl = TextEditingController();
  final _peerCtrl = TextEditingController();
  final _logCtrl = ScrollController();

  Identity? _identity;
  SignedPreKey? _spk;
  List<OneTimePreKey> _opks = const [];
  final List<String> _log = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = await _store.loadIdentity();
    final spk = await _store.loadSignedPreKey();
    final opks = await _store.loadOneTimePreKeys();
    setState(() {
      _identity = id;
      _spk = spk;
      _opks = opks;
      _handleCtrl.text = id?.handle ?? '';
    });
    _say(id == null ? 'Kimlik yok — "Üret" butonuna basın.' : 'Kimlik yüklendi.');
  }

  void _say(String msg) {
    setState(() {
      _log.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logCtrl.hasClients) {
        _logCtrl.animateTo(
          _logCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _generate() async {
    final handle = _handleCtrl.text.trim();
    if (handle.isEmpty) {
      _say('Handle boş olamaz (örn. "ali").');
      return;
    }
    setState(() => _busy = true);
    try {
      _say('IK + SPK + 100 OPK üretiliyor...');
      final id = await Identity.generate(handle: handle);
      final spk = await SignedPreKey.generate(identity: id, id: 1);
      final opks = await OneTimePreKey.generateBatch(count: 100);
      await _store.saveIdentity(id);
      await _store.saveSignedPreKey(spk);
      await _store.saveOneTimePreKeys(opks);
      setState(() {
        _identity = id;
        _spk = spk;
        _opks = opks;
      });
      _say('Üretildi ve cihaza güvenli kaydedildi (private key disk\'e şifreli).');
    } catch (e) {
      _say('HATA: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final id = _identity;
    final spk = _spk;
    if (id == null || spk == null) {
      _say('Önce kimliği üret.');
      return;
    }
    setState(() => _busy = true);
    try {
      _say('Public bundle sunucuya yükleniyor...');
      final bundle = await PublicKeyBundle.from(identity: id, spk: spk, opks: _opks);
      await _api.uploadBundle(bundle);
      _say('Yükleme başarılı (HTTP 204). Sunucu sadece public key\'leri sakladı.');
    } catch (e) {
      _say('HATA: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchPeer() async {
    final peer = _peerCtrl.text.trim();
    if (peer.isEmpty) {
      _say('Karşı tarafın handle\'ını yaz.');
      return;
    }
    setState(() => _busy = true);
    try {
      _say('Sunucudan $peer bundle\'ı çekiliyor (1 OPK tüketilir)...');
      final fetched = await _api.fetchBundle(peer);
      if (fetched == null) {
        _say('$peer sunucuda bilinmiyor (404).');
        return;
      }
      _say('Bundle alındı:');
      _say('  signed_prekey_id = ${fetched.signedPreKeyId}');
      _say('  one_time_prekey  = ${fetched.oneTimePreKey?.opkId ?? "YOK (SPK-only fallback)"}');
      _say('SPK signature doğrulanıyor (Identity sign key ile)...');
      final ok = await fetched.verifySpkSignature();
      _say(ok
          ? '✅ İmza geçerli — bu bundle gerçekten $peer\'in IK ile imzalanmış.'
          : '❌ İmza GEÇERSİZ — MITM olabilir, bu bundle\'ı KULLANMA.');
    } catch (e) {
      _say('HATA: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wipe() async {
    setState(() => _busy = true);
    await _store.wipe();
    setState(() {
      _identity = null;
      _spk = null;
      _opks = const [];
      _busy = false;
    });
    _say('Cihazdaki tüm anahtar materyali silindi.');
  }

  @override
  void dispose() {
    _api.close();
    _handleCtrl.dispose();
    _peerCtrl.dispose();
    _logCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasIdentity = _identity != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faz 2A — Anahtar Yönetimi'),
        actions: [
          if (hasIdentity)
            IconButton(
              tooltip: 'Anahtarları sıfırla',
              onPressed: _busy ? null : _wipe,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kIsWeb)
                const _Card.warning(
                  'Web demo: Tarayıcı IndexedDB native keychain değildir. '
                  'Gerçek private key için iOS/Android/macOS native build kullanın.',
                ),
              const SizedBox(height: 8),
              _StatusCard(
                identity: _identity,
                spk: _spk,
                opkCount: _opks.length,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _handleCtrl,
                enabled: !hasIdentity && !_busy,
                decoration: const InputDecoration(
                  labelText: 'Kendi handle\'ın (örn. ali)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy || hasIdentity ? null : _generate,
                      icon: const Icon(Icons.vpn_key),
                      label: const Text('Kimliği Üret'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy || !hasIdentity ? null : _upload,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Bundle\'ı Yükle'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _peerCtrl,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Karşı tarafın handle\'ı',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _fetchPeer,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('Bundle Çek + Doğrula'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    controller: _logCtrl,
                    itemCount: _log.length,
                    itemBuilder: (_, i) => SelectableText(
                      _log[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.identity,
    required this.spk,
    required this.opkCount,
  });

  final Identity? identity;
  final SignedPreKey? spk;
  final int opkCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              identity == null ? 'Kimlik: —' : 'Kimlik: ${identity!.handle}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('SPK id: ${spk?.id ?? "—"}    OPK havuzu: $opkCount'),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card.warning(this.text);

  final String text;
  static const Color _color = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.18),
        border: Border.all(color: _color, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
