{ uExpr - number boxes take arithmetic: 40/2+5, (10+2)*3, -8.
  Anything that isn't a number or + - * / ( ) is error 13 (type mismatch),
  as VB's CDbl would say; dividing by zero is error 11. }
unit uExpr;

{$mode objfpc}{$H+}

interface

var
  ExprError: Integer;        // 0, 11 or 13 after Evaluate

function Evaluate(const s: string): Double;
{ What VB's Val makes of it: the digits and one dot from the start. }
function ValLike(const t: string): Double;

implementation

uses SysUtils;

var
  Src: string;               // the expression, spaces taken out
  P: Integer;

function Peek: Char;
begin
  if P <= Length(Src) then Result := Src[P] else Result := #0;
end;

function ParseSum: Double; forward;

{ What VB's Val makes of digits and dots: "1.2.3" is 1.2. }
function ValLike(const t: string): Double;
var
  k, dots: Integer;
  fs: TFormatSettings;
  num: string;
  neg: Boolean;
begin
  num := TrimLeft(t);
  neg := (num <> '') and (num[1] = '-');
  if (num <> '') and (num[1] in ['-', '+']) then Delete(num, 1, 1);
  dots := 0;
  k := 1;
  while (k <= Length(num)) and (num[k] in ['0'..'9', '.']) do
  begin
    if num[k] = '.' then
    begin
      Inc(dots);
      if dots > 1 then Break;
    end;
    Inc(k);
  end;
  num := Copy(num, 1, k - 1);
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if (num <> '') and (num[1] = '.') then num := '0' + num;       // ".5"
  if (num <> '') and (num[Length(num)] = '.') then num := num + '0';   // "5."
  Result := StrToFloatDef(num, 0, fs);
  if neg then Result := -Result;
end;

function ParseFactor: Double;
var
  start: Integer;
  ch: Char;
  v: Double;
begin
  Result := 0;
  if ExprError <> 0 then Exit;
  ch := Peek;
  if ch = '-' then
  begin
    Inc(P);
    Exit(-ParseFactor());
  end;
  if ch = '(' then
  begin
    Inc(P);
    Result := ParseSum;
    if Peek <> ')' then begin ExprError := 13; Exit(0); end;
    Inc(P);
    Exit;
  end;
  start := P;
  while (P <= Length(Src)) and (Src[P] in ['0'..'9', '.']) do Inc(P);
  if P = start then begin ExprError := 13; Exit(0); end;
  v := ValLike(Copy(Src, start, P - start));
  Result := v;
end;

function ParseProduct: Double;
var
  op: Char;
  dv: Double;
begin
  Result := ParseFactor;
  repeat
    if ExprError <> 0 then Exit(0);
    op := Peek;
    if (op <> '*') and (op <> '/') then Break;
    Inc(P);
    if op = '*' then Result := Result * ParseFactor
    else
    begin
      dv := ParseFactor;
      if (ExprError = 0) and (dv = 0) then begin ExprError := 11; Exit(0); end;
      Result := Result / dv;
    end;
  until False;
end;

function ParseSum: Double;
var
  op: Char;
begin
  Result := ParseProduct;
  repeat
    if ExprError <> 0 then Exit(0);
    op := Peek;
    if (op <> '+') and (op <> '-') then Break;
    Inc(P);
    if op = '+' then Result := Result + ParseProduct
    else Result := Result - ParseProduct;
  until False;
end;

function Evaluate(const s: string): Double;
var
  i: Integer;
begin
  Src := '';
  for i := 1 to Length(s) do
    if s[i] <> ' ' then Src := Src + s[i];
  P := 1;
  ExprError := 0;
  if Src = '' then begin ExprError := 13; Exit(0); end;
  Result := ParseSum;
  if (ExprError = 0) and (P <= Length(Src)) then ExprError := 13;
end;

end.
