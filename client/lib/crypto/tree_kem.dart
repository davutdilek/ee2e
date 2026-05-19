import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'codec.dart';

/// TreeKEM (Tree-based Key Encapsulation Mechanism)
///
/// MLS (Messaging Layer Security) protokolünün temel yapı taşı.
/// İkili ağaç (binary tree) üzerinde yapraklar üyelere karşılık gelir.
/// Bir üye gruba katıldığında veya çıktığında, sadece yapraktan köke giden yoldaki
/// düğümler yeniden hesaplanır — O(log N) karmaşıklık.

class TreeNode {
  List<int>? secretKey;
  SimplePublicKey? publicKey;
  SimpleKeyPair? keyPair;
  String? memberId;
  TreeNode({this.secretKey, this.publicKey, this.keyPair, this.memberId});
  bool get isBlank => secretKey == null;
}

/// Basit left-balanced binary tree, düz dizi (breadth-first) olarak.
/// Derinlik d olan ağaçta:
///   - Kök: indeks 0
///   - sol(i) = 2i+1
///   - sağ(i) = 2i+2
///   - parent(i) = (i-1)/2
///   - Yapraklar: offset = leafOffset .. leafOffset + leafCount - 1
class TreeKem {
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  List<TreeNode> nodes = [];
  int leafCount = 0;
  int? myLeafIndex;

  // Derinlik: en küçük d ki 2^d >= leafCount
  int get _depth {
    if (leafCount <= 1) return 0;
    int d = 0;
    while ((1 << d) < leafCount) d++;
    return d;
  }

  // Yapraklar breadth-first dizide hangi offset'ten başlar
  int get _leafOffset => (1 << _depth) - 1;

  // Toplam düğüm = yaprak offset + yaprak sayısı
  int get _totalNodes => _leafOffset + leafCount;

  // ── Navigasyon ──
  static int _left(int i) => 2 * i + 1;
  static int _right(int i) => 2 * i + 2;
  static int _parent(int i) => i == 0 ? 0 : (i - 1) ~/ 2;

  int _leafNodeIndex(int leafIdx) => _leafOffset + leafIdx;

  /// Yapraktan köke (indeks 0) giden yol (kök dahil değil)
  List<int> _pathToRoot(int nodeIdx) {
    final path = <int>[];
    var cur = nodeIdx;
    while (cur > 0) {
      cur = _parent(cur);
      path.add(cur);
    }
    return path;
  }

  // ── Temel İşlemler ──

  Future<void> createGroup(String myId) async {
    leafCount = 1;
    myLeafIndex = 0;
    _rebuildNodesList();
    nodes[_leafNodeIndex(0)] = await _newLeaf(myId);
    await _updatePathUp(_leafNodeIndex(0));
  }

  Future<Map<String, dynamic>> addMember(String newMemberId) async {
    // Eski yaprak verilerini kaydet
    final oldLeafCount = leafCount;
    final oldLeafOffset = _leafOffset;
    final oldLeaves = <int, TreeNode>{};
    for (int i = 0; i < oldLeafCount; i++) {
      final oldIdx = oldLeafOffset + i;
      if (oldIdx < nodes.length) {
        oldLeaves[i] = nodes[oldIdx];
      }
    }

    final newLeafIdx = leafCount;
    leafCount++;

    // Yeniden boyutlandır
    final needed = _totalNodes;
    nodes = List.generate(needed, (_) => TreeNode());

    // Eski yaprakları yeni pozisyonlara geri koy
    for (final entry in oldLeaves.entries) {
      final newIdx = _leafNodeIndex(entry.key);
      if (newIdx < nodes.length) {
        nodes[newIdx] = entry.value;
      }
    }

    // Yeni üye yaprağını ekle
    final nodeIdx = _leafNodeIndex(newLeafIdx);
    nodes[nodeIdx] = await _newLeaf(newMemberId);

    // Tüm yaprakların yollarını güncelle (ağaç tamamen yeniden inşa)
    for (int i = 0; i < leafCount; i++) {
      final leafNodeIdx = _leafNodeIndex(i);
      if (leafNodeIdx < nodes.length && !nodes[leafNodeIdx].isBlank) {
        await _updatePathUp(leafNodeIdx);
      }
    }

    return {
      'type': 'tree_kem_add',
      'member_id': newMemberId,
      'leaf_index': newLeafIdx,
      'public_key': B64u.encode(nodes[nodeIdx].publicKey!.bytes),
    };
  }

