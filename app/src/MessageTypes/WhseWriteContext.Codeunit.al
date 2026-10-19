namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Shared state and request readers for the warehouse write message types (bins, default bin,
/// movements, inventory picks, inventory put-aways, inventory movements and bin replenishment).
/// Codeunit.Run cannot take the request record, so each implementation stores its validated payload
/// here before it runs itself in isolation, and reads the result back afterwards.
/// </summary>
codeunit 10078430 "Whse Write Context ori"
{
    Access = Internal;
    SingleInstance = true;

    var
        PayloadText: Text;
        ResultText: Text;
        HasResultJson: Boolean;
        ResultNo: Code[20];
        ResultQty: Decimal;
        HasResultNo: Boolean;
        SnapshotLineNo: Integer;
        HasSnapshot: Boolean;

    /// <summary>Stores the payload the isolated run will write.</summary>
    /// <param name="Payload">Normalized request that already passed validation.</param>
    internal procedure SetPayload(Payload: JsonObject)
    begin
        PayloadText := '';
        Payload.WriteTo(PayloadText);
    end;

    /// <summary>Reads the payload stored for the isolated run.</summary>
    /// <param name="Payload">Receives the payload.</param>
    /// <returns>True when a payload is present and parses.</returns>
    internal procedure TryGetPayload(var Payload: JsonObject): Boolean
    begin
        if PayloadText = '' then
            exit(false);
        exit(Payload.ReadFrom(PayloadText));
    end;

    /// <summary>Stores the JSON result produced by the isolated run.</summary>
    /// <param name="Result">Created, posted or registered document result.</param>
    internal procedure SetResult(Result: JsonObject)
    begin
        ResultText := '';
        Result.WriteTo(ResultText);
        HasResultJson := ResultText <> '';
    end;

    /// <summary>Reads the JSON result of the isolated run.</summary>
    /// <param name="Result">Receives the result.</param>
    /// <returns>True when the run stored a result.</returns>
    internal procedure TryGetResult(var Result: JsonObject): Boolean
    begin
        Clear(Result);
        if not HasResultJson then
            exit(false);
        exit(Result.ReadFrom(ResultText));
    end;

    /// <summary>Stores the document number and quantity produced by the isolated run.</summary>
    /// <param name="DocumentNo">Created or registered document number.</param>
    /// <param name="Quantity">Registered quantity, or zero for a create.</param>
    internal procedure SetResult(DocumentNo: Code[20]; Quantity: Decimal)
    begin
        ResultNo := DocumentNo;
        ResultQty := Quantity;
        HasResultNo := DocumentNo <> '';
    end;

    /// <summary>Reads the document number and quantity of the isolated run.</summary>
    /// <param name="DocumentNo">Receives the document number.</param>
    /// <param name="Quantity">Receives the quantity.</param>
    /// <returns>True when the run stored a document number.</returns>
    internal procedure TryGetResult(var DocumentNo: Code[20]; var Quantity: Decimal): Boolean
    begin
        DocumentNo := ResultNo;
        Quantity := ResultQty;
        exit(HasResultNo);
    end;

    /// <summary>Stores the highest worksheet line number that existed before a report ran.</summary>
    /// <param name="LineNo">Zero when the worksheet had no lines.</param>
    internal procedure SetSnapshot(LineNo: Integer)
    begin
        SnapshotLineNo := LineNo;
        HasSnapshot := true;
    end;

    /// <summary>Reads the worksheet line number stored before the report ran.</summary>
    /// <param name="LineNo">Receives the snapshot.</param>
    /// <returns>True when the run stored a snapshot.</returns>
    internal procedure TryGetSnapshot(var LineNo: Integer): Boolean
    begin
        LineNo := SnapshotLineNo;
        exit(HasSnapshot);
    end;

    /// <summary>Drops the payload, results and snapshot so a later call cannot reuse them.</summary>
    internal procedure Reset()
    begin
        PayloadText := '';
        ResultText := '';
        HasResultJson := false;
        ResultNo := '';
        ResultQty := 0;
        HasResultNo := false;
        SnapshotLineNo := 0;
        HasSnapshot := false;
    end;

    /// <summary>Reads a text parameter from a request object.</summary>
    /// <param name="SourceJson">Request object or one line of it.</param>
    /// <param name="KeyName">Parameter name.</param>
    /// <param name="MaxLength">Maximum accepted length.</param>
    /// <param name="Argument">Collects format errors.</param>
    /// <param name="Value">Receives the text.</param>
    /// <param name="Present">True when a non-empty text was present.</param>
    /// <param name="ParameterName">Parameter path written on an error.</param>
    /// <returns>False when the value has the wrong JSON type or is too long.</returns>
    internal procedure ReadText(SourceJson: JsonObject; KeyName: Text; MaxLength: Integer; var Argument: Record "Message Argument ori"; var Value: Text; var Present: Boolean; ParameterName: Text): Boolean
    var
        Token: JsonToken;
        ValueText: Text;
        FormatLbl: Label 'Parameter %1 must be text.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera texti.';
        TooLongLbl: Label 'Parameter %1 is longer than %2 characters.', Comment = '%1 = parameter, %2 = maximum, is-IS=Færibreytan %1 er lengri en %2 stafir.';
        TooLongNextStepLbl: Label 'Send a shorter value.', Comment = 'is-IS=Sendu styttra gildi.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if not Token.IsValue() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, '', 'text', FormatNextStep());
            exit(false);
        end;
        if Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'text' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'text', FormatNextStep());
            exit(false);
        end;
        ValueText := Token.AsValue().AsText();
        if ValueText = '' then
            exit(true);
        if StrLen(ValueText) > MaxLength then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(TooLongLbl, KeyName, MaxLength), ParameterName, CopyStr(ValueText, 1, 80), 'text', TooLongNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := ValueText;
        exit(true);
    end;

    /// <summary>Reads a decimal parameter from a request object.</summary>
    /// <param name="SourceJson">Request object or one line of it.</param>
    /// <param name="KeyName">Parameter name.</param>
    /// <param name="Argument">Collects format errors.</param>
    /// <param name="Value">Receives the number.</param>
    /// <param name="Present">True when a number was present.</param>
    /// <param name="ParameterName">Parameter path written on an error.</param>
    /// <returns>False when the value is not a JSON number.</returns>
    internal procedure ReadDecimal(SourceJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: Decimal; var Present: Boolean; ParameterName: Text): Boolean
    var
        Token: JsonToken;
        FormatLbl: Label 'Parameter %1 must be a number.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera tala.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'number' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'number', FormatNextStep());
            exit(false);
        end;
        Present := true;
        Value := Token.AsValue().AsDecimal();
        exit(true);
    end;

    /// <summary>Reads an integer parameter from a request object.</summary>
    /// <param name="SourceJson">Request object or one line of it.</param>
    /// <param name="KeyName">Parameter name.</param>
    /// <param name="Argument">Collects format errors.</param>
    /// <param name="Value">Receives the integer.</param>
    /// <param name="Present">True when an integer was present.</param>
    /// <param name="ParameterName">Parameter path written on an error.</param>
    /// <returns>False when the value is not a whole number.</returns>
    internal procedure ReadInteger(SourceJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: Integer; var Present: Boolean; ParameterName: Text): Boolean
    var
        Token: JsonToken;
        Number: Decimal;
        FormatLbl: Label 'Parameter %1 must be an integer.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera heiltala.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'number' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'integer', FormatNextStep());
            exit(false);
        end;
        Number := Token.AsValue().AsDecimal();
        if Number <> Round(Number, 1) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'integer', FormatNextStep());
            exit(false);
        end;
        Present := true;
        Value := Token.AsValue().AsInteger();
        exit(true);
    end;

    /// <summary>Reads a boolean parameter from a request object.</summary>
    /// <param name="SourceJson">Request object.</param>
    /// <param name="KeyName">Parameter name.</param>
    /// <param name="Argument">Collects format errors.</param>
    /// <param name="Value">Receives the boolean.</param>
    /// <param name="Present">True when a boolean was present.</param>
    /// <param name="ParameterName">Parameter path written on an error.</param>
    /// <returns>False when the value is not a JSON boolean.</returns>
    internal procedure ReadBoolean(SourceJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: Boolean; var Present: Boolean; ParameterName: Text): Boolean
    var
        Token: JsonToken;
        FormatLbl: Label 'Parameter %1 must be true or false.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera true eða false.';
        FormatNextStepLbl: Label 'Send true or false.', Comment = 'is-IS=Sendu true eða false.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'boolean' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'boolean', FormatNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := Token.AsValue().AsBoolean();
        exit(true);
    end;

    /// <summary>Returns true only when the key holds the JSON boolean true. Format errors are left to the readers.</summary>
    /// <param name="SourceJson">Request object.</param>
    /// <param name="KeyName">Parameter name.</param>
    /// <returns>True when the value is the boolean true.</returns>
    internal procedure IsTrue(SourceJson: JsonObject; KeyName: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not SourceJson.Get(KeyName, Token) then
            exit(false);
        if ValueKind(Token) <> 'boolean' then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure FormatNextStep(): Text
    var
        FormatNextStepLbl: Label 'Send text for codes, numbers for quantities and true or false for options.', Comment = 'is-IS=Sendu texta fyrir kóða, tölur fyrir magn og true eða false fyrir val.';
    begin
        exit(FormatNextStepLbl);
    end;

    local procedure ReceivedText(Token: JsonToken): Text
    begin
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        if ValueKind(Token) in ['text', 'number', 'boolean'] then
            exit(CopyStr(Token.AsValue().AsText(), 1, 80));
        exit('');
    end;

    local procedure ValueKind(Token: JsonToken): Text
    var
        Written: Text;
    begin
        if not Token.IsValue() then
            exit('complex');
        if Token.AsValue().IsNull() then
            exit('null');
        Token.WriteTo(Written);
        if CopyStr(Written, 1, 1) = '"' then
            exit('text');
        if (Written = 'true') or (Written = 'false') then
            exit('boolean');
        exit('number');
    end;
}
