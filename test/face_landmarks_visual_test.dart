import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:violetta_app/core/graphics/violetta_3d_render_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ViolettaFaceLandmarkDetector.resetForTest);

  test('color cluster detector finds red eyes and blue mouth markup', () async {
    await ViolettaFaceLandmarkDetector.ensureInitialized();

    expect(Violetta3DRenderEngine.landmarksDetected, isTrue);

    final Offset left = Violetta3DRenderEngine.leftEyeNorm;
    final Offset right = Violetta3DRenderEngine.rightEyeNorm;
    final Offset mouth = Violetta3DRenderEngine.mouthNorm;

    // ignore: avoid_print
    print('detected leftEyeNorm=$left rightEyeNorm=$right mouthNorm=$mouth');

    expect(left.dx, greaterThan(0.0));
    expect(left.dx, lessThan(0.5));
    expect(right.dx, greaterThan(left.dx));
    expect(right.dx, lessThan(1.0));
    expect(mouth.dy, greaterThan(left.dy));
    expect(mouth.dx, greaterThan(left.dx));
    expect(mouth.dx, lessThan(right.dx + 0.15));
  });

  test('detected norms map to rig centers inside imageRect', () async {
    await ViolettaFaceLandmarkDetector.ensureInitialized();

    final Rect imageRect = Violetta3DRenderEngine.imageRectInRig();
    final Offset leftEye = Offset(
      imageRect.left +
          Violetta3DRenderEngine.leftEyeNorm.dx * imageRect.width,
      imageRect.top +
          Violetta3DRenderEngine.leftEyeNorm.dy * imageRect.height,
    );
    final Offset rightEye = Offset(
      imageRect.left +
          Violetta3DRenderEngine.rightEyeNorm.dx * imageRect.width,
      imageRect.top +
          Violetta3DRenderEngine.rightEyeNorm.dy * imageRect.height,
    );
    final Offset mouth = Offset(
      imageRect.left + Violetta3DRenderEngine.mouthNorm.dx * imageRect.width,
      imageRect.top + Violetta3DRenderEngine.mouthNorm.dy * imageRect.height,
    );

    expect(imageRect.contains(leftEye), isTrue);
    expect(imageRect.contains(rightEye), isTrue);
    expect(imageRect.contains(mouth), isTrue);
    expect((rightEye.dx - leftEye.dx).abs(), greaterThan(8.0));
  });
}
