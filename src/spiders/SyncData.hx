package spiders;

class SyncData {
    public var name: String = "???";
    public var key: Int;
    public var x: Float;
    public var y: Float;
    public var angle: Float;
    public var size: Float;
    public var moving: Bool = false;
    public var rotating: Int = 0;
    public var state: SpiderState = SpiderState.Idle;
    public var kills: Int = 0;

    public var dirty: Bool = false;

    public function new(key: Int) {
        this.key = key;
    }
}
