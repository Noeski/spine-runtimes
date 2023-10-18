package spine.animation;

import openfl.Vector;

/** Base class for frames that use an interpolation bezier curve. */
class CurveTimeline extends Timeline {
	private static inline var LINEAR:Int = 0;
	private static inline var STEPPED:Int = 1;
	private static inline var BEZIER:Int = 2;
	private static inline var BEZIER_SIZE:Int = 18;

	private var curves:Vector<Float>; // type, x, y, ...

	public function new(frameCount:Int, bezierCount:Int, propertyIds:Vector<String>) {
		super(frameCount, propertyIds);
		curves = new Vector<Float>(frameCount + bezierCount * BEZIER_SIZE, true);
		curves[frameCount - 1] = STEPPED;
	}

	public function setLinear(frame:Int):Void {
		curves[frame] = LINEAR;
	}

	public function setStepped(frame:Int):Void {
		curves[frame] = STEPPED;
	}

	/** Shrinks the storage for Bezier curves, for use when <code>bezierCount</code> (specified in the constructor) was larger
	 * than the actual number of Bezier curves. */
	public function shrink(bezierCount:Int):Void {
		var size:Int = getFrameCount() + bezierCount * BEZIER_SIZE;
		curves.length = size;
	}

	/** Stores the segments for the specified Bezier curve. For timelines that modify multiple values, there may be more than
	 * one curve per frame.
	 * @param bezier The ordinal of this Bezier curve for this timeline, between 0 and <code>bezierCount - 1</code> (specified
	 *           in the constructor), inclusive.
	 * @param frame Between 0 and <code>frameCount - 1</code>, inclusive.
	 * @param value The index of the value for this frame that this curve is used for.
	 * @param time1 The time for the first key.
	 * @param value1 The value for the first key.
	 * @param cx1 The time for the first Bezier handle.
	 * @param cy1 The value for the first Bezier handle.
	 * @param cx2 The time of the second Bezier handle.
	 * @param cy2 The value for the second Bezier handle.
	 * @param time2 The time for the second key.
	 * @param value2 The value for the second key. */
	public function setBezier(bezier:Int, frame:Int, value:Float, time1:Float, value1:Float, cx1:Float, cy1:Float, cx2:Float, cy2:Float, time2:Float,
			value2:Float):Void {
		var i:Int = getFrameCount() + bezier * BEZIER_SIZE;
		if (value == 0)
			curves[frame] = BEZIER + i;
		var tmpx:Float = (time1 - cx1 * 2 + cx2) * 0.03,
			tmpy:Float = (value1 - cy1 * 2 + cy2) * 0.03;
		var dddx:Float = ((cx1 - cx2) * 3 - time1 + time2) * 0.006,
			dddy:Float = ((cy1 - cy2) * 3 - value1 + value2) * 0.006;
		var ddx:Float = tmpx * 2 + dddx, ddy:Float = tmpy * 2 + dddy;
		var dx:Float = (cx1 - time1) * 0.3 + tmpx + dddx * 0.16666667,
			dy:Float = (cy1 - value1) * 0.3 + tmpy + dddy * 0.16666667;
		var x:Float = time1 + dx, y:Float = value1 + dy;
		var n:Int = i + BEZIER_SIZE;
		while (i < n) {
			curves[i] = x;
			curves[i + 1] = y;
			dx += ddx;
			dy += ddy;
			ddx += dddx;
			ddy += dddy;
			x += dx;
			y += dy;

			i += 2;
		}
	}

	/** Returns the Bezier interpolated value for the specified time.
	 * @param frameIndex The index into {@link #getFrames()} for the values of the frame before <code>time</code>.
	 * @param valueOffset The offset from <code>frameIndex</code> to the value this curve is used for.
	 * @param i The index of the Bezier segments. See {@link #getCurveType(int)}. */
	public function getBezierValue(time:Float, frameIndex:Int, valueOffset:Int, i:Int):Float {
		var x:Float, y:Float;
		if (curves[i] > time) {
			x = frames[frameIndex];
			y = frames[frameIndex + valueOffset];
			return y + (time - x) / (curves[i] - x) * (curves[i + 1] - y);
		}
		var n:Int = i + BEZIER_SIZE;
		i += 2;
		while (i < n) {
			if (curves[i] >= time) {
				x = curves[i - 2];
				y = curves[i - 1];
				return y + (time - x) / (curves[i] - x) * (curves[i + 1] - y);
			}

			i += 2;
		}
		frameIndex += getFrameEntries();
		x = curves[n - 2];
		y = curves[n - 1];
		return y + (time - x) / (frames[frameIndex] - x) * (frames[frameIndex + valueOffset] - y);
	}
}
