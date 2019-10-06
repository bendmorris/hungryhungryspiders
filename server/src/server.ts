import * as express from 'express';
import * as http from 'http';
import * as WebSocket from 'ws';
import * as fs from 'fs';

const app = express();

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const names = fs.readFileSync('names.txt').toString().split('\n');

const arenaSize = 8;
const geoCacheCellSize = 0.5;
const geoCacheSize = arenaSize / geoCacheCellSize;
const eatTime = 2.5;
const maxFlies = 15;
const flySpawnTime = 2.5;
const deathBuffer = 0.001;

const PING_TIMEOUT = 15000;
const MIN_SIZE = 100;
const MAX_SIZE = 100000;
const WORST_MOVE_SPEED: number = 24;
const BEST_MOVE_SPEED: number = 256;
const WORST_ROTATE_SPEED: number = 0.5235987755982988; // 30 degrees in radians
const BEST_ROTATE_SPEED: number = 4.71238898038469; // 270 degrees in radians
const MIN_SCALE: number = 0.125;
const MAX_SCALE: number = 1;

enum SpiderState {
    Idle = 0,
    Moving = 1,
    Biting = 2,

    Fly = 66,
};

enum MessageType {
    UpdateData = 101,
    Moving = 102,
    NotMoving = 103,
    RotatingLeft = 104,
    RotatingRight = 105,
    NotRotating = 106,
    NameRequest = 107,
    SpawnMe = 123,

    Ping = 201,
    YouDied = 202,
};

function mod(v: number, n: number): number {
    return (v % n + n) % n;
}

function getCacheCell(x: number, y: number): number {
    return Math.floor(y * geoCacheSize) + Math.floor(x / geoCacheCellSize);
}

function subtractAngle(a: number, b: number): number {
    const diff = mod(a - b, Math.PI * 2);
    return diff > Math.PI ? Math.PI * 2 - diff : diff;
}

class Spider {
    name: string;
    id: number;
    x: number;
    y: number;
    angle: number;
    size: number = MIN_SIZE;
    state: SpiderState = SpiderState.Idle;
    moving: boolean = false;
    rotating: number = 0;
    currentGeoCacheCell: number = -1;

    ws?: PlayerConnection;
    dirty: boolean = true;
    lastState: SpiderState = SpiderState.Idle;
    health: number = 1;
    kills: number = 0;

    constructor(world: World, ws?: PlayerConnection) {
        let id;
        do {
            id = Math.floor(Math.random() * 65535);
        } while (world.spidersByKey.has(id));
        this.id = id;
        this.name = names[Math.floor(names.length * Math.random())];
        if (ws) {
            this.ws = ws;
        } else {
            this.state = SpiderState.Fly;
        }
        this.x = Math.random() * arenaSize;
        this.y = Math.random() * arenaSize;
        this.angle = Math.random() * Math.PI * 2;
    }

    get isFly() {
        return this.state === SpiderState.Fly;
    }

    get ratio() {
        return Math.sqrt((this.size - MIN_SIZE) / (MAX_SIZE - MIN_SIZE));
    }

    get radius() {
        return (MIN_SCALE + (MAX_SCALE - MIN_SCALE) * this.ratio) * 0.75;
    }

    get moveSpeed() {
        return BEST_MOVE_SPEED + (WORST_MOVE_SPEED - BEST_MOVE_SPEED) * this.ratio;
    }

    get rotateSpeed() {
        return BEST_ROTATE_SPEED + (WORST_ROTATE_SPEED - BEST_ROTATE_SPEED) * this.ratio;
    }

    get geoCacheCell() {
        return getCacheCell(this.x, this.y);
    }

    public isBehind(other: Spider) {
        return Math.abs(this.angle - other.angle) > 90;
    }

    public update(time: number) {
        if (this.health <= 0) {
            return;
        }
        this.state = SpiderState.Idle;
        if (this.rotating != 0) {
            const rotateSpeed = this.rotateSpeed;
            this.angle = mod(this.angle - (rotateSpeed * time) * this.rotating, 360);
            this.dirty = true;
            this.state = SpiderState.Moving;
        }
        if (this.moving) {
            var moveSpeed = this.moveSpeed * time;
            var radians = (this.angle) * Math.PI / 180;
            this.x -= moveSpeed * Math.sin(radians);
            this.x = mod(this.x, arenaSize);
            this.y -= moveSpeed * Math.cos(radians);
            this.y = mod(this.y, arenaSize);
            this.dirty = true;
            this.state = SpiderState.Moving;
        }
        return true;
    }

