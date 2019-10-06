package spiders.scenes;

import haxe.io.Bytes;
import haxe.io.BytesData;
import js.html.ArrayBuffer;
import js.html.BinaryType;
import js.html.MessageEvent;
import js.html.WebSocket;
import haxepunk.Camera;
import haxepunk.HXP;
import haxepunk.Scene;
import haxepunk.graphics.tile.Backdrop;
import haxepunk.graphics.text.BitmapText;
import haxepunk.input.Input;
import haxepunk.input.Key;
import spiders.entities.Spider;
import spiders.graphics.Splatter;

class GameScene extends Scene {
    static inline var UPDATE_THROTTLE = 0.1;
    static inline var YOU_DIED_TIME = 3.5;
    static inline var HURT_PULSE_TIME = 0.75;

    static var _initialized: Bool = initGame();
    static function initGame() {
        // stuff to do only once
        Key.define("left", [Key.LEFT, Key.A]);
        Key.define("right", [Key.RIGHT, Key.D]);
        Key.define("forward", [Key.UP, Key.W]);
        Key.define("submit", [Key.ENTER]);
        BitmapText.defineFormatTag("red", {color: 0xc00000});
        BitmapText.defineFormatTag("small", {scale: 0.5});
        return true;
    }

    var mySpider: Spider;
    var ws: WebSocket;
    var arenaSize: Int;

    var spiders: Map<Int, Spider> = new Map();
    var updateThrottle: Float = 0;

    var lastMovingSent: Bool = false;
    var lastRotatingSent: Int = 0;

    var backdrop: Backdrop;
    var splatter: Splatter;
    var scoreLabel: BitmapText;
    var leaderLabel: BitmapText;
    var youDiedLabel: BitmapText;

    var dead: Bool = false;
    var hurtCount: Int = 0;

    var leader: Int = 0;
    var leaderScore: Int = 0;

    static var pingBuffer: Bytes = Bytes.alloc(1);
    static var nameReqBuffer: Bytes = Bytes.alloc(3);
    override public function begin() {
        Music.stop();
        backdrop = new Backdrop("assets/graphics/bg.png", true, true);
        backdrop.smooth = true;
        backdrop.pixelSnapping = false;
        addGraphic(backdrop);

        splatter = new Splatter();
        addGraphic(splatter);

        var uiCamera = new Camera();

        scoreLabel = new BitmapText("Connecting...", {font: "assets/fonts/octobercrow.72.fnt", size: 72});
        scoreLabel.x = scoreLabel.y = 16;
        addGraphic(scoreLabel).camera = uiCamera;

        leaderLabel = new BitmapText(" ", {font: "assets/fonts/octobercrow.72.fnt", size: 72});
        leaderLabel.x = leaderLabel.y = 16;
        addGraphic(leaderLabel).camera = uiCamera;

        youDiedLabel = new BitmapText("<center><red>YOU DIED...</red>\n\n<small>Press <red>ENTER</red> to try again</small></center>", {font: "assets/fonts/octobercrow.72.fnt", size: 96});
        youDiedLabel.visible = false;
        var e = addGraphic(youDiedLabel);
        e.layer = -1;
        e.camera = uiCamera;
        bgColor = 0x800000;

        tryConnect();
    }

    function tryConnect() {
        ws = new WebSocket("ws://spiders.tacobell.pizza:27278");
        ws.binaryType = BinaryType.ARRAYBUFFER;
        ws.onopen = function() {
            var buf = pingBuffer;
            buf.set(0, MessageType.SpawnMe);
            ws.send(buf.getData());
        }

        ws.onmessage = readMessage;
        ws.onclose = youDied.bind(false);
    }

