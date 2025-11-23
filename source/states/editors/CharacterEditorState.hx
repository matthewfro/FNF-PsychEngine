package states.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import backend.Paths;
import backend.Mods;
import backend.ClientPrefs;
import objects.Character;
import objects.Bar;
import objects.HealthIcon;
import backend.MusicBeatState;
import states.PlayState;
import backend.ui.PsychUIBox;
import backend.ui.PsychUIInputText;
import backend.ui.PsychUIDropDownMenu;
import backend.ui.PsychUICheckBox;
import backend.ui.PsychUINumericStepper;
import backend.ui.PsychUIButton;
import backend.ui.PsychUIEventHandler;
import states.editors.content.PsychJsonPrinter; // This one still exists in 1.0.4

import openfl.display.BitmapData;

// ZIP support
import haxe.zip.Reader;
import haxe.zip.Writer;
import haxe.zip.Entry;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

using StringTools;

class CharacterEditorState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent {
	// ------------------------------------------------------------------------------------
	// CORE VARIABLES
	// ------------------------------------------------------------------------------------
	var character:Character;

	// Ghost preview (PNG or ZIP atlas)
	var ghost:FlxSprite;
	var ghostSymbol:String = null;
	var ghostFrame:Int = 0;

	// Follow pointer (camera target)
	var followObj:FlxObject;

	// Silhouettes
	var silhouettes:FlxSpriteGroup;
	var dadPos:FlxPoint = new FlxPoint(100, 150);
	var bfPos:FlxPoint = new FlxPoint(750, 150);

	// Animation list UI text
	var animListTxt:FlxText;
	var curAnim:Int = 0;

	// Cameras
	var camEditor:FlxCamera;
	var camHUD:FlxCamera;

	// UI
	var ui_main:PsychUIBox;
	var ui_char:PsychUIBox;

	// Help screen
	var helpBG:FlxSprite;
	var helpText:FlxSpriteGroup;

	// UI indicators
	var zoomText:FlxText;
	var frameText:FlxText;

	// Health bar + icon
	var healthBar:Bar;
	var healthIcon:HealthIcon;

	// Character currently being edited
	var charName:String;
	var returnToPlaystate:Bool;

	// Offset copying system
	var copiedOffset:Array<Float> = [0, 0];
	var undoOffset:Array<Float> = null;

	// ------------------------------------------------------------------------------------
	// CONSTRUCTOR
	// ------------------------------------------------------------------------------------

	public function new(c:String = null, goBack:Bool = true) {
		charName = (c != null ? c : "bf");
		returnToPlaystate = goBack;
		super();
	}

	// ------------------------------------------------------------------------------------
	// CREATE()
	// ------------------------------------------------------------------------------------

	override function create() {
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		// Stop menu music
		FlxG.sound.music.stop();

		// Cameras
		camEditor = new FlxCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;

		FlxG.cameras.reset(camEditor);
		FlxG.cameras.add(camHUD, false);

		// Background
		createBG();

		// Silhouettes
		silhouettes = new FlxSpriteGroup();
		add(silhouettes);
		createSilhouettes();

		// Character
		character = new Character(0, 0, charName, !isOpponent(charName));
		character.debugMode = true;
		add(character);

		updateCharPosition();

		// Ghost preview
		ghost = new FlxSprite();
		ghost.visible = false;
		add(ghost);

		// Camera follow object
		followObj = new FlxObject(0, 0, 1, 1);
		add(followObj);

		// UI Text
		createUIText();

		// UI panels
		createUIMenus();

		// Health bar
		createHealthUI();

		// Help screen
		createHelpMenu();

		FlxG.mouse.visible = true;

		updateAnimList();

		super.create();
	}

	// ------------------------------------------------------------------------------------
	// BACKGROUND
	// ------------------------------------------------------------------------------------

	function createBG() {
		// Use the base stage just like Psych's Character Editor
		var bg:FlxSprite = new FlxSprite(-600, -250).loadGraphic(Paths.image("stageback"));
		bg.scrollFactor.set(0.9, 0.9);
		add(bg);

		var front:FlxSprite = new FlxSprite(-650, 600).loadGraphic(Paths.image("stagefront"));
		front.setGraphicSize(Std.int(front.width * 1.1));
		front.updateHitbox();
		front.scrollFactor.set(0.9, 0.9);
		add(front);
	}

