package spiders.graphics;

import haxepunk.HXP;
import spine.SkeletonData;
import spine.animation.AnimationStateData;
import spinepunk.SpinePunk;

class SpiderSpine extends SpinePunk {
    static var _skeletonData: SkeletonData;
    static var _stateData: AnimationStateData;

    public var facingRight(get, set):Bool;
    function get_facingRight() return !skeleton.flipX;
    function set_facingRight(v:Bool)
    {
        if (facingRight != v)
        {
            skeleton.flipX = !v;
            skeleton.setToSetupPose();
        }
        return !v;
    }

    public var currentAnimation: String;

    public function new(isFly: Bool = false)
    {

        if (_skeletonData == null) {
            _skeletonData = SpinePunk.readSkeletonData("spider", "assets/graphics/");
            _stateData = new AnimationStateData(_skeletonData);
            _stateData.defaultMix = 0.25;
        }
        super(_skeletonData, _stateData);

        smooth = true;
        pixelSnapping = false;

        setAnimation(isFly ? "fly" : "idle");
        if (!isFly) {
            state.setAnimationByName(1, "blink", true);
        }
    }

   	public function setAnimation(name: String, ?loop=true, ?onFinish:Void->Void)
    {
        if (!loop || currentAnimation != name)
        {
            var trackEntry = state.setAnimationByName(0, name, loop);
            if (onFinish != null)
            {
                trackEntry.onComplete.add(function (_) onFinish());
            }
            currentAnimation = name;
        }
    }
}
