package spine.animation;

import starling.utils.Max;
import openfl.errors.ArgumentError;
import openfl.utils.Dictionary;
import openfl.Vector;
import spine.animation.Listeners.EventListeners;
import spine.Event;
import spine.Pool;
import spine.Skeleton;

class AnimationState {
	public static inline var SUBSEQUENT:Int = 0;
	public static inline var FIRST:Int = 1;
	public static inline var HOLD_SUBSEQUENT:Int = 2;
	public static inline var HOLD_FIRST:Int = 3;
	public static inline var HOLD_MIX:Int = 4;
	public static inline var SETUP:Int = 1;
	public static inline var CURRENT:Int = 2;

	private static var emptyAnimation:Animation = new Animation("<empty>", new Vector<Timeline>(), 0);

	public var data:AnimationStateData;
	public var tracks:Vector<TrackEntry> = new Vector<TrackEntry>();

	private var events:Vector<Event> = new Vector<Event>();

	public var onStart:Listeners = new Listeners();
	public var onInterrupt:Listeners = new Listeners();
	public var onEnd:Listeners = new Listeners();
	public var onDispose:Listeners = new Listeners();
	public var onComplete:Listeners = new Listeners();
	public var onEvent:EventListeners = new EventListeners();

	private var queue:EventQueue;
	private var propertyIDs:StringSet = new StringSet();

	public var animationsChanged:Bool = false;
	public var timeScale:Float = 1;
	public var trackEntryPool:Pool<TrackEntry>;

	private var unkeyedState:Int = 0;

	public function new(data:AnimationStateData) {
		if (data == null)
			throw new ArgumentError("data can not be null");
		this.data = data;
		this.queue = new EventQueue(this);
		this.trackEntryPool = new Pool(function():Dynamic {
			return new TrackEntry();
		});
	}

	public function update(delta:Float):Void {
		delta *= timeScale;
		for (i in 0...tracks.length) {
			var current:TrackEntry = tracks[i];
			if (current == null)
				continue;

			current.animationLast = current.nextAnimationLast;
			current.trackLast = current.nextTrackLast;

			var currentDelta:Float = delta * current.timeScale;

			if (current.delay > 0) {
				current.delay -= currentDelta;
				if (current.delay > 0)
					continue;
				currentDelta = -current.delay;
				current.delay = 0;
			}

			var next:TrackEntry = current.next;
			if (next != null) {
				// When the next entry's delay is passed, change to the next entry, preserving leftover time.
				var nextTime:Float = current.trackLast - next.delay;
				if (nextTime >= 0) {
					next.delay = 0;
					next.trackTime = current.timeScale == 0 ? 0 : (nextTime / current.timeScale + delta) * next.timeScale;
					current.trackTime += currentDelta;
					setCurrent(i, next, true);
					while (next.mixingFrom != null) {
						next.mixTime += currentDelta;
						next = next.mixingFrom;
					}
					continue;
				}
			} else if (current.trackLast >= current.trackEnd && current.mixingFrom == null) {
				// Clear the track when there is no next entry, the track end time is reached, and there is no mixingFrom.
				tracks[i] = null;
				queue.end(current);
				clearNext(current);
				continue;
			}

			if (current.mixingFrom != null && updateMixingFrom(current, delta)) {
				// End mixing from entries once all have completed.
				var from:TrackEntry = current.mixingFrom;
				current.mixingFrom = null;
				if (from != null)
					from.mixingTo = null;
				while (from != null) {
					queue.end(from);
					from = from.mixingFrom;
				}
			}

			current.trackTime += currentDelta;
		}

		queue.drain();
	}

	private function updateMixingFrom(to:TrackEntry, delta:Float):Bool {
		var from:TrackEntry = to.mixingFrom;
		if (from == null)
			return true;

		var finished:Bool = updateMixingFrom(from, delta);

		from.animationLast = from.nextAnimationLast;
		from.trackLast = from.nextTrackLast;

		// Require mixTime > 0 to ensure the mixing from entry was applied at least once.
		if (to.mixTime > 0 && to.mixTime >= to.mixDuration) {
			// Require totalAlpha == 0 to ensure mixing is complete, unless mixDuration == 0 (the transition is a single frame).
			if (from.totalAlpha == 0 || to.mixDuration == 0) {
				to.mixingFrom = from.mixingFrom;
				if (from.mixingFrom != null)
					from.mixingFrom.mixingTo = to;
				to.interruptAlpha = from.interruptAlpha;
				queue.end(from);
			}
			return finished;
		}

		from.trackTime += delta * from.timeScale;
		to.mixTime += delta;
		return false;
	}