	// ------------------------------------------------------------------------------------
	// SILHOUETTES
	// ------------------------------------------------------------------------------------

	function createSilhouettes() {
		var silDad = new FlxSprite(dadPos.x, dadPos.y).loadGraphic(Paths.image("editors/silhouetteDad"));
		silDad.antialiasing = ClientPrefs.data.antialiasing;
		silDad.active = false;
		silDad.alpha = 0.30;
		silhouettes.add(silDad);

		var silBF = new FlxSprite(bfPos.x, bfPos.y + 350).loadGraphic(Paths.image("editors/silhouetteBF"));
		silBF.antialiasing = ClientPrefs.data.antialiasing;
		silBF.active = false;
		silBF.alpha = 0.30;
		silhouettes.add(silBF);
	}

	// ------------------------------------------------------------------------------------
	// CHARACTER POSITIONING
	// ------------------------------------------------------------------------------------

	function isOpponent(name:String):Bool {
		// Psych’s native logic simplified:
		if (name == "bf" || name.startsWith("bf-") || name.endsWith("-player"))
			return false;
		return true;
	}

	function updateCharPosition() {
		if (character.isPlayer) {
			character.setPosition(bfPos.x + character.positionArray[0], bfPos.y + character.positionArray[1]);
		} else {
			character.setPosition(dadPos.x + character.positionArray[0], dadPos.y + character.positionArray[1]);
		}

		updateFollowPos();
	}

	function updateFollowPos() {
		var mid = character.getMidpoint();

		var offX:Float = 0;
		var offY:Float = 0;

		if (!character.isPlayer) {
			offX = mid.x + 150 + character.cameraPosition[0];
			offY = mid.y - 100 + character.cameraPosition[1];
		} else {
			offX = mid.x - 100 - character.cameraPosition[0];
			offY = mid.y - 100 + character.cameraPosition[1];
		}

		followObj.x = offX;
		followObj.y = offY;

		// Snap camera (used only when character loads)
		FlxG.camera.scroll.x = followObj.x - FlxG.width / 2;
		FlxG.camera.scroll.y = followObj.y - FlxG.height / 2;
	}

	// ------------------------------------------------------------------------------------
	// ANIMATION LIST TEXT + UPDATE
	// ------------------------------------------------------------------------------------

