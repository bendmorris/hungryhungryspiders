package spiders;

@:enum abstract MessageType(UInt) from UInt to UInt {
    var UpdateData = 101;
    var Moving = 102;
    var NotMoving = 103;
    var RotatingLeft = 104;
    var RotatingRight = 105;
    var NotRotating = 106;
    var NameRequest = 107;
    var SpawnMe = 123;
    var Ping = 201;
    var YouDied = 202;
}
