package spiders.scenes;

import haxe.io.Bytes;
import haxe.io.BytesData;
import js.html.ArrayBuffer;
import js.html.BinaryType;
import js.html.MessageEvent;
import js.html.WebSocket;
import haxepunk.HXP;
import haxepunk.Scene;
import haxepunk.graphics.tile.Backdrop;
import haxepunk.input.Input;
import haxepunk.input.Key;
import spiders.entities.Spider;
import spiders.graphics.Splatter;

class GameScene extends Scene {
    static inline var UPDATE_THROTTLE = 0.125;

    var mySpider: Spider;
    var ws: WebSocket;

    var spiders: Map<Int, Spider> = new Map();
    var updateThrottle: Float = 0;

    var lastMovingSent: Bool = false;
    var lastRotatingSent: Int = 0;

    var splatter: Splatter;

    static var pingBuffer: Bytes = Bytes.alloc(1);
    override public function begin() {
        ws = new WebSocket("ws://localhost:27278");
        ws.binaryType = BinaryType.ARRAYBUFFER;
        ws.onopen = function() {
            trace("sent");
            var buf = pingBuffer;
            buf.set(0, MessageType.SpawnMe);
            ws.send(buf.getData());
        }

        ws.onmessage = readMessage;

        var backdrop = new Backdrop("assets/graphics/bg.png", true, true);
        backdrop.smooth = true;
        backdrop.pixelSnapping = false;
        addGraphic(backdrop);

        splatter = new Splatter();
        addGraphic(splatter);
    }

    function readMessage(message: MessageEvent) {
        var data: Bytes = Bytes.ofData(message.data);
        var cursor = 0;
        while (cursor < data.length) {
            var messageType = data.get(cursor++);
            switch (messageType) {
                case MessageType.SpawnMe:
                    // TODO: protect against multiple spawns
                    var key = data.getUInt16(cursor); cursor += 2;
                    var syncData = new SyncData(key);
                    mySpider = new Spider(syncData, splatter, true);
                    syncData.x = data.getFloat(cursor); cursor += 4;
                    mySpider.x = syncData.x * Game.TILE_SIZE;
                    syncData.y = data.getFloat(cursor); cursor += 4;
                    mySpider.y = syncData.y * Game.TILE_SIZE;
                    syncData.angle = data.getFloat(cursor); cursor += 4;
                    mySpider.angle = syncData.angle;
                    spiders[key] = mySpider;
                    Key.define("left", [Key.LEFT, Key.A]);
                    Key.define("right", [Key.RIGHT, Key.D]);
                    Key.define("forward", [Key.UP, Key.W]);

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
                        if (!spiders.exists(id)) {
                            var syncData = new SyncData(id);
                            spiders[id] = new Spider(syncData, splatter, false);
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
                        spider.syncData.size = data.getFloat(cursor); cursor += 4;
                        spider.syncData.moving = data.get(cursor) != 0; ++cursor;
                        spider.syncData.rotating = data.get(cursor); ++cursor;
                        spider.syncData.state = data.get(cursor); ++cursor;
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
            }
        }
    }

    function gameUpdate() {
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
    }

    function rotate(dir: Int) {
        var rotateSpeed = mySpider.rotateSpeed;
        var newAngle = mySpider.angle + (rotateSpeed * HXP.elapsed) * dir;
        mySpider.angle = mySpider.syncData.angle = (newAngle % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
        mySpider.syncData.dirty = true;
    }

    function moveForward() {
        var moveSpeed = mySpider.moveSpeed * HXP.elapsed;
        mySpider.x += moveSpeed * Math.cos(mySpider.angle);
        mySpider.syncData.x = mySpider.x / Game.TILE_SIZE;
        mySpider.y -= moveSpeed * Math.sin(mySpider.angle);
        mySpider.syncData.y = mySpider.y / Game.TILE_SIZE;
        mySpider.syncData.dirty = true;
    }
}