	public function apply(skeleton:Skeleton):Bool {
		if (skeleton == null)
			throw new ArgumentError("skeleton cannot be null.");
		if (animationsChanged)
			_animationsChanged();
		var applied:Bool = false;

		for (i in 0...tracks.length) {
			var current:TrackEntry = tracks[i];
			if (current == null || current.delay > 0)
				continue;
			applied = true;
			var blend:MixBlend = i == 0 ? MixBlend.first : current.mixBlend;

			// Apply mixing from entries first.
			var mix:Float = current.alpha;
			if (current.mixingFrom != null) {
				mix *= applyMixingFrom(current, skeleton, blend);
			} else if (current.trackTime >= current.trackEnd && current.next == null) {
				mix = 0;
			}

			// Apply current entry.
			var animationLast:Float = current.animationLast,
				animationTime:Float = current.getAnimationTime(),
				applyTime:Float = animationTime;
			var applyEvents:Vector<Event> = events;
			if (current.reverse) {
				applyTime = current.animation.duration - applyTime;
				applyEvents = null;
			}
			var timelines:Vector<Timeline> = current.animation.timelines;
			var timelineCount:Int = timelines.length;
			var timeline:Timeline;
			if ((i == 0 && mix == 1) || blend == MixBlend.add) {
				for (timeline in timelines) {
					timeline.apply(skeleton, animationLast, applyTime, applyEvents, mix, blend, MixDirection.mixIn);
				}
			} else {
				var timelineMode:Vector<Int> = current.timelineMode;

				var firstFrame:Bool = current.timelinesRotation.length == 0;
				if (firstFrame)
					current.timelinesRotation.length = timelineCount << 1;

				for (ii in 0...timelineCount) {
					var timeline:Timeline = timelines[ii];
					var timelineBlend:MixBlend = timelineMode[ii] == SUBSEQUENT ? blend : MixBlend.setup;
					timeline.apply(skeleton, animationLast, applyTime, applyEvents, mix, timelineBlend, MixDirection.mixIn);
				}
			}
			queueEvents(current, animationTime);
			events.length = 0;
			current.nextAnimationLast = animationTime;
			current.nextTrackLast = current.trackTime;
		}

		// Set slots attachments to the setup pose, if needed. This occurs if an animation that is mixing out sets attachments so
		// subsequent timelines see any deform, but the subsequent timelines don't set an attachment (eg they are also mixing out or
		// the time is before the first key).
		var setupState:Int = unkeyedState + SETUP;
		for (slot in skeleton.slots) {
			if (slot.attachmentState == setupState) {
				var attachmentName:String = slot.data.attachmentName;
				slot.attachment = attachmentName == null ? null : skeleton.getAttachmentForSlotIndex(slot.data.index, attachmentName);
			}
		}
		unkeyedState += 2; // Increasing after each use avoids the need to reset attachmentState for every slot.

		queue.drain();
		return applied;
	}

