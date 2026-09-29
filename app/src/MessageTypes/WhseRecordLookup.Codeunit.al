namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Record lookup for warehouse message types.
/// Same rules as Foundation's internal FindRecordByIdentifiers: subject and request JSON
/// keys are tried, and the error response is written on Argument when no single record results.
/// </summary>
codeunit 10078455 "Whse Record Lookup ori"
{
    Access = Internal;

    var
        SubjectSourceTok: Label 'subject', Locked = true;
        GuidTok: Label 'GUID', Locked = true;
        IntegerTok: Label 'integer', Locked = true;
        IdentifierMissingErr: Label '%1 identifier is missing. Pass it as the subject, or as one of: %2.', Comment = '%1 = table caption, %2 = accepted JSON keys, is-IS=Auðkenni vantar fyrir %1. Sendu það sem subject eða sem eitt af: %2.';
        IdentifierMissingNextStepTxt: Label 'Send the number or SystemId as the subject, or in one of: %1.', Comment = '%1 = accepted JSON keys, is-IS=Sendu númerið eða SystemId sem subject eða í einu af: %1.';
        IdentifierNotFoundErr: Label '%1 "%2" was not found (from %3).', Comment = '%1 = table caption, %2 = value received, %3 = subject or JSON key, is-IS=%1 "%2" fannst ekki (úr %3).';
        IdentifierNotFoundNextStepTxt: Label 'Check the number with Data.Records.Get on table %1.', Comment = '%1 = table caption, is-IS=Athugaðu númerið með Data.Records.Get á töflunni %1.';
        IdentifierAmbiguousErr: Label '%1 "%2" matches more than one document. Pass it as one of: %3.', Comment = '%1 = table caption, %2 = value received, %3 = JSON keys of the matching document types, is-IS=%1 "%2" passar við fleiri en eitt skjal. Sendu það sem eitt af: %3.';
        IdentifierAmbiguousNextStepTxt: Label 'Send the number again in the key of the document type you mean: %1.', Comment = '%1 = JSON keys, is-IS=Sendu númerið aftur í lyklinum fyrir þá skjalagerð sem þú átt við: %1.';
        IdentifiersDisagreeErr: Label 'The identifiers in %1 and %2 point to different records.', Comment = '%1 = first source, %2 = second source, is-IS=Auðkennin í %1 og %2 vísa á mismunandi færslur.';
        IdentifiersDisagreeNextStepTxt: Label 'Send only one identifier: %1 or %2.', Comment = '%1 = first source, %2 = second source, is-IS=Sendu aðeins eitt auðkenni: %1 eða %2.';
        IdentifiersConflictErr: Label 'The request identifies more than one %1.', Comment = '%1 = table caption, is-IS=Beiðnin auðkennir fleiri en eitt %1.';
        InvalidIdentifierFormatErr: Label '"%1" is not a valid %2 (from %3).', Comment = '%1 = value received, %2 = expected format, %3 = subject or JSON key, is-IS="%1" er ekki gilt %2 (úr %3).';
        RecordNotFoundSummaryErr: Label '%1 was not found.', Comment = '%1 = table caption, is-IS=%1 fannst ekki.';

    /// <summary>
    /// Finds one record from the subject and the request JSON keys.
    /// </summary>
    /// <param name="Argument">The message argument. Receives the error response when lookup fails.</param>
    /// <param name="TableNo">The table to look in.</param>
    /// <param name="SubjectSpec">What a subject can be, separated by '|': guid, no, entry, or doc&lt;ordinal&gt;:&lt;key&gt;.</param>
    /// <param name="KeySpec">Request JSON keys and their kinds, separated by commas, e.g. systemId=guid,no=no.</param>
    /// <param name="FoundSystemId">Receives the SystemId of the record found.</param>
    /// <returns>True when exactly one record was found.</returns>
    procedure FindRecord(var Argument: Record "Message Argument ori"; TableNo: Integer; SubjectSpec: Text; KeySpec: Text; var FoundSystemId: Guid): Boolean
    var
        RecordReference: RecordRef;
        RequestJson: JsonObject;
        Token: JsonToken;
        LookupErrors: JsonArray;
        ConflictError: JsonObject;
        Entry: JsonToken;
        KeyEntry: Text;
        KeyName: Text;
        KeyNames: TextBuilder;
        Value: Text;
        FoundSource: Text;
        TableCaptionText: Text;
        Supplied: Boolean;
    begin
        Clear(FoundSystemId);
        RecordReference.Open(TableNo);
        TableCaptionText := RecordReference.Caption();
        if Argument.Subject <> '' then begin
            Supplied := true;
            TryIdentifier(RecordReference, SubjectSpec, Argument.Subject, SubjectSourceTok, FoundSystemId, FoundSource, LookupErrors, ConflictError);
        end;
        RequestJson := Argument.GetRequestJson();
        foreach KeyEntry in KeySpec.Split(',') do begin
            KeyName := KeyEntry.Split('=').Get(1);
            if KeyNames.Length() > 0 then
                KeyNames.Append(', ');
            KeyNames.Append(KeyName);
            if RequestJson.Get(KeyName, Token) then begin
                Value := Argument.TokenAsText(Token);
                if Value <> '' then begin
                    Supplied := true;
                    TryIdentifier(RecordReference, KeyEntry.Split('=').Get(2), Value, KeyName, FoundSystemId, FoundSource, LookupErrors, ConflictError);
                end;
            end;
        end;
        RecordReference.Close();

        if ConflictError.Keys().Count() > 0 then begin
            FlushOneError(Argument, ConflictError);
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(IdentifiersConflictErr, TableCaptionText));
            exit(false);
        end;
        if not IsNullGuid(FoundSystemId) then
            exit(true);
        if not Supplied then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(IdentifierMissingErr, TableCaptionText, KeyNames.ToText()), '', '', '', StrSubstNo(IdentifierMissingNextStepTxt, KeyNames.ToText()));
        foreach Entry in LookupErrors do
            FlushOneError(Argument, Entry.AsObject());
        Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(RecordNotFoundSummaryErr, TableCaptionText));
        exit(false);
    end;

    local procedure TryIdentifier(var RecordReference: RecordRef; Kinds: Text; Value: Text; IdentifierSource: Text; var FoundSystemId: Guid; var FoundSource: Text; var LookupErrors: JsonArray; var ConflictError: JsonObject)
    var
        Kind: Text;
        CandidateSystemId: Guid;
        MatchSystemId: Guid;
        MatchKeys: TextBuilder;
        Matches: Integer;
        EntryNo: Integer;
        IsGuidValue: Boolean;
        TriedKey: Boolean;
    begin
        IsGuidValue := Evaluate(CandidateSystemId, Value);
        foreach Kind in Kinds.Split('|') do
            if Kind = 'guid' then begin
                if IsGuidValue then begin
                    TriedKey := true;
                    if FindBySystemId(RecordReference, CandidateSystemId) then begin
                        Matches += 1;
                        MatchSystemId := CandidateSystemId;
                    end;
                end;
            end else
                if not IsGuidValue then begin
                    TriedKey := true;
                    if Kind = 'entry' then
                        if not Evaluate(EntryNo, Value, 9) then begin
                            LookupErrors.Add(BuildErrorEntry("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(InvalidIdentifierFormatErr, Value, IntegerTok, IdentifierSource), IdentifierSource, Value, IntegerTok, ''));
                            exit;
                        end;
                    if FindByKey(RecordReference, DocumentKindOrdinal(Kind), Value) then begin
                        Matches += 1;
                        MatchSystemId := RecordReference.Field(RecordReference.SystemIdNo()).Value();
                        if MatchKeys.Length() > 0 then
                            MatchKeys.Append(', ');
                        MatchKeys.Append(DocumentKindKey(Kind, IdentifierSource));
                    end;
                end;

        if not TriedKey then begin
            LookupErrors.Add(BuildErrorEntry("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(InvalidIdentifierFormatErr, Value, GuidTok, IdentifierSource), IdentifierSource, Value, GuidTok, ''));
            exit;
        end;
        case Matches of
            0:
                LookupErrors.Add(BuildErrorEntry("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(IdentifierNotFoundErr, RecordReference.Caption(), Value, IdentifierSource), IdentifierSource, Value, '', StrSubstNo(IdentifierNotFoundNextStepTxt, RecordReference.Caption())));
            1:
                if IsNullGuid(FoundSystemId) then begin
                    FoundSystemId := MatchSystemId;
                    FoundSource := IdentifierSource;
                end else
                    if MatchSystemId <> FoundSystemId then
                        ConflictError := BuildErrorEntry("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(IdentifiersDisagreeErr, FoundSource, IdentifierSource), IdentifierSource, Value, '', StrSubstNo(IdentifiersDisagreeNextStepTxt, FoundSource, IdentifierSource));
            else
                LookupErrors.Add(BuildErrorEntry("Bifrost Error Code ori"::AmbiguousRecord, StrSubstNo(IdentifierAmbiguousErr, RecordReference.Caption(), Value, MatchKeys.ToText()), IdentifierSource, Value, '', StrSubstNo(IdentifierAmbiguousNextStepTxt, MatchKeys.ToText())));
        end;
    end;

    local procedure FindBySystemId(var RecordReference: RecordRef; RecordSystemId: Guid): Boolean
    var
        SystemIdField: FieldRef;
    begin
        RecordReference.Reset();
        SystemIdField := RecordReference.Field(RecordReference.SystemIdNo());
        SystemIdField.SetRange(RecordSystemId);
        exit(RecordReference.FindFirst());
    end;

    local procedure FindByKey(var RecordReference: RecordRef; DocumentTypeOrdinal: Integer; Value: Text): Boolean
    var
        DocumentTypeField: FieldRef;
        NoField: FieldRef;
        IntegerValue: Integer;
    begin
        RecordReference.Reset();
        if DocumentTypeOrdinal >= 0 then begin
            DocumentTypeField := RecordReference.Field(RecordReference.KeyIndex(1).FieldIndex(1).Number());
            DocumentTypeField.SetRange(DocumentTypeOrdinal);
            NoField := RecordReference.Field(RecordReference.KeyIndex(1).FieldIndex(2).Number());
        end else
            NoField := RecordReference.Field(RecordReference.KeyIndex(1).FieldIndex(1).Number());
        case NoField.Type() of
            FieldType::Integer:
                begin
                    if not Evaluate(IntegerValue, Value, 9) then
                        exit(false);
                    NoField.SetRange(IntegerValue);
                end;
            FieldType::Code:
                begin
                    if StrLen(Value) > NoField.Length() then
                        exit(false);
                    NoField.SetRange(UpperCase(Value));
                end;
            else begin
                if StrLen(Value) > NoField.Length() then
                    exit(false);
                NoField.SetRange(Value);
            end;
        end;
        exit(RecordReference.FindFirst());
    end;

    local procedure DocumentKindOrdinal(Kind: Text) Ordinal: Integer
    begin
        Ordinal := -1;
        if not Kind.StartsWith('doc') then
            exit;
        if not Evaluate(Ordinal, Kind.Split(':').Get(1).Substring(4), 9) then
            Ordinal := -1;
    end;

    local procedure DocumentKindKey(Kind: Text; IdentifierSource: Text): Text
    begin
        if Kind.Contains(':') then
            exit(Kind.Split(':').Get(2));
        exit(IdentifierSource);
    end;

    local procedure BuildErrorEntry(ErrorCode: Enum "Bifrost Error Code ori"; Message: Text; Parameter: Text; Received: Text; Expected: Text; NextStep: Text) Entry: JsonObject
    begin
        AddCodeProperty(Entry, 'code', ErrorCode);
        AddTextProperty(Entry, 'error', Message);
        AddTextProperty(Entry, 'parameter', Parameter);
        AddTextProperty(Entry, 'received', CopyStr(Received, 1, 250));
        AddTextProperty(Entry, 'expected', Expected);
        AddTextProperty(Entry, 'nextStep', NextStep);
    end;

    local procedure FlushOneError(var Argument: Record "Message Argument ori"; Entry: JsonObject)
    var
        Token: JsonToken;
        Parameter: Text;
        Received: Text;
        Expected: Text;
        NextStep: Text;
        Message: Text;
    begin
        Entry.Get('error', Token);
        Message := Token.AsValue().AsText();
        Parameter := ReadTextProperty(Entry, 'parameter');
        Received := ReadTextProperty(Entry, 'received');
        Expected := ReadTextProperty(Entry, 'expected');
        NextStep := ReadTextProperty(Entry, 'nextStep');
        Entry.Get('code', Token);
        Argument.AddError(ErrorCodeFromName(Token.AsValue().AsText()), Message, Parameter, Received, Expected, NextStep);
    end;

    local procedure ReadTextProperty(Entry: JsonObject; PropertyKey: Text): Text
    var
        Token: JsonToken;
    begin
        if not Entry.Get(PropertyKey, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure AddTextProperty(var Entry: JsonObject; PropertyKey: Text; Value: Text)
    begin
        if Value <> '' then
            Entry.Add(PropertyKey, Value);
    end;

    local procedure AddCodeProperty(var Entry: JsonObject; PropertyKey: Text; ErrorCode: Enum "Bifrost Error Code ori")
    begin
        if ErrorCode = "Bifrost Error Code ori"::None then
            exit;
        Entry.Add(PropertyKey, ErrorCodeName(ErrorCode));
    end;

    local procedure ErrorCodeName(ErrorCode: Enum "Bifrost Error Code ori"): Text
    var
        Index: Integer;
    begin
        Index := Enum::"Bifrost Error Code ori".Ordinals().IndexOf(ErrorCode.AsInteger());
        if Index = 0 then
            exit('');
        exit(Enum::"Bifrost Error Code ori".Names().Get(Index));
    end;

    local procedure ErrorCodeFromName(Name: Text): Enum "Bifrost Error Code ori"
    var
        Index: Integer;
    begin
        Index := Enum::"Bifrost Error Code ori".Names().IndexOf(Name);
        if Index = 0 then
            exit("Bifrost Error Code ori"::None);
        exit(Enum::"Bifrost Error Code ori".FromInteger(Enum::"Bifrost Error Code ori".Ordinals().Get(Index)));
    end;
}
