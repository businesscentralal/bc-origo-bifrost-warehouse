namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Shared assertions that tie a runtime answer to the help of its message type (#71): the answered error code and
/// nextStep are declared in the errors chapter, and no help text names an AL object or an internal procedure.
/// </summary>
codeunit 97030 "Whse Contract Assert ori"
{
    Access = Internal;

    var
        Assert: Codeunit "Library Assert";

    /// <summary>
    /// Asserts that the error the runtime answered is declared in the errors chapter of the type: an entry with the same
    /// code and, when the answer has a nextStep, the same nextStep. The contract is English, so the answer must be too.
    /// </summary>
    /// <param name="MessageType">The message type that answered.</param>
    /// <param name="ResponseJson">The English answer.</param>
    internal procedure AssertAnswerDeclared(MessageType: Enum "Message Type ori"; ResponseJson: JsonObject)
    var
        ErrorCode: Text;
        NextStep: Text;
    begin
        ErrorCode := TextValue(ResponseJson, 'code');
        NextStep := TextValue(ResponseJson, 'nextStep');
        Assert.AreNotEqual('', ErrorCode, 'The answer has an error code: ' + ResponseText(ResponseJson));
        Assert.IsTrue(IsDeclared(MessageType, ErrorCode, NextStep), TypeName(MessageType) + ' declares ' + ErrorCode + ' with the nextStep "' + NextStep + '" in its errors chapter.');
    end;

    /// <summary>
    /// Asserts that the answer and every entry in its errors[] are declared in the errors chapter of the type (#74): the
    /// MultipleErrors answer and each problem it lists, each with its own code and nextStep.
    /// </summary>
    /// <param name="MessageType">The message type that answered.</param>
    /// <param name="ResponseJson">The English answer.</param>
    internal procedure AssertAnswerAndErrorsDeclared(MessageType: Enum "Message Type ori"; ResponseJson: JsonObject)
    var
        Token: JsonToken;
        Entry: JsonToken;
        ErrorCode: Text;
        NextStep: Text;
    begin
        AssertAnswerDeclared(MessageType, ResponseJson);
        if not ResponseJson.Get('errors', Token) then
            exit;
        if not Token.IsArray() then
            exit;
        foreach Entry in Token.AsArray() do begin
            ErrorCode := TextValue(Entry.AsObject(), 'code');
            NextStep := TextValue(Entry.AsObject(), 'nextStep');
            Assert.IsTrue(IsDeclared(MessageType, ErrorCode, NextStep), TypeName(MessageType) + ' declares the listed ' + ErrorCode + ' with the nextStep "' + NextStep + '" in its errors chapter.');
        end;
    end;

    /// <summary>
    /// Returns whether the errors chapter of the type has an entry with the code and, when given, the nextStep. A declared
    /// nextStep with the placeholders &lt;parameter&gt; and YYYY-MM-DD matches an answer that fills them in (#74).
    /// </summary>
    /// <param name="MessageType">The message type.</param>
    /// <param name="ErrorCode">The error code.</param>
    /// <param name="NextStep">The nextStep, or empty to match the code only.</param>
    /// <returns>True when such an entry exists.</returns>
    internal procedure IsDeclared(MessageType: Enum "Message Type ori"; ErrorCode: Text; NextStep: Text): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Token: JsonToken;
        Entry: JsonToken;
    begin
        if not ContractMgt.GetContract(MessageType, Contract) then
            exit(false);
        if not Contract.Get('errors', Token) then
            exit(false);
        foreach Entry in Token.AsArray() do
            if TextValue(Entry.AsObject(), 'code') = ErrorCode then
                if (NextStep = '') or NextStepMatches(TextValue(Entry.AsObject(), 'nextStep'), NextStep) then
                    exit(true);
        exit(false);
    end;

    /// <summary>
    /// Returns whether an answered nextStep matches a declared one: the same text, or the declared pattern with each
    /// placeholder (&lt;parameter&gt;, YYYY-MM-DD) standing for a non-empty part of the answer, e.g. "Resend &lt;parameter&gt; as
    /// YYYY-MM-DD." matches "Resend shipmentDateFrom as 2026-10-20.".
    /// </summary>
    /// <param name="Declared">The nextStep in the errors chapter.</param>
    /// <param name="Answered">The nextStep of the answer.</param>
    /// <returns>True when the answer matches.</returns>
    internal procedure NextStepMatches(Declared: Text; Answered: Text): Boolean
    var
        Segments: List of [Text];
        Segment: Text;
        Rest: Text;
        Position: Integer;
        Index: Integer;
    begin
        if Declared = Answered then
            exit(true);
        if not (Declared.Contains(ParameterPlaceholder()) or Declared.Contains(DatePlaceholder())) then
            exit(false);
        Segments := Declared.Replace(ParameterPlaceholder(), WildcardMark()).Replace(DatePlaceholder(), WildcardMark()).Split(WildcardMark());
        Rest := Answered;
        for Index := 1 to Segments.Count() do begin
            Segment := Segments.Get(Index);
            case true of
                Index = 1:
                    begin
                        if not Rest.StartsWith(Segment) then
                            exit(false);
                        Rest := CopyStr(Rest, StrLen(Segment) + 1);
                    end;
                Index = Segments.Count():
                    exit(Rest.EndsWith(Segment) and (StrLen(Rest) > StrLen(Segment)));
                else begin
                    Position := StrPos(CopyStr(Rest, 2), Segment);
                    if (Segment = '') or (Position = 0) then
                        exit(false);
                    Rest := CopyStr(Rest, Position + 1 + StrLen(Segment));
                end;
            end;
        end;
        exit(false);
    end;

    /// <summary>
    /// Asserts that a help text names no AL object, object number or internal procedure: no codeunit, no
    /// "report|table|page|codeunit|xmlport|query" followed by a number, no implementation codeunit name and no dispatcher
    /// procedure or option name.
    /// </summary>
    /// <param name="HelpText">The text to check.</param>
    /// <param name="Context">Names the type and chapter in the failure message.</param>
    internal procedure AssertNamesNoAlObject(HelpText: Text; Context: Text)
    var
        Forbidden: Text;
    begin
        Forbidden := FindAlReference(HelpText);
        Assert.AreEqual('', Forbidden, Context + ' names an AL object or internal procedure: "' + Forbidden + '"');
    end;

    /// <summary>Returns the first AL object or internal procedure reference in the text, or empty.</summary>
    /// <param name="HelpText">The text to check.</param>
    /// <returns>The offending fragment, or empty.</returns>
    internal procedure FindAlReference(HelpText: Text): Text
    var
        Lowered: Text;
        Fragment: Text;
        ObjectWord: Text;
    begin
        Lowered := LowerCase(HelpText);
        foreach Fragment in ForbiddenFragments() do
            if Lowered.Contains(LowerCase(Fragment)) then
                exit(Fragment);
        foreach ObjectWord in ObjectWords() do begin
            Fragment := NumberedObject(Lowered, ObjectWord);
            if Fragment <> '' then
                exit(Fragment);
        end;
        exit(IssueReference(Lowered));
    end;

    /// <summary>Returns the Warehouse.* message types.</summary>
    /// <returns>Every message type whose name starts with Warehouse.</returns>
    internal procedure WarehouseTypes() Types: List of [Enum "Message Type ori"]
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        Index: Integer;
    begin
        Names := Enum::"Message Type ori".Names();
        Ordinals := Enum::"Message Type ori".Ordinals();
        for Index := 1 to Names.Count() do
            if Names.Get(Index).StartsWith('Warehouse.') then
                Types.Add(Enum::"Message Type ori".FromInteger(Ordinals.Get(Index)));
    end;

    /// <summary>Returns the name of a message type.</summary>
    /// <param name="MessageType">The message type.</param>
    /// <returns>The enum value name, e.g. Warehouse.Pick.Create.</returns>
    internal procedure TypeName(MessageType: Enum "Message Type ori"): Text
    begin
        exit(Enum::"Message Type ori".Names().Get(Enum::"Message Type ori".Ordinals().IndexOf(MessageType.AsInteger())));
    end;

    local procedure ForbiddenFragments() Fragments: List of [Text]
    begin
        Fragments.Add('codeunit');
        Fragments.Add('Impl ori');
        Fragments.Add('Helper ori');
        Fragments.Add('Context ori');
        Fragments.Add('Lookup ori');
        Fragments.Add('Parts ori');
        Fragments.Add('Dispatcher.');
        Fragments.Add('OmitCommit');
        Fragments.Add('BC report');
        Fragments.Add('BC table');
        Fragments.Add('BC page');
        Fragments.Add('Whse.-');
    end;

    /// <summary>Returns the first issue reference (core#985, #71) in the text, or empty (#74).</summary>
    local procedure IssueReference(Lowered: Text): Text
    var
        Position: Integer;
        Offset: Integer;
        Start: Integer;
        NextChar: Text;
    begin
        Offset := 0;
        Position := StrPos(Lowered, '#');
        while Position > 0 do begin
            NextChar := CopyStr(Lowered, Offset + Position + 1, 1);
            if (NextChar <> '') and (StrPos('0123456789', NextChar) > 0) then begin
                Start := Offset + Position - 4;
                if Start < 1 then
                    Start := 1;
                exit(CopyStr(Lowered, Start, Offset + Position - Start + 6));
            end;
            Offset += Position;
            Position := StrPos(CopyStr(Lowered, Offset + 1), '#');
        end;
        exit('');
    end;

    local procedure ParameterPlaceholder(): Text
    begin
        exit('<parameter>');
    end;

    local procedure DatePlaceholder(): Text
    begin
        exit('YYYY-MM-DD');
    end;

    local procedure WildcardMark(): Text
    begin
        exit('|');
    end;

    local procedure ObjectWords() Words: List of [Text]
    begin
        Words.Add('report ');
        Words.Add('table ');
        Words.Add('page ');
        Words.Add('xmlport ');
        Words.Add('query ');
    end;

    local procedure NumberedObject(Lowered: Text; ObjectWord: Text): Text
    var
        Position: Integer;
        Offset: Integer;
        NextChar: Text;
    begin
        Offset := 0;
        Position := StrPos(Lowered, ObjectWord);
        while Position > 0 do begin
            NextChar := CopyStr(Lowered, Offset + Position + StrLen(ObjectWord), 1);
            if (NextChar <> '') and (StrPos('0123456789', NextChar) > 0) then
                exit(CopyStr(Lowered, Offset + Position, StrLen(ObjectWord) + 5));
            Offset += Position + StrLen(ObjectWord) - 1;
            Position := StrPos(CopyStr(Lowered, Offset + 1), ObjectWord);
        end;
        exit('');
    end;

    local procedure TextValue(Source: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not Source.Get(KeyName, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure ResponseText(ResponseJson: JsonObject) Result: Text
    begin
        ResponseJson.WriteTo(Result);
    end;
}
