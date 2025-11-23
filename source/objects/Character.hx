package objects;

import flixel.FlxSprite;
import flixel.FlxG;
import flixel.util.FlxColor;
import flixel.text.FlxText;
import flixel.util.FlxSort;
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.zip.Reader;
import haxe.zip.Entry;
import sys.FileSystem;
import sys.io.File;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.geom.ColorTransform;
#if flxanimate
import flxanimate._PsychFlxAnimate.FlxAnimate;
import flxanimate.animate.FlxAnim;
import flxanimate.animate.FlxSymbol;
#end
import backend.Paths;
import backend.ClientPrefs;
import backend.animation.PsychAnimationController;

/**
 * CharacterFile structure (matches Psych 1.0.4)
 */
typedef CharacterFile = {
	var animations:Array<AnimArray>;
	var image:String;
	var scale:Float;
	var sing_duration:Float;
	var healthicon:String;
	var position:Array<Float>;
	var camera_position:Array<Float>;
	var flip_x:Bool;
	var no_antialiasing:Bool;
	var healthbar_colors:Array<Int>;
	var vocals_file:String;
	@:optional var _editor_isPlayer:Null<Bool>;
}

typedef AnimArray = {
	var anim:String;
	var name:String;
	var fps:Int;
	var loop:Bool;
	var indices:Array<Int>;
	var offsets:Array<Int>;
}

/**
 * Character with ZIP Animate Import support
 */
class Character extends FlxSprite {
	public static final DEFAULT_CHARACTER:String = "bf";

	public var animOffsets:Map<String, Array<Float>> = new Map();
	public var extraData:Map<String, Dynamic> = new Map();
	public var debugMode:Bool = false;

	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;

	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var stunned:Bool = false;

	public var singDuration:Float = 4;
	public var idleSuffix:String = "";
	public var danceIdle:Bool = false;
	public var skipDance:Bool = false;

