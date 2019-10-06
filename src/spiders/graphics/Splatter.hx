package spiders.graphics;

import haxepunk.HXP;
import haxepunk.graphics.emitter.Emitter;
import haxepunk.utils.BlendMode;
import haxepunk.utils.Ease;

class Splatter extends Emitter {
    public function new() {
        super("assets/graphics/splat.png", 128, 128);
        smooth = true;
        for (i in 1 ... 5) {
            var s = "splat" + i;
            newType(s, [i - 1], BlendMode.Subtract);
            setMotion(s, 0, 0, 10, 360, 0, 5);
            setRotation(s, 0, 0, 360, 0);
            setAlpha(s, 1, 0, Ease.quadOut);
        }
    }

    public function splat(x: Float, y: Float, radius: Float, n: Int) {
        for (i in 0 ... n) {
            emitInCircle("splat" + Math.floor(1 + Math.random() * 3), x, y, radius);
        }
    }

    public function offsetSplats(ox: Int, oy: Int) {
        var p = _particle;
        while (p != null) {
            p._x += ox;
            p._y += oy;
            p = p._next;
        }
    }
}
