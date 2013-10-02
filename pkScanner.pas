unit pkScanner;

interface

uses
  System.SysUtils,
  Generics.Collections;

type
  TLexemCode = (lcUnknown, lcReservedWord, lcIdentificator, lcConstant, lcInteger, lcFloat, lcError, lcSeparator,
    lcOperation, lcChar, lcString);

  TScannerState = (ssNone, ssInComment, ssInString, ssInStringQuote, ssInOperation);

  TOperationType = (ptAdd, ptSub, ptMulti, ptDiv, ptIntDiv, ptMode, { } ptNone);
  TReserwedWordType = (rwArray, { } rwNone);

  TLexem = record
    Code: TLexemCode;
    Value: String;
    ValueInt: Integer;
    ValueFloat: Extended;
    ValueChar: Char;
    ValueOperation: TOperationType;
    ValueSeparator: Char;
    ValueReserwedWord: TReserwedWordType;
    Row: Integer;
    Col: Integer;
  end;

  TPasScanner = class
  private
    CurRow: LongInt;
    CurCol: LongInt;
    RCurLexem: TLexem;
    REndOfScan: Boolean;
    RFile: TextFile;
    RReservedWords: TList<String>;
    ROperations: TList<String>;
    ROperators: set of Char;
    RLangSymbols: set of Char;
    RSeparators: set of Char;
    RSkipSymbols: set of Char;
    RPointersSymbols: set of Char;
    RReadNextChar: Boolean;
    RCurChar: Char;
    procedure Init;
    procedure ClearCurLexem;
    function IsIdentificator(S: String): Boolean;
    function IsReservedWord(S: String): Boolean;
    function IsOperation(S: String): Boolean;
    function IsConstant(S: String): Boolean;
    function IsChar(S: String): Boolean;
  public
    property EndOfScan: Boolean read REndOfScan;
    property CurLexem: TLexem read RCurLexem;
    constructor Create;
    procedure ScanFile(FileName: String);
    destructor Free;
    function Next: Boolean;
    function NextAndGet: TLexem;
  end;

implementation

{ TPasScaner }

function TPasScanner.IsChar(S: String): Boolean;
var
  i: Integer;
begin
  Result := true;
  if Length(S) < 2 then Exit(false);
  if S[1] <> '#' then Exit(false);
  for i := 2 to Length(S) do
    if not(S[i] in ['0' .. '9']) then Exit(false);
end;

function TPasScanner.IsConstant(S: String): Boolean;
var
  i, t: Integer;
  F: Boolean;
begin
  if S = '' then Exit(false);
  S := AnsiUpperCase(S);
  Result := true;
  t := 0;
  if (S[1] = '$') and (Length(S) > 1) then t := 1;
  for i := 1 + t to Length(S) do
    if (S[i] in ['.', '0' .. '9']) or ((t = 1) and (S[i] in ['A' .. 'F'])) then begin
      if (t = 1) and (S[i] = '.') then Exit(false);
      if (S[i] = '.') and ((i = Length(S)) or (i = 1)) then Exit(false);
    end
    else Exit(false);
end;

function TPasScanner.IsIdentificator(S: String): Boolean;
var
  i: Integer;
begin
  if Length(S) = 0 then Exit(false);
  Result := true;
  if not(S[1] in ['A' .. 'Z', 'a' .. 'z']) or (IsOperation(S)) then Exit(false);
  for i := 2 to Length(S) do
    if not(S[i] in ['0' .. '9', 'A' .. 'Z', 'a' .. 'z']) then Exit(false);
end;

function TPasScanner.IsOperation(S: String): Boolean;
begin
  Exit(ROperations.Contains(AnsiUpperCase(S)));
end;

function TPasScanner.IsReservedWord(S: String): Boolean;
begin
  Exit(RReservedWords.Contains(AnsiUpperCase(S)));
end;

procedure TPasScanner.ScanFile(FileName: String);
begin
  CurRow := 1;
  CurCol := 1;
  ClearCurLexem;
  RReadNextChar := true;
  REndOfScan := false;
  assign(RFile, FileName);
  reset(RFile);
end;

