package states.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.text.FlxText;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxSort;
import flixel.util.FlxSignal;
import flixel.addons.display.FlxBackdrop;

import flxanimate.FlxAnimate;

import openfl.utils.Assets;
import openfl.utils.ByteArray;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;

import sys.FileSystem;
import sys.io.File;

import objects.Character;
import objects.HealthIcon;
import objects.Bar;
import backend.Paths;
import backend.ClientPrefs;

import states.PlayState;
import backend.MusicBeatState;

import backend.ui.PsychUIBox;
import backend.ui.PsychUIInputText;
import backend.ui.PsychUIEventHandler;
import backend.ui.PsychUIDropDownMenu;
import backend.ui.PsychUICheckBox;
import backend.ui.PsychUINumericStepper;
import backend.ui.PsychUIButton;
import states.editors.content.PsychJsonPrinter;

import haxe.Json;
import haxe.io.Bytes;
import haxe.zip.Reader;
import haxe.zip.Entry;

using StringTools;

class CharacterEditorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	// ===========================================================
	// CORE VARIABLES
	// ===========================================================

	var character:Character;
	var ghost:FlxSprite;
	var animateGhost:FlxAnimate;
	var animateGhostImage:String;

	var isAnimateSprite:Bool = false;
	var silhouettes:FlxSpriteGroup;

	var dadPosition:FlxPoint;
	var bfPosition:FlxPoint;

	var cameraFollowPointer:FlxSprite;
	var cameraZoomText:FlxText;
	var frameAdvanceText:FlxText;

	var helpBg:FlxSprite;
	var helpTexts:FlxSpriteGroup;

	var healthBar:Bar;
	var healthIcon:HealthIcon;

	var anims:Array<AnimArray>;
	var animsTxt:FlxText;
	var curAnim:Int = 0;

	var UI_box:PsychUIBox;
	var UI_characterbox:PsychUIBox;

	var unsavedProgress:Bool = false;

	var selectedFormat = new FlxTextFormat(FlxColor.LIME);
	var _char:String;
	var _goToPlayState:Bool;

	// Ghost opacity
	var ghostAlpha:Float = 0.6;

	// ZIP STATE
	var currentZipPath:String = "";
	var loadedZipData:Map<String, Bytes> = new Map<String, Bytes>();

	// Used for file saving
	var _file:FileReference;

	// ===========================================================
	// CONSTRUCTOR
	// ===========================================================
	public function new(char:String = null, goToPlayState:Bool = true)
	{
		super();
		_char = char != null ? char : Character.DEFAULT_CHARACTER;
		_goToPlayState = goToPlayState;
	}

	// ===========================================================
	// CREATE()
	// ===========================================================
	override function create()
	{
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		FlxG.sound.music.stop();

		var camEditor = initPsychCamera();
		var camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		// ---------------------------------------------
		// Load background
		// ---------------------------------------------
		loadBackground();

		// ---------------------------------------------
		// Silhouette references (BF / Dad outlines)
		// ---------------------------------------------
		dadPosition = FlxPoint.get(100, 100);
		bfPosition = FlxPoint.get(770, 100);

		silhouettes = new FlxSpriteGroup();
		add(silhouettes);

		var dadSil = new FlxSprite(dadPosition.x, dadPosition.y).loadGraphic(Paths.image("editors/silhouetteDad"));
		dadSil.antialiasing = ClientPrefs.data.antialiasing;
		dadSil.offset.set(-4, 1);
		dadSil.active = false;
		silhouettes.add(dadSil);

		var bfSil = new FlxSprite(bfPosition.x, bfPosition.y + 350).loadGraphic(Paths.image("editors/silhouetteBF"));
		bfSil.antialiasing = ClientPrefs.data.antialiasing;
		bfSil.offset.set(-6, 2);
		bfSil.active = false;
		silhouettes.add(bfSil);

		silhouettes.alpha = 0.25;

		// ---------------------------------------------
		// GHOST SPRITES (PNG/XML or Animate)
		// ---------------------------------------------
		ghost = new FlxSprite();
		ghost.visible = false;
		ghost.alpha = ghostAlpha;
		add(ghost);

		animsTxt = new FlxText(10, 32, 400, '');
		animsTxt.setFormat(null, 16, FlxColor.WHITE, LEFT);
		animsTxt.scrollFactor.set();
		animsTxt.cameras = [camHUD];
		add(animsTxt);

		// ---------------------------------------------
		// Load character
		// ---------------------------------------------
		addCharacter();

		// ---------------------------------------------
		// Camera follow pointer
		// ---------------------------------------------
		cameraFollowPointer = new FlxSprite().makeGraphic(2, 2, FlxColor.WHITE);
		cameraFollowPointer.visible = false;
		add(cameraFollowPointer);

		// ---------------------------------------------
		// Health bar + icon
		// ---------------------------------------------
		healthBar = new Bar(30, FlxG.height - 75);
		healthBar.scrollFactor.set();
		healthBar.cameras = [camHUD];

		healthIcon = new HealthIcon(character.healthIcon, false, false);
		healthIcon.y = FlxG.height - 150;
		healthIcon.cameras = [camHUD];

		add(healthBar);
		add(healthIcon);

		// ---------------------------------------------
		// Camera zoom label
		// ---------------------------------------------
		cameraZoomText = new FlxText(0, 50, 200, "Zoom: 1x");
		cameraZoomText.setFormat(null, 16, FlxColor.WHITE, CENTER);
		cameraZoomText.scrollFactor.set();
		cameraZoomText.screenCenter(X);
		cameraZoomText.cameras = [camHUD];
		add(cameraZoomText);

		// ---------------------------------------------
		// Frame advance label
		// ---------------------------------------------
		frameAdvanceText = new FlxText(0, 75, 350, "");
		frameAdvanceText.setFormat(null, 16, FlxColor.WHITE, CENTER);
		frameAdvanceText.scrollFactor.set();
		frameAdvanceText.screenCenter(X);
		frameAdvanceText.cameras = [camHUD];
		add(frameAdvanceText);

		// ---------------------------------------------
		// Help screen overlay
		// ---------------------------------------------
		buildHelpScreen(camHUD);

		// ---------------------------------------------
		// UI Panels
		// ---------------------------------------------
		buildUIPanels(camHUD);

		super.create();
	}

	// ===========================================================
	// BACKGROUND LOADING
	// ===========================================================
	function loadBackground()
	{
		var bg = new FlxBackdrop(Paths.image("editors/ce_bg"));
		bg.scrollFactor.set(0.2, 0.2);
		add(bg);
	}

	// ===========================================================
	// ZIP LOADING SYSTEM
	// ===========================================================

	/**
	 * Loads a ZIP file selected by the user (characterName.zip)
	 * containing:
	 *   data.json       -> character JSON
	 *   library.json    -> Animate JSON (if Animate atlas)
	 *   symbols/*       -> atlased images or extracted frames
	 */
	public function loadCharacterFromZip(fileRef:FileReference)
	{
		fileRef.addEventListener(Event.COMPLETE, function(_) {
			var bytes:Bytes = Bytes.ofData(fileRef.data);
			loadZipBytes(bytes);
		});
		fileRef.addEventListener(IOErrorEvent.IO_ERROR, function(_) {
			FlxG.log.error("Could not load ZIP");
		});
		fileRef.load();
	}

	/**
	 * Takes ZIP bytes and parses every entry inside it.
	 * All files are stored in loadedZipData[ filename ] = Bytes.
	 */
	function loadZipBytes(bytes:Bytes)
	{
		loadedZipData = new Map<String, Bytes>();

		try {
			var reader = new Reader(bytes);
			for (entry in reader.read()) {
				var name = entry.fileName;
				var data = entry.data;
				loadedZipData.set(name, data);
			}
		}
		catch (e:Dynamic) {
			FlxG.log.error("ZIP parse error: " + e);
			return;
		}

		// Look for data.json
		if (!loadedZipData.exists("data.json")) {
			FlxG.log.error("ZIP missing data.json");
			return;
		}

		var dataJson = loadedZipData.get("data.json").toString();
		try {
			var parsed = Json.parse(dataJson);
			loadCharacterFromZipData(parsed);
		}
		catch (e:Dynamic) {
			FlxG.log.error("Could not parse data.json: " + e);
		}
	}

	/**
	 * Loads character fields using the JSON extracted from ZIP.
	 * This feeds directly into Character.loadCharacterFile(),
	 * but with overrides for image pathing (symbols/*).
	 */
	function loadCharacterFromZipData(json:Dynamic)
	{
		if (json == null) return;

		// Write the JSON into a temp location so Character.hx can load it.
		var tempPath = "mods/temp_zip_char.json";
		try {
			File.saveContent(tempPath, Json.stringify(json));
		}
		catch(e:Dynamic) {
			FlxG.log.error("Failed to save temp ZIP JSON: " + e);
		}

		// Now tell character to load from that JSON
		_char = json.image; // use its declared name
		addCharacter(true, tempPath);

		// Load Animate JSON / library.json
		if (loadedZipData.exists("library.json")) {
			loadAnimateJsonFromZip();
		}

		// Load extracted symbol frames (PNG)
		loadSymbolPNGsFromZip();

		unsavedProgress = true;
		FlxG.log.notice("Loaded ZIP character");
	}

	/**
	 * Attempts to load Animate JSON (library.json) from the ZIP.
	 * This allows loading Animate atlases directly without files in mods/.
	 */
	function loadAnimateJsonFromZip()
	{
		var libBytes = loadedZipData.get("library.json");
		if (libBytes == null) return;

		try {
			var jsonStr = libBytes.toString();
			var parsed = Json.parse(jsonStr);

			if (animateGhost == null) {
				animateGhost = new FlxAnimate(0, 0);
				animateGhost.showPivot = false;
				add(animateGhost);
			}

			animateGhostImage = _char;
			Paths.loadAnimateAtlasFromData(animateGhost, parsed, loadedZipData); 
		}
		catch(e:Dynamic) {
			FlxG.log.error("Animate ZIP load failed: " + e);
		}
	}

	/**
	 * Loads images from symbols/* inside ZIP.
	 * These PNG files override the multiatlas or Animate frames.
	 */
	function loadSymbolPNGsFromZip()
	{
		for (entryName => bytes in loadedZipData)
		{
			if (!entryName.startsWith("symbols/")) continue;
			if (!entryName.toLowerCase().endsWith(".png")) continue;

			var shortName = entryName.substring("symbols/".length);
			var fullPath = "mods/images/" + _char + "/" + shortName;

			try {
				File.saveBytes(fullPath, bytes);
			}
			catch(e:Dynamic) {
				FlxG.log.error("Couldn't save symbol PNG: " + e);
			}
		}

		FlxG.log.notice("Extracted PNG symbols from ZIP");
	}

	// ===========================================================
	// RELOAD CHARACTER (WITH ZIP SUPPORT)
	// ===========================================================

	/**
	 * Adds character to the stage. Supports:
	 *  - Normal JSON
	 *  - ZIP imported JSON (temp path)
	 */
	function addCharacter(reload:Bool = false, ?forcedJsonPath:String = null)
	{
		var oldPos = -1;

		if (character != null)
		{
			oldPos = members.indexOf(character);
			remove(character);
			character.destroy();
		}

		var isPlayer = (!reload ? !predictCharacterIsNotPlayer(_char) : character != null ? character.isPlayer : false);

		character = new Character(0, 0, _char, isPlayer);

		// If loading from ZIP temp JSON
		if (forcedJsonPath != null && FileSystem.exists(forcedJsonPath))
		{
			var jsonText = File.getContent(forcedJsonPath);
			try {
				var jsonDyn = Json.parse(jsonText);
				character.loadCharacterFile(jsonDyn);
			}
			catch(e:Dynamic) {
				FlxG.log.error("Could not load forced ZIP JSON: " + e);
			}
		}

		character.debugMode = true;
		character.missingCharacter = false;

		if (oldPos > -1)
			insert(oldPos, character);
		else
			add(character);

		updateCharacterPositions();
		reloadAnimList();
		updateHealthBar();
		updatePointerPos(false);
	}

	// ===========================================================
	// HELP SCREEN
	// ===========================================================
	function buildHelpScreen(camHUD:FlxCamera)
	{
		var textLines = [
			"CAMERA",
			"E/Q - Zoom",
			"J/K/L/I - Move",
			"R - Reset",
			"",
			"OFFSETS",
			"Arrow keys - Move offset",
			"Ctrl+C = Copy, Ctrl+V = Paste",
			"Ctrl+R = Reset, Ctrl+Z = Undo",
			"",
			"ANIM",
			"W/S - Select Animation",
			"Space - Replay",
			"A/D - Frame Advance",
			"",
			"OTHER",
			"F12 - Toggle Silhouettes",
			"F1 - Help"
		];

		helpBg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		helpBg.scale.set(FlxG.width, FlxG.height);
		helpBg.alpha = 0.6;
		helpBg.cameras = [camHUD];
		helpBg.visible = false;
		add(helpBg);

		helpTexts = new FlxSpriteGroup();
		helpTexts.cameras = [camHUD];

		for (i => str in textLines)
		{
			if (str.length < 1) continue;

			var t = new FlxText(0, 0, 600, str, 16);
			t.setFormat(null, 16, FlxColor.WHITE, CENTER);
			t.screenCenter();
			t.y += ((i - textLines.length / 2) * 32) + 16;
			t.active = false;
			helpTexts.add(t);
		}

		helpTexts.visible = false;
		add(helpTexts);
	}

	// ===========================================================
	// UI PANEL BUILDING (PARTIAL)
	// ===========================================================
	function buildUIPanels(camHUD:FlxCamera)
	{
		UI_box = new PsychUIBox(FlxG.width - 275, 25, 250, 120, ["Ghost", "Settings", "ZIP"]);
		UI_box.cameras = [camHUD];

		UI_characterbox = new PsychUIBox(UI_box.x - 100, UI_box.y + UI_box.height + 10, 350, 280, ["Animations", "Character"]);
		UI_characterbox.cameras = [camHUD];

		add(UI_box);
		add(UI_characterbox);

		addGhostUI();
		addSettingsUI();
		addAnimationsUI();
		addCharacterUI();
		addZipUI();

		UI_box.selectedName = "Settings";
		UI_characterbox.selectedName = "Character";
	}

	// ===========================================================
	// ZIP UI PANEL
	// ===========================================================
	function addZipUI()
	{
		var tab = UI_box.getTab("ZIP").menu;

		var btnLoad = new PsychUIButton(20, 15, "Import ZIP", function () {
			var fr = new FileReference();
			fr.addEventListener(Event.SELECT, function(_) {
				loadCharacterFromZip(fr);
			});
			fr.browse();
		});

		var btnExport = new PsychUIButton(20, 55, "Export ZIP", function () {
			exportCharacterToZip();
		});

		tab.add(btnLoad);
		tab.add(btnExport);
	}

	// ===========================================================
	// ZIP EXPORT
	// ===========================================================
	function exportCharacterToZip()
	{
		if (_file != null) return;

		var zipEntries:Array<Entry> = [];
		var name = _char + ".zip";

		// 1. Add data.json
		var dataJson = Json.stringify({
			animations: character.animationsArray,
			image: character.imageFile,
			scale: character.jsonScale,
			sing_duration: character.singDuration,
			healthicon: character.healthIcon,
			position: character.positionArray,
			camera_position: character.cameraPosition,
			flip_x: character.originalFlipX,
			no_antialiasing: character.noAntialiasing,
			healthbar_colors: character.healthColorArray,
			vocals_file: character.vocalsFile
		}, "\t");

		zipEntries.push(makeZipEntry("data.json", Bytes.ofString(dataJson)));

		// 2. Add frames from mods/images/character/symbols/*
		var folder = "mods/images/" + _char + "/";
		if (FileSystem.exists(folder))
		{
			for (file in FileSystem.readDirectory(folder))
			{
				if (file.toLowerCase().endsWith(".png"))
				{
					var bytes = File.getBytes(folder + file);
					zipEntries.push(makeZipEntry("symbols/" + file, bytes));
				}
			}
		}

		// Build ZIP
		var output = Reader.write(zipEntries);
		_file = new FileReference();
		_file.save(output, name);
	}

	function makeZipEntry(path:String, bytes:Bytes):Entry
	{
		return {
			fileName: path,
			fileSize: bytes.length,
			fileTime: Date.now(),
			compressed: false,
			data: bytes
		};
	}
	// ===========================================================
	// ANIMATION LIST / DROPDOWN RELOADERS
	// ===========================================================

	inline function reloadAnimList()
	{
		anims = character.animationsArray;
		if (anims.length > 0)
		{
			curAnim = 0;
			character.playAnim(anims[0].anim, true);
		}

		updateAnimText();
		if (animationDropDown != null) reloadAnimationDropDown();
	}

	inline function reloadAnimationDropDown()
	{
		if (animationDropDown == null) return;

		var names:Array<String> = [];
		for (a in anims) names.push(a.anim);

		if (names.length < 1) names.push("NO ANIMATIONS");

		animationDropDown.list = names;
		if (curAnim >= 0 && curAnim < names.length)
			animationDropDown.selectedLabel = names[curAnim];
	}

	inline function updateAnimText()
	{
		animsTxt.removeFormat(selectedFormat);

		var buf:String = '';
		for (i => anim in anims)
		{
			if (i > 0) buf += "\n";

			if (i == curAnim)
			{
				var s = buf.length;
				buf += anim.anim + ": " + anim.offsets;
				animsTxt.addFormat(selectedFormat, s, buf.length);
			}
			else
				buf += anim.anim + ": " + anim.offsets;
		}

		animsTxt.text = buf;
	}

	// ===========================================================
	// FRAME ADVANCE + OFFSET EDIT SYSTEM
	// ===========================================================

	var holdingArrows:Float = 0;
	var arrowAccel:Float = 0;

	var holdingFrame:Float = 0;
	var frameAccel:Float = 0;

	var undoOffsets:Array<Float> = null;

	function handleOffsetMovement(elapsed:Float)
	{
		var shiftMul = FlxG.keys.pressed.SHIFT ? 10 : 1;

		var moved = false;

		// Button presses (instant)
		if (FlxG.keys.justPressed.LEFT)
		{
			character.offset.x += shiftMul;
			moved = true;
		}
		if (FlxG.keys.justPressed.RIGHT)
		{
			character.offset.x -= shiftMul;
			moved = true;
		}
		if (FlxG.keys.justPressed.UP)
		{
			character.offset.y += shiftMul;
			moved = true;
		}
		if (FlxG.keys.justPressed.DOWN)
		{
			character.offset.y -= shiftMul;
			moved = true;
		}

		// Hold movement
		var anyHeld = (FlxG.keys.pressed.LEFT || FlxG.keys.pressed.RIGHT || FlxG.keys.pressed.UP || FlxG.keys.pressed.DOWN);
		if (anyHeld)
		{
			holdingArrows += elapsed;
			if (holdingArrows > 0.5)
			{
				arrowAccel += elapsed;
				if (arrowAccel > 1/60)
				{
					if (FlxG.keys.pressed.LEFT)  character.offset.x += shiftMul;
					if (FlxG.keys.pressed.RIGHT) character.offset.x -= shiftMul;
					if (FlxG.keys.pressed.UP)    character.offset.y += shiftMul;
					if (FlxG.keys.pressed.DOWN)  character.offset.y -= shiftMul;

					arrowAccel -= 1/60;
					moved = true;
				}
			}
		}
		else
			holdingArrows = 0;

		// Mouse drag offset
		if (FlxG.mouse.pressedRight && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0))
		{
			character.offset.x -= FlxG.mouse.deltaScreenX;
			character.offset.y -= FlxG.mouse.deltaScreenY;
			moved = true;
		}

		// Ctrl + shortcuts
		if (FlxG.keys.pressed.CONTROL)
		{
			if (FlxG.keys.justPressed.C)
			{
				copiedOffset[0] = character.offset.x;
				copiedOffset[1] = character.offset.y;
				moved = true;
			}
			else if (FlxG.keys.justPressed.V)
			{
				undoOffsets = [ character.offset.x, character.offset.y ];
				character.offset.x = copiedOffset[0];
				character.offset.y = copiedOffset[1];
				moved = true;
			}
			else if (FlxG.keys.justPressed.R)
			{
				undoOffsets = [ character.offset.x, character.offset.y ];
				character.offset.set(0, 0);
				moved = true;
			}
			else if (FlxG.keys.justPressed.Z && undoOffsets != null)
			{
				character.offset.x = undoOffsets[0];
				character.offset.y = undoOffsets[1];
				moved = true;
			}
		}

		if (moved)
		{
			var a = anims[curAnim];
			if (a != null)
			{
				a.offsets[0] = Std.int(character.offset.x);
				a.offsets[1] = Std.int(character.offset.y);

				character.addOffset(a.anim, a.offsets[0], a.offsets[1]);
				updateAnimText();
			}
			unsavedProgress = true;
		}
	}

	function handleFrameAdvance(elapsed:Float)
	{
		if (character.isAnimationNull()) return;

		var isLeft = false;
		var isRight = false;

		if (FlxG.keys.justPressed.A) isLeft = true;
		if (FlxG.keys.justPressed.D) isRight = true;

		// hold
		if (FlxG.keys.pressed.A || FlxG.keys.pressed.D)
		{
			holdingFrame += elapsed;
			if (holdingFrame > 0.5)
			{
				frameAccel += elapsed;
				if (frameAccel > 0.1)
				{
					isLeft = FlxG.keys.pressed.A;
					isRight = FlxG.keys.pressed.D;
					frameAccel -= 0.1;
				}
			}
		}
		else
			holdingFrame = 0;

		if (!isLeft && !isRight) return;

		character.animPaused = true;

		var frame = 0;
		var length = 0;

		if (!character.isAnimateAtlas)
		{
			frame = character.animation.curAnim.curFrame;
			length = character.animation.curAnim.numFrames;
		}
		else
		{
			frame = character.atlas.anim.curFrame;
			length = character.atlas.anim.length;
		}

		if (length < 1) return;

		if (isLeft) frame--;
		if (isRight) frame++;

		frame = FlxMath.wrap(frame, 0, length - 1);

		if (!character.isAnimateAtlas)
			character.animation.curAnim.curFrame = frame;
		else
			character.atlas.anim.curFrame = frame;

		frameAdvanceText.text = 'Frames: ( $frame / ${length-1} )';
		frameAdvanceText.color = FlxColor.WHITE;
	}

	// ===========================================================
	// CAMERA MOVEMENT
	// ===========================================================

	function handleCameraControls(elapsed:Float)
	{
		var shift = FlxG.keys.pressed.SHIFT ? 4 : 1;
		var slow = FlxG.keys.pressed.CONTROL ? 0.25 : 1;

		if (FlxG.keys.pressed.J) FlxG.camera.scroll.x -= elapsed * 500 * shift * slow;
		if (FlxG.keys.pressed.L) FlxG.camera.scroll.x += elapsed * 500 * shift * slow;
		if (FlxG.keys.pressed.I) FlxG.camera.scroll.y -= elapsed * 500 * shift * slow;
		if (FlxG.keys.pressed.K) FlxG.camera.scroll.y += elapsed * 500 * shift * slow;

		// zoom
		var prevZoom = FlxG.camera.zoom;
		if (FlxG.keys.justPressed.R && !FlxG.keys.pressed.CONTROL) FlxG.camera.zoom = 1;
		else if (FlxG.keys.pressed.E)
		{
			FlxG.camera.zoom += elapsed * FlxG.camera.zoom * shift * slow;
			if (FlxG.camera.zoom > 3) FlxG.camera.zoom = 3;
		}
		else if (FlxG.keys.pressed.Q)
		{
			FlxG.camera.zoom -= elapsed * FlxG.camera.zoom * shift * slow;
			if (FlxG.camera.zoom < 0.1) FlxG.camera.zoom = 0.1;
		}

		if (prevZoom != FlxG.camera.zoom)
		{
			cameraZoomText.text = "Zoom: " + FlxMath.roundDecimal(FlxG.camera.zoom, 2) + "x";
		}
	}

	// ===========================================================
	// CHARACTER POSITION AND POINTER
	// ===========================================================

	inline function updateCharacterPositions()
	{
		if (!character.isPlayer)
			character.setPosition(dadPosition.x, dadPosition.y);
		else
			character.setPosition(bfPosition.x, bfPosition.y);

		character.x += character.positionArray[0];
		character.y += character.positionArray[1];

		updatePointer(false);
	}

	inline function updatePointer(snap:Bool = true)
	{
		if (character == null) return;

		var offX = 0.0;
		var offY = 0.0;

		if (!character.isPlayer)
		{
			offX = character.getMidpoint().x + 150 + character.cameraPosition[0];
			offY = character.getMidpoint().y - 100 + character.cameraPosition[1];
		}
		else
		{
			offX = character.getMidpoint().x - 100 - character.cameraPosition[0];
			offY = character.getMidpoint().y - 100 + character.cameraPosition[1];
		}

		cameraFollowPointer.setPosition(offX, offY);

		if (snap)
		{
			FlxG.camera.scroll.x = cameraFollowPointer.getMidpoint().x - FlxG.width/2;
			FlxG.camera.scroll.y = cameraFollowPointer.getMidpoint().y - FlxG.height/2;
		}
	}

	// ===========================================================
	// HEALTH BAR & ICON UPDATE
	// ===========================================================

	inline function updateHealthBar()
	{
		healthColorStepperR.value = character.healthColorArray[0];
		healthColorStepperG.value = character.healthColorArray[1];
		healthColorStepperB.value = character.healthColorArray[2];

		var col = FlxColor.fromRGB(
			character.healthColorArray[0],
			character.healthColorArray[1],
			character.healthColorArray[2]
		);

		healthBar.leftBar.color = col;
		healthBar.rightBar.color = col;

		healthIcon.changeIcon(character.healthIcon, false);

		#if DISCORD_ALLOWED
		DiscordClient.changePresence(
			"Character Editor",
			"Character: " + _char,
			healthIcon.getCharacter()
		);
		#end
	}

	// ===========================================================
	// SILHOUETTE & HELP SCREEN TOGGLES
	// ===========================================================

	inline function toggleSilhouette()
	{
		silhouettes.visible = !silhouettes.visible;
	}

	inline function toggleHelp()
	{
		helpBg.visible = !helpBg.visible;
		helpTexts.visible = helpBg.visible;
	}

	// ===========================================================
	// ZIP EXPORT SYSTEM
	// ===========================================================

	public function exportCharacterZip()
	{
		if (character == null)
		{
			showPopup("Error", "No character loaded to export!");
			return;
		}

		var exportName = _char;
		if (exportName == "") exportName = "character";

		var zipEntries:Array<Entry> = [];

		// -------------------------------------------------------
		// 1. data.json - Character metadata
		// -------------------------------------------------------
		var dataObj:Dynamic = {
			name: exportName,
			scale: character.jsonScale,
			flip_x: character.originalFlipX,
			sing_duration: character.singDuration,
			healthicon: character.healthIcon,
			no_antialiasing: character.noAntialiasing,
			position: character.positionArray,
			camera_position: character.cameraPosition,
			healthbar_colors: character.healthColorArray,
			image: character.imageFile,
			vocals_file: character.vocalsFile,
			_editor_isPlayer: character.editorIsPlayer,
			animations: character.animationsArray
		};

		var dataBytes = Bytes.ofString(Json.stringify(dataObj, "\t"));
		zipEntries.push(makeZipEntry("data.json", dataBytes));

		// -------------------------------------------------------
		// 2. library.json or Animation.json depending on format
		// -------------------------------------------------------
		if (character.isAnimateAtlas)
		{
			var libJson = buildLibraryJson();
			zipEntries.push(makeZipEntry("library.json", Bytes.ofString(libJson)));
		}
		else
		{
			// For plain PNG/XML characters we still generate a spritemap for completeness
			var pngXml = buildSpritesheetXml();
			zipEntries.push(makeZipEntry("library.json", Bytes.ofString(pngXml)));
		}

		// -------------------------------------------------------
		// 3. Generate SYMBOL folders for Animate JSON exports
		// -------------------------------------------------------
		if (character.isAnimateAtlas)
			exportAnimateSymbols(zipEntries);

		// -------------------------------------------------------
		// 4. PNG + XML exports for frame-by-frame sprites
		// -------------------------------------------------------
		exportFramePNGs(zipEntries);

		// -------------------------------------------------------
		// 5. ZIP WRITING
		// -------------------------------------------------------
		var zipBytes = createZipBytes(zipEntries);

		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, onZipExportComplete);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onZipExportError);
		_file.save(zipBytes, exportName + ".zip");
	}

	function onZipExportComplete(_)
	{
		showPopup("Export Complete", "Character exported successfully!");
	}

	function onZipExportError(e:IOErrorEvent)
	{
		showPopup("Error", "Failed to export ZIP:\n" + e.text);
	}

	// ===========================================================
	// ZIP HELPER
	// ===========================================================

	function createZipBytes(entries:Array<Entry>):Bytes
	{
		var output = new BytesOutput();
		var writer = new haxe.zip.Writer(output);
		writer.write(entries);
		return output.getBytes();
	}

	// ===========================================================
	// BUILD library.json (Animate format)
	// ===========================================================

	function buildLibraryJson():String
	{
		// Building the data used by FlxAnimate style atlases
		var symbols:Array<Dynamic> = [];

		for (a in anims)
		{
			symbols.push({
				name: a.name,
				fps: a.fps,
				loop: a.loop,
				frames: a.indices
			});
		}

		var obj:Dynamic = {
			atlas: character.imageFile,
			symbols: symbols
		};

		return Json.stringify(obj, "\t");
	}

	// ===========================================================
	// BUILD SPRITESHEET XML (fallback for PNG/XML)
	// ===========================================================

	function buildSpritesheetXml():String
	{
		var xml = '<TextureAtlas imagePath="' + character.imageFile + '.png">\n';

		for (a in anims)
		{
			var prefix = a.name;

			for (i in 0...a.indices.length)
			{
				var id = a.indices[i];
				xml += '\t<SubTexture name="' + prefix + id + '" x="0" y="0" width="0" height="0" frameX="0" frameY="0" frameWidth="0" frameHeight="0"/>\n';
			}
		}

		xml += '</TextureAtlas>';
		return xml;
	}

	// ===========================================================
	// EXPORT SYMBOLS (Animate system)
	// ===========================================================

	function exportAnimateSymbols(zipEntries:Array<Entry>)
	{
		if (!character.isAnimateAtlas || character.atlas == null) return;

		var anim = character.atlas.anim;

		for (symbolName in anim.symbols.keys())
		{
			var frames = anim.symbols.get(symbolName);
			var folderName = "symbols/" + symbolName + "/";

			for (i in 0...frames.length)
			{
				var frame = frames[i];

				var b = renderFrameToBytes(frame);
				var filename = folderName + "frame" + i + ".png";

				if (b != null)
				{
					zipEntries.push(makeZipEntry(filename, b));
				}
			}
		}
	}

	// ===========================================================
	// EXPORT FRAME-BY-FRAME (PNG/XML)
	// ===========================================================

	function exportFramePNGs(zipEntries:Array<Entry>)
	{
		if (character.isAnimateAtlas)
			return; // handled by exportAnimateSymbols()

		var baseFolder = "frames/";

		for (a in anims)
		{
			var folder = baseFolder + a.anim + "/";
			var indices = a.indices;

			var numFrames = indices != null && indices.length > 0 ? indices.length : 1;

			for (i in 0...numFrames)
			{
				var frameIndex = i;
				var b = renderCharacterFrame(a.anim, frameIndex);

				if (b != null)
				{
					var filename = folder + "frame" + frameIndex + ".png";
					zipEntries.push(makeZipEntry(filename, b));
				}
			}

			// XML for this animation
			var xml = buildSingleAnimXML(a);
			zipEntries.push(makeZipEntry(folder + a.anim + ".xml", Bytes.ofString(xml)));
		}
	}

	// Render PNG from a FlxSprite frame
	function renderCharacterFrame(anim:String, frameIndex:Int):Bytes
	{
		character.playAnim(anim, true);
		character.animPaused = true;

		if (!character.isAnimateAtlas)
			character.animation.curAnim.curFrame = frameIndex;
		else
			character.atlas.anim.curFrame = frameIndex;

		return captureSpriteToPNG(character);
	}

	function renderFrameToBytes(frame:Dynamic):Bytes
	{
		if (frame == null) return null;

		// draw into bitmap
		var spr = new FlxSprite();
		spr.pixels = frame;
		return captureSpriteToPNG(spr);
	}

	// ===========================================================
	// BUILD XML FOR SINGLE ANIMATION
	// ===========================================================

	function buildSingleAnimXML(a:AnimArray):String
	{
		var xml = '<Animation name="' + a.anim + '">\n';

		for (i in 0...a.indices.length)
		{
			xml += '\t<Frame index="' + a.indices[i] + '" x="0" y="0" w="0" h="0" offsetX="' + a.offsets[0] + '" offsetY="' + a.offsets[1] + '"/>\n';
		}

		xml += '</Animation>';
		return xml;
	}

	// ===========================================================
	// PNG CAPTURE
	// ===========================================================

	function captureSpriteToPNG(spr:FlxSprite):Bytes
	{
		var bmp = new BitmapData(Std.int(spr.frameWidth), Std.int(spr.frameHeight), true, 0x00000000);
		var mat = new Matrix();
		mat.translate(-spr.offset.x, -spr.offset.y);

		bmp.draw(spr.pixels, mat);

		var ba = new ByteArray();
		var png = new PNGEncoderOptions();
		bmp.encode(ba, png);

		return Bytes.ofData(ba);
	}

	// ===========================================================
	// POPUP
	// ===========================================================

	function showPopup(title:String, text:String)
	{
		trace("[CharacterEditor] " + title + ": " + text);
		// You can add an on-screen popup window here if needed
	}

	// ===========================================================
	// UI CALLBACKS (buttons)
	// ===========================================================

	function onClickExportZip(_)
	{
		exportCharacterZip();
	}

	function onClickImportZip(_)
	{
		openFileDialog(importZipSelected, ["zip"]);
	}

	function importZipSelected(fileRef:FileReference)
	{
		fileRef.addEventListener(Event.COMPLETE, onZipLoad);
		fileRef.addEventListener(IOErrorEvent.IO_ERROR, onZipLoadError);
		fileRef.load();
	}

	function onZipLoad(e:Event)
	{
		var fr:FileReference = cast e.target;
		var bytes = Bytes.ofData(fr.data);

		var zip = new haxe.zip.Reader(new haxe.io.BytesInput(bytes));
		var entries = zip.read();

		var tmpFolder = Sys.getCwd() + "/tmp_char_zip/";
		if (!FileSystem.exists(tmpFolder))
			FileSystem.createDirectory(tmpFolder);

		// Extract ZIP contents
		for (entry in entries)
		{
			var outPath = tmpFolder + entry.fileName;
			var dir = haxe.io.Path.directory(outPath);

			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);

			File.saveBytes(outPath, entry.data);
		}

		loadImportedCharacter(tmpFolder);
	}

	function onZipLoadError(e:IOErrorEvent)
	{
		showPopup("Error", "Couldn't load ZIP file:\n" + e.text);
	}

	// ===========================================================
	// LOAD IMPORTED ZIP CHARACTER
	// ===========================================================

	function loadImportedCharacter(path:String)
	{
		var dataPath = path + "data.json";
		if (!FileSystem.exists(dataPath))
		{
			showPopup("Invalid ZIP", "ZIP does not contain a data.json file!");
			return;
		}

		var jsonData = Json.parse(File.getContent(dataPath));

		// Write character.json into mods folder
		var dest = Paths.getModPath("characters/" + jsonData.name + ".json");
		File.saveContent(dest, Json.stringify(jsonData, "\t"));

		// Copy all PNGs and XMLs
		copyFolder(path + "frames/", Paths.getModPath("images/" + jsonData.image + "/"));
		copyFolder(path + "symbols/", Paths.getModPath("images/" + jsonData.image + "/symbols/"));

		// Reload UI
		_char = jsonData.name;
		reloadCharacter(_char, false);

		showPopup("Success", "Character imported and updated!");
	}

	// ===========================================================
	// FOLDER COPY
	// ===========================================================

	function copyFolder(from:String, to:String)
	{
		if (!FileSystem.exists(from))
			return;

		if (!FileSystem.exists(to))
			FileSystem.createDirectory(to);

		for (file in FileSystem.readDirectory(from))
		{
			var full = from + file;
			var dest = to + file;

			if (FileSystem.isDirectory(full))
			{
				copyFolder(full + "/", dest + "/");
			}
			else
			{
				var bytes = File.getBytes(full);
				File.saveBytes(dest, bytes);
			}
		}
	}

	// ===========================================================
	// SAVE / LOAD CHARACTER.JSON
	// ===========================================================

	function onClickSaveJson(_)
	{
		var json = Json.stringify({
			image: character.imageFile,
			scale: character.jsonScale,
			flip_x: character.originalFlipX,
			no_antialiasing: character.noAntialiasing,
			position: character.positionArray,
			camera_position: character.cameraPosition,
			healthbar_colors: character.healthColorArray,
			vocals_file: character.vocalsFile,
			sing_duration: character.singDuration,
			_editor_isPlayer: character.editorIsPlayer,
			healthicon: character.healthIcon,
			animations: character.animationsArray
		}, "\t");

		var fr = new FileReference();
		fr.save(json, character.curCharacter + ".json");
	}

	function onClickLoadJson(_)
	{
		openFileDialog(loadJsonSelected, ["json"]);
	}

	function loadJsonSelected(fr:FileReference)
	{
		fr.addEventListener(Event.COMPLETE, jsonLoadComplete);
		fr.load();
	}

	function jsonLoadComplete(e:Event)
	{
		var fr:FileReference = cast e.target;
		var json = Json.parse(fr.data.readUTFBytes(fr.data.length));

		_char = json.name != null ? json.name : "character";
		var out = Paths.getModPath("characters/" + _char + ".json");
		File.saveContent(out, Json.stringify(json, "\t"));

		reloadCharacter(_char, false);
	}

	// ===========================================================
	// OPEN FILE DIALOG
	// ===========================================================

	function openFileDialog(callback:FileReference -> Void, filters:Array<String>)
	{
		var fr = new FileReference();
		fr.addEventListener(Event.SELECT, function(_) callback(fr));

		var fl:Array<FileFilter> = [];
		for (f in filters)
			fl.push(new FileFilter(f.toUpperCase() + " files", "*." + f));

		fr.browse(fl);
	}

	// ===========================================================
	// INPUT HANDLING (keyboard shortcuts)
	// ===========================================================

	function keyHandler()
	{
		if (FlxG.keys.justPressed.R)
			resetCharacter();

		if (FlxG.keys.justPressed.ESCAPE)
			exitEditor();

		if (FlxG.keys.justPressed.S && FlxG.keys.pressed.CONTROL)
			onClickSaveJson(null);

		if (FlxG.keys.justPressed.E && FlxG.keys.pressed.CONTROL)
			exportCharacterZip();
	}

	// ===========================================================
	// RESET CHARACTER (pose + selected anim)
	// ===========================================================

	function resetCharacter()
	{
		if (character == null) return;

		character.playAnim("idle", true);
		offsetX.value = character.offset.x;
		offsetY.value = character.offset.y;
	}

	// ===========================================================
	// EXIT EDITOR
	// ===========================================================

	function exitEditor()
	{
		FlxG.sound.play(Paths.sound("cancelMenu"));
		FlxG.switchState(new MainMenuState());
	}

	// ===========================================================
	// CLEANUP
	// ===========================================================

	override public function destroy()
	{
		if (character != null)
			character.destroy();

		if (_file != null)
		{
			_file.removeEventListener(Event.COMPLETE, onZipExportComplete);
			_file.removeEventListener(IOErrorEvent.IO_ERROR, onZipExportError);
		}

		super.destroy();
	}

	// ===========================================================
	// END OF CLASS
	// ===========================================================
}
