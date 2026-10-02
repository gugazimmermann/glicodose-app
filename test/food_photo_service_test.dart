import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes_app/services/food_photo_service.dart';

void main() {
  group('mergeFoodText', () {
    test('replaces an empty field and appends to existing text', () {
      expect(mergeFoodText('', '  prato de arroz '), 'prato de arroz');
      expect(mergeFoodText('   ', 'feijão'), 'feijão');
      expect(mergeFoodText('pão ', 'queijo'), 'pão queijo');
      expect(mergeFoodText('pão', '  '), 'pão');
    });
  });

  group('foodPhotoMimeType', () {
    test('uses jpeg unless the file name says otherwise', () {
      expect(foodPhotoMimeType('IMG_1.jpg'), 'image/jpeg');
      expect(foodPhotoMimeType('prato.PNG'), 'image/png');
      expect(foodPhotoMimeType('prato.webp'), 'image/webp');
      expect(foodPhotoMimeType('prato.gif'), 'image/gif');
    });
  });

  test('ensureFoodPhotoBytes rejects a tiny photo', () {
    expect(
      () => ensureFoodPhotoBytes(Uint8List(8)),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Foto inválida'),
        ),
      ),
    );
  });
}
