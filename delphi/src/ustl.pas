{ uStl - Export for Rapid Prototyping: the part as a binary STL file.
  The 1989 rules: every triangle faces out, neighbours share whole edges,
  everything in the all-positive corner of space, millimetres. The header
  must not begin with "solid", or some programs read the file as text. }
unit uStl;

{$mode objfpc}{$H+}

interface

uses uMesh;

function WriteStl(const t: TTriArray; n: Integer; const APath, ATitle: string): Boolean;

implementation

uses SysUtils, Classes, Math;

function WriteStl(const t: TTriArray; n: Integer; const APath, ATitle: string): Boolean;
var
  fs: TFileStream;
  i: Integer;
  mx, my, mz, nx, ny, nz: Double;
  hdr: array[0..79] of AnsiChar;
  h: AnsiString;
  cnt: LongWord;
  attr: Word;

  procedure PutS(v: Double);
  var
    s: Single;
  begin
    s := v;
    fs.WriteBuffer(s, 4);
  end;

begin
  Result := False;
  if n = 0 then Exit;
  // the lowest corner, so everything can be moved to x, y, z >= 0
  mx := t[0].X1; my := t[0].Y1; mz := t[0].Z1;
  for i := 0 to n - 1 do
    with t[i] do
    begin
      mx := Min(mx, Min(X1, Min(X2, X3)));
      my := Min(my, Min(Y1, Min(Y2, Y3)));
      mz := Min(mz, Min(Z1, Min(Z2, Z3)));
    end;
  h := 'Binary STL from SolidCraft 98: ' + ATitle + ', mm';
  FillChar(hdr, SizeOf(hdr), ' ');
  Move(h[1], hdr, Min(80, Length(h)));
  try
    if FileExists(APath) then DeleteFile(APath);
    fs := TFileStream.Create(APath, fmCreate);
  except
    Exit;
  end;
  try
    fs.WriteBuffer(hdr, 80);
    cnt := n;
    fs.WriteBuffer(cnt, 4);
    attr := 0;
    for i := 0 to n - 1 do
      with t[i] do
      begin
        TriNormal(t[i], nx, ny, nz);
        PutS(nx); PutS(ny); PutS(nz);
        PutS(X1 - mx); PutS(Y1 - my); PutS(Z1 - mz);
        PutS(X2 - mx); PutS(Y2 - my); PutS(Z2 - mz);
        PutS(X3 - mx); PutS(Y3 - my); PutS(Z3 - mz);
        fs.WriteBuffer(attr, 2);
      end;
    Result := True;
  finally
    fs.Free;
  end;
end;

end.
