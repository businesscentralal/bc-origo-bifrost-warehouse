namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Holds the normalized movement payload and the number written by an isolated run.
/// Codeunit.Run cannot take the request record, so the implementation stores it here.
/// </summary>
codeunit 10078475 "Whse Movement Context ori"
{
    Access = Internal;
    SingleInstance = true;

    var
        PayloadText: Text;
        ResultNo: Code[20];
        ResultQty: Decimal;
        HasResult: Boolean;

    /// <summary>Stores the payload the isolated process will write.</summary>
    /// <param name="Payload">Normalized request that already passed validation.</param>
    internal procedure SetPayload(Payload: JsonObject)
    begin
        PayloadText := '';
        Payload.WriteTo(PayloadText);
    end;

    /// <summary>Reads the payload stored for the isolated process.</summary>
    /// <param name="Payload">Receives the payload.</param>
    /// <returns>True when a payload is present and parses.</returns>
    internal procedure TryGetPayload(var Payload: JsonObject): Boolean
    begin
        if PayloadText = '' then
            exit(false);
        exit(Payload.ReadFrom(PayloadText));
    end;

    /// <summary>Stores the document number and quantity produced by the isolated run.</summary>
    /// <param name="DocumentNo">Movement or registered movement number.</param>
    /// <param name="Quantity">Registered quantity, or zero for a create.</param>
    internal procedure SetResult(DocumentNo: Code[20]; Quantity: Decimal)
    begin
        ResultNo := DocumentNo;
        ResultQty := Quantity;
        HasResult := DocumentNo <> '';
    end;

    /// <summary>Reads the result of the isolated run.</summary>
    /// <param name="DocumentNo">Receives the document number.</param>
    /// <param name="Quantity">Receives the quantity.</param>
    /// <returns>True when the run stored a document number.</returns>
    internal procedure TryGetResult(var DocumentNo: Code[20]; var Quantity: Decimal): Boolean
    begin
        DocumentNo := ResultNo;
        Quantity := ResultQty;
        exit(HasResult);
    end;

    /// <summary>Drops the payload and result so a later call cannot reuse them.</summary>
    internal procedure Reset()
    begin
        PayloadText := '';
        ResultNo := '';
        ResultQty := 0;
        HasResult := false;
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
        FormatNextStepLbl: Label 'Send text for codes and numbers for quantities.', Comment = 'is-IS=Sendu texta fyrir kóða og tölur fyrir magn.';
        TooLongLbl: Label 'Parameter %1 is longer than %2 characters.', Comment = '%1 = parameter, %2 = maximum, is-IS=Færibreytan %1 er lengri en %2 stafir.';
        TooLongNextStepLbl: Label 'Send a shorter value.', Comment = 'is-IS=Sendu styttra gildi.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if not Token.IsValue() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, '', 'text', FormatNextStepLbl);
            exit(false);
        end;
        if Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'text' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'text', FormatNextStepLbl);
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
        FormatNextStepLbl: Label 'Send text for codes and numbers for quantities.', Comment = 'is-IS=Sendu texta fyrir kóða og tölur fyrir magn.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'number' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'number', FormatNextStepLbl);
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
        FormatNextStepLbl: Label 'Send text for codes and numbers for quantities.', Comment = 'is-IS=Sendu texta fyrir kóða og tölur fyrir magn.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() and Token.AsValue().IsNull() then
            exit(true);
        if ValueKind(Token) <> 'number' then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'integer', FormatNextStepLbl);
            exit(false);
        end;
        Number := Token.AsValue().AsDecimal();
        if Number <> Round(Number, 1) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText(Token), 'integer', FormatNextStepLbl);
            exit(false);
        end;
        Present := true;
        Value := Token.AsValue().AsInteger();
        exit(true);
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