  Future<Map<String, dynamic>> removeMember(int leafIdx) async {
    final nodeIdx = _leafNodeIndex(leafIdx);
    if (nodeIdx >= nodes.length) throw Exception('Geçersiz yaprak');
    final removedId = nodes[nodeIdx].memberId ?? '?';

    // Yaprak ve üst yolunu temizle
    nodes[nodeIdx] = TreeNode();
    for (final p in _pathToRoot(nodeIdx)) {
      nodes[p] = TreeNode();
    }

    // Kendi yaprak sırrımızı yenile → Forward Secrecy
    if (myLeafIndex != null) {
      final myNodeIdx = _leafNodeIndex(myLeafIndex!);
      nodes[myNodeIdx] = await _newLeaf(nodes[myNodeIdx].memberId ?? '');
      await _updatePathUp(myNodeIdx);
    }

    return {'type': 'tree_kem_remove', 'member_id': removedId, 'leaf_index': leafIdx};
  }

  Future<Map<String, dynamic>> selfUpdate() async {
    if (myLeafIndex == null) throw Exception('Grupta değilim');
    final myNodeIdx = _leafNodeIndex(myLeafIndex!);
    final memberId = nodes[myNodeIdx].memberId ?? '';

    // Yeni yaprak → Post-Compromise Security
    nodes[myNodeIdx] = await _newLeaf(memberId);
    await _updatePathUp(myNodeIdx);

    return {
      'type': 'tree_kem_update',
      'leaf_index': myLeafIndex!,
      'public_key': B64u.encode(nodes[myNodeIdx].publicKey!.bytes),
    };
  }

  Future<List<int>> deriveGroupSecret() async {
    if (leafCount == 0) throw Exception('Ağaç boş');
    if (nodes[0].secretKey == null) {
      throw Exception('Kök sırrı türetilemiyor');
    }
    return _kdf(nodes[0].secretKey!, 'EE2E_TreeKEM_Group');
  }

  // ── İç yardımcılar ──

  void _rebuildNodesList() {
    final needed = _totalNodes;
    while (nodes.length < needed) nodes.add(TreeNode());
  }

  Future<void> _updatePathUp(int startNodeIdx) async {
    for (final p in _pathToRoot(startNodeIdx)) {
      final l = _left(p);
      final r = _right(p);
      final lSecret = (l < nodes.length) ? nodes[l].secretKey : null;
      final rSecret = (r < nodes.length) ? nodes[r].secretKey : null;

      List<int>? newSecret;
      if (lSecret != null && rSecret != null) {
        newSecret = await _kdf([...lSecret, ...rSecret], 'EE2E_TreeKEM_Node');
      } else if (lSecret != null) {
        newSecret = await _kdf(lSecret, 'EE2E_TreeKEM_Promote');
      } else if (rSecret != null) {
        newSecret = await _kdf(rSecret, 'EE2E_TreeKEM_Promote');
      }

      if (newSecret != null) {
        final kp = await _x25519.newKeyPair();
        final pub = await kp.extractPublicKey() as SimplePublicKey;
        nodes[p] = TreeNode(secretKey: newSecret, publicKey: pub, keyPair: kp);
      }
    }
  }

  Future<TreeNode> _newLeaf(String memberId) async {
    final kp = await _x25519.newKeyPair();
    final pub = await kp.extractPublicKey() as SimplePublicKey;
    return TreeNode(
      secretKey: _randomBytes(32),
      publicKey: pub,
      keyPair: kp,
      memberId: memberId,
    );
  }

  Future<List<int>> _kdf(List<int> input, String info) async {
    final out = await _hkdf.deriveKey(
      secretKey: SecretKey(input),
      nonce: List<int>.filled(32, 0),
      info: utf8.encode(info),
    );
    return out.extractBytes();
  }

  List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }
}
