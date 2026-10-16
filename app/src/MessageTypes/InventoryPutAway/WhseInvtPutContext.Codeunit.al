namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Holds the normalized inventory-put-away payload and the JSON result of an isolated run.
/// Codeunit.Run cannot take the request record, so the implementation stores it here.
/// </summary>
codeunit 10078419 "Whse InvtPut Context ori"
{
    Access = Internal;
    SingleInstance = true;

    var
        PayloadText: Text;
        ResultText: Text;
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

    /// <summary>Stores the JSON result produced by the isolated run.</summary>
    /// <param name="Result">Created or posted inventory put-away result.</param>
    internal procedure SetResult(Result: JsonObject)
    begin
        ResultText := '';
        Result.WriteTo(ResultText);
        HasResult := ResultText <> '';
    end;

    /// <summary>Reads the result of the isolated run.</summary>
    /// <param name="Result">Receives the result.</param>
    /// <returns>True when the run stored a result.</returns>
    internal procedure TryGetResult(var Result: JsonObject): Boolean
    begin
        Clear(Result);
        if not HasResult then
            exit(false);
        exit(Result.ReadFrom(ResultText));
    end;

    /// <summary>Drops the payload and result so a later call cannot reuse them.</summary>
    internal procedure Reset()
    begin
        PayloadText := '';
        ResultText := '';
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
