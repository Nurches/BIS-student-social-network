// D-02 (Week 11): the Flutter logo must not survive in any icon size, because
// on iOS the push shows the app icon.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// SHA-256 of the icons `flutter create` writes (Flutter 3.41 template).
const _flutterTemplateIcons = {
  '7770183009e914112de7d8ef1d235a6a30c5834424858e0d2f8253f6b8d31926',
  'cab10a0d391ec5bc09ef50ce49e8ad401cee7ef03707ec0923a222c5c2b3d212',
  'b9ad02cf6576a04d1b6806ac02a2431481b448dd0c2e505ce25842d1f7c4730b',
  'c6e6d3b215ae744a9c391f4c4d44157eff5e739d6ad6c39f9bfa5df66dddd267',
  '5dee24dc104ac76dc162e42ae0beb163d426bf365562ee28ba7b3ad368559a60',
  'a9b21eb6f4271385655a8771f76e29eef8c1107d7879cbcfc567e6619d1f716a',
  'e677d701ffe4af7bc2935098d6b3984cc9ab7ace573e6900955a5535b12410cf',
  '7c61c42fc7b657d9cf314d32a4ec458f0647c3aaf360be1b9377857266ec2499',
  '19be171481dc71a0b2803ebcd01dd8b0c5fd5778dee34c0a3cabc948c225f24e',
  '4209a49e44a92ec40a327d3455eb1b1c153ee83d75de1c2be0a12ab18b2ff9de',
  '836c918cb613249eba0483a6b02fa3df3c1c0a89a315ee4d3b88509b83c7ab73',
  '41c7d42f6e61f8fe7f30b1ffa2256aecbc9682be06d18c4a3062043e1a2e547c',
  '5d7e5bdf01b93802bc973345b3a78c038907147625035952a08a115a563b7f81',
  '6a7c8f0d703e3682108f9662f813302236240d3f8f638bb391e32bfb96055fef',
  'c7c0c0189145e4e32a401c61c9bdc615754b0264e7afae24e834bb81049eaf81',
  'e14aa40904929bf313fded22cf7e7ffcbf1d1aac4263b5ef1be8bfce650397aa',
  '4d470bf22d5c17d84edc5f82516d1ba8a1c09559cd761cefb792f86d9f52b540',
  '3c34e1f298d0c9ea3455d46db6b7759c8211a49e9ec6e44b635fc5c87dfb4180',
};

const _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

List<File> _pngs(String dir, bool Function(String name) keep) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.png') && keep(f.uri.pathSegments.last))
    .toList();

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

void main() {
  test('no iOS Icon-App-* file is the Flutter template icon', () {
    final icons = _pngs(_iosIcons, (name) => name.startsWith('Icon-App-'));
    expect(icons, hasLength(greaterThanOrEqualTo(15)));
    for (final icon in icons) {
      expect(
        _flutterTemplateIcons,
        isNot(contains(_sha256(icon))),
        reason: '${icon.path} is still the Flutter logo',
      );
    }
  });

  test('every Icon-App-* listed in Contents.json exists', () {
    final contents = File('$_iosIcons/Contents.json').readAsStringSync();
    final names = RegExp(
      r'"filename"\s*:\s*"([^"]+)"',
    ).allMatches(contents).map((m) => m.group(1)!).toSet();
    expect(names, contains('Icon-App-1024x1024@1x.png'));
    for (final name in names) {
      expect(File('$_iosIcons/$name').existsSync(), isTrue, reason: name);
    }
  });

  test('no Android launcher icon is the Flutter template icon', () {
    final icons = _pngs(
      'android/app/src/main/res',
      (name) => name == 'ic_launcher.png',
    );
    expect(icons, hasLength(5));
    for (final icon in icons) {
      expect(_flutterTemplateIcons, isNot(contains(_sha256(icon))));
    }
  });

  test('Android pushes use the Qatys status-bar icon', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains('com.google.firebase.messaging.default_notification_icon'),
    );
    expect(manifest, contains('@drawable/ic_stat_qatys'));
    expect(
      File('android/app/src/main/res/drawable/ic_stat_qatys.xml').existsSync(),
      isTrue,
    );
  });
}
