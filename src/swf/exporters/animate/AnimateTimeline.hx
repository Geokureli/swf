package swf.exporters.animate;

import lime.utils.Log;
import openfl.display.DisplayObject;
import openfl.display.FrameLabel;
import openfl.display.FrameScript;
import openfl.display.MovieClip;
import openfl.display.Scene;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.display.Timeline;
// import openfl.events.Event;
import openfl.filters.BitmapFilter;
import openfl.filters.BlurFilter;
import openfl.filters.ColorMatrixFilter;
import openfl.filters.ConvolutionFilter;
import openfl.filters.DisplacementMapFilter;
import openfl.filters.DropShadowFilter;
import openfl.filters.GlowFilter;
import openfl.geom.ColorTransform;
#if hscript
import hscript.Interp;
import hscript.Parser;
#end

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(swf.exporters.animate.AnimateLibrary)
@:access(swf.exporters.animate.AnimateSymbol)
@:access(openfl.display.DisplayObject)
@:access(openfl.display.MovieClip)
@:access(openfl.geom.ColorTransform)
class AnimateTimeline extends Timeline
{
	#if 0
	// Suppress checkstyle warning
	private static var __unusedImport:Array<Class<Dynamic>> = [
		AnimateBitmapSymbol, AnimateButtonSymbol, AnimateDynamicTextSymbol, AnimateFontSymbol, AnimateShapeSymbol, AnimateSpriteSymbol,
		AnimateStaticTextSymbol, AnimateSymbol, BlurFilter, ColorMatrixFilter, ConvolutionFilter, DisplacementMapFilter, DropShadowFilter, GlowFilter
	];
	#end

	@:noCompletion private var __activeInstances:Array<FrameSymbolInstance>;
	@:noCompletion private var __activeInstancesByFrameObjectID:Map<Int, FrameSymbolInstance>;
	@:noCompletion private var __previousInstancesByDepth:Map<Int, FrameSymbolInstance>;
	@:noCompletion private var __instanceFields:Array<String>;
	@:noCompletion private var __library:AnimateLibrary;
	@:noCompletion private var __previousFrame:Int;
	@:noCompletion private var __sprite:Sprite;
	@:noCompletion private var __symbol:AnimateSpriteSymbol;

	public function new(library:AnimateLibrary, symbol:AnimateSpriteSymbol)
	{
		super();

		__library = library;
		__symbol = symbol;

		frameRate = library.frameRate;
		var labels = [];
		scripts = [];

		var frame:Int;
		var frameData:AnimateFrame;

		#if hscript
		var parser = null;
		#end

		for (i in 0...__symbol.frames.length)
		{
			frame = i + 1;
			frameData = __symbol.frames[i];

			if (frameData.labels != null)
			{
				for (label in frameData.labels)
				{
					labels.push(new FrameLabel(label, frame));
				}
			}

			if (frameData.script != null)
			{
				scripts.push(new FrameScript(frameData.script, frame));
			}
			else if (frameData.scriptSource != null)
			{
				try
				{
					#if hscript
					if (parser == null)
					{
						parser = new Parser();
						parser.allowTypes = true;
					}

					var program = parser.parseString(frameData.scriptSource);
					var interp = new Interp();

					var script = function(scope:MovieClip)
					{
						interp.variables.set("this", scope);
						interp.execute(program);
					};

					scripts.push(new FrameScript(script, frame));
					#elseif js
					var script = untyped untyped #if haxe4 js.Syntax.code #else __js__ #end ("eval({0})", "(function(){" + frameData.scriptSource + "})");
					var wrapper = function(scope:MovieClip)
					{
						try
						{
							script.call(scope);
						}
						catch (e:Dynamic)
						{
							Log.info("Error evaluating frame script\n "
								+ e
								+ "\n"
								+ haxe.CallStack.exceptionStack().map(function(a)
								{
									return untyped a[2];
								}).join("\n")
								+ "\n"
								+ e.stack
								+ "\n"
								+ untyped script.toString());
						}
					}

					scripts.push(new FrameScript(wrapper, frame));
					#end
				}
				catch (e:Dynamic)
				{
					if (__symbol.className != null)
					{
						Log.warn("Unable to evaluate frame script source for symbol \"" + __symbol.className + "\" frame " + frame + "\n"
							+ frameData.scriptSource);
					}
					else
					{
						Log.warn("Unable to evaluate frame script source:\n" + frameData.scriptSource);
					}
				}
			}
		}

		scenes = [new Scene("", labels, __symbol.frames.length)];
	}

	public override function attachMovieClip(movieClip:MovieClip):Void
	{
		init(movieClip);
	}

