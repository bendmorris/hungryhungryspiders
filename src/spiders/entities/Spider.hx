package spiders.entities;

import haxepunk.Entity;
import haxepunk.HXP;

class Spider extends Entity {
    static inline var MIN_SIZE = 100;
    static inline var MAX_SIZE = 100000;
    static inline var WORST_MOVE_SPEED: Int = 24;
    static inline var BEST_MOVE_SPEED: Int = 192;
    static inline var WORST_ROTATE_SPEED: Float = 0.5235987755982988; // 30 degrees in radians
    static inline var BEST_ROTATE_SPEED: Float = 3.141592653589793; // 180 degrees in radians
    static inline var WORST_ANIMATION_SPEED: Float = 0.5;
    static inline var BEST_ANIMATION_SPEED: Float = 2;
    static inline var MIN_SCALE: Float = 0.125;
    static inline var MAX_SCALE: Float = 1;
    static inline var SPLAT_TIME: Float = 0.25;

    public var sp(get, never): SpiderSpine;
    inline function get_sp() return cast graphic;

    public var ratio(get, never): Float;
    inline function get_ratio() {
        return Math.sqrt((size - MIN_SIZE) / (MAX_SIZE - MIN_SIZE));
    }

    public var size(default, set): Float;
    inline function set_size(v: Float) {
        this.size = v;
        var ratio = this.ratio;
        sp.speed = BEST_ANIMATION_SPEED + (WORST_ANIMATION_SPEED - BEST_ANIMATION_SPEED) * ratio;
        sp.scale = this.scale;
        return v;
    }

    public var angle(default, set): Float;
    inline function set_angle(v: Float) {
        this.angle = v;
        sp.angle = v * 180 / Math.PI - 90;
        return v;
    }

    public var scale(get, never): Float;
    inline function get_scale() {
        return MIN_SCALE + (MAX_SCALE - MIN_SCALE) * ratio;
    }

    public var moveSpeed(get, never): Float;
    inline function get_moveSpeed() {
        return BEST_MOVE_SPEED + (WORST_MOVE_SPEED - BEST_MOVE_SPEED) * ratio;
    }

    public var rotateSpeed(get, never): Float;
    inline function get_rotateSpeed() {
        return BEST_ROTATE_SPEED + (WORST_ROTATE_SPEED - BEST_ROTATE_SPEED) * ratio;
    }

    public var syncData: SyncData;
    public var pc: Bool;
    public var moving: Bool = false;

    var splatTimer: Float;
    var splatter: Splatter;

    public function new(syncData: SyncData, splatter: Splatter, pc: Bool) {
        super(new SpiderSpine());
        size = MIN_SIZE;
        this.syncData = syncData;
        this.pc = pc;
        this.splatter = splatter;
    }

    public function setAnimation(name: String, ?loop=true, ?onFinish:Void->Void) {
        sp.setAnimation(name, loop, onFinish);
    }

    override public function update() {
        // gradually adjust state
        if (!pc) moving = false;
        if (Math.abs(syncData.angle - angle) > Math.PI / 16) {
            angle += (syncData.angle - angle) / 2;
            moving = true;
        }
        if (Math.abs(syncData.size - size) > 0.1) {
            size += (syncData.size - size) / 2;
        }
        if (Math.abs(syncData.x * Game.TILE_SIZE - x) > 2) {
            x += (syncData.x * Game.TILE_SIZE - x) / 2;
            moving = true;
        }
        if (Math.abs(syncData.y * Game.TILE_SIZE - y) > 2) {
            y += (syncData.y * Game.TILE_SIZE - y) / 2;
            moving = true;
        }
        // show animation when the position actually changes, not when the server says they're moving
        switch (syncData.state) {
            case SpiderState.Idle, SpiderState.Moving: sp.setAnimation(moving ? "scurry" : "idle", true);
            case SpiderState.Biting: {
                sp.setAnimation("bite", true);
                splatTimer += HXP.elapsed / SPLAT_TIME * Math.random() * 2;
                if (splatTimer >= 1) {
                    --splatTimer;
                    splatter.splat(x, y, Game.TILE_SIZE * scale / 2, 1);
                }
            }
            case SpiderState.Fly: sp.setAnimation("fly");
        }
    }
}
