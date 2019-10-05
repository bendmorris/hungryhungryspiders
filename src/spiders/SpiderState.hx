package spiders;

@:enum abstract SpiderState(Int) from Int to Int {
    var Idle = 0;
    var Moving = 1;
    var Biting = 2;

    var Fly = 66;
}
