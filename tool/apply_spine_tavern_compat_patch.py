#!/usr/bin/env python3
"""Tavern edition: add the SpineWidgetController APIs the app expects to a stock
spine_flutter 4.2.36 runtime fetched from pub.dev.

The original author builds against a private, locally customised Spine runtime
that is not in the repository. These additions are a functional equivalent for
the public runtime: frame-rate throttling, a clamped per-update delta, and
before/after animation-apply hooks. ``paintOverflow`` is accepted and stored.

Usage: python tool/apply_spine_tavern_compat_patch.py [--runtime PATH]
Idempotent: re-running on a patched runtime is a no-op.
"""

from argparse import ArgumentParser
from pathlib import Path
import sys

MARKER = '// tavern-compat-patch'

REPLACEMENTS = [
    (
        "  final void Function(SpineWidgetController controller, Canvas canvas, List<RenderCommand> commands)? onAfterPaint;\n",
        "  final void Function(SpineWidgetController controller, Canvas canvas, List<RenderCommand> commands)? onAfterPaint;\n"
        "  " + MARKER + "\n"
        "  final void Function(SpineWidgetController controller)? onBeforeApplyAnimation;\n"
        "  final void Function(SpineWidgetController controller)? onAfterApplyAnimation;\n"
        "  /// Target update rate; null or <= 0 updates every frame.\n"
        "  double? targetFramesPerSecond;\n"
        "  /// Upper bound for a single update delta in seconds.\n"
        "  final double? maxDeltaTime;\n"
        "  /// Extra paint area reserved around the widget (stored for callers).\n"
        "  final EdgeInsets paintOverflow;\n"
        "  /// Delta in seconds used by the most recent skeleton update.\n"
        "  double updateDelta = 0;\n",
    ),
    (
        "      {this.onInitialized, this.onBeforeUpdateWorldTransforms, this.onAfterUpdateWorldTransforms, this.onBeforePaint, this.onAfterPaint});\n",
        "      {this.onInitialized, this.onBeforeUpdateWorldTransforms, this.onAfterUpdateWorldTransforms, this.onBeforePaint, this.onAfterPaint,\n"
        "      this.onBeforeApplyAnimation, this.onAfterApplyAnimation, this.targetFramesPerSecond, this.maxDeltaTime,\n"
        "      this.paintOverflow = EdgeInsets.zero});\n",
    ),
    (
        "    _deltaTime = _stopwatch.elapsedTicks / _stopwatch.frequency;\n"
        "    _stopwatch.reset();\n"
        "    _stopwatch.start();\n"
        "    if (_controller.isPlaying) {\n"
        "      _controller.onBeforeUpdateWorldTransforms?.call(_controller);\n"
        "      _skeletonDrawable.update(_deltaTime);\n"
        "      _controller.onAfterUpdateWorldTransforms?.call(_controller);\n"
        "      markNeedsPaint();\n"
        "      _scheduleFrame();\n"
        "    }\n",
        "    _deltaTime += _stopwatch.elapsedTicks / _stopwatch.frequency;\n"
        "    _stopwatch.reset();\n"
        "    _stopwatch.start();\n"
        "    if (_controller.isPlaying) {\n"
        "      final fps = _controller.targetFramesPerSecond;\n"
        "      if (_firstUpdated && fps != null && fps > 0 && _deltaTime < 1 / fps) {\n"
        "        _scheduleFrame();\n"
        "        return;\n"
        "      }\n"
        "      var delta = _deltaTime;\n"
        "      _deltaTime = 0;\n"
        "      final maxDelta = _controller.maxDeltaTime;\n"
        "      if (maxDelta != null && maxDelta > 0 && delta > maxDelta) delta = maxDelta;\n"
        "      _controller.updateDelta = delta;\n"
        "      if (!_skeletonDrawable.isDisposed) {\n"
        "        _skeletonDrawable.animationState.update(delta);\n"
        "        _controller.onBeforeApplyAnimation?.call(_controller);\n"
        "        _skeletonDrawable.animationState.apply(_skeletonDrawable.skeleton);\n"
        "        _controller.onAfterApplyAnimation?.call(_controller);\n"
        "        _controller.onBeforeUpdateWorldTransforms?.call(_controller);\n"
        "        _skeletonDrawable.skeleton.update(delta);\n"
        "        _skeletonDrawable.skeleton.updateWorldTransform(Physics.update);\n"
        "        _controller.onAfterUpdateWorldTransforms?.call(_controller);\n"
        "      }\n"
        "      markNeedsPaint();\n"
        "      _scheduleFrame();\n"
        "    } else {\n"
        "      _deltaTime = 0;\n"
        "    }\n",
    ),
]

DRAWABLE = (
    "  void update(double delta) {\n    if (_disposed) return;\n",
    "  " + MARKER + "\n  bool get isDisposed => _disposed;\n\n"
    "  void update(double delta) {\n    if (_disposed) return;\n",
)


def patch_gradle(root: Path) -> None:
    # androidx dependencies of the app need the plugin to compile against 34+.
    gradle = root / 'android' / 'build.gradle'
    if not gradle.exists():
        return
    text = gradle.read_text(encoding='utf-8')
    if 'compileSdkVersion 31' in text:
        gradle.write_text(text.replace('compileSdkVersion 31', 'compileSdkVersion 36'), encoding='utf-8')
        print('spine_flutter Android compileSdk -> 36')


def main() -> int:
    parser = ArgumentParser()
    parser.add_argument('--runtime', default='packages/spine_flutter')
    args = parser.parse_args()
    root = Path(args.runtime)
    patch_gradle(root)
    widget = root / 'lib' / 'spine_widget.dart'
    core = root / 'lib' / 'spine_flutter.dart'
    w = widget.read_text(encoding='utf-8')
    c = core.read_text(encoding='utf-8')
    if MARKER in w and MARKER in c:
        print('Tavern Spine compatibility patch already applied.')
        return 0
    for old, new in REPLACEMENTS:
        if w.count(old) != 1:
            print(f'Incompatible spine_widget.dart; hunk not found:\n{old[:80]}', file=sys.stderr)
            return 1
        w = w.replace(old, new)
    if c.count(DRAWABLE[0]) != 1:
        print('Incompatible spine_flutter.dart; SkeletonDrawable.update not found.', file=sys.stderr)
        return 1
    c = c.replace(DRAWABLE[0], DRAWABLE[1])
    widget.write_text(w, encoding='utf-8')
    core.write_text(c, encoding='utf-8')
    print('Tavern Spine compatibility patch applied.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
