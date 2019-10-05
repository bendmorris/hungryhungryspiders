import haxepunk.Engine;
import haxepunk.HXP;

class Main extends Engine {
    static function main() {
        new Main(1920, 1080, 30, true);
    }

    override public function init() {
        HXP.scene = new spiders.scenes.GameScene();
    }
}