	public override function enterFrame(currentFrame:Int):Void
	{
		if (__symbol != null && currentFrame != __previousFrame)
		{
			__updateFrameLabel();

			var loopedSinceLastFrameUpdate:Bool = (__previousFrame > __currentFrame);

			var currentInstancesByDepth:Map<Int,
				FrameSymbolInstance> = null; // <depth, FrameSymbolInstance>  frameObject.id should be the same as FrameSymbolInstance.initFrameObjectID

			// start from scratch if we have looped around or starting from beginning.
			// Otherwise we need to keep the objects on the timeline active (when we are doing a goto either backward or forward, or just playing sequentially)
			if (__previousInstancesByDepth == null /*|| (!isGoTo && (loopedSinceLastFrameUpdate || __previousFrame < 0))*/)
			{
				currentInstancesByDepth = new Map();
			}
			else
			{
				currentInstancesByDepth = __previousInstancesByDepth;
			}

			var frame:Int;
			var frameData:AnimateFrame;
			var instance:FrameSymbolInstance;

			// main loop to get updated frame object information and apply it to display objects.
			var updateFrameStart:Int = (loopedSinceLastFrameUpdate || __previousFrame < 0) ? 0 : __previousFrame;
			for (i in updateFrameStart...__currentFrame)
			{
				frame = i + 1;
				frameData = __symbol.frames[i];

				if (frameData.objects == null) continue;

				var lastFrameObjectDepths:Array<Int> = new Array();

				// Collect all depths present on the last frame
				if (currentInstancesByDepth.iterator().hasNext())
				{
					for (frameObjectDepth in currentInstancesByDepth.keys())
					{
						lastFrameObjectDepths.push(frameObjectDepth);
					}
				}
				// anything that is on this frame we don't need to delete, so remove from the list
				if (lastFrameObjectDepths.iterator().hasNext())
				{
					for (frameObject in frameData.objects)
					{
						lastFrameObjectDepths.remove(frameObject.depth);
					}
				}
				// delete anything that is left (means that depth was only present on the last frame)
				for (depth in lastFrameObjectDepths)
				{
					currentInstancesByDepth.remove(depth);
				}

				for (frameObject in frameData.objects)
				{
					// if is a new character sequentially in the timeline and has move information we check the old object
					// at that depth after creating the new one and any information not applied by the frameObject is applied by the old object at that depth
					//--
					// if both hasChracter and hasMove are false then we just need to create a new character and
					// add it at the depth and remove the previous object at that depth if it is not the same object already being use (frameObjectID)
					// this should only happen when doing a goto
					if (frameObject.hasCharacter == frameObject.hasMove)
					{
						var oldInstance:FrameSymbolInstance = null;
						if (currentInstancesByDepth.exists(frameObject.depth))
						{
							oldInstance = currentInstancesByDepth.get(frameObject.depth);
							currentInstancesByDepth.remove(frameObject.depth);
						}

						instance = __activeInstancesByFrameObjectID.get(frameObject.id);

						if (instance != null)
						{
							currentInstancesByDepth.set(frameObject.depth, instance);
							if (!frameObject.hasCharacter
								&& !frameObject.hasMove
								&& oldInstance != null
								&& instance.initFrameObjectID == oldInstance.initFrameObjectID)
							{
								continue; // this object is already on the timeline and being used, no need to update
							}
							__updateDisplayObject(instance.displayObject, frameObject);

							if (oldInstance != null && frameObject.hasMove)
							{
								if (frameObject.name == null)
								{
									instance.displayObject.name = oldInstance.displayObject.name;
								}
								if (frameObject.matrix == null)
								{
									instance.displayObject.transform.matrix = oldInstance.displayObject.transform.matrix;
								}
								if (frameObject.colorTransform == null)
								{
									instance.displayObject.transform.colorTransform = oldInstance.displayObject.transform.colorTransform;
								}
								if (frameObject.filters == null)
								{
									instance.displayObject.filters = oldInstance.displayObject.filters;
								}
								if (frameObject.visible == null)
								{
									instance.displayObject.visible = oldInstance.displayObject.visible;
								}
								if (frameObject.blendMode == null)
								{
									instance.displayObject.blendMode = oldInstance.displayObject.blendMode;
								}
								if (frameObject.cacheAsBitmap == null)
								{
									// instance.displayObject.cacheAsBitmap = oldInstance.displayObject.cacheAsBitmap;
								}
							}
						}
					}
					else
					{
						// if hasMove we should be modifying the current object, unless we are doing a goto and the object doesn't exist
						instance = null;
						if (frameObject.hasMove)
						{
							instance = currentInstancesByDepth.get(frameObject.depth);
							if (instance != null && instance.initFrameObjectID != frameObject.id)
							{ // throw away changes made by scripts if it isn't the same id
								instance = null;
							}
						}
						// if frameObject.hasCharacter or we are doing a goto and the character doesn't exist yet, we need to make it
						if (instance == null)
						{
							instance = __activeInstancesByFrameObjectID.get(frameObject.id);
							if (instance != null)
							{
								currentInstancesByDepth.set(frameObject.depth, instance);
							}
						}
						if (instance != null)
						{
							__updateDisplayObject(instance.displayObject, frameObject);
						}
					}
				}
			}

			// TODO: Less garbage?

			var currentInstances = new Array<FrameSymbolInstance>();
			var currentMasks = new Array<FrameSymbolInstance>();

			for (instance in currentInstancesByDepth)
			{
				if (currentInstances.indexOf(instance) == -1)
				{
					currentInstances.push(instance);

					if (instance.clipDepth > 0)
					{
						currentMasks.push(instance);
					}
				}
			}

			__previousInstancesByDepth = currentInstancesByDepth;
			currentInstances.sort(__sortDepths);

			// TODO: Speed up removal
			for (instance in __activeInstances)
			{
				if (currentInstances.indexOf(instance) == -1)
				{
					__sprite.removeChild(instance.displayObject);
				}
			}

			// TODO: Revisit ordering with manually added objects

			// TODO: Less garbage?

			var currentInstances = new Array<FrameSymbolInstance>();
			var currentMasks = new Array<FrameSymbolInstance>();

			for (instance in currentInstancesByDepth)
			{
				if (currentInstances.indexOf(instance) == -1)
				{
					currentInstances.push(instance);

					if (instance.clipDepth > 0)
					{
						currentMasks.push(instance);
					}
				}
			}

			currentInstances.sort(__sortDepths);

			var existingChild:DisplayObject;
			var targetDepth:Int;
			var targetChild:DisplayObject;
			var child:DisplayObject;
			var maskApplied:Bool;

			for (i in 0...currentInstances.length)
			{
				existingChild = (i < __sprite.numChildren) ? __sprite.getChildAt(i) : null;
				instance = currentInstances[i];

				targetDepth = instance.depth;
				targetChild = instance.displayObject;

				if (existingChild != targetChild)
				{
					__sprite.addChildAt(targetChild, i);
				}

				child = targetChild;
				maskApplied = false;

				for (mask in currentMasks)
				{
					if (targetDepth > mask.depth && targetDepth <= mask.clipDepth)
					{
						child.mask = mask.displayObject;
						maskApplied = true;
						break;
					}
				}

				if (currentMasks.length > 0 && !maskApplied && child.mask != null)
				{
					child.mask = null;
				}
			}

			// TODO: How to tell if shapes are for a scale9Grid clip?
			if (__sprite.scale9Grid != null)
			{
				__sprite.graphics.clear();
				if (currentInstances.length > 0)
				{
					var shape:Shape = cast currentInstances[0].displayObject;
					__sprite.graphics.copyFrom(shape.graphics);
				}
			}
			else
			{
				var child;
				var i = currentInstances.length;
				var length = __sprite.numChildren;

				while (i < length)
				{
					child = __sprite.getChildAt(i);

					// TODO: Faster method of determining if this was automatically added?

					for (instance in __activeInstances)
					{
						if (instance.displayObject == child)
						{
							// set MovieClips back to initial state (autoplay)
							if (#if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (child, MovieClip))
							{
								var movie:MovieClip = cast child;
								movie.gotoAndPlay(1);
							}

							__sprite.removeChild(child);
							i--;
							length--;
						}
					}

					i++;
				}

				#if !openfljs
				// TODO: Can this be done once?
				__updateInstanceFields();
				#end
			}

			__previousFrame = currentFrame;
		}
	}

	private function init(sprite:Sprite):Void
	{
		if (__activeInstances != null) return;

		__sprite = sprite;

		__instanceFields = [];
		__previousFrame = -1;

		__activeInstances = [];
		__activeInstancesByFrameObjectID = new Map();

		var frame:Int;
		var frameData:AnimateFrame;
		var instance:FrameSymbolInstance;
		var duplicate:Bool;
		var symbol:AnimateSymbol;
		var displayObject:DisplayObject;

		// TODO: Create later?

		for (i in 0...scenes[0].numFrames)
		{
			frame = i + 1;
			frameData = __symbol.frames[i];

			if (frameData.objects == null) continue;

			for (frameObject in frameData.objects)
			{
				if (__activeInstancesByFrameObjectID.exists(frameObject.id))
				{
					continue;
				}
				else
				{
					instance = null;
					duplicate = false;

					for (activeInstance in __activeInstances)
					{
						if (activeInstance.displayObject != null
							&& activeInstance.characterID == frameObject.symbol
							&& activeInstance.depth == frameObject.depth)
						{
							// TODO: Fix duplicates in exporter
							instance = activeInstance;
							duplicate = true;
							break;
						}
					}
				}

				if (instance == null)
				{
					symbol = __library.symbols.get(frameObject.symbol);

					if (symbol != null)
					{
						displayObject = symbol.__createObject(__library);

						if (displayObject != null)
						{
							#if !flash
							// displayObject.parent = __sprite;
							// displayObject.stage = __sprite.stage;

							// if (__sprite.stage != null) displayObject.dispatchEvent(new Event(Event.ADDED_TO_STAGE, false, false));
							#end

							if (frameObject.clipDepth > 0)
							{
								// TODO: Is this needed?
								displayObject.visible = false;
								// displayObject.isTimelineMask = true;
							}

							instance = new FrameSymbolInstance(frame, frameObject.id, frameObject.symbol, frameObject.depth, displayObject,
								frameObject.clipDepth);
						}
					}
				}

				if (instance != null)
				{
					__activeInstancesByFrameObjectID.set(frameObject.id, instance);

					if (!duplicate)
					{
						__activeInstances.push(instance);
						__updateDisplayObject(instance.displayObject, frameObject);
					}
				}
			}
		}

		#if !openfljs
		__instanceFields = Type.getInstanceFields(Type.getClass(__sprite));
		#end

		enterFrame(1);
	}

	public override function initializeSprite(sprite:Sprite):Void
	{
		if (__activeInstances != null) return;

		init(sprite);

		__activeInstances = null;
		__activeInstancesByFrameObjectID = null;
		__instanceFields = null;
		__sprite = null;
		__previousFrame = -1;
	}

	@:noCompletion private function __sortDepths(a:FrameSymbolInstance, b:FrameSymbolInstance):Int
	{
		return a.depth - b.depth;
	}

	@:noCompletion private function __updateDisplayObject(displayObject:DisplayObject, frameObject:AnimateFrameObject, reset:Bool = false):Void
	{
		if (displayObject == null) return;

		if (frameObject.name != null)
		{
			displayObject.name = frameObject.name;
		}

		if (frameObject.matrix != null)
		{
			displayObject.transform.matrix = frameObject.matrix;
		}

		if (frameObject.colorTransform != null)
		{
			displayObject.transform.colorTransform = frameObject.colorTransform;
		}
		else if (reset #if !flash && !displayObject.transform.colorTransform.__isDefault(false) #end)
		{
			displayObject.transform.colorTransform = new ColorTransform();
		}

		displayObject.transform = displayObject.transform;

		if (frameObject.filters != null)
		{
			var filters:Array<BitmapFilter> = [];

			for (filter in frameObject.filters)
			{
				switch (filter)
				{
					case BlurFilter(blurX, blurY, quality):
						filters.push(new BlurFilter(blurX, blurY, quality));

					case ColorMatrixFilter(matrix):
						filters.push(new ColorMatrixFilter(matrix));

					case DropShadowFilter(distance, angle, color, alpha, blurX, blurY, strength, quality, inner, knockout, hideObject):
						filters.push(new DropShadowFilter(distance, angle, color, alpha, blurX, blurY, strength, quality, inner, knockout, hideObject));

					case GlowFilter(color, alpha, blurX, blurY, strength, quality, inner, knockout):
						filters.push(new GlowFilter(color, alpha, blurX, blurY, strength, quality, inner, knockout));
				}
			}

			displayObject.filters = filters;
		}
		else
		{
			displayObject.filters = null;
		}

		if (frameObject.visible != null)
		{
			displayObject.visible = frameObject.visible;
		}

		if (frameObject.blendMode != null)
		{
			displayObject.blendMode = frameObject.blendMode;
		}

		if (frameObject.cacheAsBitmap != null)
		{
			displayObject.cacheAsBitmap = frameObject.cacheAsBitmap;
		}

		#if openfljs
		Reflect.setField(__sprite, displayObject.name, displayObject);
		#end
	}

	@:noCompletion private function __updateInstanceFields():Void
	{
		for (field in __instanceFields)
		{
			var length = __sprite.numChildren;
			for (i in 0...length)
			{
				var child = __sprite.getChildAt(i);
				if (child.name == field)
				{
					Reflect.setField(__sprite, field, child);
					break;
				}
			}
		}
	}
}

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
private class FrameSymbolInstance
{
	public var characterID:Int;
	public var clipDepth:Int;
	public var depth:Int;
	public var displayObject:DisplayObject;
	public var initFrame:Int;
	public var initFrameObjectID:Int; // TODO: Multiple frame object IDs may refer to the same instance

	public function new(initFrame:Int, initFrameObjectID:Int, characterID:Int, depth:Int, displayObject:DisplayObject, clipDepth:Int)
	{
		this.initFrame = initFrame;
		this.initFrameObjectID = initFrameObjectID;
		this.characterID = characterID;
		this.depth = depth;
		this.displayObject = displayObject;
		this.clipDepth = clipDepth;
	}
}
