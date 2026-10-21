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

The source is plain VB6 text: `SolidCraft98.vbp` plus `.frm` and `.bas`
files in `src/`. There are no `.frx` files: icons, the logo and the splash
are drawn at startup.

It builds with [twinBASIC](https://twinbasic.com), which reads VB6 projects.
Classic VB6 should open it too.

| File | What it does |
|---|---|
| `frmMain.frm` | MDI frame: menus, toolbar, status bar |
| `frmPart.frm` | A part window: tree, viewport, timeline |
| `frmParams.frm` | The one dialog every command uses for its numbers |
| `frmAbout.frm`, `frmSplash.frm` | About box and splash |
| `modCommands.bas` | Every command, once |
| `modModel.bas` | The design `Type`, feature list, save and open |
| `modKernel.bas` | Turns features into edges ("geometry kernel") |
| `modView.bas` | Projection, orbit, drawing |
| `modIcons.bas` | Toolbar icons as 16x16 text pixel art |

`tools/pixpng.py` renders the icons in `modIcons.bas` to a PNG, so you can
check them without building.