	private function applyMixingFrom(to:TrackEntry, skeleton:Skeleton, blend:MixBlend):Float {
		var from:TrackEntry = to.mixingFrom;
		if (from.mixingFrom != null)
			applyMixingFrom(from, skeleton, blend);

		var mix:Float = 0;
		if (to.mixDuration == 0) // Single frame mix to undo mixingFrom changes.
		{
			mix = 1;
			if (blend == MixBlend.first)
				blend = MixBlend.setup;
		} else {
			mix = to.mixTime / to.mixDuration;
			if (mix > 1)
				mix = 1;
			if (blend != MixBlend.first)
				blend = from.mixBlend;
		}

		var attachments:Bool = mix < from.attachmentThreshold,
			drawOrder:Bool = mix < from.drawOrderThreshold;
		var timelineCount:Int = from.animation.timelines.length;
		var timelines:Vector<Timeline> = from.animation.timelines;
		var alphaHold:Float = from.alpha * to.interruptAlpha,
			alphaMix:Float = alphaHold * (1 - mix);
		var animationLast:Float = from.animationLast,
			animationTime:Float = from.getAnimationTime(),
			applyTime:Float = animationTime;
		var applyEvents:Vector<Event> = null;
		if (from.reverse) {
			applyTime = from.animation.duration - applyTime;
		} else if (mix < from.eventThreshold) {
			applyEvents = events;
		}

		if (blend == MixBlend.add) {
			for (timeline in timelines) {
				timeline.apply(skeleton, animationLast, applyTime, applyEvents, alphaMix, blend, MixDirection.mixOut);
			}
		} else {
			var timelineMode:Vector<Int> = from.timelineMode;
			var timelineHoldMix:Vector<TrackEntry> = from.timelineHoldMix;

			var firstFrame:Bool = from.timelinesRotation.length != timelineCount << 1;
			if (firstFrame)
				from.timelinesRotation.length = timelineCount << 1;
			var timelinesRotation:Vector<Float> = from.timelinesRotation;

			from.totalAlpha = 0;
			for (i in 0...timelineCount) {
				var timeline:Timeline = timelines[i];
				var direction:MixDirection = MixDirection.mixOut;
				var timelineBlend:MixBlend;
				var alpha:Float = 0;
				switch (timelineMode[i]) {
					case SUBSEQUENT:
						if (!drawOrder && Std.isOfType(timeline, DrawOrderTimeline))
							continue;
						timelineBlend = blend;
						alpha = alphaMix;
					case FIRST:
						timelineBlend = MixBlend.setup;
						alpha = alphaMix;
					case HOLD_SUBSEQUENT:
						timelineBlend = blend;
						alpha = alphaHold;
					case HOLD_FIRST:
						timelineBlend = MixBlend.setup;
						alpha = alphaHold;
					default:
						timelineBlend = MixBlend.setup;
						var holdMix:TrackEntry = timelineHoldMix[i];
						alpha = alphaHold * Math.max(0, 1 - holdMix.mixTime / holdMix.mixDuration);
				}

				from.totalAlpha += alpha;

				if (drawOrder && Std.isOfType(timeline, DrawOrderTimeline) && timelineBlend == MixBlend.setup)
					direction = MixDirection.mixIn;
				timeline.apply(skeleton, animationLast, applyTime, applyEvents, alpha, timelineBlend, direction);
			}
		}

		if (to.mixDuration > 0)
			queueEvents(from, animationTime);
		events.length = 0;
		from.nextAnimationLast = animationTime;
		from.nextTrackLast = from.trackTime;

		return mix;
	}

	private function setAttachment(skeleton:Skeleton, slot:Slot, attachmentName:String, attachments:Bool):Void {
		slot.attachment = attachmentName == null ? null : skeleton.getAttachmentForSlotIndex(slot.data.index, attachmentName);
		if (attachments)
			slot.attachmentState = unkeyedState + CURRENT;
	}

	private function queueEvents(entry:TrackEntry, animationTime:Float):Void {
		var animationStart:Float = entry.animationStart,
			animationEnd:Float = entry.animationEnd;
		var duration:Float = animationEnd - animationStart;
		var trackLastWrapped:Float = entry.trackLast % duration;

		// Queue events before complete.
		var event:Event;
		var i:Int = 0;
		var n:Int = events.length;
		while (i < n) {
			event = events[i++];
			if (event == null)
				continue;
			if (event.time < trackLastWrapped)
				break;
			if (event.time > animationEnd)
				continue; // Discard events outside animation start/end.
			queue.event(entry, event);
		}

		// Queue complete if completed a loop iteration or the animation.
		var complete:Bool;
		if (entry.loop) {
			complete = duration == 0 || trackLastWrapped > entry.trackTime % duration;
		} else {
			complete = animationTime >= animationEnd && entry.animationLast < animationEnd;
		}
		if (complete)
			queue.complete(entry);

		// Queue events after complete.
		while (i < n) {
			event = events[i++];
			if (event == null)
				continue;
			if (event.time < animationStart)
				continue; // Discard events outside animation start/end.
			queue.event(entry, event);
		}
	}

	public function clearTracks():Void {
		var oldTrainDisabled:Bool = queue.drainDisabled;
		queue.drainDisabled = true;
		for (i in 0...tracks.length) {
			clearTrack(i);
		}
		tracks.length = 0;
		queue.drainDisabled = oldTrainDisabled;
		queue.drain();
	}

	public function clearTrack(trackIndex:Int):Void {
		if (trackIndex >= tracks.length)
			return;
		var current:TrackEntry = tracks[trackIndex];
		if (current == null)
			return;

		queue.end(current);
		clearNext(current);

		var entry:TrackEntry = current;
		while (true) {
			var from:TrackEntry = entry.mixingFrom;
			if (from == null)
				break;
			queue.end(from);
			entry.mixingFrom = null;
			entry.mixingTo = null;
			entry = from;
		}

		tracks[current.trackIndex] = null;

		queue.drain();
	}

