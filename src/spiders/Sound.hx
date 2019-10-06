package spiders;

import haxepunk.HXP;
import haxepunk.Sfx;

class Sound {
    static inline var FORMAT: String = "ogg";
    static var loaded: Map<String, Sfx> = new Map();

    public static inline function play(sound: String, volume: Float = 1) {
        if (!loaded.exists(sound)) {
            loaded[sound] = new Sfx('assets/sounds/$sound.$FORMAT');
            loaded[sound].type = "sfx";
        }
        loaded[sound].play(volume);
    }
}