	function createUIText() {
		animListTxt = new FlxText(10, 32, 400, "");
		animListTxt.setFormat(null, 16, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
		animListTxt.scrollFactor.set();
		animListTxt.cameras = [camHUD];
		animListTxt.borderSize = 1;
		add(animListTxt);

		zoomText = new FlxText(0, 50, 200, "Zoom: 1x");
		zoomText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		zoomText.borderSize = 1;
		zoomText.scrollFactor.set();
		zoomText.screenCenter(X);
		zoomText.cameras = [camHUD];
		add(zoomText);

		frameText = new FlxText(0, 75, 300, "");
		frameText.setFormat(null, 16, FlxColor.WHITE, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		frameText.borderSize = 1;
		frameText.scrollFactor.set();
		frameText.screenCenter(X);
		frameText.cameras = [camHUD];
		add(frameText);

		var tip:FlxText = new FlxText(FlxG.width - 300, FlxG.height - 24, 300, "Press F1 for Help", 20);
		tip.cameras = [camHUD];
		tip.setFormat(null, 16, FlxColor.WHITE, RIGHT, OUTLINE_FAST, FlxColor.BLACK);
		tip.borderSize = 1;
		tip.scrollFactor.set();
		tip.active = false;
		add(tip);
	}

	function updateAnimList() {
		animListTxt.text = "";

		var index = 0;
		for (a in character.animationsArray) {
			var line = a.anim + ": " + a.offsets;

			if (index == curAnim)
				animListTxt.text += "> " + line + "\n";
			else
				animListTxt.text += "  " + line + "\n";

			index++;
		}
	}

	// ------------------------------------------------------------------------------------
	// HEALTH BAR + ICON
	// ------------------------------------------------------------------------------------

	function createHealthUI() {
		healthBar = new Bar(30, FlxG.height - 75);
		healthBar.scrollFactor.set();
		healthBar.cameras = [camHUD];
		add(healthBar);

		healthIcon = new HealthIcon(character.healthIcon, false, false);
		healthIcon.y = FlxG.height - 150;
		healthIcon.cameras = [camHUD];
		add(healthIcon);

		applyHealthColor();
	}

	function applyHealthColor() {
		var c = character.healthColorArray;
		healthBar.leftBar.color = healthBar.rightBar.color = FlxColor.fromRGB(c[0], c[1], c[2]);
		healthIcon.changeIcon(character.healthIcon, false);
	}

	// ------------------------------------------------------------------------------------
	// UI PANEL SETUP
	// ------------------------------------------------------------------------------------

	function createUI() {
		uiBox = new PsychUIBox(FlxG.width - 420, 10, 400, FlxG.height - 20);
		uiBox.cameras = [camHUD];
		add(uiBox);

		var title = new FlxText(0, 0, 380, "Character Editor Settings");
		title.setFormat(null, 20, FlxColor.YELLOW, CENTER, OUTLINE_FAST, FlxColor.BLACK);
		title.borderSize = 1;
		title.x = uiBox.x + 10;
		title.y = uiBox.y + 10;
		title.cameras = [camHUD];
		add(title);

		// Character select dropdown ---------------------------------------------
		var charList:Array<String> = Character.loadCharacterList();
		characterDropdown = new PsychUIDropDownMenu(uiBox.x + 10, uiBox.y + 55, 380, charList);
		characterDropdown.cameras = [camHUD];
		characterDropdown.eventHandler = this;
		add(characterDropdown);

		// Image input -----------------------------------------------------------
		imageInput = new PsychUIInputText(uiBox.x + 10, uiBox.y + 110, 180, "");
		imageInput.cameras = [camHUD];
		add(imageInput);

		// Reload button ---------------------------------------------------------
		var reloadBtn = new PsychUIButton(uiBox.x + 200, uiBox.y + 110, 180, 30, "Reload Character");
		reloadBtn.cameras = [camHUD];
		reloadBtn.onClick = function() {
			reloadCharacter(characterName, true);
		};
		add(reloadBtn);
	}

	// ------------------------------------------------------------------------------------
	// CHARACTER LOADING
	// ------------------------------------------------------------------------------------

	function reloadCharacter(name:String, resetCamera:Bool = false) {
		if (Std.isOfType(character, Character))
			remove(character);

		characterName = name;

		character = new Character(0, 0, name, false);

		add(character);

		// UI sync
		imageInput.text = character.image;

		// position character properly
		updateCharPosition();

		if (resetCamera) {
			FlxG.camera.zoom = 1;
			updateFollowPos();
		}

		updateAnimList();
		updateFrameText();
	}

	// ------------------------------------------------------------------------------------
	// GHOST LOADING (PRELOAD ALL ANIMATIONS FOR PREVIEW)
	// ------------------------------------------------------------------------------------

	function loadGhost() {
		if (ghost != null)
			remove(ghost);

		ghost = new Character(0, 0, characterName, false);
		ghost.alpha = 0.25;
		ghost.visible = showGhost;
		add(ghost);

		updateGhostPosition();
	}

	function updateGhostPosition() {
		if (ghost == null)
			return;

		if (ghost.isPlayer)
			ghost.setPosition(bfPos.x + ghost.positionArray[0], bfPos.y + ghost.positionArray[1]);
		else
			ghost.setPosition(dadPos.x + ghost.positionArray[0], dadPos.y + ghost.positionArray[1]);
	}

	// ------------------------------------------------------------------------------------
	// ZIP + PNG HANDLING (Matches Your Character.hx)
	// ------------------------------------------------------------------------------------

	inline function hasZip(image:String):Bool {
		var path = Paths.modFolders("images/" + image + ".zip");
		return FileSystem.exists(path);
	}

	function reloadImage() {
		var img = imageInput.text.trim();
		if (img.length < 1)
			return;

		character.image = img;

		// reload character with updated image
		reloadCharacter(characterName, false);

		// reload ghost
		loadGhost();
	}

	// ------------------------------------------------------------------------------------
	// FRAME TEXT UPDATE (Used in Part 4)
	// ------------------------------------------------------------------------------------

	function updateFrameText() {
		if (character.atlas != null) {
			frameText.text = "Symbol: " + character.getSymbolName() + " / Frame: " + character.getFrame() + " / Total: "
				+ character.getFrameCount(character.getSymbolName());
		} else {
			frameText.text = "No Atlas Loaded";
		}
	}

	// ------------------------------------------------------------------------------------
	// ANIMATION LIST + CONTROLS
	// ------------------------------------------------------------------------------------

	function playAnim(name:String) {
		if (character == null)
			return;

		character.playAnim(name, true);

		// sync ghost
		if (ghost != null)
			ghost.playAnim(name, true);

		updateFrameText();
	}

	// ------------------------------------------------------------------------------------
	// OFFSET EDITOR
	// ------------------------------------------------------------------------------------

	function createOffsetUI() {
		var yStart = uiBox.y + 210;

		var label = new FlxText(uiBox.x + 10, yStart, 200, "Offsets (X / Y)");
		label.setFormat(null, 14, FlxColor.WHITE);
		label.cameras = [camHUD];
		add(label);

		offsetX = new PsychUINumericStepper(uiBox.x + 10, yStart + 30, 100, 1, -2000, 2000);
		offsetX.cameras = [camHUD];
		offsetX.eventHandler = this;
		add(offsetX);

		offsetY = new PsychUINumericStepper(uiBox.x + 150, yStart + 30, 100, 1, -2000, 2000);
		offsetY.cameras = [camHUD];
		offsetY.eventHandler = this;
		add(offsetY);

		// apply instantly
		applyOffsetBtn = new PsychUIButton(uiBox.x + 10, yStart + 70, 380, 30, "Apply Offset");
		applyOffsetBtn.cameras = [camHUD];
		applyOffsetBtn.onClick = function() {
			applyOffsets();
		};
		add(applyOffsetBtn);
	}

	function applyOffsets() {
		if (character == null)
			return;

		character.offset.set(offsetX.value, offsetY.value);

		// ghost follow
		if (ghost != null)
			ghost.offset.set(offsetX.value, offsetY.value);
	}

	function syncOffsetUI() {
		offsetX.value = Std.int(character.offset.x);
		offsetY.value = Std.int(character.offset.y);
	}

	// ------------------------------------------------------------------------------------
	// ANIMATION STEP / FRAME CONTROL
	// ------------------------------------------------------------------------------------

	function createFrameUI() {
		var yStart = uiBox.y + 310;

		var label = new FlxText(uiBox.x + 10, yStart, 200, "Frame Controls");
		label.setFormat(null, 14, FlxColor.WHITE);
		label.cameras = [camHUD];
		add(label);

		var prevBtn = new PsychUIButton(uiBox.x + 10, yStart + 30, 120, 30, "< Prev Frame");
		prevBtn.cameras = [camHUD];
		prevBtn.onClick = function() stepFrame(-1);
		add(prevBtn);

		var nextBtn = new PsychUIButton(uiBox.x + 150, yStart + 30, 120, 30, "Next Frame >");
		nextBtn.cameras = [camHUD];
		nextBtn.onClick = function() stepFrame(1);
		add(nextBtn);

		var pauseBtn = new PsychUIButton(uiBox.x + 290, yStart + 30, 100, 30, "Pause/Play");
		pauseBtn.cameras = [camHUD];
		pauseBtn.onClick = togglePause;
		add(pauseBtn);
	}

	function stepFrame(dir:Int) {
		if (character == null)
			return;
		if (character.atlas == null)
			return;

		var symbol = character.getSymbolName();
		var total = character.getFrameCount(symbol);
		var frame = character.getFrame();

		frame += dir;

		if (frame < 0)
			frame = total - 1;
		if (frame >= total)
			frame = 0;

		character.setFrame(symbol, frame);
		if (ghost != null)
			ghost.setFrame(symbol, frame);

		updateFrameText();
	}

	function togglePause() {
		if (character == null)
			return;

		character.animPaused = !character.animPaused;

		if (ghost != null)
			ghost.animPaused = character.animPaused;
	}

	// ------------------------------------------------------------------------------------
	// ANIMATION EDITOR PANEL
	// ------------------------------------------------------------------------------------

	function createAnimationUI() {
		var yStart = uiBox.y + 370;

		var label = new FlxText(uiBox.x + 10, yStart, 300, "Animation Editor");
		label.setFormat(null, 16, FlxColor.CYAN);
		label.cameras = [camHUD];
		add(label);

		// FPS
		fpsStepper = new PsychUINumericStepper(uiBox.x + 10, yStart + 30, 100, 1, 1, 120);
		fpsStepper.cameras = [camHUD];
		fpsStepper.eventHandler = this;
		add(fpsStepper);

		var fpsLabel = new FlxText(uiBox.x + 120, yStart + 35, 60, "FPS");
		fpsLabel.setFormat(null, 14, FlxColor.WHITE);
		fpsLabel.cameras = [camHUD];
		add(fpsLabel);

		// Loop toggle
		loopCheckBox = new PsychUICheckBox(uiBox.x + 10, yStart + 70, "Loop Animation", false);
		loopCheckBox.cameras = [camHUD];
		loopCheckBox.eventHandler = this;
		add(loopCheckBox);

		// Index edit input
		indicesInput = new PsychUIInputText(uiBox.x + 10, yStart + 110, 380, "");
		indicesInput.cameras = [camHUD];
		add(indicesInput);

		var indexLabel = new FlxText(uiBox.x + 10, yStart + 90, 180, "Frame Indices (comma-separated)");
		indexLabel.setFormat(null, 14, FlxColor.GRAY);
		indexLabel.cameras = [camHUD];
		add(indexLabel);

		// ADD animation button
		var addBtn = new PsychUIButton(uiBox.x + 10, yStart + 150, 180, 30, "Add Animation");
		addBtn.cameras = [camHUD];
		addBtn.onClick = function() {
			addAnimation();
		};
		add(addBtn);

		// DELETE animation button
		var delBtn = new PsychUIButton(uiBox.x + 210, yStart + 150, 180, 30, "Delete Animation");
		delBtn.cameras = [camHUD];
		delBtn.onClick = function() {
			deleteAnimation();
		};
		add(delBtn);

		syncAnimationUI();
	}

	// ------------------------------------------------------------------------------------
	// APPLYING EDIT CHANGES
	// ------------------------------------------------------------------------------------

	function syncAnimationUI() {
		if (character == null || animDropdown == null)
			return;

		var name = animDropdown.selectedLabel;
		var info = character.getAnimationData(name);

		if (info == null)
			return;

		fpsStepper.value = info.fps;
		loopCheckBox.checked = info.loop;

		indicesInput.text = info.indices.length > 0 ? info.indices.join(",") : "";
	}

	function applyAnimChanges() {
		if (character == null)
			return;
		if (animDropdown == null)
			return;

		var name = animDropdown.selectedLabel;

		var fps = Std.int(fpsStepper.value);
		var loop = loopCheckBox.checked;

		var indexList:Array<Int> = [];
		if (indicesInput.text.trim().length > 0) {
			var split = indicesInput.text.split(",");
			for (s in split) {
				var v = Std.parseInt(s.trim());
				if (v != null)
					indexList.push(v);
			}
		}

		character.updateAnimationSettings(name, fps, loop, indexList);

		if (ghost != null)
			ghost.updateAnimationSettings(name, fps, loop, indexList);

		updateFrameText();
	}

	// ------------------------------------------------------------------------------------
	// ADD / DELETE ANIMATIONS
	// ------------------------------------------------------------------------------------

	function addAnimation() {
		var newName = "newAnim" + FlxG.random.int(0, 999);

		character.addAnimation(newName);
		if (ghost != null)
			ghost.addAnimation(newName);

		updateAnimList();
		animDropdown.selectLabel(newName);
		syncAnimationUI();

		FlxG.sound.play(Paths.sound("confirmMenu"));
	}

	function deleteAnimation() {
		if (animDropdown == null)
			return;

		var name = animDropdown.selectedLabel;
		if (name == "idle")
			return; // cannot delete idle

		character.deleteAnimation(name);
		if (ghost != null)
			ghost.deleteAnimation(name);

		updateAnimList();
		syncAnimationUI();
	}

	// ------------------------------------------------------------------------------------
	// SAVE CHARACTER JSON
	// ------------------------------------------------------------------------------------

	function saveCharacterFile() {
		if (character == null)
			return;

		var outPath = Paths.modFolders("characters/" + characterName + ".json");

		var json = character.exportToJSON();
		File.saveContent(outPath, json);

		FlxG.sound.play(Paths.sound("confirmMenu"));
		trace("Saved character: " + outPath);
	}

	// ============================================================
	// ZIP EXPORT
	// ============================================================

	function exportAsZip() {
		if (character == null)
			return;

		var outName = characterName + ".zip";
		var savePath = Paths.modFolders("images/" + outName);

		trace("Export ZIP -> " + savePath);

		var zipEntries = new List<Entry>();

		// ---------------------------------------
		// 1. data.json
		// ---------------------------------------
		var charJson = character.exportAtlasJSON();
		var dataBytes = Bytes.ofString(charJson);
		zipEntries.add(makeZipEntry("data.json", dataBytes));

		// ---------------------------------------
		// 2. symbols/*.png
		// ---------------------------------------
		var symbolMap = character.exportSymbols();

		for (symbolName => bmpData in symbolMap.keyValueIterator()) {
			var pngBytes = bitmapToPNG(bmpData);
			zipEntries.add(makeZipEntry("symbols/" + symbolName + ".png", pngBytes));
		}

		// ---------------------------------------
		// 3. Write ZIP file
		// ---------------------------------------
		var out = new BytesOutput();
		var writer = new Writer(out);

		writer.write(zipEntries);

		File.saveBytes(savePath, out.getBytes());

		FlxG.sound.play(Paths.sound("confirmMenu"));
		trace("ZIP saved successfully!");
	}

	inline function makeZipEntry(path:String, bytes:Bytes):Entry {
		var entry:Entry = {
			fileName: path,
			fileSize: bytes.length,
			fileTime: Date.now(),
			compressed: false,
			dataSize: bytes.length,
			data: bytes,
			crc32: haxe.crypto.Crc32.make(bytes)
		};
		return entry;
	}

	// ============================================================
	// ZIP IMPORT
	// ============================================================

	function importZip() {
		var file:String = dialogOpenFile("zip");

		if (file == null || file.length == 0)
			return;

		trace("Import ZIP: " + file);

		var bytes = File.getBytes(file);
		var reader = new Reader(new BytesInput(bytes));
		var entries = reader.read();

		var tempFolder = Paths.modFolders("images/__temp_import_" + characterName + "/");
		if (!sys.FileSystem.exists(tempFolder))
			sys.FileSystem.createDirectory(tempFolder);

		var symbolFolder = tempFolder + "symbols/";
		if (!sys.FileSystem.exists(symbolFolder))
			sys.FileSystem.createDirectory(symbolFolder);

		var newJson:String = null;

		// Extract all files
		for (e in entries) {
			var dest = tempFolder + e.fileName;
			var folder = haxe.io.Path.directory(dest);

			if (!sys.FileSystem.exists(folder))
				sys.FileSystem.createDirectory(folder);

			File.saveBytes(dest, e.data);

			if (e.fileName == "data.json")
				newJson = e.data.toString();
		}

		if (newJson == null) {
			FlxG.log.error("ZIP missing data.json!");
			return;
		}

		// Reload
		character.loadFromZipFolder(tempFolder);
		loadGhost();

		updateAnimList();
		syncAnimationUI();

		FlxG.sound.play(Paths.sound("confirmMenu"));
	}

	// ============================================================
	// SPRITESHEET (PNG + XML) EXPORT
	// ============================================================

	function exportPngXml() {
		if (character == null)
			return;

		var output = Paths.modFolders("images/" + characterName + "_sheet.png");
		var outputXml = Paths.modFolders("images/" + characterName + ".xml");

		var sheet = character.buildSpritesheet();
		var xml = character.buildSpritesheetXML();

		File.saveBytes(output, bitmapToPNG(sheet));
		File.saveContent(outputXml, xml);

		FlxG.sound.play(Paths.sound("confirmMenu"));
		trace("PNG + XML export finished!");
	}

	function bitmapToPNG(bmp:BitmapData):Bytes {
		var png = new PNGEncoderOptions();
		return bmp.encode(bmp.rect, png);
	}

	// ============================================================
	// FILE PICKER HELPERS
	// ============================================================

	function dialogOpenFile(ext:String):String {
		var filter:Array<FileFilter> = [];
		filter.push(new FileFilter(ext.toUpperCase() + " files", "*." + ext));
		filter.push(new FileFilter("All files", "*.*"));

		return FileDialog.open("Select " + ext.toUpperCase() + " file", "", filter);
	}
}