	private function setCurrent(index:Int, current:TrackEntry, interrupt:Bool):Void {
		var from:TrackEntry = expandToIndex(index);
		tracks[index] = current;

		if (from != null) {
			if (interrupt)
				queue.interrupt(from);
			current.mixingFrom = from;
			from.mixingTo = current;
			current.mixTime = 0;

			// Store the interrupted mix percentage.
			if (from.mixingFrom != null && from.mixDuration > 0) {
				current.interruptAlpha *= Math.min(1, from.mixTime / from.mixDuration);
			}

			from.timelinesRotation.length = 0; // Reset rotation for mixing out, in case entry was mixed in.
		}

		queue.start(current);
	}

	public function setAnimationByName(trackIndex:Int, animationName:String, loop:Bool):TrackEntry {
		var animation:Animation = data.skeletonData.findAnimation(animationName);
		if (animation == null)
			throw new ArgumentError("Animation not found: " + animationName);
		return setAnimation(trackIndex, animation, loop);
	}

	public function setAnimation(trackIndex:Int, animation:Animation, loop:Bool):TrackEntry {
		if (animation == null)
			throw new ArgumentError("animation cannot be null.");
		var interrupt:Bool = true;
		var current:TrackEntry = expandToIndex(trackIndex);
		if (current != null) {
			if (current.nextTrackLast == -1) {
				// Don't mix from an entry that was never applied.
				tracks[trackIndex] = current.mixingFrom;
				queue.interrupt(current);
				queue.end(current);
				clearNext(current);
				current = current.mixingFrom;
				interrupt = false;
			} else {
				clearNext(current);
			}
		}
		var entry:TrackEntry = trackEntry(trackIndex, animation, loop, current);
		setCurrent(trackIndex, entry, interrupt);
		queue.drain();
		return entry;
	}

	public function addAnimationByName(trackIndex:Int, animationName:String, loop:Bool, delay:Float):TrackEntry {
		var animation:Animation = data.skeletonData.findAnimation(animationName);
		if (animation == null)
			throw new ArgumentError("Animation not found: " + animationName);
		return addAnimation(trackIndex, animation, loop, delay);
	}

	public function addAnimation(trackIndex:Int, animation:Animation, loop:Bool, delay:Float):TrackEntry {
		if (animation == null)
			throw new ArgumentError("animation cannot be null.");

		var last:TrackEntry = expandToIndex(trackIndex);
		if (last != null) {
			while (last.next != null) {
				last = last.next;
			}
		}

		var entry:TrackEntry = trackEntry(trackIndex, animation, loop, last);

		if (last == null) {
			setCurrent(trackIndex, entry, true);
			queue.drain();
		} else {
			last.next = entry;
			entry.previous = last;
			if (delay <= 0)
				delay += last.getTrackComplete() - entry.mixDuration;
		}

		entry.delay = delay;
		return entry;
	}

	public function setEmptyAnimation(trackIndex:Int, mixDuration:Float):TrackEntry {
		var entry:TrackEntry = setAnimation(trackIndex, emptyAnimation, false);
		entry.mixDuration = mixDuration;
		entry.trackEnd = mixDuration;
		return entry;
	}

	public function addEmptyAnimation(trackIndex:Int, mixDuration:Float, delay:Float):TrackEntry {
		var entry:TrackEntry = addAnimation(trackIndex, emptyAnimation, false, delay);
		if (delay <= 0)
			entry.delay += entry.mixDuration - mixDuration;
		entry.mixDuration = mixDuration;
		entry.trackEnd = mixDuration;
		return entry;
	}

	public function setEmptyAnimations(mixDuration:Float):Void {
		var oldDrainDisabled:Bool = queue.drainDisabled;
		queue.drainDisabled = true;
		for (i in 0...tracks.length) {
			var current:TrackEntry = tracks[i];
			if (current != null)
				setEmptyAnimation(current.trackIndex, mixDuration);
		}
		queue.drainDisabled = oldDrainDisabled;
		queue.drain();
	}

	private function expandToIndex(index:Int):TrackEntry {
		if (index < tracks.length)
			return tracks[index];
		tracks.length = index + 1;
		return null;
	}

	private function trackEntry(trackIndex:Int, animation:Animation, loop:Bool, last:TrackEntry):TrackEntry {
		var entry:TrackEntry = cast(trackEntryPool.obtain(), TrackEntry);
		entry.trackIndex = trackIndex;
		entry.animation = animation;
		entry.loop = loop;
		entry.holdPrevious = false;

		entry.eventThreshold = 0;
		entry.attachmentThreshold = 0;
		entry.drawOrderThreshold = 0;

		entry.animationStart = 0;
		entry.animationEnd = animation.duration;
		entry.animationLast = -1;
		entry.nextAnimationLast = -1;

		entry.delay = 0;
		entry.trackTime = 0;
		entry.trackLast = -1;
		entry.nextTrackLast = -1;
		entry.trackEnd = Max.INT_MAX_VALUE;
		entry.timeScale = 1;

		entry.alpha = 1;
		entry.interruptAlpha = 1;
		entry.mixTime = 0;
		entry.mixDuration = last == null ? 0 : data.getMix(last.animation, animation);
		entry.mixBlend = MixBlend.replace;
		return entry;
	}

