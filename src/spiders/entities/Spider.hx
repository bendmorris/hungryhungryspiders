package spiders.entities;

import haxepunk.Entity;
import haxepunk.HXP;
import haxepunk.graphics.text.BitmapText;
import haxepunk.utils.Color;

class Spider extends WrapAroundEntity {
    static inline var MIN_SIZE = 100;
    static inline var MAX_SIZE = 100000;
    static inline var WORST_MOVE_SPEED: Int = 16;
    static inline var BEST_MOVE_SPEED: Int = 512;
    static inline var WORST_ROTATE_SPEED: Float = 0.3141592653589793; // 18 degrees in radians
    static inline var BEST_ROTATE_SPEED: Float = 4.71238898038469; // 270 degrees in radians
    static inline var WORST_ANIMATION_SPEED: Float = 0.5;
    static inline var BEST_ANIMATION_SPEED: Float = 2;
    static inline var MIN_SCALE: Float = 0.125;
    static inline var MAX_SCALE: Float = 1;
    static inline var SPLAT_TIME: Float = 0.25;
    static inline var MIN_BITE_TIME: Float = 2;
    static inline var PULSE_TIME: Float = 0.5;

    public var ratio(get, never): Float;
    inline function get_ratio() {
        return Math.sqrt((Math.max(MIN_SIZE, size) - MIN_SIZE) / (MAX_SIZE - MIN_SIZE));
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
    var lastState: SpiderState = SpiderState.Idle;
    var biteTime: Float = 0;
    var pulseTime: Float = 0;

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
        if (biteTime > 0) return;
        sp.setAnimation(name, loop, onFinish);
    }

    override public function update() {
        width = height = Std.int(sp.scale * Game.TILE_SIZE);
        originX = originY = Std.int(width / 2);
        // gradually adjust state
        if (!pc) moving = false;
        if (biteTime > 0) {
            biteTime -= HXP.elapsed / MIN_BITE_TIME;
        }
        angle = syncData.angle;
        nameLabel.color = Color.White.lerp(0xff8080, pulseTime);
        if (pulseTime > 0) {
            pulseTime -= HXP.elapsed / PULSE_TIME;
            if (pulseTime < 0) pulseTime = 0;
        }
        if (Math.abs(syncData.size - size) > 1) {
            if (syncData.size > size) {
                pulseTime = 1;
            }
            size += (syncData.size - size) / 2;
        }
        var dx = Math.abs(syncData.x * Game.TILE_SIZE - x),
            dy = Math.abs(syncData.y * Game.TILE_SIZE - y);
        if (dx > 2) {
            if (dx < 128) x += (syncData.x * Game.TILE_SIZE - x) / 4;
            else x = syncData.x * Game.TILE_SIZE;
            moving = true;
        }
        if (dy > 2) {
            if (dy < 128) y += (syncData.y * Game.TILE_SIZE - y) / 4;
            else y = syncData.y * Game.TILE_SIZE;
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
                if (lastState != SpiderState.Biting) {
                    var maxDist = HXP.width * 2;
                    var d = (Math.sqrt(Math.pow(x - HXP.scene.camera.x, 2) + Math.pow(y - HXP.scene.camera.y, 2)));
                    if (d < maxDist) {
                        Sound.play("splash", (maxDist - d) / maxDist);
                    }
                }
                biteTime = 1;
            }
            case SpiderState.Fly: sp.setAnimation("fly");
        }
        lastState = syncData.state;

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
