import 'dart:math';
import 'dart:typed_data';

/// Trafik analizi (Traffic Analysis) saldırılarına karşı mesajları sabit
/// bir blok boyutuna tamamlamak için kullanılan Padding sınıfı.
class MessagePadding {
  /// Blok boyutu (örneğin 512 byte)
  static const int blockSize = 512;

  /// Verilen plaintext'i 512 byte'ın katlarına tamamlar.
  /// Format: [4 byte uzunluk (Big Endian)] + [Orijinal Veri] + [Rastgele Dolgu]
  static List<int> pad(List<int> data) {
    final payloadLength = data.length;
    final totalLengthRequired = 4 + payloadLength;
    
    int paddedSize = (totalLengthRequired / blockSize).ceil() * blockSize;
    if (paddedSize == 0) paddedSize = blockSize;
    
    final paddingBytesCount = paddedSize - totalLengthRequired;
    
    final builder = BytesBuilder();
    
    final lengthData = ByteData(4)..setUint32(0, payloadLength, Endian.big);
    builder.add(lengthData.buffer.asUint8List());
    
    builder.add(data);
    
    if (paddingBytesCount > 0) {
      final random = Random.secure();
      final paddingBytes = List<int>.generate(paddingBytesCount, (_) => random.nextInt(256));
      builder.add(paddingBytes);
    }
    
    return builder.toBytes();
  }

  /// Dolgulu verinin içerisinden orijinal mesajı çıkarır.
  static List<int> unpad(List<int> paddedData) {
    if (paddedData.length < 4) {
      throw Exception('Padding hatası: Veri çok kısa');
    }
    
    final byteData = ByteData.sublistView(Uint8List.fromList(paddedData));
    final payloadLength = byteData.getUint32(0, Endian.big);
    
    if (4 + payloadLength > paddedData.length) {
      throw Exception('Padding hatası: Veri bozuk veya eksik');
    }
    
    return paddedData.sublist(4, 4 + payloadLength);
  }
}