procedure TPasScanner.ClearCurLexem;
begin
  with RCurLexem do begin
    Code := lcUnknown;
    Value := '';
    Row := -1;
    Col := -1;
  end;
end;

constructor TPasScanner.Create;
begin
  Init;
end;

destructor TPasScanner.Free;
begin
  RReservedWords.Free;
  ROperations.Free;
end;

procedure TPasScanner.Init;
begin
  RReservedWords := TList<String>.Create;
  with RReservedWords do begin
    Add('ARRAY');
    Add('BEGIN');
    Add('CASE');
    Add('CONST');
    Add('DO');
    Add('DOWNTO');
    Add('ELSE');
    Add('END');
    Add('FILE');
    Add('FOR');
    Add('FUNCTION');
    Add('GOTO');
    Add('IF');
    Add('IN');
    Add('LABEL');
    Add('NIL');
    Add('OF');
    Add('PROCEDURE');
    Add('PROGRAM');
    Add('RECORD');
    Add('REPEAT');
    Add('SET');
    Add('THEN');
    Add('TO');
    Add('TYPE');
    Add('UNTIL');
    Add('VAR');
    Add('WHILE');
    Add('WITH');
  end;
  // ----
  ROperations := TList<String>.Create;
  with ROperations do begin
    Add('+');
    Add('-');
    Add('*');
    Add('/');
    Add('DIV');
    Add('MOD');
    Add('<');
    Add('>');
    Add('<=');
    Add('>=');
    Add(':=');
    Add('=');
    Add('<>');
    Add('@');
    Add('^');
    Add('XOR');
    Add('NOT');
    Add('AND');
    Add('OR');
    Add('NOT');
    Add('SHL');
    Add('SHR');
  end;
  // ----
  RSeparators := [',', '(', ')', ';', '[', ']', ':'];
  ROperators := ['+', '-', '*', '/', '<', '>', '=', ':'];
  RPointersSymbols := ['@', '^'];
  RLangSymbols := ['A' .. 'Z', '0' .. '9', '_'];
  RSkipSymbols := [' ', #9];
end;

function TPasScanner.Next: Boolean;
var
  i, j: Integer;
  State, PreviousState: TScannerState;

  procedure AssignLex(LexCode: TLexemCode; newCurRow, newCurCol: Integer);
  begin
    with RCurLexem do begin
      if LexCode = lcConstant then begin
        if (trystrtoint(Value, ValueInt)) then LexCode := lcInteger
        else if (not trystrtofloat(Value, ValueFloat)) then LexCode := lcFloat
        else LexCode := lcError;
      end;
      if (LexCode = lcChar) then
        try
          ValueChar := chr(StrToInt(Copy(Value, 2, Length(Value) - 1)));
        except
          LexCode := lcError;
        end;
      if (LexCode = lcString) and (Length(Value) = 1) then begin
        ValueChar := Value[1];
        LexCode := lcChar;
      end;
      if (LexCode = lcOperation) then ValueOperation := TOperationType(ROperations.IndexOf(Value))
      else ValueOperation := ptNone;
      if (LexCode = lcReservedWord) then ValueReserwedWord := TReserwedWordType(RReservedWords.IndexOf(Value))
      else ValueReserwedWord := rwNone;
      if (LexCode = lcSeparator) then ValueSeparator := Value[1]
      else ValueSeparator := #0;
      Code := LexCode;
      Col := CurCol;
      Row := CurRow;
    end;
    CurRow := newCurRow;
    CurCol := newCurCol;
  end;

  procedure DoChecks(i, j: Integer);
  begin
    if (IsOperation(RCurLexem.Value)) then AssignLex(lcOperation, i, j)
    else if (IsReservedWord(RCurLexem.Value)) then AssignLex(lcReservedWord, i, j)
    else if (IsIdentificator(RCurLexem.Value)) then AssignLex(lcIdentificator, i, j)
    else if (IsConstant(RCurLexem.Value)) then AssignLex(lcConstant, i, j)
    else if (IsChar(RCurLexem.Value)) then AssignLex(lcChar, i, j)
    else if (Length(RCurLexem.Value) = 1) and (RCurLexem.Value[1] in RSeparators) then AssignLex(lcSeparator, i, j)
    else AssignLex(lcError, i, j);
  end;

begin
  if REndOfScan then Exit(false);
  Result := true;
  ClearCurLexem;
  j := CurCol;
  i := CurRow;
  State := ssNone;
  PreviousState := ssNone;
  if EOF(RFile) and (RReadNextChar = false) then begin
    RCurLexem.Value := RCurChar;
    DoChecks(i, j);
  end;
  while not EOF(RFile) do begin
    if i <> CurRow then j := 1;
    if State = ssInString then begin
      AssignLex(lcError, i, j);
      Exit;
    end;
    if RCurLexem.Value <> '' then begin
      DoChecks(i, j);
      RReadNextChar := true;
      Exit;
    end;
    while not EOln(RFile) do begin
      if RReadNextChar then read(RFile, RCurChar);
      RReadNextChar := true;
      if (RCurChar = '''') and not(State in [ssInString, ssInStringQuote]) and (RCurLexem.Value <> '') then begin
        DoChecks(i, j);
        RReadNextChar := false;
        Exit;
      end;

      if (RCurChar = '{') and (State <> ssInComment) then begin
        PreviousState := State;
        State := ssInComment;
        Inc(j);
        continue;
      end;

      if (RCurChar = '}') and (State = ssInComment) then begin
        State := PreviousState;
        Inc(j);
        continue;
      end;

      if (State = ssInComment) then begin
        Inc(j);
        continue;
      end;

      if (RCurChar = '''') and not(State in [ssInString, ssInStringQuote]) then begin
        State := ssInString;
        Inc(j);
        continue;
      end;

      if (State = ssInStringQuote) and (RCurChar <> '''') then begin
        AssignLex(lcString, i, j);
        RReadNextChar := false;
        Exit;
      end;

      if (State = ssInString) and (RCurChar = '''') then begin
        State := ssInStringQuote;
        RReadNextChar := true;
        Inc(j);
        continue;
      end;

      if (State = ssInStringQuote) and (RCurChar = '''') then State := ssInString;

      if (AnsiUpperCase(CurLexem.Value) = 'END') and (RCurChar = '.') then begin
        AssignLex(lcReservedWord, i, Succ(j));
        RReadNextChar := false;
        REndOfScan := true;
        Exit;
      end;

      if (RCurChar in RPointersSymbols) and (RCurLexem.Value = '') then begin
        RCurLexem.Value := RCurChar;
        AssignLex(lcOperation, i, Succ(j));
        Exit;
      end;

      if (RCurLexem.Value = '/') and (RCurChar = '/') then begin
        RCurLexem.Value := '';
        State := ssNone;
        break;
      end;

      if (State = ssInOperation) and (not(RCurChar in ROperators - ['/'])) then begin
        DoChecks(i, j);
        RReadNextChar := false;
        Exit;
      end;

      if (RCurChar in RSeparators) and (RCurLexem.Value = '') and (RCurChar <> ':') then begin
        RCurLexem.Value := RCurChar;
        AssignLex(lcSeparator, i, j);
        Exit;
      end;

      if not(State in [ssInOperation, ssInString]) and (RCurLexem.Value <> '') and
        (RCurChar in RSeparators + ROperators + RSkipSymbols + RPointersSymbols + ['#']) then begin
        DoChecks(i, j);
        RReadNextChar := false;
        Exit;
      end;

      if not(State in [ssInString, ssInStringQuote]) then begin
        if (RCurChar in ROperators) then State := ssInOperation
        else State := ssNone;
      end;

      if not(RCurChar in RSkipSymbols) then RCurLexem.Value := RCurLexem.Value + RCurChar;

      Inc(j);
    end;
    readln(RFile);
    Inc(i);
  end;
  if State = ssInStringQuote then AssignLex(lcString, i, j)
  else if RCurLexem.Value <> '' then DoChecks(i, j)
  else Result := false;
  REndOfScan := true;
  closefile(RFile);
end;

function TPasScanner.NextAndGet: TLexem;
begin
  Next;
  Exit(RCurLexem);
end;

end.
