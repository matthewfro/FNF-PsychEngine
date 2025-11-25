package objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import backend.Paths;
import backend.ClientPrefs;
import backend.animation.PsychAnimationController;
import states.PlayState;
import states.stages.objects.TankmenBG;
import backend.Song;
import backend.Song.SwagSong;
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import sys.io.File;
import sys.FileSystem;
import haxe.zip.Reader;
import haxe.zip.Entry;
import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;
import openfl.geom.Matrix;
import openfl.geom.ColorTransform;

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

class Character extends FlxSprite {
	// ====================================================
	// CORE FIELDS
	// ====================================================
	public static inline final DEFAULT_CHARACTER:String = "bf";

	public var animOffsets:Map<String, Array<Dynamic>> = new Map();
	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;
	public var debugMode:Bool = false;

	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var stunned:Bool = false;
	public var skipDance:Bool = false;
	public var danceIdle:Bool = false;
	public var danced:Bool = false;
	public var idleSuffix:String = '';
	public var singDuration:Float = 4;

	public var healthIcon:String = "face";
	public var animationsArray:Array<AnimArray> = [];
	public var animationNotes:Array<Dynamic> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];
	public var healthColorArray:Array<Int> = [255, 0, 0];

	public var missingCharacter:Bool = false;
	public var missingText:FlxText;
	public var hasMissAnimations:Bool = false;
	public var vocalsFile:String = '';
	public var jsonScale:Float = 1;
	public var imageFile:String = '';
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;
	public var editorIsPlayer:Null<Bool> = null;

	// ====================================================
	// ZIP SYSTEM
	// ====================================================
	public var isZip:Bool = false;
	public var zipIsAnimate:Bool = false;
	public var zipIsSpritesheet:Bool = false;

	public var zipSymbols:Array<String> = [];
	public var zipFrames:Map<String, Array<BitmapData>> = new Map();
	public var animateMap:Map<String, Array<Int>> = new Map();

	public var zipSpritesheetPNG:BitmapData = null;
	public var zipSpritesheetXML:String = null;

	private var _zipFrame:Int = 0;

	private var _lastPlayedAnimation:String = "";

	public var isAnimateAtlas:Bool = false;

	#if flxanimate
	public var atlas:FlxAnimate;
	#end

	public var animateData:String = null;
	public var libraryData:String = null;

	public var spritePNG:Bytes = null;
	public var spriteXML:String = null;

	// NEW (REQUIRED)
	public var zipLibrary:Dynamic = null;
	public var zipData:Dynamic = null;

	// ====================================================
	// CONSTRUCTOR
	// ====================================================

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false) {
		super(x, y);

		animation = new PsychAnimationController(this);

		animOffsets = new Map<String, Array<Dynamic>>();
		this.isPlayer = isPlayer;

		changeCharacter(character);

		switch (curCharacter) {
			case 'pico-speaker':
				skipDance = true;
				loadMappedAnims();
				playAnim("shoot1");
			case 'pico-blazin', 'darnell-blazin':
				skipDance = true;
		}
	}

	// ====================================================
	// CHANGE CHARACTER
	// ====================================================

	public function changeCharacter(character:String) {
		animationsArray = [];
		animOffsets = [];
		curCharacter = character;
		var characterPath:String = 'characters/$character.json';

		var path:String = Paths.getPath(characterPath, TEXT);
		#if MODS_ALLOWED
		if (!FileSystem.exists(path))
		#else
		if (!Assets.exists(path))
		#end
		{
			path = Paths.getSharedPath('characters/' + DEFAULT_CHARACTER +
				'.json'); // If a character couldn't be found, change him to BF just to prevent a crash
			missingCharacter = true;
			missingText = new FlxText(0, 0, 300, 'ERROR:\n$character.json', 16);
			missingText.alignment = CENTER;
		}

		try {
			#if MODS_ALLOWED
			loadCharacterFile(Json.parse(File.getContent(path)));
			#else
			loadCharacterFile(Json.parse(Assets.getText(path)));
			#end
		} catch (e:Dynamic) {
			trace('Error loading character file of "$character": $e');
		}

		skipDance = false;
		hasMissAnimations = hasAnimation('singLEFTmiss') || hasAnimation('singDOWNmiss') || hasAnimation('singUPmiss') || hasAnimation('singRIGHTmiss');
		recalculateDanceIdle();
		dance();
	}

	// ====================================================
	// LOAD CHARACTER JSON
	// ====================================================

	public function loadCharacterFile(json:Dynamic):Void {
		// Reset
		isZip = false;
		zipIsAnimate = false;
		zipIsSpritesheet = false;
		zipSymbols = [];
		zipFrames = new Map();
		animateMap = new Map();
		zipSpritesheetPNG = null;
		zipSpritesheetXML = null;

		isAnimateAtlas = false;

		imageFile = json.image;
		jsonScale = json.scale;

		//--------------------------------------------------
		// 1. ZIP
		//--------------------------------------------------
		var zipPath = Paths.getPath('images/${imageFile}.zip', TEXT);

		#if MODS_ALLOWED
		var hasZip = FileSystem.exists(zipPath);
		#else
		var hasZip = Assets.exists(zipPath);
		#end

		if (hasZip) {
			isZip = true;
			loadZIP(zipPath);
		}

		//--------------------------------------------------
		// 2. Animate Atlas
		//--------------------------------------------------
		#if flxanimate
		if (!isZip) {
			var animJSON = Paths.getPath('images/' + imageFile + '/Animation.json', TEXT);
			var foundAnim = #if MODS_ALLOWED FileSystem.exists(animJSON) #else Assets.exists(animJSON) #end;

			if (foundAnim) {
				isAnimateAtlas = true;
				loadAnimateAtlas(json.image);
			}
		}
		#end

		//--------------------------------------------------
		// 3. MultiAtlas
		//--------------------------------------------------
		if (!isZip && !isAnimateAtlas) {
			loadPNGXMLOrMultiAtlas(json.image);
		}

		//--------------------------------------------------
		// Apply core fields
		//--------------------------------------------------
		scale.set(jsonScale, jsonScale);
		updateHitbox();

		positionArray = json.position;
		cameraPosition = json.camera_position;

		healthIcon = json.healthicon;
		singDuration = json.sing_duration;
		vocalsFile = json.vocals_file != null ? json.vocals_file : '';
		healthColorArray = json.healthbar_colors != null ? json.healthbar_colors : [161, 161, 161];

		noAntialiasing = json.no_antialiasing == true;
		antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

		originalFlipX = json.flip_x;
		editorIsPlayer = json._editor_isPlayer;
		flipX = (json.flip_x != isPlayer);

		//--------------------------------------------------
		// Load animations
		//--------------------------------------------------
		animationsArray = json.animations;

		for (anim in animationsArray) {
			if (!isZip && !isAnimateAtlas) {
				if (anim.indices != null && anim.indices.length > 0)
					animation.addByIndices(anim.anim, anim.name, anim.indices, "", anim.fps, anim.loop);
				else
					animation.addByPrefix(anim.anim, anim.name, anim.fps, anim.loop);
			}

			#if flxanimate
			if (isAnimateAtlas) {
				if (anim.indices != null && anim.indices.length > 0)
					atlas.anim.addBySymbolIndices(anim.anim, anim.name, anim.indices, anim.fps, anim.loop);
				else
					atlas.anim.addBySymbol(anim.anim, anim.name, anim.fps, anim.loop);
			}
			#end

			if (anim.offsets != null && anim.offsets.length > 1)
				addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
			else
				addOffset(anim.anim, 0, 0);
		}

		danceIdle = (hasAnimation('danceLeft') && hasAnimation('danceRight'));
	}

	// ====================================================
	// UPDATE
	// ====================================================

	override function update(elapsed:Float) {
		#if flxanimate
		if (isAnimateAtlas)
			atlas.update(elapsed);
		#end

		if (debugMode || isAnimationNull()) {
			super.update(elapsed);
			return;
		}

		// Hey timer
		if (heyTimer > 0) {
			var rate:Float = (PlayState.instance != null ? PlayState.instance.playbackRate : 1.0);
			heyTimer -= elapsed * rate;

			if (heyTimer <= 0) {
				var name = getAnimationName();
				if (specialAnim && (name == "hey" || name == "cheer")) {
					specialAnim = false;
					dance();
				}
				heyTimer = 0;
			}
		} else if (specialAnim && isAnimationFinished()) {
			specialAnim = false;
			dance();
		} else if (getAnimationName().endsWith("miss") && isAnimationFinished()) {
			dance();
			finishAnimation();
		}

		// Pico-speaker
		switch (curCharacter) {
			case "pico-speaker":
				if (animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0]) {
					var nd:Int = (animationNotes[0][1] > 2) ? 3 : 1;
					nd += FlxG.random.int(0, 1);

					playAnim("shoot" + nd, true);
					animationNotes.shift();
				}

				if (isAnimationFinished())
					playAnim(getAnimationName(), false, false, animation.curAnim.frames.length - 3);
		}

		// Hold logic
		if (getAnimationName().startsWith("sing"))
			holdTimer += elapsed;
		else if (isPlayer)
			holdTimer = 0;

		if (!isPlayer) {
			var limit = Conductor.stepCrochet * 0.0011;
			#if FLX_PITCH
			if (FlxG.sound.music != null)
				limit /= FlxG.sound.music.pitch;
			#end

			if (holdTimer >= limit * singDuration) {
				dance();
				holdTimer = 0;
			}
		}

		super.update(elapsed);
	}

	inline public function isAnimationNull():Bool {
		#if flxanimate
		if (isAnimateAtlas)
			return atlas.anim.curInstance == null || atlas.anim.curSymbol == null;
		#end

		return animation.curAnim == null;
	}

	inline public function getAnimationName():String {
		return _lastPlayedAnimation;
	}

	public function isAnimationFinished():Bool {
		if (isAnimationNull())
			return false;

		#if flxanimate
		if (isAnimateAtlas)
			return atlas.anim.finished;
		#end

		return animation.curAnim.finished;
	}

	public function finishAnimation():Void {
		if (isAnimationNull())
			return;

		#if flxanimate
		if (isAnimateAtlas) {
			atlas.anim.curFrame = atlas.anim.length - 1;
			return;
		}
		#end

		animation.curAnim.finish();
	}

	public function hasAnimation(anim:String):Bool {
		return animOffsets.exists(anim);
	}

	// ====================================================
	// animPaused property
	// ====================================================
	public var animPaused(get, set):Bool;

	private function get_animPaused():Bool {
		if (isAnimationNull())
			return false;

		#if flxanimate
		if (isAnimateAtlas)
			return !atlas.anim.isPlaying;
		#end

		return animation.curAnim.paused;
	}

	private function set_animPaused(v:Bool):Bool {
		if (isAnimationNull())
			return v;

		#if flxanimate
		if (isAnimateAtlas) {
			if (v)
				atlas.animation.paused = v; // v = true means pause
			return v;
		}
		#end

		animation.curAnim.paused = v;
		return v;
	}

	// ====================================================
	// DANCE
	// ====================================================

	public function dance() {
		if (!debugMode && !skipDance && !specialAnim) {
			if (danceIdle) {
				danced = !danced;
				playAnim((danced ? 'danceRight' : 'danceLeft') + idleSuffix);
			} else if (hasAnimation('idle' + idleSuffix))
				playAnim('idle' + idleSuffix);
		}
	}

	// ====================================================
	// PLAY ANIMATION
	// ====================================================

	public function playAnim(name:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void {
		specialAnim = false;

		#if flxanimate
		if (isAnimateAtlas) {
			atlas.anim.play(name, Force, Reversed, Frame);
			atlas.update(0);
		} else
		#end
		{
			animation.play(name, Force, Reversed, Frame);
		}

		_lastPlayedAnimation = name;

		if (hasAnimation(name)) {
			var off = animOffsets.get(name);
			offset.set(off[0], off[1]);
		}

		if (curCharacter.startsWith("gf-") || curCharacter == "gf") {
			if (name == "singLEFT")
				danced = true;
			else if (name == "singRIGHT")
				danced = false;
			else if (name == "singUP" || name == "singDOWN")
				danced = !danced;
		}
	}

	// ====================================================
	// OFFSET
	// ====================================================

	public function addOffset(name:String, x:Float = 0, y:Float = 0) {
		animOffsets.set(name, [x, y]);
	}

	// ====================================================
	// LOAD MAPPED ANIMS (PICO SPEAKER)
	// ====================================================

	function loadMappedAnims():Void {
		try {
			var songData:SwagSong = Song.getChart('picospeaker', Paths.formatToSongPath(Song.loadedSongName));
			if (songData != null) {
				for (section in songData.notes)
					for (sn in section.sectionNotes)
						animationNotes.push(sn);
			}

			TankmenBG.animationNotes = animationNotes;
			animationNotes.sort(sortAnims);
		} catch (e:Dynamic) {}
	}

	function sortAnims(a:Array<Dynamic>, b:Array<Dynamic>):Int {
		if (a[0] < b[0])
			return -1;
		if (a[0] > b[0])
			return 1;
		return 0;
	}

	public var danceEveryNumBeats:Int = 2;

	private var settingCharacterUp:Bool = true;

	public function recalculateDanceIdle() {
		var lastDanceIdle:Bool = danceIdle;
		danceIdle = (hasAnimation('danceLeft' + idleSuffix) && hasAnimation('danceRight' + idleSuffix));

		if (settingCharacterUp) {
			danceEveryNumBeats = (danceIdle ? 1 : 2);
		} else if (lastDanceIdle != danceIdle) {
			var calc:Float = danceEveryNumBeats;
			if (danceIdle)
				calc /= 2;
			else
				calc *= 2;

			danceEveryNumBeats = Math.round(Math.max(calc, 1));
		}
		settingCharacterUp = false;
	}

	public function quickAnimAdd(name:String, anim:String) {
		animation.addByPrefix(name, anim, 24, false);
	}

	// ====================================================
	// MultiAtlas Loader
	// ====================================================

	private function loadPNGXMLOrMultiAtlas(image:String):Void {
		frames = Paths.getMultiAtlas(image.split(","));
	}

	// ====================================================
	// Animate Atlas
	// ====================================================
	#if flxanimate
	private function loadAnimateAtlas(image:String):Void {
		atlas = new FlxAnimate();
		atlas.showPivot = false;

		try
			Paths.loadAnimateAtlas(atlas, image)
		catch (e:Dynamic)
			FlxG.log.warn('Could not load Animate atlas: $image -> $e');
	}
	#end

	// ====================================================
	// ZIP LOADING
	// ====================================================

	public function loadZIP(path:String):Void {
		var bytes:Bytes = #if MODS_ALLOWED File.getBytes(path) #else Assets.getBytes(path) #end;
		var reader = new Reader(new BytesInput(bytes));
		var data = entry.data; // Bytes

		var list = reader.read(); // List<haxe.zip.Entry>

		for (entry in list) // <--- this defines entry correctly
		{
			var fn:String = entry.fileName.toLowerCase();
			var bytes:Bytes = entry.data; // <--- safe, correct API

			switch (fn) {
				case "data.json":
					animateData = bytes.toString();

				case "library.json":
					libraryData = bytes.toString();

				default:
					// Load XML
					if (fn.endsWith(".xml"))
						spriteXML = bytes.toString();

					// Load PNG bytes
					if (fn.endsWith(".png"))
						spritePNG = bytes;
			}
		}

		var animateData:String = null;
		var libraryData:String = null;
		var spritePNG:Bytes = null;
		var spriteXML:String = null;

		zipLibrary = null;
		zipData = null;

		for (entry in list) {
			var fn = entry.fileName.toLowerCase();
			var bytes = entry.data;

			if (fn == "data.json")
				animateData = bytes.toString();
			if (fn == "library.json")
				libraryData = bytes.toString();

			if (StringTools.startsWith(fn, "symbols/") && StringTools.endsWith(fn, ".png")) {
				var name = fn.substring(8, fn.length - 4);
				var bytes = entry.data;
				var bmp = BitmapData.fromBytes(bytes);

				if (!zipSymbols.contains(name))
					zipSymbols.push(name);

				if (!zipFrames.exists(name))
					zipFrames.set(name, []);

				zipFrames.get(name).push(bmp);
			}

			if (fn == "spritemap.png")
				spritePNG = bytes; // bytes is already PNG data

			if (fn == "spritemap.xml" || fn == "spritesheet.xml")
				spriteXML = bytes.toString();
		}

		if (animateData != null) {
			zipIsAnimate = true;
			zipData = Json.parse(animateData);

			if (libraryData != null)
				zipLibrary = Json.parse(libraryData);

			loadAnimateZIP();
			return;
		}

		if (spritePNG != null && spriteXML != null) {
			zipIsSpritesheet = true;
			loadSpritesheetZIP(spritePNG, spriteXML);
			return;
		}

		isZip = false;
	}

	private function loadAnimateZIP():Void {
		frames = null;
		animateMap = new Map();

		if (zipData.animations != null) {
			for (field in Reflect.fields(zipData.animations)) {
				var arr:Array<Int> = [];
				var obj = Reflect.field(zipData.animations, field);

				if (obj.frames != null) {
					var frames:Array<Dynamic> = cast obj.frames;
					for (f in frames)
						arr.push(f);
				}

				animateMap.set(field, arr);
			}
		}
	}

	private function loadSpritesheetZIP(png:Bytes, xml:String):Void {
		var bmp = BitmapData.fromBytes(png);
		frames = FlxAtlasFrames.fromSparrow(bmp, xml);
	}

	// ====================================================
	// ANIMATE ZIP DRAW HELPERS
	// ====================================================

	private function getSymbolMatrix(symbol:String, frame:Int):Matrix {
		if (zipLibrary == null)
			return null;
		if (!Reflect.hasField(zipLibrary.symbols, symbol))
			return null;

		var sym = Reflect.field(zipLibrary.symbols, symbol);

		if (!Reflect.hasField(sym, "timeline"))
			return null;

		var layers = sym.timeline.layers;
		if (layers == null || layers.length == 0)
			return null;

		var layer = layers[0];
		var framesArr = layer.frames;

		if (frame < 0 || frame >= framesArr.length)
			frame = framesArr.length - 1;

		var frameData = framesArr[frame];
		if (frameData == null || frameData.elements == null || frameData.elements.length == 0)
			return null;

		var elem = frameData.elements[0];
		if (elem == null || elem.matrix == null)
			return null;

		var m = new Matrix();
		m.a = elem.matrix[0];
		m.b = elem.matrix[1];
		m.c = elem.matrix[2];
		m.d = elem.matrix[3];
		m.tx = elem.matrix[4];
		m.ty = elem.matrix[5];

		return m;
	}

	private function getFrame():Int {
		return _zipFrame;
	}

	private function getZipBitmap(anim:String, frame:Int):BitmapData {
		if (!zipFrames.exists(anim))
			return null;
		var arr = zipFrames.get(anim);
		if (arr.length == 0)
			return null;

		if (frame < 0)
			frame = 0;
		if (frame >= arr.length)
			frame = arr.length - 1;

		return arr[frame];
	}

	// ====================================================
	// DRAW OVERRIDE
	// ====================================================

	override public function draw() {
		var lastAlpha = alpha;
		var lastColor = color;

		// Animate Atlas
		#if flxanimate
		if (isAnimateAtlas) {
			if (atlas.anim.curInstance != null) {
				copyAtlasValues();
				atlas.draw();
			}

			alpha = lastAlpha;
			color = lastColor;

			if (missingCharacter && visible) {
				missingText.x = getMidpoint().x - 150;
				missingText.y = getMidpoint().y - 10;
				missingText.draw();
			}

			return;
		}
		#end

		if (!isZip || zipIsSpritesheet) {
			super.draw();

			if (missingCharacter && visible) {
				alpha = lastAlpha;
				color = lastColor;
				missingText.x = getMidpoint().x - 150;
				missingText.y = getMidpoint().y - 10;
				missingText.draw();
			}

			return;
		}

		// ZIP ANIMATE MODE
		var anim = getAnimationName();
		var frame = getFrame();
		var bmp = getZipBitmap(anim, frame);

		if (bmp == null) {
			super.draw();
			return;
		}

		var mat = getSymbolMatrix(anim, frame);
		var m = new Matrix();

		if (mat != null)
			m.concat(mat);

		m.scale(scale.x, scale.y);
		m.translate(x - offset.x, y - offset.y);

		FlxG.camera.buffer.draw(bmp, m, colorTransform);

		alpha = lastAlpha;
		color = lastColor;
	}

	// ====================================================
	// COPY ATLAS VALUES
	// ====================================================

	public function copyAtlasValues() {
		#if flxanimate
		@:privateAccess
		{
			atlas.cameras = cameras;
			atlas.scrollFactor = scrollFactor;
			atlas.scale = scale;
			atlas.offset = offset;
			atlas.origin = origin;
			atlas.x = x;
			atlas.y = y;
			atlas.angle = angle;
			atlas.alpha = alpha;
			atlas.visible = visible;
			atlas.flipX = flipX;
			atlas.flipY = flipY;
			atlas.shader = shader;
			atlas.antialiasing = antialiasing;
			atlas.colorTransform = colorTransform;
			atlas.color = color;
		}
		#end
	}

	#if flxanimate
	override public function destroy() {
		atlas = FlxDestroyUtil.destroy(atlas);
		super.destroy();
	}
	#end
}
