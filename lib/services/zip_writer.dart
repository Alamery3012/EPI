import 'dart:convert';
import 'dart:typed_data';

/// Minimal ZIP writer (stored entries, UTF-8 names) used for the OpenXML
/// .xlsx package. No third-party dependency, so the format is fully under
/// our control (FRS-DOC-01).
class ZipWriter {
  final _entries = <_Entry>[];

  void addString(String name, String content) => addBytes(name, Uint8List.fromList(utf8.encode(content)));

  void addBytes(String name, Uint8List data) => _entries.add(_Entry(name, data, crc32(data)));

  Uint8List build({DateTime? when}) {
    final t = when ?? DateTime.now();
    final dosTime = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
    final dosDate = ((t.year - 1980) << 9) | (t.month << 5) | t.day;
    final out = BytesBuilder();
    final central = BytesBuilder();
    for (final e in _entries) {
      final name = utf8.encode(e.name);
      final offset = out.length;
      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 0x0800, Endian.little) // UTF-8 names
        ..setUint16(8, 0, Endian.little) // stored
        ..setUint16(10, dosTime, Endian.little)
        ..setUint16(12, dosDate, Endian.little)
        ..setUint32(14, e.crc, Endian.little)
        ..setUint32(18, e.data.length, Endian.little)
        ..setUint32(22, e.data.length, Endian.little)
        ..setUint16(26, name.length, Endian.little)
        ..setUint16(28, 0, Endian.little);
      out.add(local.buffer.asUint8List());
      out.add(name);
      out.add(e.data);

      final c = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, 0x0800, Endian.little)
        ..setUint16(10, 0, Endian.little)
        ..setUint16(12, dosTime, Endian.little)
        ..setUint16(14, dosDate, Endian.little)
        ..setUint32(16, e.crc, Endian.little)
        ..setUint32(20, e.data.length, Endian.little)
        ..setUint32(24, e.data.length, Endian.little)
        ..setUint16(28, name.length, Endian.little)
        ..setUint16(30, 0, Endian.little)
        ..setUint16(32, 0, Endian.little)
        ..setUint16(34, 0, Endian.little)
        ..setUint16(36, 0, Endian.little)
        ..setUint32(38, 0, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central.add(c.buffer.asUint8List());
      central.add(name);
    }
    final cdOffset = out.length;
    final cd = central.takeBytes();
    out.add(cd);
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _entries.length, Endian.little)
      ..setUint16(10, _entries.length, Endian.little)
      ..setUint32(12, cd.length, Endian.little)
      ..setUint32(16, cdOffset, Endian.little)
      ..setUint16(20, 0, Endian.little);
    out.add(end.buffer.asUint8List());
    return out.takeBytes();
  }
}

class _Entry {
  final String name;
  final Uint8List data;
  final int crc;
  _Entry(this.name, this.data, this.crc);
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
