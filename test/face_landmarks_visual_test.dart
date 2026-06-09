import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:violetta_app/core/graphics/violetta_3d_render_engine.dart';

void main() {
  test('compare hardcoded landmarks vs PNG norms on current rig', () {
    const Size rigSize = Violetta3DRenderEngine.canvasSize;
    final Rect imageRect = Violetta3DRenderEngine.imageRectInRig();

    final Offset expectedLeftEye = Offset(
      imageRect.left + Violetta3DRenderEngine.leftEyeNorm.dx * imageRect.width,
      imageRect.top + Violetta3DRenderEngine.leftEyeNorm.dy * imageRect.height,
    );
    final Offset expectedRightEye = Offset(
      imageRect.left + Violetta3DRenderEngine.rightEyeNorm.dx * imageRect.width,
      imageRect.top + Violetta3DRenderEngine.rightEyeNorm.dy * imageRect.height,
    );
    final Offset expectedMouth = Offset(
      imageRect.left + Violetta3DRenderEngine.mouthNorm.dx * imageRect.width,
      imageRect.top + Violetta3DRenderEngine.mouthNorm.dy * imageRect.height,
    );

    const Offset hardcodedLeftEye = Offset(221.1, 131.7);
    const Offset hardcodedRightEye = Offset(242.6, 134.3);
    const Offset hardcodedMouth = Offset(245.5, 155.0);

    final Offset leftDelta = hardcodedLeftEye - expectedLeftEye;
    final Offset rightDelta = hardcodedRightEye - expectedRightEye;
    final Offset mouthDelta = hardcodedMouth - expectedMouth;

    // ignore: avoid_print
    print('--- Landmark alignment report (${rigSize.width.toInt()}x${rigSize.height.toInt()}) ---');
    // ignore: avoid_print
    print('imageRect: $imageRect');
    // ignore: avoid_print
    print('leftEye  expected=$expectedLeftEye hardcoded=$hardcodedLeftEye delta=$leftDelta');
    // ignore: avoid_print
    print('rightEye expected=$expectedRightEye hardcoded=$hardcodedRightEye delta=$rightDelta');
    // ignore: avoid_print
    print('mouth    expected=$expectedMouth hardcoded=$hardcodedMouth delta=$mouthDelta');

    final double leftDistance = leftDelta.distance;
    final double rightDistance = rightDelta.distance;
    final double mouthDistance = mouthDelta.distance;

    // ignore: avoid_print
    print(
      'RESULT: ${leftDistance < 3 && rightDistance < 3 && mouthDistance < 3 ? "ALIGNED" : "MISALIGNED"} '
      '(distances: left=$leftDistance, right=$rightDistance, mouth=$mouthDistance px)',
    );

    expect(leftDistance < 3.0 && rightDistance < 3.0 && mouthDistance < 3.0, isTrue);
  });
}
