package spiders;

import haxepunk.Sfx;

class Music {
    static inline var FORMAT: String = "ogg";
    static var _music: Map<String, Sfx> = new Map();

    static var playing: Null<String>;
    static var current: Sfx;

    public static function play(music: String) {
        if (current != null && playing == music)
            return;
        if (current != null) {
            current.stop();
            current = null;
        }
        if (!_music.exists(music)) {
            _music[music] = new Sfx('assets/sounds/$music.$FORMAT');
            _music[music].type = "music";
        }
        current = _music[playing = music];
        current.play(1, 0, true);
    }

    public static function stop() {
        if (current != null) {
            current.stop();
            current = null;
            playing = null;
        }
    }
}
