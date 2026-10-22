{ Checks the core against the Windows version's results, no UI. }
program coretest;
{$mode objfpc}{$H+}
uses SysUtils, uModel, uKernel, uMesh, uStl, uExpr, uImport;
var
  d: TDesign;
  e: TEdgeArray;
  t: TTriArray;
  r, i, n: Integer;
  serr, notice, err: string;
  names: array[0..2] of string = ('Plate with holes', 'Revolved parts', 'Flange');
  ex: array[0..5] of string = ('40/2+5', '(10+2)*3', '-8', '20mm', '40/0', '1.2.3');
  v: Double;
begin
  r := LoadDesign(d, 'tests/Mounting Plate.sc98');
  WriteLn('load ', r, ' "', d.Title, '" features ', d.Count);
  for i := 1 to d.Count do WriteLn('  ', i, ' ', d.F[i].Name, ' | ', KindName(d.F[i].Kind), ' | ', Describe(d, i));
  WriteLn('edges ', Regenerate(d, e));
  n := MeshDesign(d, t, MESH_SEGS, serr);
  WriteLn('triangles ', n, ' err "', serr, '"');
  WriteLn('stl ', WriteStl(t, n, 'tests/out/plate.stl', d.Title));
  WriteLn('save ', SaveDesign(d, 'tests/out/resaved.sc98'));
  for i := 0 to 2 do
  begin
    if ImportSolidCraft('tests/' + names[i] + '.solidcraft', d, notice, err) then
    begin
      WriteLn('import ', names[i], ': ', d.Count, ' features; notice: ', StringReplace(notice, LineEnding, ' / ', [rfReplaceAll]));
      for r := 1 to d.Count do WriteLn('  ', r, ' ', d.F[r].Name, ' | ', Describe(d, r));
      n := MeshDesign(d, t, MESH_SEGS, serr);
      WriteStl(t, n, 'tests/out/import' + IntToStr(i) + '.stl', d.Title);
    end
    else WriteLn('import ', names[i], ' FAILED: ', err);
  end;
  for i := 0 to 5 do
  begin
    v := Evaluate(ex[i]);
    WriteLn('eval "', ex[i], '" = ', FmtN(v, 3), ' err ', ExprError);
  end;
end.
