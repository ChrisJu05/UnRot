import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// Minimal PNG encoder for 8-bit grey, RGB or RGBA pixel data.
Uint8List encodePng(int width, int height, int channels, Uint8List pixels) {
  if (channels < 1 || channels > 4 || channels == 2) throw ArgumentError('channels must be 1, 3 or 4');
  final rowBytes = width * channels;
  if (pixels.length < rowBytes * height) throw ArgumentError('not enough pixel data');
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    raw.add(Uint8List.sublistView(pixels, y * rowBytes, (y + 1) * rowBytes));
  }
  final idat = ZLibEncoder(level: 6).convert(raw.takeBytes());
  final colorType = switch (channels) {
    1 => 0,
    3 => 2,
    _ => 6,
  };
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, colorType)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final out = BytesBuilder(copy: false)..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(idat));
  _chunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final length = ByteData(4)..setUint32(0, data.length);
  out.add(length.buffer.asUint8List());
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out.add(typeBytes);
  out.add(data);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  out.add(crc.buffer.asUint8List());
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
