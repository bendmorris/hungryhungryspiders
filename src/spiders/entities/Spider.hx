package spiders.entities;

import haxepunk.Entity;
import haxepunk.HXP;
import haxepunk.graphics.text.BitmapText;

class Spider extends WrapAroundEntity {
    static inline var MIN_SIZE = 100;
    static inline var MAX_SIZE = 100000;
    static inline var WORST_MOVE_SPEED: Int = 24;
    static inline var BEST_MOVE_SPEED: Int = 256;
    static inline var WORST_ROTATE_SPEED: Float = 0.5235987755982988; // 30 degrees in radians
    static inline var BEST_ROTATE_SPEED: Float = 4.71238898038469; // 180 degrees in radians
    static inline var WORST_ANIMATION_SPEED: Float = 0.5;
    static inline var BEST_ANIMATION_SPEED: Float = 2;
    static inline var MIN_SCALE: Float = 0.125;
    static inline var MAX_SCALE: Float = 1;
    static inline var SPLAT_TIME: Float = 0.25;

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
        nameLabel.scale = this.scale * (pc ? 12 : 10);
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

    var sp: SpiderSpine;
    var nameLabel: BitmapText;

    public function new(arenaWidth: Int, arenaHeight: Int, syncData: SyncData, splatter: Splatter, pc: Bool) {
        super(arenaWidth, arenaHeight, sp = new SpiderSpine());
        this.syncData = syncData;
        this.pc = pc;
        this.splatter = splatter;
        nameLabel = new BitmapText("???", {font: "assets/fonts/octobercrow.72.fnt"});
        addGraphic(nameLabel);
        size = MIN_SIZE;
    }

    public function setAnimation(name: String, ?loop=true, ?onFinish:Void->Void) {
        sp.setAnimation(name, loop, onFinish);
    }

    override public function update() {
        // gradually adjust state
        if (!pc) moving = false;
        angle = syncData.angle;
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

        if (nameLabel != null) {
            if (syncData.state == SpiderState.Fly) {
                // flies don't have names
                nameLabel.visible = false;
            } else {
                nameLabel.text = syncData.name;
                nameLabel.x = -nameLabel.textWidth / 2;
            }
        }
    }
}
