{ uJson - reads JSON into a table of nodes, just arrays. A port of the
  Windows version's modJson. Nodes are numbered from 1; 0 means "none", so
  lookups chain without checking: JNum(JGet(JGet(r, 'a'), 'b')) is 0 when
  either key is missing. Strings stay UTF-8, as Lazarus likes them. }
unit uJson;

{$mode objfpc}{$H+}

interface

const
  JS_NULL = 0; JS_BOOL = 1; JS_NUM = 2; JS_STR = 3; JS_ARR = 4; JS_OBJ = 5;

var
  JsonErr: string;

function JsonParse(const s: RawByteString): Integer;
function JKind(n: Integer): Integer;
function JCount(n: Integer): Integer;
function JStr(n: Integer): string;
function JNum(n: Integer): Double;
function JBool(n: Integer): Boolean;
function JGet(n: Integer; const AKey: string): Integer;
function JItem(n, i: Integer): Integer;

implementation

uses SysUtils;

type
  TJNode = record
    Kind: Integer;
    Key: string;
    S: string;
    N: Double;
    First, NextSib, Count: Integer;
  end;
  EJson = class(Exception);

var
  Nodes: array of TJNode;
  NodeCount: Integer;
  Txt: RawByteString;
  Pos0: Integer;          // 1-based

procedure Fail(const t: string);
begin
  raise EJson.Create(t);
end;

function NewNode(kind: Integer): Integer;
begin
  Inc(NodeCount);
  if NodeCount >= Length(Nodes) then SetLength(Nodes, Length(Nodes) * 2 + 1024);
  Nodes[NodeCount] := Default(TJNode);
  Nodes[NodeCount].Kind := kind;
  Result := NodeCount;
end;

function Ch: Char; inline;
begin
  if Pos0 <= Length(Txt) then Result := Txt[Pos0] else Result := #0;
end;