    function readMessage(message: MessageEvent) {
        var data: Bytes = Bytes.ofData(message.data);
        var cursor = 0;
        while (cursor < data.length) {
            var messageType = data.get(cursor++);
            switch (messageType) {
                case MessageType.SpawnMe:
                    Sound.play("new");
                    // TODO: protect against multiple spawns
                    arenaSize = data.getUInt16(cursor); cursor += 2;
                    var key = data.getUInt16(cursor); cursor += 2;
                    var syncData = new SyncData(key);
                    mySpider = new Spider(arenaSize * Game.TILE_SIZE, arenaSize * Game.TILE_SIZE, syncData, splatter, true);
                    syncData.x = data.getFloat(cursor); cursor += 4;
                    mySpider.x = syncData.x * Game.TILE_SIZE;
                    syncData.y = data.getFloat(cursor); cursor += 4;
                    mySpider.y = syncData.y * Game.TILE_SIZE;
                    trace('spawned at ${syncData.x} ${syncData.y}');
                    syncData.angle = data.getFloat(cursor); cursor += 4;
                    mySpider.angle = syncData.angle;
                    var nameLength = data.get(cursor); ++cursor;
                    syncData.name = data.getString(cursor, nameLength); cursor += nameLength;
                    spiders[key] = mySpider;

                    add(mySpider);

                    preUpdate.bind(gameUpdate);

                    var buf = pingBuffer;
                    buf.set(0, MessageType.Ping);
                    ws.send(buf.getData());

                case MessageType.UpdateData:
                    var dirtyCount = data.getUInt16(cursor); cursor += 2;
                    for (i in 0 ... dirtyCount) {
                        var id = data.getUInt16(cursor); cursor += 2;
                        var isNew = false;
                        var isMe = id == mySpider.syncData.key;
                        if (!spiders.exists(id)) {
                            var syncData = new SyncData(id);
                            spiders[id] = new Spider(arenaSize * Game.TILE_SIZE, arenaSize * Game.TILE_SIZE, syncData, splatter, false);
                            add(spiders[id]);
                            isNew = true;
                        }
                        var spider = spiders[id];
                        if (!spider.pc) {
                            spider.syncData.x = data.getFloat(cursor); cursor += 4;
                            spider.syncData.y = data.getFloat(cursor); cursor += 4;
                            if (isNew) {
                                spider.x = spider.syncData.x * Game.TILE_SIZE;
                                spider.y = spider.syncData.y * Game.TILE_SIZE;
                            }
                        } else {
                            cursor += 8;
                        }
                        spider.syncData.angle = data.getFloat(cursor); cursor += 4;
                        var originalSize = spider.syncData.size;
                        spider.syncData.size = data.getFloat(cursor); cursor += 4;
                        if (isMe && spider.syncData.size < originalSize) {
                            getHurt();
                        }
                        spider.syncData.moving = data.get(cursor) != 0; ++cursor;
                        spider.syncData.rotating = data.get(cursor); ++cursor;
                        spider.syncData.state = data.get(cursor); ++cursor;
                        spider.syncData.kills = data.getUInt16(cursor); cursor += 2;
                        if (spider.syncData.kills > leaderScore) {
                            leader = id;
                            leaderScore = spider.syncData.kills;
                        }
                        if (isNew && spider.syncData.state != SpiderState.Fly) {
                            // request the new spider's name
                            var buf = nameReqBuffer;
                            buf.set(0, MessageType.NameRequest);
                            buf.setUInt16(1, id);
                            ws.send(buf.getData());
                        }
                    }
                    var removedCount = data.getUInt16(cursor); cursor += 2;
                    for (i in 0 ... removedCount) {
                        var id = data.getUInt16(cursor); cursor += 2;
                        if (id == mySpider.syncData.key) {
                            // TODO: oh no I was removed
                        } else if (spiders.exists(id)) {
                            var spider = spiders[id];
                            splatter.splat(spider.x, spider.y, spider.scale * Game.TILE_SIZE, Math.floor(2 + Math.random() * spider.scale * 8));
                            remove(spider);
                            spiders.remove(id);
                        }
                    }

                case MessageType.Ping:
                    var buf = pingBuffer;
                    buf.set(0, MessageType.Ping);
                    ws.send(buf.getData());

                case MessageType.NameRequest:
                    var key = data.getUInt16(cursor); cursor += 2;
                    var length = data.get(cursor); ++cursor;
                    var name = data.getString(cursor, length); cursor += length;
                    var spider = this.spiders[key];
                    if (spider != null) {
                        spider.syncData.name = name;
                    }

                case MessageType.YouDied:
                    // too bad
                    youDied(true);

                default:
                    throw "invalid message type: " + messageType;
            }
        }
    }

    function getHurt() {
        backdrop.alpha = 0.25;
        hurtCount = 2;
    }

    function youDied(realDeath: Bool) {
        if (!dead) {
            Music.play("death");
            Sound.play("dead");
            backdrop.alpha = 1;
            if (!realDeath) {
                youDiedLabel.text = "<center><red>" + (mySpider != null ? "CONNECTION DIED" : "COULDN'T CONNECT") + "...</red>\n\n<small>Press <red>ENTER</red> to reconnect</small></center>";
            }
            youDiedLabel.x = (HXP.width - youDiedLabel.textWidth) / 2;
            youDiedLabel.y = (HXP.height - youDiedLabel.textHeight) / 2;
            youDiedLabel.visible = true;
            youDiedLabel.alpha = 0;
            if (mySpider != null) {
                mySpider.syncData.size = 0;
            }
            updateScoreLabel();
            dead = true;
            if (ws != null && ws.readyState == 1) {
                ws.close();
            }

            onInputPressed.submit.bind(function() {
                // workaround to avoid disposing assets
                HXP.scene = new GameScene();
            });
        }
    }

