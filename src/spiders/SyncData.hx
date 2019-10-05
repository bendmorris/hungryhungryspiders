package spiders;

class SyncData {
    public var key: Int;
    public var x: Float;
    public var y: Float;
    public var angle: Float;
    public var size: Float;
    public var moving: Bool;
    public var rotating: Int;
    public var state: SpiderState;

    public var dirty: Bool = false;

    public function new(key: Int) {
        this.key = key;
    }
}
