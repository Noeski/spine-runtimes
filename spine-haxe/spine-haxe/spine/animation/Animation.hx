package spine.animation;

import openfl.errors.ArgumentError;
import openfl.utils.Dictionary;
import openfl.Vector;
import spine.Event;
import spine.Skeleton;

class Animation {
	private var _name:String;
	private var _timelines:Vector<Timeline>;
	private var _timelineIds:Dictionary<String, Bool> = new Dictionary<String, Bool>();

	public var duration:Float = 0;

	public function new(name:String, timelines:Vector<Timeline>, duration:Float) {
		if (name == null)
			throw new ArgumentError("name cannot be null.");
		if (timelines == null)
			throw new ArgumentError("timelines cannot be null.");
		_name = name;
		_timelines = timelines;
		for (timeline in timelines) {
			var ids:Vector<String> = timeline.propertyIds;
			for (id in ids) {
				_timelineIds[id] = true;
			}
		}
		this.duration = duration;
	}

	public function hasTimeline(ids:Vector<String>):Bool {
		for (id in ids) {
			if (_timelineIds[id])
				return true;
		}
		return false;
	}

	/** Poses the skeleton at the specified time for this animation. */
	public function apply(skeleton:Skeleton, lastTime:Float, time:Float, loop:Bool, events:Vector<Event>, alpha:Float, blend:MixBlend,
			direction:MixDirection):Void {
		if (skeleton == null)
			throw new ArgumentError("skeleton cannot be null.");

		if (loop && duration != 0) {
			time %= duration;
			if (lastTime > 0)
				lastTime %= duration;
		}

		for (timeline in timelines) {
			timeline.apply(skeleton, lastTime, time, events, alpha, blend, direction);
		}
	}

	public var name(get, never):String;

	private function get_name():String {
		return _name;
	}

	public function toString():String {
		return _name;
	}

	public var timelines(get, never):Vector<Timeline>;

	private function get_timelines():Vector<Timeline> {
		return _timelines;
	}
}