    function gameUpdate() {
        if (dead) {
            youDiedLabel.alpha += HXP.elapsed / YOU_DIED_TIME;
            if (youDiedLabel.alpha > 1) youDiedLabel.alpha = 1;
            backdrop.alpha -= HXP.elapsed / YOU_DIED_TIME;
            if (backdrop.alpha < 0.25) backdrop.alpha = 0.25;
            return;
        }
        if (backdrop.alpha < 1) {
            backdrop.alpha += HXP.elapsed / HURT_PULSE_TIME / 0.75;
            if (backdrop.alpha >= 1) {
                backdrop.alpha = 1;
                if (hurtCount > 0) {
                    --hurtCount;
                    backdrop.alpha = 0.25;
                }
            }
        }
        var left = Input.check("left");
        var right = Input.check("right");
        mySpider.moving = false;
        if (left != right) {
            rotate(left ? 1 : -1);
            mySpider.moving = true;
        }
        if (Input.check("forward")) {
            moveForward();
            mySpider.moving = true;
        }
        camera.scale = 0.25 / mySpider.scale;
        camera.setTo(mySpider.x, mySpider.y, 0.5, 0.5);

        if (updateThrottle > 0) {
            updateThrottle -= HXP.elapsed;
        }

        if (mySpider.syncData.dirty && updateThrottle <= 0) {
            var buf = Bytes.alloc(15 + (mySpider.syncData.moving != lastMovingSent ? 1 : 0) + (mySpider.syncData.rotating != lastRotatingSent ? 1 : 0));
            var cursor = 0;
            buf.set(cursor, MessageType.UpdateData); ++cursor;
            buf.setUInt16(cursor, mySpider.syncData.key); cursor += 2;
            buf.setFloat(cursor, mySpider.syncData.x); cursor += 4;
            buf.setFloat(cursor, mySpider.syncData.y); cursor += 4;
            buf.setFloat(cursor, mySpider.syncData.angle); cursor += 4;
            if (mySpider.syncData.moving != lastMovingSent) {
                lastMovingSent = mySpider.syncData.moving;
                buf.set(cursor, lastMovingSent ? MessageType.Moving : MessageType.NotMoving);
            }
            if (mySpider.syncData.rotating != lastRotatingSent) {
                lastRotatingSent = mySpider.syncData.rotating;
                buf.set(cursor, lastRotatingSent == 0 ? MessageType.NotRotating : (lastRotatingSent > 0 ? MessageType.RotatingLeft : MessageType.RotatingRight));
            }
            ws.send(buf.getData());
            mySpider.syncData.dirty = false;
            updateThrottle = UPDATE_THROTTLE;
        }

        updateScoreLabel();

        if (leaderScore > 0 && spiders[leader] != null) {
            var leader = spiders[leader];
            leaderLabel.visible = true;
            leaderLabel.text = '<right>Leader:\n<red>${leader.syncData.name}</red>  ${leaderScore}</right>';
            leaderLabel.x = HXP.width - 16 - leaderLabel.textWidth;
            leaderLabel.y = 16;
        } else {
            leaderLabel.visible = false;
            leaderScore = 0;
        }
    }

    function updateScoreLabel() {
        if (mySpider != null) {
            scoreLabel.text = '<red>Blood: ${Math.floor(mySpider.syncData.size)}</red>\nSouls: ${mySpider.syncData.kills}';
        } else {
            scoreLabel.text = '<red>Blood: 0</red>\nSouls: 0';
        }
    }

    function rotate(dir: Int) {
        var rotateSpeed = mySpider.rotateSpeed;
        var newAngle = mySpider.angle + (rotateSpeed * HXP.elapsed) * dir;
        mySpider.angle = mySpider.syncData.angle = (newAngle % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
        mySpider.syncData.dirty = true;
    }

    function moveForward() {
        var arenaSize = arenaSize * Game.TILE_SIZE;
        var moveSpeed = mySpider.moveSpeed * HXP.elapsed;
        var offsetX = 0, offsetY = 0;
        mySpider.x += moveSpeed * Math.cos(mySpider.angle);
        if (mySpider.x < 0) offsetX += arenaSize;
        if (mySpider.x > arenaSize) offsetX -= arenaSize;
        mySpider.y -= moveSpeed * Math.sin(mySpider.angle);
        if (mySpider.y < 0) offsetY += arenaSize;
        if (mySpider.y > arenaSize) offsetY -= arenaSize;

        if (offsetX != 0 || offsetY != 0) {
            mySpider.x += offsetX;
            mySpider.y += offsetY;
            splatter.offsetSplats(offsetX, offsetY);
        }
        mySpider.syncData.x = mySpider.x / Game.TILE_SIZE;
        mySpider.syncData.y = mySpider.y / Game.TILE_SIZE;
        mySpider.syncData.dirty = true;
    }
}
