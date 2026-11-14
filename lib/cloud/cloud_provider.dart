import 'dart:typed_data';

abstract class CloudProvider {
  String get name;
  bool get configured;
  Future<void> connect();
  Future<void> disconnect();
  Future<List<String>> list();
  Future<Uint8List> read(String key);
  Future<void> write(String key, Uint8List bytes);
}

class CloudFailure implements Exception {
  final String message;
  const CloudFailure(this.message);
  @override
  String toString() => message;
}