    public bite(other: Spider, time: number) {
        if (this.health <= 0 || other.health <= 0) return;
        this.state = SpiderState.Biting;
        let eat = Math.max(Math.min(Math.min(this.size, other.size) * time / eatTime, other.size - MIN_SIZE), 0);
        other.size -= eat;
        if (other.size <= MIN_SIZE) {
            other.health -= time / deathBuffer;
            if (other.health <= 0) {
                eat += MIN_SIZE;
                if (!other.isFly) this.kills += Math.max(1, other.kills);
            }
            other.size = MIN_SIZE;
        }
        if (eat > 0) {
            this.size += eat;
            this.health += time / deathBuffer;
            if (this.health > 1) this.health = 1;
            if (this.size > MAX_SIZE) this.size = MAX_SIZE;
            this.dirty = other.dirty = true;
        }
    }
}

interface PlayerConnection extends WebSocket {
    _spider: Spider;
    _playerKey: number;
    _lastPing: number;
}

const cellOffsets = [-geoCacheSize - 1, -geoCacheSize, -geoCacheSize + 1, -1, 0, 1, geoCacheSize - 1, geoCacheSize, geoCacheSize + 1];

class World {
    public spiders: Array<Spider> = [];
    public spidersByKey: Map<number, Spider> = new Map();
    public geoCache: Array<Array<Spider>> = [];
    public removed: Array<number> = [];

    _flySpawnTime: number = 0;
    _flyCount: number = 0;

    constructor() {
        const size = geoCacheSize * geoCacheSize;
        for (let i = 0; i < size; ++i) {
            this.geoCache[i] = [];
        }
    }

    public addSpider(conn: PlayerConnection): Spider {
        const spider = new Spider(this, conn);
        this.spiders.push(spider);
        this.spidersByKey.set(spider.id, spider);
        return spider;
    }

    public addFly(): void {
        const fly = new Spider(this);
        this.spiders.push(fly);
        this.spidersByKey.set(fly.id, fly);
    }

    public removeSpider(spider: Spider, alreadyRemoved: boolean = false) {
        if (!alreadyRemoved) {
            const index = this.spiders.indexOf(spider);
            if (index !== -1) {
                this.spiders.splice(index, 1);
                this.removed.push(spider.id);
            }
        }
        this.spidersByKey.delete(spider.id);
        const geoCacheCell = this.geoCache[spider.currentGeoCacheCell];
        if (geoCacheCell) {
            const geoIndex = geoCacheCell.indexOf(spider);
            if (geoIndex !== -1) {
                geoCacheCell.splice(geoIndex, 1);
            }
        }
        if (spider.isFly) {
            --this._flyCount;
        }
    }

