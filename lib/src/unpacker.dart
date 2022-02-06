import 'dart:convert';
import 'dart:typed_data';

abstract class ExtensionFactory {

}

/// Streaming API for unpacking (deserializing) data from msgpack binary format.
///
/// unpackXXX methods returns value if it exist, or `null`.
/// Throws [FormatException] if value is not an requested type,
/// but in that case throwing exception not corrupt internal state,
/// so other unpackXXX methods can be called after that.
class Unpacker {
  /// Manipulates with provided [Uint8List] to sequentially unpack values.
  /// Use [Unpaker.fromList()] to unpack raw `List<int>` bytes.
  Unpacker(this._list, {this.extensionFactory}) : _d = ByteData.view(_list.buffer, _list.offsetInBytes);

  ///Convenient
  Unpacker.fromList(List<int> l, {ExtensionFactory? extensionFactory}) : this(Uint8List.fromList(l), extensionFactory: extensionFactory);

  final ExtensionFactory? extensionFactory;

  final Uint8List _list;
  final ByteData _d;
  int _offset = 0;

  final _strCodec = const Utf8Codec();

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a bool,
  bool? unpackBool() {
    final b = _d.getUint8(_offset);
    bool? v;
    if (b == 0xc2) {
      v = false;
      _offset += 1;
    } else if (b == 0xc3) {
      v = true;
      _offset += 1;
    } else if (b == 0xc0) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('bool', b, _offset);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not an integer,
  int? unpackInt() {
    final b = _d.getUint8(_offset);
    int? v;
    if (b <= 0x7f || b >= 0xe0) {
      /// Int value in fixnum range [-32..127] encoded in header 1 byte
      v = _d.getInt8(_offset);
      _offset += 1;
    } else if (b == 0xcc) {
      v = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == 0xcd) {
      v = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xce) {
      v = _d.getUint32(++_offset);
      _offset += 4;
    } else if (b == 0xcf) {
      v = _d.getUint64(++_offset);
      _offset += 8;
    } else if (b == 0xd0) {
      v = _d.getInt8(++_offset);
      _offset += 1;
    } else if (b == 0xd1) {
      v = _d.getInt16(++_offset);
      _offset += 2;
    } else if (b == 0xd2) {
      v = _d.getInt32(++_offset);
      _offset += 4;
    } else if (b == 0xd3) {
      v = _d.getInt64(++_offset);
      _offset += 8;
    } else if (b == 0xc0) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('integer', b, _offset);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a Double.
  double? unpackDouble() {
    final b = _d.getUint8(_offset);
    double? v;
    if (b == 0xca) {
      v = _d.getFloat32(++_offset);
      _offset += 4;
    } else if (b == 0xcb) {
      v = _d.getFloat64(++_offset);
      _offset += 8;
    } else if (b == 0xc0) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('double', b, _offset);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Empty
  /// Throws [FormatException] if value is not a String.
  String? unpackString() {
    final b = _d.getUint8(_offset);
    if (b == 0xc0) {
      _offset += 1;
      return null;
    }
    int len;

    /// fixstr 101XXXXX stores a byte array whose len is upto 31 bytes:
    if (b & 0xE0 == 0xA0) {
      len = b & 0x1F;
      _offset += 1;
    } else if (b == 0xc0) {
      _offset += 1;
      return null;
    } else if (b == 0xd9) {
      len = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == 0xda) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xdb) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('String', b, _offset);
    }
    final data =
        Uint8List.view(_list.buffer, _list.offsetInBytes + _offset, len);
    _offset += len;
    return _strCodec.decode(data);
  }

  /// Unpack [List.length] if packed value is an [List] or `null`.
  ///
  /// Encoded in msgpack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [List] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [List].
  int unpackListLength() {
    final b = _d.getUint8(_offset);
    int len;
    if (b & 0xF0 == 0x90) {
      /// fixarray 1001XXXX stores an array whose length is upto 15 elements:
      len = b & 0xF;
      _offset += 1;
    } else if (b == 0xc0) {
      len = 0;
      _offset += 1;
    } else if (b == 0xdc) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xdd) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('List length', b, _offset);
    }
    return len;
  }

  /// Unpack [Map.length] if packed value is an [Map] or `null`.
  ///
  /// Encoded in msgpack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [Map] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [Map].
  int unpackMapLength() {
    final b = _d.getUint8(_offset);
    int len;
    if (b & 0xF0 == 0x80) {
      /// fixmap 1000XXXX stores a map whose length is upto 15 elements
      len = b & 0xF;
      _offset += 1;
    } else if (b == 0xc0) {
      len = 0;
      _offset += 1;
    } else if (b == 0xde) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xdf) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('Map length', b, _offset);
    }
    return len;
  }

  /// Unpack an Ext 8-byte
  ///
  /// ext 8 stores an integer and a byte array whose length is upto (2^8)-1 bytes:
  /// +--------+--------+--------+========+
  /// |  0xc7  |XXXXXXXX|  type  |  data  |
  /// +--------+--------+--------+========+
  ///
  /// where
  /// * XXXXXXXX is a 8-bit unsigned integer which represents N
  /// * YYYYYYYY_YYYYYYYY is a 16-bit big-endian unsigned integer which represents N
  /// * ZZZZZZZZ_ZZZZZZZZ_ZZZZZZZZ_ZZZZZZZZ is a big-endian 32-bit unsigned integer which represents N
  /// * N is a length of data
  /// * type is a signed 8-bit signed integer
  /// * type < 0 is reserved for future extension including 2-byte type information
  List<int> unpackExt8(ExtensionFactory extensionFactory) {
    print('unpacking ext8...'); // TODO remove
    final int constant = _d.getUint8(_offset++);
    assert(constant == 0xc7);

    final int n = _d.getUint8(_offset++);

    final int type = _d.getUint8(_offset++);
    print('type is $type');

    final List<int> buffer = <int>[-420];
    for (int i = 0; i < n; i++) {
      buffer.add(_d.getUint8(_offset++));
    }

    return buffer;
  }

  /// Unpack value if packed value is binary or `null`.
  ///
  /// Encoded in msgpack packet null unpacks to [List] with 0 length for convenience.
  /// Throws [FormatException] if value is not a binary.
  List<int> unpackBinary() {
    final b = _d.getUint8(_offset);
    int len;
    if (b == 0xc4) {
      len = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == 0xc0) {
      len = 0;
      _offset += 1;
    } else if (b == 0xc5) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == 0xc6) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('Binary', b, _offset);
    }
    final data =
        Uint8List.view(_list.buffer, _list.offsetInBytes + _offset, len);
    _offset += len;
    return data.toList();
  }

  Object? _unpack() {
    final b = _d.getUint8(_offset);
    if (b <= 0x7f ||
        b >= 0xe0 ||
        b == 0xcc ||
        b == 0xcd ||
        b == 0xce ||
        b == 0xcf ||
        b == 0xd0 ||
        b == 0xd1 ||
        b == 0xd2 ||
        b == 0xd3) {
      return unpackInt();
    } else if (b == 0xc0 || b == 0xc2 || b == 0xc3) {
      return unpackBool(); //null included
    } else if (b == 0xca || b == 0xcb) {
      return unpackDouble();
    } else if ((b & 0xE0) == 0xA0 ||
        b == 0xc0 ||
        b == 0xd9 ||
        b == 0xda ||
        b == 0xdb) {
      return unpackString();
    } else if (b == 0xc4 || b == 0xc5 || b == 0xc6) {
      return unpackBinary();
    } else if ((b & 0xF0) == 0x90 || b == 0xdc || b == 0xdd) {
      return unpackList();
    } else if ((b & 0xF0) == 0x80 || b == 0xde || b == 0xdf) {
      return unpackMap();
    } else if (b == 0xc7) {
      if (extensionFactory != null) {
        return unpackExt8(extensionFactory!);
      } else {
        throw const FormatException('Tried to unpack ext8 but no extensionFactory provided!');
      }
    } else {
      throw _formatException('Unknown', b, _offset);
    }
  }

  /// Automatically unpacks `bytes` to [List] where items has corresponding data types.
  ///
  /// Return types declared as [Object] instead of `dynamic` for safety reasons.
  /// You need explicitly cast to proper types. And in case with [Object]
  /// compiler checks will force you to do it whereas with `dynamic` it will not.
  List<Object?> unpackList() {
    final length = unpackListLength();
    return List.generate(length, (_) => _unpack());
  }

  /// Automatically unpacks `bytes` to [Map] where key and values has corresponding data types.
  ///
  /// Return types declared as [Object] instead of `dynamic` for safety reasons.
  /// You need explicitly cast to proper types. And in case with [Object]
  /// compiler checks will force you to do it whereas with `dynamic` it will not.
  Map<Object?, Object?> unpackMap() {
    final length = unpackMapLength();
    return {for (var i = 0; i < length; i++) _unpack(): _unpack()};
  }

  Exception _formatException(String type, int b, int offset) => FormatException(
      'Try to unpack $type value, but it\'s not an $type, byte = $b, offset = $offset');
}
