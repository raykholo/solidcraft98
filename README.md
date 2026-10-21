# SolidCraft 98

A parametric CAD program written the way it would have been written in 1999:
in Visual Basic, with an MDI window, a `TreeView`, a `ListView` in Report mode
and a wireframe viewport drawn with `Line`, one edge at a time.

It's a joke, but it works. You can sketch, extrude, revolve, drill a hole,
orbit the part, and save it to a file nobody else can read.

## What's in it

- A grey MDI main window with a menu bar, a toolbar of hand-drawn
  16-colour icons, and a status bar.
- Each part opens in its own child window, which you can minimise inside the
  app by accident.
- A feature tree on the left and a timeline along the bottom.
- A wireframe viewport. It starts isometric. Drag with the left button to
  orbit and the right button to pan; `+` and `-` zoom.
- Commands: Sketch Rectangle, Sketch Circle, Extrude, Revolve, and Hole (on
  the top face of a box). Plus Undo, Zoom to Fit and Regenerate.
- Save and Open use `Put` and `Get` on a single `Type`. Open a file from a
  newer version and you're told so. Open one from an older version and
  you're also told so.
- Number boxes go through `CDbl` with no validation, so typing `20mm` gets you
  a genuine `Run-time error '13': Type mismatch`. It's caught and shown, not
  a crash.
- An About box and a splash screen, both drawn in code.

## The Turbo button

Like the button on the front of a 1990s PC, except backwards. The LED next to
it reads 66 MHz normally and 33 MHz with Turbo on, and Turbo switches on the
authentic 1999 behaviour. With Turbo off, everything just works.

With Turbo on:

- **Regenerate** (F5) says "Did not converge. Try again." twice, then
  succeeds on the third press. The solver uses a `Variant`.
- **Orbit** is capped at 4 frames a second, and the status bar says so.
- **"20mm" in a number box** escalates: Type mismatch, then Still a type
  mismatch, then "It's a TextBox, not a mind reader", then a tip about
  `Val()`. On the fifth try it gives up and takes 20.
- **Dividing by zero** in a number box (they take arithmetic, so `40/0`)
  gets a full-screen blue fatal exception. Press any key; the part is fine.
  With Turbo off it's a plain run-time error 11.
- **File > Send To 3 1/2 Floppy (A:)** saves the part to the hard disk, then
  "copies" it to three floppies, asking for each disk. Turbo saves include an
  uncompressed preview bitmap, for speed.
- **Y2K**: on 31 December 1999 by the PC's clock, at midnight, every
  dimension becomes 19100 mm. Start with `SolidCraft98.exe /Y2KTEST` to see
  it a minute after launch without touching the clock.
- **DLL Hell**: Help > About, Shift-click the logo. A setup program copies
  MSCOMCTL.OCX over itself to 112% and asks you to restart Windows.

Either way:

- **Cal**, the caliper assistant, notices when you sketch a rectangle.
- **Type WIN98** in the About box for the demo-scene credits.
- **The Konami code** in the viewport (up up down down left right left right
  B A) spins the part at full speed for three seconds: "60 fps (lying)".
- **File > Publish to Web** writes a home page for the part: a marquee, a hit
  counter, an animated "under construction" GIF and a picture of the part.

Every one of these is only drawn on screen. Nothing touches system files,
the clock or a disk drive, and no design is ever lost.

## Keys

| Key | Command |
|---|---|
| Ctrl+N / Ctrl+O / Ctrl+S | New, Open, Save |
| Ctrl+Z | Undo last feature |
| R, C | Sketch rectangle, sketch circle |
| E, V, H | Extrude, Revolve, Hole |
| I, F | Isometric view, Zoom to fit |
| F5 | Regenerate |
| F1 | Help (it isn't installed) |

## Everything is a command

In 1999 the Extrude logic would have lived in `cmdExtrude_Click`, been
copy-pasted into `mnuExtrude_Click` and again into `Form_KeyDown`, and the
three copies would have drifted apart by the second release.

Here the joke stays in this paragraph. The toolbar, the menus and the
keyboard all call `RunCommand "Extrude"` in `modCommands.bas`, and there is
one copy of each command.

## Source

The source is plain VB6 text: `src/SolidCraft98.vbp` plus `.frm` and `.bas`
files. There are no `.frx` files: the icons, the logo and the splash are
drawn at startup.

| File | What it does |
|---|---|
| `frmMain.frm` | MDI frame: menus, toolbar, status bar |
| `frmPart.frm` | A part window: tree, viewport, timeline |
| `frmParams.frm` | The one dialog every command uses for its numbers |
| `frmAbout.frm`, `frmSplash.frm` | About box and splash |
| `modCommands.bas` | Every command, once |
| `modModel.bas` | The design `Type`, the feature list, Save and Open |
| `modKernel.bas` | Turns features into edges (the "geometry kernel") |
| `modView.bas` | Projection, orbit, drawing |
| `modBars.bas` | The toolbar and status bar, drawn in PictureBoxes |
| `modIcons.bas` | Toolbar icons as 16x16 text pixel art |
| `modClassic.bas` | Keeps the classic look on modern Windows; coloured text |
| `modTurbo.bas` | The Turbo button and the 1999 behaviour behind it |
| `modExpr.bas` | Arithmetic in number boxes |
| `modGif.bas`, `modPublish.bas` | GIF writer and Publish to Web |
| `frmFloppy`, `frmFatal`, `frmSetup`, `frmCal`, `frmCredits` | The easter eggs |

The toolbar and status bar are drawn by hand rather than taken from
MSCOMCTL.OCX, because that OCX doesn't ship with current Windows. The
TreeView and ListView are the MSCOMCTL ones as far as VB6 is concerned.

## Building

It builds with [twinBASIC](https://twinbasic.com), from the command line:

```
python3 tools/vb2tb.py src/SolidCraft98.vbp build/src
python3 tools/impexp.py import build/SolidCraft98.twinproj build/src --overwrite
twinBASIC.exe build\SolidCraft98.twinproj --buildAndExit32
```

`vb2tb.py` does what twinBASIC's own VBP import does, without the IDE: it
turns each `.frm` into twinBASIC's form format, converts twips to pixels,
maps the MSCOMCTL TreeView and ListView onto twinBASIC's built-in common
controls, and embeds the manifest and the icon. `impexp.py` is twinBASIC's
own MIT-licensed import/export tool, which packs the folder into a project.
The EXE lands in `build/Build/`.

A VB6 IDE should open `SolidCraft98.vbp` as it is. Put
`SolidCraft98.exe.manifest` next to the EXE you make.

## Where it runs

Windows 11, where it was built and tested, and ReactOS 0.4.16, the free
NT-compatible operating system. On ReactOS, with the Classic theme at
800x600, it looks the way it was always meant to: grey 3D chrome and blue
gradient title bars. The same `.sc98` files open on both. On a screen too
small for the window it starts maximised.

## Tools

| Tool | What it does |
|---|---|
| `tools/vb2tb.py` | VB6 project to twinBASIC source folder |
| `tools/impexp.py` | twinBASIC's project packer (MIT, unchanged) |
| `tools/pixpng.py` | Renders the icons in `modIcons.bas` to a PNG |
| `tools/mkico.py` | Makes `SolidCraft98.ico` from the "App" icon |