    public update(time: number): void {
        // spawn flies
        if (this._flyCount < maxFlies) {
            this._flySpawnTime -= time;
            if (this._flySpawnTime <= 0) {
                this._flySpawnTime += flySpawnTime;
                ++this._flyCount;
                this.addFly();
            }
        }

        // check for ping timeouts or deaths
        const now = Date.now();
        let players = 0;
        for (let i = this.spiders.length - 1; i > -1; --i) {
            const spider = this.spiders[i];
            if (!spider.isFly) ++players;
            if (spider.health <= 0) {
                // died
                if (spider.ws) {
                    let writeCursor = 0;
                    const write = new Buffer(1);
                    write.writeUInt8(MessageType.YouDied, writeCursor); ++writeCursor;
                    spider.ws.send(write);
                }
                this.spiders.splice(i, 1);
                this.removed.push(spider.id);
                this.removeSpider(spider, true);
            } else if (spider.ws && now - spider.ws._lastPing > PING_TIMEOUT) {
                console.log(`[${spider.id.toString(16)}]: ping timeout`);
                spider.ws.close();
                this.spiders.splice(i, 1);
                this.removed.push(spider.id);
                this.removeSpider(spider, true);
            }
        }
        // short circuit if server is full of flies
        if (!players) return;
        // update
        for (const spider of this.spiders) {
            if (!spider.isFly) spider.update(time);
            // update geocache
            const geoCacheCell = spider.geoCacheCell;
            if (spider.currentGeoCacheCell !== geoCacheCell) {
                const geoCache = this.geoCache[spider.currentGeoCacheCell];
                if (geoCache) {
                    const index = geoCache.indexOf(spider);
                    if (index) {
                        geoCache.splice(index, 1);
                    }
                }
                try {
                    this.geoCache[geoCacheCell].push(spider);
                    spider.currentGeoCacheCell = geoCacheCell;
                } catch (e) {
                    console.error(`failed to add to geocache: (${spider.x}, ${spider.y}) = cell ${geoCacheCell}`)
                }
            }
        }
        // check for collisions
        for (const spider of this.spiders) {
            if (spider.isFly) continue;
            const currentCell = spider.currentGeoCacheCell;
            for (const offset of cellOffsets) {
                const cell = this.geoCache[currentCell + offset];
                if (cell && cell.length) {
                    for (const otherSpider of cell) {
                        if (spider == otherSpider) continue;
                        const distance = Math.sqrt(Math.pow(spider.x - otherSpider.x, 2) + Math.pow(spider.y - otherSpider.y, 2));
                        if (distance <= spider.radius + otherSpider.radius) {
                            const angleBetween = mod(Math.atan2(spider.y - otherSpider.y, otherSpider.x - spider.x), Math.PI * 2);
                            if (subtractAngle(angleBetween, spider.angle) < Math.PI / 3) {
                                // spider is facing otherSpider
                                if (otherSpider.isFly || spider.size > otherSpider.size) {
                                    // spider is bigger, so this is good enough
                                    spider.bite(otherSpider, time);
                                } else if (subtractAngle(angleBetween, otherSpider.angle) < Math.PI / 2) {
                                    const angleDiff = subtractAngle(spider.angle, otherSpider.angle);
                                    const vectorDiff = subtractAngle(angleBetween, otherSpider.angle);
                                    if (vectorDiff < Math.PI / 2 && angleDiff < Math.PI / 3) {
                                        // otherSpider is facing away
                                        spider.bite(otherSpider, time);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (spider.state !== spider.lastState) {
                spider.dirty = true;
                spider.lastState = spider.state;
            }
        }

        // send updates
        let updateBuffer = this.makeUpdate(true);

        if (updateBuffer) {
            console.log(`sending update of size ${updateBuffer.length}`);
            for (const spider of this.spiders) {
                if (spider.ws) spider.ws.send(updateBuffer);
            }
        }
    }

    public makeUpdate(onlyDirty: boolean): (Buffer | undefined) {
        let dirtyCount = 0;
        let removedCount = 0;
        for (const spider of this.spiders) {
            if (!onlyDirty || spider.dirty) {
                ++dirtyCount;
            }
        }
        if (onlyDirty) {
            removedCount = this.removed.length;
        }
        if (dirtyCount > 0) {
            const updateBuffer = new Buffer(3 + 23 * dirtyCount + 2 * (removedCount + 1));
            let updateCursor = 0;
            updateBuffer.writeUInt8(MessageType.UpdateData, updateCursor); ++updateCursor;
            updateBuffer.writeUInt16LE(dirtyCount, updateCursor); updateCursor += 2;
            for (const spider of this.spiders) {
                if (!onlyDirty || spider.dirty) {
                    updateBuffer.writeUInt16LE(spider.id, updateCursor); updateCursor += 2;
                    updateBuffer.writeFloatLE(spider.x, updateCursor); updateCursor += 4;
                    updateBuffer.writeFloatLE(spider.y, updateCursor); updateCursor += 4;
                    updateBuffer.writeFloatLE(spider.angle, updateCursor); updateCursor += 4;
                    updateBuffer.writeFloatLE(spider.size, updateCursor); updateCursor += 4;
                    updateBuffer.writeUInt8(spider.moving ? 1 : 0, updateCursor); ++updateCursor;
                    updateBuffer.writeInt8(spider.rotating, updateCursor); ++updateCursor;
                    updateBuffer.writeUInt8(spider.state, updateCursor); ++updateCursor;
                    updateBuffer.writeUInt16LE(spider.kills, updateCursor); updateCursor += 2;
                    if (onlyDirty) {
                        spider.dirty = false;
                    }
                }
            }
            updateBuffer.writeUInt16LE(removedCount, updateCursor); updateCursor += 2;
            if (onlyDirty) {
                for (const id of this.removed) {
                    updateBuffer.writeUInt16LE(id, updateCursor); updateCursor += 2;
                }
                this.removed.length = 0;
            }
            return updateBuffer;
        }
        return undefined;
    }
}

const world = new World();

wss.on('connection', (ws: WebSocket) => {
    const conn: PlayerConnection = <any>ws;
    function sendPing() {
        const write = new Buffer(1);
        write.writeUInt8(MessageType.Ping, 0);
        ws.send(write);
    }
    ws.on('message', (message: Buffer) => {
        conn._lastPing = Date.now();
        let cursor = 0;
        while (cursor < message.length) {
            var messageType: number = message.readUInt8(cursor++);
            switch (messageType) {
                case MessageType.SpawnMe: {
                    const spider = conn._spider = world.addSpider(conn);
                    const key = conn._playerKey = spider.id;
                    console.log(`[${key.toString(16)}]: spawning`);
                    let writeCursor = 0;
                    const write = new Buffer(18 + spider.name.length);
                    write.writeUInt8(MessageType.SpawnMe, writeCursor); writeCursor++;
                    write.writeUInt16LE(arenaSize, writeCursor); writeCursor += 2;
                    write.writeUInt16LE(key, writeCursor); writeCursor += 2;
                    write.writeFloatLE(spider.x, writeCursor); writeCursor += 4;
                    write.writeFloatLE(spider.y, writeCursor); writeCursor += 4;
                    write.writeFloatLE(spider.angle, writeCursor); writeCursor += 4;
                    write.writeUInt8(spider.name.length, writeCursor); writeCursor++;
                    write.write(spider.name, writeCursor, 'ascii'); writeCursor += spider.name.length;
                    ws.send(write);
                    const updateBuffer = world.makeUpdate(false);
                    if (updateBuffer) {
                        ws.send(updateBuffer);
                    }
                    break;
                }
                case MessageType.UpdateData: {
                    console.log(`[${conn._playerKey.toString(16)}]: update`);
                    const key = message.readUInt16LE(cursor); cursor += 2;
                    if (key === conn._playerKey) {
                        const spider = conn._spider;
                        spider.x = mod(message.readFloatLE(cursor), arenaSize); cursor += 4;
                        spider.y = mod(message.readFloatLE(cursor), arenaSize); cursor += 4;
                        spider.angle = message.readFloatLE(cursor); cursor += 4;
                        spider.dirty = true;
                    } else {
                        // invalid player key
                        console.error(`invalid: ${key}`);
                        return;
                    }
                    break;
                }
                case MessageType.Moving: case MessageType.NotMoving: {
                    console.log(`[${conn._playerKey.toString(16)}]: move update`);
                    const key = message.readUInt16LE(cursor); cursor += 2;
                    if (key === conn._playerKey) {
                        const spider = conn._spider;
                        spider.moving = messageType === MessageType.Moving;
                        spider.dirty = true;
                    } else {
                        // invalid player key
                        console.error(`invalid: ${key}`);
                        return;
                    }
                    break;
                }
                case MessageType.RotatingLeft: case MessageType.RotatingRight: case MessageType.NotRotating: {
                    console.log(`[${conn._playerKey.toString(16)}]: rotate update`);
                    const key = message.readUInt16LE(cursor); cursor += 2;
                    if (key === conn._playerKey) {
                        const spider = conn._spider;
                        spider.rotating = messageType === MessageType.NotRotating ? 0 : (messageType === MessageType.RotatingLeft ? 1 : -1);
                        spider.dirty = true;
                    } else {
                        // invalid player key
                        console.error(`invalid: ${key}`);
                        return;
                    }
                    break;
                }
                case MessageType.Ping: {
                    console.log(`[${conn._playerKey.toString(16)}]: ping`);
                    setTimeout(sendPing, 5000);
                    break;
                }
                case MessageType.NameRequest: {
                    const key = message.readUInt16LE(cursor); cursor += 2;
                    const spider = world.spidersByKey.get(key);
                    if (spider) {
                        let writeCursor = 0;
                        const write = new Buffer(4 + spider.name.length);
                        write.writeUInt8(MessageType.NameRequest, writeCursor); writeCursor++;
                        write.writeUInt16LE(key, writeCursor); writeCursor += 2;
                        write.writeUInt8(spider.name.length, writeCursor); writeCursor++;
                        write.write(spider.name, writeCursor, 'ascii'); writeCursor += spider.name.length;
                        ws.send(write);
                    } else {
                        console.error(`unknown spider's name requested [${key.toString(16)}]`);
                    }
                    break;
                }
                default: {
                    console.error(`[${conn._playerKey.toString(16)}]: invalid message type: ${messageType.toString(16)}`);
                    // invalid message type
                    return;
                }
            }
        }
    });
    ws.on('close', () => {
        console.log('close');
        world.removeSpider(conn._spider);
    });
});

let lastUpdate = Date.now();
setInterval(() => {
    const current = Date.now();
    world.update((current - lastUpdate) / 1000);
    lastUpdate = current;
}, 125);

const port = process.env.PORT || 27278;

server.listen(port, () => {
    console.log(`Server started on port ${port}`);
});
