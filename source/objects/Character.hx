package objects;

import backend.animation.PsychAnimationController;
import flixel.util.FlxDestroyUtil;
import flixel.util.FlxSort;
import openfl.utils.Assets;
import openfl.utils.AssetType;
import haxe.Json;
import haxe.io.Bytes;
import haxe.zip.Reader;
import sys.io.File;
import sys.FileSystem;
#if flxanimate
import flxanimate.FlxAnimate;
#end
#if MODS_ALLOWED
import sys.io.File;
#end

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
	/** fallback */
	public static final DEFAULT_CHARACTER:String = 'bf';

	// ----------------------------------
	// VARS
	// ----------------------------------
	public var animOffsets:Map<String, Array<Dynamic>> = [];
	public var extraData:Map<String, Dynamic> = new Map();
	public var debugMode:Bool = false;

	public var curCharacter:String = DEFAULT_CHARACTER;
	public var isPlayer:Bool = false;

	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var stunned:Bool = false;

	public var singDuration:Float = 4;
	public var idleSuffix:String = '';
	public var danceIdle:Bool = false;
	public var skipDance:Bool = false;

	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];

	public var healthIcon:String = 'face';
	public var healthColorArray:Array<Int> = [255, 0, 0];

	public var vocalsFile:String = '';

	public var jsonScale:Float = 1;
	public var originalFlipX:Bool = false;
	public var noAntialiasing:Bool = false;

	public var editorIsPlayer:Null<Bool> = null;
	public var missingCharacter:Bool = false;
	public var missingText:FlxText;

	public var animationNotes:Array<Dynamic> = [];

	// Animate Atlas + ZIP support
	public var isAnimateAtlas(default, null):Bool = false;
	public var isAnimateZip(default, null):Bool = false;

	#if flxanimate
	public var atlas:FlxAnimate;
	#end

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false) {
		super(x, y);
		this.isPlayer = isPlayer;

		animation = new PsychAnimationController(this);

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

	// ================================================================
	// CHANGE CHARACTER
	// ================================================================
	public function changeCharacter(character:String) {
		animationsArray = [];
		animOffsets = [];
		curCharacter = character;

		var basePath = 'characters/$character.json';
		var path = Paths.getPath(basePath, TEXT);

		#if MODS_ALLOWED
		var exists = FileSystem.exists(path);
		#else
		var exists = Assets.exists(path);
		#end

		if (!exists) {
			path = Paths.getSharedPath('characters/' + DEFAULT_CHARACTER + '.json');
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
		} catch (e) {
			trace('Error loading character $character: $e');
		}

		skipDance = false;
		recalcMissAnimations();
		recalculateDanceIdle();
		dance();
	}

	inline function recalcMissAnimations() {
		hasMissAnimations = hasAnimation('singLEFTmiss') || hasAnimation('singDOWNmiss') || hasAnimation('singUPmiss') || hasAnimation('singRIGHTmiss');
	}

	// ================================================================
	// FILE LOADING (JSON / ATLAS / ZIP)
	// ================================================================
	public function loadCharacterFile(json:Dynamic) {
		isAnimateAtlas = false;
		isAnimateZip = false;

		var image:String = json.image;
		imageFile = image;

		// 1. ZIP detection (mods/images/IMAGE.zip)
		#if MODS_ALLOWED
		var zipPath = Paths.getModPath('images/' + image + '.zip');
		if (FileSystem.exists(zipPath)) {
			loadZipCharacter(zipPath);
			isAnimateZip = true;
		}
		#end

		// 2. Animate Atlas detection (Animation.json)
		if (!isAnimateZip
			&& #if MODS_ALLOWED FileSystem.exists(Paths.getPath('images/' + image + '/Animation.json',
				TEXT)) #else Assets.exists(Paths.getPath('images/' + image + '/Animation.json', TEXT)) #end) {
			loadAnimateAtlas(image);
			isAnimateAtlas = true;
		}

		// 3. Standard PNG+XML Frames
		if (!isAnimateAtlas && !isAnimateZip) {
			frames = Paths.getMultiAtlas(image.split(','));
		}

		// ----------------------------------------------
		// Apply JSON properties
		// ----------------------------------------------
		jsonScale = json.scale;
		if (json.scale != 1) {
			scale.set(json.scale, json.scale);
			updateHitbox();
		}

		positionArray = json.position;
		cameraPosition = json.camera_position;

		healthIcon = json.healthicon;
		singDuration = json.sing_duration;
		flipX = (json.flip_x != isPlayer);
		originalFlipX = json.flip_x;

		noAntialiasing = json.no_antialiasing;
		antialiasing = ClientPrefs.data.antialiasing && !noAntialiasing;

		healthColorArray = json.healthbar_colors;
		vocalsFile = json.vocals_file;

		editorIsPlayer = json._editor_isPlayer;

		animationsArray = json.animations;

		// Load animations from JSON
		addAnimationsFromJSON();

		#if flxanimate
		if (isAnimateAtlas || isAnimateZip)
			copyAtlasValues();
		#end
	}

	// ================================================================
	// LOAD ZIP (data.json + library.json + symbols/)
	// ================================================================
	#if MODS_ALLOWED
	function loadZipCharacter(zipPath:String) {
		try {
			var bytes = File.getBytes(zipPath);
			var reader = new Reader(new haxe.io.BytesInput(bytes));
			var entries = reader.read();

			var tempDir = Paths.getModPath('images/__temp_zip_' + curCharacter + "/");

			if (!FileSystem.exists(tempDir))
				FileSystem.createDirectory(tempDir);

			for (entry in entries) {
				var outPath = tempDir + entry.fileName;
				var dir = haxe.io.Path.directory(outPath);

				if (!FileSystem.exists(dir))
					FileSystem.createDirectory(dir);

				File.saveBytes(outPath, entry.data);
			}

			// Now load data.json + library.json with FlxAnimate
			var dataPath = tempDir + "data.json";
			var libraryPath = tempDir + "library.json";

			if (FileSystem.exists(dataPath) && FileSystem.exists(libraryPath)) {
				#if flxanimate
				atlas = new FlxAnimate();
				atlas.showPivot = false;

				atlas.loadFromAnimateFolder(tempDir);
				isAnimateZip = true;
				#end
			}
		} catch (e) {
			trace("ZIP load failed: " + e);
		}
	}
	#end

	// ================================================================
	// LOAD FLXANIMATE ATLAS
	// ================================================================
	#if flxanimate
	function loadAnimateAtlas(image:String) {
		atlas = new FlxAnimate();
		atlas.showPivot = false;

		try {
			Paths.loadAnimateAtlas(atlas, image);
		} catch (e) {
			FlxG.log.warn('Could not load Animate atlas for ' + image + ": " + e);
		}
	}
	#end

	// ================================================================
	// ADD ANIMATIONS FROM JSON
	// ================================================================
	public function addAnimationsFromJSON() {
		for (anim in animationsArray) {
			// add animation:
			addAnimation(anim.anim, anim.name, anim.fps, anim.loop, anim.indices);

			// apply stored offsets
			addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
		}

		// Special idle suffix logic (like week 6 characters)
		recalculateDanceIdle();
	}

	// Add offset to animOffsets map + controller
	public function addOffset(name:String, x:Float, y:Float) {
		animOffsets.set(name, [x, y]);
		animation.addOffset(name, x, y);
	}

	inline public function hasAnimation(name:String):Bool {
		if (!isAnimateAtlas && !isAnimateZip)
			return animation.animExists(name);

		#if flxanimate
		return atlas != null && atlas.anim.hasAnimation(name);
		#else
		return false;
		#end
	}

	// ================================================================
	// PLAY ANIMATION (ZIP, ATLAS, PNG)
	// ================================================================
	public function playAnim(name:String, force:Bool = false, reversed:Bool = false, frame:Int = 0) {
		specialAnim = (name.startsWith("hey") || name.startsWith("sing") || name.contains("special"));

		holdTimer = 0;

		if (!isAnimateAtlas && !isAnimateZip) {
			// Standard psych animation controller
			animation.play(name, force, reversed, frame);
		} else {
			#if flxanimate
			if (atlas != null) {
				atlas.anim.play(name, force, reversed, frame);
				atlas.anim.curFrame = frame;

				// Sync this sprite size to frame bounds
				this.offset.set(0, 0);
			}
			#end
		}

		// Apply offsets
		if (animOffsets.exists(name)) {
			var arr = animOffsets.get(name);
			offset.set(arr[0], arr[1]);
		}

		// Handle flip for players
		flipX = (originalFlipX != isPlayer);
	}

	// ================================================================
	// DANCE IDLE LOGIC (BOPPING)
	// ================================================================
	inline function recalculateDanceIdle() {
		danceIdle = hasAnimation('idle') || hasAnimation('danceLeft');
	}

	public function dance() {
		if (skipDance)
			return;

		if (hasAnimation('idle')) {
			playAnim('idle' + idleSuffix, true);
		} else if (hasAnimation('danceLeft')) {
			playAnim('danceLeft', true);
		} else {
			// No dance animations found
		}
	}

	// Called once animation should stop forcing itself
	public function finishAnimation() {
		specialAnim = false;
	}

	// ================================================================
	// MISS ANIMATION LOGIC
	// ================================================================
	public var hasMissAnimations:Bool = false;

	public function recalcMiss() {
		hasMissAnimations = hasAnimation('singLEFTmiss') || hasAnimation('singDOWNmiss') || hasAnimation('singUPmiss') || hasAnimation('singRIGHTmiss');
	}

	public function playSing(dir:Int, miss:Bool) {
		var suffix = '';
		switch dir {
			case 0:
				suffix = 'LEFT';
			case 1:
				suffix = 'DOWN';
			case 2:
				suffix = 'UP';
			case 3:
				suffix = 'RIGHT';
		}

		var animName = "sing" + suffix + (miss ? "miss" : "");

		if (hasAnimation(animName)) {
			playAnim(animName, true);
		} else if (!miss) {
			// fallback if no miss anim exists
			playAnim('sing' + suffix, true);
		}

		holdTimer = 0;
	}

	// ================================================================
	// UPDATE (ATLAS + PNG COMPAT)
	// ================================================================
	override public function update(elapsed:Float) {
		super.update(elapsed);

		#if flxanimate
		if (isAnimateAtlas || isAnimateZip) {
			if (atlas != null) {
				atlas.update(elapsed);

				// Sync the FlxSprite's graphic from the atlas current frame
				var bmp = atlas.getBitmap();
				if (bmp != null)
					this.pixels = bmp;

				updateHitbox();
			}
		}
		#end

		// Singing hold logic
		if (specialAnim) {
			holdTimer += elapsed;
			if (holdTimer >= singDuration) {
				holdTimer = 0;
				finishAnimation();
				dance();
			}
		}

		// 'Hey' animation timeout
		if (heyTimer > 0) {
			heyTimer -= elapsed;
			if (heyTimer <= 0) {
				heyTimer = 0;
				finishAnimation();
				dance();
			}
		}
	}

	// ================================================================
	// ON BEAT UPDATE
	// ================================================================
	public function beatHit() {
		if (!specialAnim && danceIdle) {
			dance();
		}
	}

	// ================================================================
	// COPY ATLAS VALUES -> HITBOX / SCALE SYNC
	// ================================================================
	#if flxanimate
	inline function copyAtlasValues() {
		if (atlas == null)
			return;

		var bmp = atlas.getBitmap();
		if (bmp != null)
			this.pixels = bmp;

		updateHitbox();

		// Respect JSON scale
		scale.set(jsonScale, jsonScale);
		updateHitbox();
	}
	#end

	// ================================================================
	// DRAW (ATLAS + ZIP + PNG)
	// ================================================================
	#if flxanimate
	override public function draw() {
		var lastAlpha = alpha;
		var lastColor = color;

		// Missing character tint
		if (missingCharacter) {
			alpha = 0.6;
			color = FlxColor.BLACK;
		}

		if (isAnimateAtlas || isAnimateZip) {
			if (atlas != null) {
				// Sync atlas sprite state
				atlas.x = x;
				atlas.y = y;
				atlas.offset.set(offset.x, offset.y);
				atlas.scale.set(scale.x, scale.y);
				atlas.antialiasing = antialiasing;
				atlas.flipX = flipX;
				atlas.flipY = flipY;
				atlas.scrollFactor.set(scrollFactor.x, scrollFactor.y);
				atlas.visible = visible;
				atlas.alpha = lastAlpha;
				atlas.color = lastColor;
				atlas.shader = shader;

				atlas.draw();
			}

			// Draw missing text
			if (missingCharacter && visible) {
				missingText.x = getMidpoint().x - 150;
				missingText.y = getMidpoint().y - 10;
				missingText.draw();
			}

			alpha = lastAlpha;
			color = lastColor;
			return;
		}

		// Regular sprite drawing
		super.draw();

		// Missing text in PNG mode
		if (missingCharacter && visible) {
			missingText.x = getMidpoint().x - 150;
			missingText.y = getMidpoint().y - 10;
			missingText.draw();
		}

		alpha = lastAlpha;
		color = lastColor;
	}
	#end

	// ================================================================
	// DESTROY
	// ================================================================
	override public function destroy() {
		#if flxanimate
		atlas = FlxDestroyUtil.destroy(atlas);
		#end
		extraData = null;
		missingText = null;
		super.destroy();
	}

	// ================================================================
	// CAMERA OFFSET HELPERS
	// ================================================================
	public inline function getCameraOffset():FlxPoint {
		return FlxPoint.get(cameraPosition[0], cameraPosition[1]);
	}

	public inline function getCharOffset():FlxPoint {
		return FlxPoint.get(positionArray[0], positionArray[1]);
	}

	// ================================================================
	// CHARACTER RESET HELPERS
	// ================================================================
	public function resetDance() {
		danced = false;
		dance();
	}

	public function resetOffsets() {
		for (anim in animationsArray) {
			anim.offsets = [0, 0];
			animOffsets.set(anim.anim, [0, 0]);
		}
	}

	// ================================================================
	// ZIP ATLAS UTILITIES
	// ================================================================
	#if flxanimate
	private function zipAtlasUpdate() {
		if (!isAnimateZip || atlas == null)
			return;

		atlas.update(FlxG.elapsed);

		var bmp = atlas.getBitmap();
		if (bmp != null)
			this.pixels = bmp;

		updateHitbox();
	}
	#end

	// ================================================================
	// GETTERS
	// ================================================================
	inline public function animExists(a:String):Bool {
		return hasAnimation(a);
	}

	inline public function getCurAnim():String {
		return getAnimationName();
	}

	inline public function getAnimationName():String {
		if (!isAnimateAtlas && !isAnimateZip) {
			return animation.curAnim != null ? animation.curAnim.name : '';
		}

		#if flxanimate
		return atlas.anim.curSymbol != null ? atlas.anim.curSymbol : '';
		#else
		return '';
		#end
	}

	// ================================================================
	// ANIMATION FINISHED CHECK (ATLAS + PNG)
	// ================================================================
	public function isAnimationFinished():Bool {
		if (!isAnimateAtlas && !isAnimateZip) {
			return animation.curAnim != null && animation.curAnim.finished;
		}

		#if flxanimate
		if (atlas != null && atlas.anim != null) {
			return atlas.anim.finished;
		}
		#end

		return true;
	}

	// ================================================================
	// FRAME ADVANCE SUPPORT
	// ================================================================
	public function setAnimFrame(frame:Int) {
		if (!isAnimateAtlas && !isAnimateZip) {
			if (animation.curAnim != null) {
				animation.curAnim.curFrame = FlxMath.wrap(frame, 0, animation.curAnim.numFrames - 1);
			}
			return;
		}

		#if flxanimate
		if (atlas != null && atlas.anim != null) {
			frame = FlxMath.wrap(frame, 0, atlas.anim.length - 1);
			atlas.anim.curFrame = frame;
			var bmp = atlas.getBitmap();
			if (bmp != null)
				this.pixels = bmp;
		}
		#end
	} //--------------------------------------------------------------------

	// ZIP → BITMAP / ATLAS EXPORT HELPERS
	//--------------------------------------------------------------------

	#if flxanimate
	/**
	 * Extracts a specific symbol frame from the ZIP atlas and returns a BitmapData.
	 * Used by Character Editor when exporting PNG+XML.
	 */
	public function getZipFrame(symbol:String, frame:Int):BitmapData {
		if (!isAnimateZip || atlas == null)
			return null;

		try {
			var inst = atlas.anim.getInstance(symbol);
			if (inst == null)
				return null;

			var realFrame = FlxMath.wrap(frame, 0, inst.frames.length - 1);

			return atlas.getSymbolFrame(symbol, realFrame);
		} catch (e) {
			trace("Error extracting ZIP frame: " + e);
			return null;
		}
	}

	/**
	 * Export all frames of a symbol (for PNG/XML exporting).
	 */
	public function exportZipSymbol(symbol:String):Array<BitmapData> {
		var result:Array<BitmapData> = [];

		if (!isAnimateZip || atlas == null)
			return result;

		try {
			var inst = atlas.anim.getInstance(symbol);
			if (inst == null)
				return result;

			for (i in 0...inst.frames.length) {
				var bmp = atlas.getSymbolFrame(symbol, i);
				if (bmp != null)
					result.push(bmp.clone());
			}
		} catch (e) {
			trace("Error exporting symbol frames: " + e);
		}

		return result;
	}
	#end

	//--------------------------------------------------------------------
	// XML EXPORT SUPPORT
	//--------------------------------------------------------------------

	/**
	 * Generates FNF-style XML from ZIP atlas metadata.
	 * Only used when exporting ZIP → PNG+XML.
	 */
	public function generateXMLForSymbol(symbol:String):String {
		#if flxanimate
		if (!isAnimateZip || atlas == null)
			return "";

		var inst = atlas.anim.getInstance(symbol);
		if (inst == null)
			return "";

		var xml = '<TextureAtlas imagePath="' + imageFile + '.png">\n';

		for (i in 0...inst.frames.length) {
			var f = inst.frames[i];
			xml += '    <SubTexture name="' + symbol + i + '" x="' + f.rect.x + '" y="' + f.rect.y + '" width="' + f.rect.width + '" height="'
				+ f.rect.height + '" frameX="' + f.offset.x + '" frameY="' + f.offset.y + '" frameWidth="' + f.frameSize.x + '" frameHeight="'
				+ f.frameSize.y + '"/>\n';
		}

		xml += '</TextureAtlas>';
		return xml;
		#else
		return "";
		#end
	}

	//--------------------------------------------------------------------
	// CHARACTER JSON VALIDATION
	//--------------------------------------------------------------------

	/**
	 * Prevents malformed JSON from crashing the game.
	 * Ensures ALL expected fields exist.
	 */
	public static function sanitizeJSON(raw:Dynamic):Dynamic {
		var j = raw;

		if (j.animations == null)
			j.animations = [];
		if (j.image == null)
			j.image = "";
		if (j.scale == null)
			j.scale = 1.0;
		if (j.sing_duration == null)
			j.sing_duration = 4.0;
		if (j.healthicon == null)
			j.healthicon = "face";

		if (j.position == null)
			j.position = [0, 0];
		if (j.camera_position == null)
			j.camera_position = [0, 0];
		if (j.flip_x == null)
			j.flip_x = false;
		if (j.no_antialiasing == null)
			j.no_antialiasing = false;
		if (j.healthbar_colors == null)
			j.healthbar_colors = [161, 161, 161];
		if (j.vocals_file == null)
			j.vocals_file = "";
		if (j._editor_isPlayer == null)
			j._editor_isPlayer = null;

		// sanitize each animation entry
		for (a in j.animations) {
			if (a.offsets == null)
				a.offsets = [0, 0];
			if (a.indices == null)
				a.indices = [];
			if (a.loop == null)
				a.loop = false;
			if (a.fps == null)
				a.fps = 24;
			if (a.name == null)
				a.name = "";
			if (a.anim == null)
				a.anim = "";
		}

		return j;
	}

	//--------------------------------------------------------------------
	// CHARACTER DATA EXPORT (BACK TO JSON)
	//--------------------------------------------------------------------

	/**
	 * Converts internal character state back into saveable JSON.
	 * Used by Character Editor's Save button.
	 */
	public function exportJSON():Dynamic {
		return {
			animations: animationsArray,
			image: imageFile,
			scale: jsonScale,
			sing_duration: singDuration,
			healthicon: healthIcon,

			position: positionArray,
			camera_position: cameraPosition,

			flip_x: originalFlipX,
			no_antialiasing: noAntialiasing,
			healthbar_colors: healthColorArray,
			vocals_file: vocalsFile,
			_editor_isPlayer: isPlayer
		};
	}

	//--------------------------------------------------------------------
	// UTILITY HELPERS
	//--------------------------------------------------------------------

	/**
	 * Forces frame recalculation (editor compatibility).
	 */
	public inline function refreshAtlas() {
		#if flxanimate
		if (atlas != null) {
			atlas.update(0);
			var bmp = atlas.getBitmap();
			if (bmp != null)
				this.pixels = bmp;
		}
		#end
	}

	/**
	 * Makes sure offsets are applied even after frame advance
	 */
	public inline function reapplyOffsets() {
		var anim = getAnimationName();
		if (hasAnimation(anim)) {
			var o = animOffsets.get(anim);
			if (o != null)
				offset.set(o[0], o[1]);
		}
	}

	//--------------------------------------------------------------------
	// END OF CLASS
	//--------------------------------------------------------------------
}