	public var healthIcon:String = "face";
	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];
	public var healthColorArray:Array<Int> = [255, 0, 0];

	public var vocalsFile:String = "";
	public var jsonScale:Float = 1;
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;
	public var editorIsPlayer:Null<Bool> = null;

	public var missingCharacter:Bool = false;
	public var missingText:FlxText;

	// ZIP/Animate support
	public var isZipAtlas(default, null):Bool = false;
	public var zipSymbols:Map<String, BitmapData> = new Map();
	public var zipAnimations:Map<String, Array<Int>> = new Map(); // timeline frames
	public var zipFPS:Map<String, Int> = new Map();
	public var zipLoop:Map<String, Bool> = new Map();
	public var zipOffsets:Map<String, Array<Float>> = new Map();
	public var zipSymbolCount:Int = 0;

	#if flxanimate
	public var atlas:FlxAnimate; // will be used to display ZIP frames

	#end
	public function new(x:Float, y:Float, ?character:String = "bf", ?isPlayer:Bool = false) {
		super(x, y);

		this.isPlayer = isPlayer;
		animOffsets = new Map<String, Array<Float>>();
		animation = new PsychAnimationController(this);

		changeCharacter(character);
	}

	// ===================================================================================
	// ZIP SUPPORT
	// ===================================================================================

	/**
	 * Reads a .zip file into a map of entries.
	 */
	function readZip(path:String):Map<String, Bytes> {
		var assets = new Map<String, Bytes>();

		if (!FileSystem.exists(path)) {
			return assets;
		}

		var bytes = File.getBytes(path);
		var input = new BytesInput(bytes);
		var reader = new Reader(input);

		for (entry in reader.read()) {
			var name = entry.fileName;
			var data = entry.data;

			if (data != null)
				assets.set(name, data);
		}
		return assets;
	}

	/**
	 * Loads ZIP-based Animate data.json + symbols/*.png
	 */
	function loadZipAtlas(imageName:String) {
		isZipAtlas = false;
		zipSymbols = new Map();
		zipAnimations = new Map();
		zipFPS = new Map();
		zipLoop = new Map();
		zipOffsets = new Map();

		#if flxanimate
		// Prepare our atlas object (Psych Engine's version)
		atlas = new FlxAnimate();
		atlas.showPivot = false;
		#end

		var zipPath = Paths.modImages(imageName + ".zip");
		if (!FileSystem.exists(zipPath)) {
			// Not a zip atlas
			return;
		}

		var entries = readZip(zipPath);
		if (entries.keys().length == 0)
			return;

		// must contain data.json
		if (!entries.exists("data.json"))
			return;

		// Parse data.json
		var dataStr = entries.get("data.json").toString();
		var json:Dynamic = null;
		try {
			json = Json.parse(dataStr);
		} catch (e) {
			trace("ERROR parsing data.json in ZIP: " + e);
			return;
		}

		// symbols table (id → path)
		if (json.symbols != null) {
			for (sym in json.symbols) {
				if (sym.type == 0) // bitmap symbol
				{
					var idStr = Std.string(sym.id);
					var path:String = sym.path;
					if (path != null && entries.exists(path)) {
						var bmpBytes = entries.get(path);
						var bd = BitmapData.fromBytes(bmpBytes);
						zipSymbols.set(idStr, bd);
					}
				}
			}
		}

		// assets define animation timelines
		if (json.assets != null) {
			zipSymbolCount = 0;

			for (asset in json.assets) {
				var file:String = asset.file;
				var className:String = asset.className; // typically "idle", "singLEFT", etc.
				var symbols = asset.symbols;

				if (symbols == null || className == null)
					continue;

				// The animation timeline is stored inside asset.symbols
				// They represent one MovieClip timeline
				for (mc in symbols) {
					var mcId = Std.string(mc.id);
					var mcFrames = mc.frames;

					if (mcFrames == null)
						continue;

					var frameList:Array<Int> = [];
					var fps:Int = (mc.frameRate != null ? mc.frameRate : 24);
					var loop:Bool = (mc.loop != null ? mc.loop : true);

					// Parse frames sequence
					for (fr in mcFrames) {
						// Each frame has an array of "objects"
						// objects[].symbol resolves to a bitmap symbol ID
						if (fr.objects != null && fr.objects.length > 0) {
							var obj = fr.objects[0];
							var symbolId = Std.string(obj.symbol);
							frameList.push(Std.parseInt(symbolId));
						}
					}

					zipAnimations.set(className, frameList);
					zipFPS.set(className, fps);
					zipLoop.set(className, loop);

					zipSymbolCount++;
				}
			}
		}

		isZipAtlas = true;
	}

	// ===================================================================================
	// CHARACTER JSON + ATLAS FALLBACKS
	// ===================================================================================

	public function loadCharacterFile(json:Dynamic) {
		// -------------------------------------
		// Reset previous data
		// -------------------------------------
		isZipAtlas = false;
		#if flxanimate
		atlas = null;
		#end
		frames = null;
		zipSymbols = new Map();
		zipAnimations = new Map();
		zipFPS = new Map();
		zipLoop = new Map();
		zipOffsets = new Map();

		animationsArray = [];
		animOffsets = new Map<String, Array<Float>>();

		// -------------------------------------
		// Parse JSON core
		// -------------------------------------
		imageFile = json.image;
		jsonScale = json.scale;
		if (json.scale != 1) {
			scale.set(jsonScale, jsonScale);
			updateHitbox();
		}

		positionArray = json.position;
		cameraPosition = json.camera_position;
		healthIcon = json.healthicon;
		singDuration = json.sing_duration;
		flipX = (json.flip_x != isPlayer);
		healthColorArray = (json.healthbar_colors != null && json.healthbar_colors.length > 2) ? json.healthbar_colors : [161, 161, 161];
		vocalsFile = (json.vocals_file != null ? json.vocals_file : "");
		originalFlipX = (json.flip_x == true);
		editorIsPlayer = json._editor_isPlayer;

		noAntialiasing = (json.no_antialiasing == true);
		antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

		animationsArray = json.animations;

		// ===================================================================================
		// 1) ZIP ATLAS ATTEMPT FIRST
		// ===================================================================================
		loadZipAtlas(imageFile);

		if (!isZipAtlas) {
			// ===================================================================================
			// 2) REGULAR MULTI-ATLAS / SPARROW FALLBACK
			// ===================================================================================
			frames = Paths.getMultiAtlas(imageFile.split(","));
		}

		// ===================================================================================
		// Register animations for whichever system is active
		// ===================================================================================
		if (isZipAtlas) {
			// ----------------------------------------------------------
			// ZIP/ANIMATE MODE: JSON "animations" drives the timeline
			// ----------------------------------------------------------
			for (anim in animationsArray) {
				var key:String = anim.anim;
				var xmlName:String = anim.name;
				var fps:Int = anim.fps;
				var loop:Bool = anim.loop;
				var indices = anim.indices;

				// Use ZIP frames if animation exists
				if (zipAnimations.exists(key)) {
					// Accept indices override if provided
					if (indices != null && indices.length > 0) {
						var override:Array<Int> = [];
						for (i in indices)
							override.push(i);
						zipAnimations.set(key, override);
					}
					zipFPS.set(key, fps);
					zipLoop.set(key, loop);
				}

				// Offsets
				if (anim.offsets != null && anim.offsets.length >= 2)
					animOffsets.set(key, [anim.offsets[0], anim.offsets[1]]);
				else
					animOffsets.set(key, [0, 0]);
			}
		} else {
			// ----------------------------------------------------------
			// VANILLA MULTI-ATLAS MODE
			// ----------------------------------------------------------
			for (anim in animationsArray) {
				var key = anim.anim;
				var name = anim.name;
				var fps = anim.fps;
				var loop = anim.loop;

				if (anim.indices != null && anim.indices.length > 0)
					animation.addByIndices(key, name, anim.indices, "", fps, loop);
				else
					animation.addByPrefix(key, name, fps, loop);

				if (anim.offsets != null && anim.offsets.length >= 2)
					animOffsets.set(key, [anim.offsets[0], anim.offsets[1]]);
				else
					animOffsets.set(key, [0, 0]);
			}
		}

		// ZIP OFFSET Safety: if any animation exists without offsets, assign zeros
		if (isZipAtlas) {
			for (animKey in zipAnimations.keys()) {
				if (!animOffsets.exists(animKey))
					animOffsets.set(animKey, [0, 0]);
			}
		}

		// After finishing animation registration, prepare drawing
		if (isZipAtlas) {
			#if flxanimate
			setupZipAtlasDisplay();
			#end
		}
	}

	// ===================================================================================
	// ZIP → FlxAnimate DISPLAY INITIALIZATION (stub; finished in Part 4)
	// ===================================================================================
	#if flxanimate
	function setupZipAtlasDisplay() {
		if (atlas == null)
			return;

		// Set base properties
		atlas.antialiasing = antialiasing;

		x = x; // no-op to keep consistent
		y = y;

		atlas.x = this.x;
		atlas.y = this.y;
		atlas.scale.copyFrom(this.scale);
		atlas.angle = this.angle;

		// Actual frame step/draw implemented in Part 4
	}
	#end

	// ===================================================================================
	// ZIP ANIMATION PLAYBACK SYSTEM
	// Psych Engine 1.0.4 compatible
	// No BitmapData API, no unsupported FlxAnimate functions
	// Uses frame-based PNG stamping into a temp FlxSprite
	// ===================================================================================
	var zipAnim:String = "";
	var zipFrame:Int = 0;
	var zipTime:Float = 0;
	var zipFPS:Int = 24;
	var zipLoopFlag:Bool = true;
	var zipPlaying:Bool = false;

	// symbol PNG cache for drawing
	var zipFrameCache:Map<String, Map<Int, FlxSprite>> = new Map(); // symbol → frame → sprite

	// -------------------------------------------------------------------------
	// Retrieve a single ZIP symbol frame (as FlxSprite) — NO BitmapData
	// -------------------------------------------------------------------------
	function getZipFrame(symbol:String, frame:Int):FlxSprite {
		if (!zipSymbols.exists(symbol))
			return null;
		var all = zipSymbols.get(symbol);
		if (frame < 0 || frame >= all.length)
			return null;

		// CACHE
		if (!zipFrameCache.exists(symbol))
			zipFrameCache.set(symbol, new Map());

		if (zipFrameCache.get(symbol).exists(frame))
			return zipFrameCache.get(symbol).get(frame);

		// Create sprite
		var spr = new FlxSprite();
		spr.loadGraphic(all[frame]);
		spr.antialiasing = antialiasing;

		zipFrameCache.get(symbol).set(frame, spr);
		return spr;
	}

	// Total frames for symbol
	function getZipFrameCount(symbol:String):Int {
		return zipSymbols.exists(symbol) ? zipSymbols.get(symbol).length : 0;
	}

	// ===================================================================================
	// PLAY ANIMATION (ZIP overrides default system)
	// ===================================================================================
	override public function playAnim(name:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0) {
		// -------------------------------------------------------------------------
		// ZIP MODE
		// -------------------------------------------------------------------------
		if (isZipAtlas) {
			if (!zipAnimations.exists(name)) {
				// fall back to default animations if missing
				super.playAnim(name, Force, Reversed, Frame);
				zipPlaying = false;
				_lastPlayedAnimation = name;
				return;
			}

			zipAnim = name;
			_lastPlayedAnimation = name;

			zipFPS = 24;
			if (zipFPS.exists(name))
				zipFPS = zipFPS.get(name);

			zipLoopFlag = zipLoop.exists(name) ? zipLoop.get(name) : true;

			zipFrame = Frame;
			zipTime = 0;
			zipPlaying = true;

			// Offsets
			if (animOffsets.exists(name)) {
				var arr = animOffsets.get(name);
				offset.set(arr[0], arr[1]);
			} else
				offset.set(0, 0);

			return;
		}

		// -------------------------------------------------------------------------
		// Vanilla mode
		// -------------------------------------------------------------------------
		super.playAnim(name, Force, Reversed, Frame);
		_lastPlayedAnimation = name;

		if (animOffsets.exists(name)) {
			var arr = animOffsets.get(name);
			offset.set(arr[0], arr[1]);
		} else
			offset.set(0, 0);
	}

	// ===================================================================================
	// IS ANIMATION FINISHED
	// ===================================================================================
	public override function isAnimationFinished():Bool {
		if (isZipAtlas) {
			if (!zipPlaying)
				return true;

			var frames = zipAnimations.get(zipAnim);
			return zipFrame >= frames.length - 1 && !zipLoopFlag;
		} else
			return super.isAnimationFinished();
	}

	// ===================================================================================
	// IS ANIMATION NULL
	// ===================================================================================
	public override function isAnimationNull():Bool {
		if (isZipAtlas)
			return (zipAnim == "" || !zipPlaying);
		return super.isAnimationNull();
	}

	// ===================================================================================
	// UPDATE — frame stepping for ZIP
	// ===================================================================================
	override public function update(elapsed:Float) {
		if (isZipAtlas) {
			if (zipPlaying) {
				zipTime += elapsed;
				var spf:Float = 1.0 / zipFPS;

				while (zipTime >= spf) {
					zipTime -= spf;
					zipFrame++;

					var totalFrames = zipAnimations.get(zipAnim).length;

					if (zipFrame >= totalFrames) {
						if (zipLoopFlag)
							zipFrame = 0;
						else {
							zipFrame = totalFrames - 1;
							zipPlaying = false;
						}
					}
				}
			}

			super.update(elapsed);
			return;
		}

		super.update(elapsed);
	}

	// ===================================================================================
	// DRAW — ZIP rendering: stamp PNG frame into screen-space sprite
	// ===================================================================================
	override public function draw() {
		if (!isZipAtlas) {
			super.draw();
			return;
		}

		// ZIP SYMBOL DRAWING
		if (zipAnim == "" || !zipAnimations.exists(zipAnim)) {
			super.draw();
			return;
		}

		var frames = zipAnimations.get(zipAnim);
		var symbol = Std.string(frames[zipFrame]);
		var spr = getZipFrame(symbol, zipFrame);

		if (spr == null) {
			super.draw();
			return;
		}

		// Position/scale copied from self
		spr.x = this.x;
		spr.y = this.y;
		spr.scale.copyFrom(this.scale);
		spr.offset.copyFrom(this.offset);
		spr.angle = this.angle;
		spr.antialiasing = this.antialiasing;
		spr.cameras = this.cameras;

		spr.draw();
	}

	// ===================================================================================
	// DANCING, IDLES, HOLDTIMERS, MISS ANIMS, SPECIAL ANIMS
	// Psych Engine accurate behavior
	// ===================================================================================
	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var stunned:Bool = false;

	public var idleSuffix:String = "";
	public var danceIdle:Bool = false;
	public var skipDance:Bool = false;
	public var specialAnim:Bool = false;
	public var danced:Bool = false;

	public var hasMissAnimations:Bool = false;
	public var danceEveryNumBeats:Int = 1;

	var settingCharacterUp:Bool = true;

	// ===================================================================================
	// DANCE
	// ===================================================================================
	public function dance() {
		if (debugMode || skipDance || specialAnim)
			return;

		if (danceIdle) {
			// GF head-bopping
			danced = !danced;

			if (danced)
				playAnim("danceRight" + idleSuffix);
			else
				playAnim("danceLeft" + idleSuffix);
		} else {
			if (hasAnimation("idle" + idleSuffix))
				playAnim("idle" + idleSuffix);
		}
	}

	// ===================================================================================
	// RECALCULATE DANCE IDLE
	// ===================================================================================
	public function recalculateDanceIdle() {
		var last = danceIdle;
		danceIdle = (hasAnimation("danceLeft" + idleSuffix) && hasAnimation("danceRight" + idleSuffix));

		if (settingCharacterUp) {
			danceEveryNumBeats = danceIdle ? 1 : 2;
		} else if (last != danceIdle) {
			var calc = danceEveryNumBeats;
			if (danceIdle)
				calc /= 2;
			else
				calc *= 2;

			danceEveryNumBeats = Std.int(Math.max(calc, 1));
		}

		settingCharacterUp = false;
	}

	// ===================================================================================
	// HAS ANIMATION
	// ===================================================================================
	public function hasAnimation(anim:String):Bool {
		if (isZipAtlas)
			return zipAnimations.exists(anim);
		return animOffsets.exists(anim);
	}

	// ===================================================================================
	// UPDATE — dancing, missing anim fixes, special anim cleanup
	// ===================================================================================
	override public function update(elapsed:Float) {
		// ZIP mode pre-step
		if (isZipAtlas) {
			super.update(elapsed); // allows frame stepping from Part 4
			updateCharacterLogic(elapsed);
			return;
		}

		super.update(elapsed);
		updateCharacterLogic(elapsed);
	}

	// ===================================================================================
	// CORE LOGIC — separated so both ZIP and non-ZIP share the same behavior
	// ===================================================================================
	function updateCharacterLogic(elapsed:Float) {
		if (isAnimationNull())
			return;

		// ==============================================================
		// MISS FINISHED → Return to Idle
		// ==============================================================
		if (getAnimationName().endsWith("miss") && isAnimationFinished()) {
			dance();
			finishAnimation();
		}

		// ==============================================================
		// Special animations: hey/cheer
		// ==============================================================
		if (heyTimer > 0) {
			var rate:Float = (PlayState.instance != null ? PlayState.instance.playbackRate : 1.0);
			heyTimer -= elapsed * rate;

			if (heyTimer <= 0) {
				if (specialAnim && (getAnimationName() == "hey" || getAnimationName() == "cheer"))
					dance();

				specialAnim = false;
				heyTimer = 0;
			}
		} else if (specialAnim && isAnimationFinished()) {
			specialAnim = false;
			dance();
		}

		// ==============================================================
		// Speaker logic (Pico-speaker)
		// ==============================================================
		if (curCharacter == "pico-speaker") {
			if (animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0]) {
				var n = 1;
				if (animationNotes[0][1] > 2)
					n = 3;

				n += FlxG.random.int(0, 1);
				playAnim("shoot" + n, true);
				animationNotes.shift();
			}

			if (!isZipAtlas) {
				if (isAnimationFinished())
					playAnim(getAnimationName(), false, false, animation.curAnim.frames.length - 3);
			}
		}

		// ==============================================================
		// Hold timer (for singing)
		// ==============================================================
		if (getAnimationName().startsWith("sing")) {
			holdTimer += elapsed;
		} else if (isPlayer) {
			holdTimer = 0;
		}

		if (!isPlayer
			&& holdTimer >= Conductor.stepCrochet * (0.0011 #if FLX_PITCH / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1) #end) * singDuration) {
			dance();
			holdTimer = 0;
		}

		// ==============================================================
		// LOOP animations like "idle-loop"
		// ==============================================================
		var name = getAnimationName();
		if (isAnimationFinished() && hasAnimation(name + "-loop"))
			playAnim(name + "-loop");
	}

	// ===================================================================================
	// JSON SAVE (for Character Editor)
	// ===================================================================================

	public function buildEditorJson():Dynamic {
		var out:Dynamic = {
			name: curCharacter,
			image: imageFile,
			scale: jsonScale,
			sing_duration: singDuration,
			flip_x: originalFlipX,
			no_antialiasing: noAntialiasing,
			position: positionArray,
			camera_position: cameraPosition,
			healthicon: healthIcon,
			healthbar_colors: healthColorArray,
			vocals_file: vocalsFile,
			_editor_isPlayer: editorIsPlayer,
			animations: []
		};

		for (anim in animationsArray) {
			out.animations.push({
				anim: anim.anim,
				name: anim.name,
				fps: anim.fps,
				loop: anim.loop,
				indices: anim.indices,
				offsets: anim.offsets
			});
		}

		return out;
	}

	// ===================================================================================
	// ZIP CLEANUP
	// ===================================================================================

	function clearZipCache() {
		if (!isZipAtlas)
			return;

		zipAnimations = new Map();
		zipSymbols = new Map();
		zipOffsets = new Map();
		zipFPS = new Map();
		zipLoop = new Map();
		zipFrameCache = new Map();

		zipAnim = "";
		zipFrame = 0;
		zipTime = 0;
		zipFPS = 24;
		zipLoopFlag = true;
		zipPlaying = false;

		isZipAtlas = false;
	}

	// ===================================================================================
	// DESTROY
	// ===================================================================================

	override public function destroy() {
		clearZipCache();

		#if flxanimate
		atlas = null;
		#end

		animOffsets = null;
		animationsArray = null;
		animationNotes = null;

		super.destroy();
	}

	// ===================================================================================
	// CHARACTER END
	// ===================================================================================
}