	/** Removes the {@link TrackEntry#getNext() next entry} and all entries after it for the specified entry. */
	public function clearNext(entry:TrackEntry):Void {
		var next:TrackEntry = entry.next;
		while (next != null) {
			queue.dispose(next);
			next = next.next;
		}
		entry.next = null;
	}

	private function _animationsChanged():Void {
		animationsChanged = false;

		propertyIDs.clear();
		var entry:TrackEntry = null;
		for (i in 0...tracks.length) {
			entry = tracks[i];
			if (entry == null)
				continue;
			while (entry.mixingFrom != null) {
				entry = entry.mixingFrom;
			}
			do {
				if (entry.mixingTo == null || entry.mixBlend != MixBlend.add)
					computeHold(entry);
				entry = entry.mixingTo;
			} while (entry != null);
		}
	}

	private function computeHold(entry:TrackEntry):Void {
		var to:TrackEntry = entry.mixingTo;
		var timelines:Vector<Timeline> = entry.animation.timelines;
		var timelinesCount:Int = entry.animation.timelines.length;
		var timelineMode:Vector<Int> = entry.timelineMode;
		timelineMode.length = timelinesCount;
		entry.timelineHoldMix.length = 0;
		var timelineHoldMix:Vector<TrackEntry> = entry.timelineHoldMix;
		timelineHoldMix.length = timelinesCount;

		if (to != null && to.holdPrevious) {
			for (i in 0...timelinesCount) {
				timelineMode[i] = propertyIDs.addAll(timelines[i].propertyIds) ? HOLD_FIRST : HOLD_SUBSEQUENT;
			}
			return;
		}

		var continueOuter:Bool;
		for (i in 0...timelinesCount) {
			continueOuter = false;
			var timeline:Timeline = timelines[i];
			var ids:Vector<String> = timeline.propertyIds;
			if (!propertyIDs.addAll(ids)) {
				timelineMode[i] = SUBSEQUENT;
			} else if (to == null
				|| Std.isOfType(timeline, AttachmentTimeline)
				|| Std.isOfType(timeline, DrawOrderTimeline)
				|| Std.isOfType(timeline, EventTimeline)
				|| !to.animation.hasTimeline(ids)) {
				timelineMode[i] = FIRST;
			} else {
				var next:TrackEntry = to.mixingTo;
				while (next != null) {
					if (next.animation.hasTimeline(ids)) {
						next = next.mixingTo;
						continue;
					}
					if (entry.mixDuration > 0) {
						timelineMode[i] = HOLD_MIX;
						timelineHoldMix[i] = next;
						continueOuter = true;
						break;
					}
					break;
				}
				if (continueOuter)
					continue;
				timelineMode[i] = HOLD_FIRST;
			}
		}
	}

	public function getCurrent(trackIndex:Int):TrackEntry {
		if (trackIndex >= tracks.length)
			return null;
		return tracks[trackIndex];
	}

	public var fHasEndListener(get, never):Bool;

	private function get_fHasEndListener():Bool {
		return onComplete.listeners.length > 0 || onEnd.listeners.length > 0;
	}

	public function clearListeners():Void {
		onStart.listeners.length = 0;
		onInterrupt.listeners.length = 0;
		onEnd.listeners.length = 0;
		onDispose.listeners.length = 0;
		onComplete.listeners.length = 0;
		onEvent.listeners.length = 0;
	}

	public function clearListenerNotifications():Void {
		queue.clear();
	}
}

class StringSet {
	private var entries:Dictionary<String, Bool> = new Dictionary<String, Bool>();
	private var size:Int = 0;

	public function new() {}

	public function add(value:String):Bool {
		var contains:Bool = entries[value];
		entries[value] = true;
		if (!contains) {
			size++;
			return true;
		}
		return false;
	}

	public function addAll(values:Vector<String>):Bool {
		var oldSize:Int = size;
		for (i in 0...values.length) {
			add(values[i]);
		}
		return oldSize != size;
	}

	public function contains(value:String):Bool {
		return entries[value];
	}

	public function clear():Void {
		entries = new Dictionary<String, Bool>();
		size = 0;
	}
}