procedure SkipSpace;
begin
  while (Pos0 <= Length(Txt)) and (Txt[Pos0] in [' ', #9, #10, #13]) do Inc(Pos0);
end;

function CodePointToUTF8(cp: LongWord): string;
begin
  if cp < $80 then Result := Chr(cp)
  else if cp < $800 then Result := Chr($C0 or (cp shr 6)) + Chr($80 or (cp and $3F))
  else Result := Chr($E0 or (cp shr 12)) + Chr($80 or ((cp shr 6) and $3F)) + Chr($80 or (cp and $3F));
end;

function ParseString: string;
var
  c: Char;
begin
  Result := '';
  Inc(Pos0);                       // the opening quote
  repeat
    if Pos0 > Length(Txt) then Fail('Unterminated string');
    c := Txt[Pos0];
    if c = '"' then
    begin
      Inc(Pos0);
      Break;
    end
    else if c = '\' then
    begin
      case Txt[Pos0 + 1] of
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'u': begin
               Result := Result + CodePointToUTF8(StrToInt('$' + Copy(Txt, Pos0 + 2, 4)));
               Inc(Pos0, 4);
             end;
      else
        Result := Result + Txt[Pos0 + 1];      // \" \\ \/
      end;
      Inc(Pos0, 2);
    end
    else
    begin
      Result := Result + c;
      Inc(Pos0);
    end;
  until False;
end;

function ParseValue: Integer; forward;

function ParseObject: Integer;
var
  child, last: Integer;
  key: string;
begin
  Result := NewNode(JS_OBJ);
  last := 0;
  Inc(Pos0);
  SkipSpace;
  if Ch = '}' then begin Inc(Pos0); Exit; end;
  repeat
    SkipSpace;
    if Ch <> '"' then Fail('Expected a member name');
    key := ParseString;
    SkipSpace;
    if Ch <> ':' then Fail('Expected :');
    Inc(Pos0);
    child := ParseValue;
    Nodes[child].Key := key;
    if last = 0 then Nodes[Result].First := child else Nodes[last].NextSib := child;
    last := child;
    Inc(Nodes[Result].Count);
    SkipSpace;
    case Ch of
      ',': Inc(Pos0);
      '}': begin Inc(Pos0); Break; end;
    else
      Fail('Expected , or }');
    end;
  until False;
end;

function ParseArray: Integer;
var
  child, last: Integer;
begin
  Result := NewNode(JS_ARR);
  last := 0;
  Inc(Pos0);
  SkipSpace;
  if Ch = ']' then begin Inc(Pos0); Exit; end;
  repeat
    child := ParseValue;
    if last = 0 then Nodes[Result].First := child else Nodes[last].NextSib := child;
    last := child;
    Inc(Nodes[Result].Count);
    SkipSpace;
    case Ch of
      ',': Inc(Pos0);
      ']': begin Inc(Pos0); Break; end;
    else
      Fail('Expected , or ]');
    end;
  until False;
end;

function ParseValue: Integer;
var
  start: Integer;
  s: string;
  fs: TFormatSettings;
begin
  SkipSpace;
  if Pos0 > Length(Txt) then Fail('The JSON ended early');
  case Ch of
    '{': Result := ParseObject;
    '[': Result := ParseArray;
    '"': begin
           s := ParseString;
           Result := NewNode(JS_STR);
           Nodes[Result].S := s;
         end;
    't', 'f', 'n':
      if Copy(Txt, Pos0, 4) = 'true' then
      begin
        Result := NewNode(JS_BOOL); Nodes[Result].N := 1; Inc(Pos0, 4);
      end
      else if Copy(Txt, Pos0, 5) = 'false' then
      begin
        Result := NewNode(JS_BOOL); Inc(Pos0, 5);
      end
      else if Copy(Txt, Pos0, 4) = 'null' then
      begin
        Result := NewNode(JS_NULL); Inc(Pos0, 4);
      end
      else
        Fail('Unexpected word in JSON');
  else
    start := Pos0;
    while (Pos0 <= Length(Txt)) and (Txt[Pos0] in ['0'..'9', '+', '-', '.', 'e', 'E']) do Inc(Pos0);
    if Pos0 = start then Fail('Unexpected character in JSON');
    Result := NewNode(JS_NUM);
    fs := DefaultFormatSettings;
    fs.DecimalSeparator := '.';
    Nodes[Result].N := StrToFloatDef(Copy(Txt, start, Pos0 - start), 0, fs);
  end;
end;

function JsonParse(const s: RawByteString): Integer;
begin
  Txt := s;
  if Copy(Txt, 1, 3) = #$EF#$BB#$BF then Delete(Txt, 1, 3);     // a byte order mark
  Pos0 := 1;
  NodeCount := 0;
  SetLength(Nodes, 1024);
  JsonErr := '';
  try
    SkipSpace;
    Result := ParseValue;
    SkipSpace;
    if Pos0 <= Length(Txt) then Fail('Unexpected text after the JSON value');
  except
    on e: Exception do
    begin
      JsonErr := e.Message;
      Result := 0;
    end;
  end;
end;

function JKind(n: Integer): Integer;
begin
  if n > 0 then Result := Nodes[n].Kind else Result := JS_NULL;
end;

function JCount(n: Integer): Integer;
begin
  if n > 0 then Result := Nodes[n].Count else Result := 0;
end;

function JStr(n: Integer): string;
begin
  Result := '';
  if n = 0 then Exit;
  case Nodes[n].Kind of
    JS_STR: Result := Nodes[n].S;
    JS_NUM: Result := FloatToStr(Nodes[n].N);
    JS_BOOL: if Nodes[n].N <> 0 then Result := 'true' else Result := 'false';
  end;
end;

function JNum(n: Integer): Double;
var
  fs: TFormatSettings;
begin
  Result := 0;
  if n = 0 then Exit;
  case Nodes[n].Kind of
    JS_NUM, JS_BOOL: Result := Nodes[n].N;
    JS_STR:
      begin
        fs := DefaultFormatSettings;
        fs.DecimalSeparator := '.';
        Result := StrToFloatDef(Nodes[n].S, 0, fs);
      end;
  end;
end;

function JBool(n: Integer): Boolean;
begin
  Result := (n > 0) and (Nodes[n].N <> 0);
end;

function JGet(n: Integer; const AKey: string): Integer;
var
  c: Integer;
begin
  Result := 0;
  if (n = 0) or (Nodes[n].Kind <> JS_OBJ) then Exit;
  c := Nodes[n].First;
  while c > 0 do
  begin
    if Nodes[c].Key = AKey then Exit(c);
    c := Nodes[c].NextSib;
  end;
end;

function JItem(n, i: Integer): Integer;
var
  c, k: Integer;
begin
  Result := 0;
  if n = 0 then Exit;
  c := Nodes[n].First;
  k := 0;
  while c > 0 do
  begin
    if k = i then Exit(c);
    Inc(k);
    c := Nodes[c].NextSib;
  end;
end;

end.
