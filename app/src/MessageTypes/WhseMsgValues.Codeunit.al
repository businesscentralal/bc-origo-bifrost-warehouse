namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Small shared readers for the warehouse journal, worksheet and activity line message types (#48-#50, #55-#57).
/// Payload values were validated before the isolated run, so these readers only read; request validation
/// stays in "Whse Write Context ori".
/// </summary>
codeunit 10078467 "Whse Msg Values ori"
{
    Access = Internal;

    /// <summary>Reads a text value, or an empty text when the key is missing or not a value.</summary>
    /// <param name="Parent">Object to read.</param>
    /// <param name="Name">Key name.</param>
    /// <returns>The text value.</returns>
    internal procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    /// <summary>Reads a decimal value, or zero.</summary>
    /// <param name="Parent">Object to read.</param>
    /// <param name="Name">Key name.</param>
    /// <returns>The number.</returns>
    internal procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;

    /// <summary>Reads an integer value, or zero.</summary>
    /// <param name="Parent">Object to read.</param>
    /// <param name="Name">Key name.</param>
    /// <returns>The integer.</returns>
    internal procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        if Token.AsValue().IsNull() then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;

    /// <summary>Reads a boolean value, or false.</summary>
    /// <param name="Parent">Object to read.</param>
    /// <param name="Name">Key name.</param>
    /// <returns>The boolean.</returns>
    internal procedure BooleanValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        if Token.AsValue().IsNull() then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;

    /// <summary>Reads a date written as YYYY-MM-DD, or 0D.</summary>
    /// <param name="Parent">Object to read.</param>
    /// <param name="Name">Key name.</param>
    /// <returns>The date.</returns>
    internal procedure DateValue(Parent: JsonObject; Name: Text): Date
    var
        Value: Date;
    begin
        if not Evaluate(Value, TextValue(Parent, Name), 9) then
            exit(0D);
        exit(Value);
    end;

    /// <summary>Returns the array under a key, or an empty array.</summary>
    /// <param name="Parent">Object to read.</param>
    /// <param name="Name">Key name.</param>
    /// <returns>The array.</returns>
    internal procedure ArrayValue(Parent: JsonObject; Name: Text): JsonArray
    var
        Token: JsonToken;
        Empty: JsonArray;
    begin
        if not Parent.Get(Name, Token) then
            exit(Empty);
        if not Token.IsArray() then
            exit(Empty);
        exit(Token.AsArray());
    end;

    /// <summary>Reads an optional date parameter written as YYYY-MM-DD.</summary>
    /// <param name="SourceJson">Request object or one line of it.</param>
    /// <param name="KeyName">Parameter name.</param>
    /// <param name="Argument">Collects format errors.</param>
    /// <param name="Value">Receives the date.</param>
    /// <param name="Present">True when a date was present.</param>
    /// <param name="ParameterName">Parameter path written on an error.</param>
    /// <returns>False when the value is not a date.</returns>
    internal procedure ReadDate(SourceJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: Date; var Present: Boolean; ParameterName: Text): Boolean
    var
        Context: Codeunit "Whse Write Context ori";
        ReceivedText: Text;
        TextPresent: Boolean;
        FormatLbl: Label 'Parameter %1 must be a date written as YYYY-MM-DD.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera dagsetning á sniðinu YYYY-MM-DD.';
        FormatNextStepLbl: Label 'Send the date as YYYY-MM-DD.', Comment = 'is-IS=Sendu dagsetninguna á sniðinu YYYY-MM-DD.';
    begin
        Value := 0D;
        Present := false;
        if not Context.ReadText(SourceJson, KeyName, 10, Argument, ReceivedText, TextPresent, ParameterName) then
            exit(false);
        if not TextPresent then
            exit(true);
        if not Evaluate(Value, ReceivedText, 9) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), ParameterName, ReceivedText, 'YYYY-MM-DD', Context.DateNextStep(ParameterName, ReceivedText, FormatNextStepLbl));
            exit(false);
        end;
        Present := true;
        exit(true);
    end;

    /// <summary>Reads an optional array parameter.</summary>
    /// <param name="SourceJson">Request object.</param>
    /// <param name="KeyName">Parameter name.</param>
    /// <param name="Argument">Collects format errors.</param>
    /// <param name="Value">Receives the array.</param>
    /// <param name="Present">True when an array was present.</param>
    /// <returns>False when the value is not an array.</returns>
    internal procedure ReadArray(SourceJson: JsonObject; KeyName: Text; var Argument: Record "Message Argument ori"; var Value: JsonArray; var Present: Boolean): Boolean
    var
        Token: JsonToken;
        FormatLbl: Label 'Parameter %1 must be an array of objects.', Comment = '%1 = parameter, is-IS=Færibreytan %1 verður að vera fylki hluta.';
        FormatNextStepLbl: Label 'Send the lines as an array of objects.', Comment = 'is-IS=Sendu línurnar sem fylki hluta.';
    begin
        Clear(Value);
        Present := false;
        if not SourceJson.Get(KeyName, Token) then
            exit(true);
        if Token.IsValue() then
            if Token.AsValue().IsNull() then
                exit(true);
        if not Token.IsArray() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, KeyName), KeyName, '', 'array', FormatNextStepLbl);
            exit(false);
        end;
        Value := Token.AsArray();
        Present := true;
        exit(true);
    end;

    /// <summary>Returns the object at an array index, or adds a format error.</summary>
    /// <param name="Lines">The array.</param>
    /// <param name="Index">Zero-based index.</param>
    /// <param name="ArrayName">Parameter name of the array.</param>
    /// <param name="Argument">Collects format errors.</param>
    /// <param name="LineObject">Receives the object.</param>
    /// <returns>True when the entry is an object.</returns>
    internal procedure TryGetLineObject(Lines: JsonArray; Index: Integer; ArrayName: Text; var Argument: Record "Message Argument ori"; var LineObject: JsonObject): Boolean
    var
        Token: JsonToken;
        FormatLbl: Label 'Each entry of %1 must be an object.', Comment = '%1 = parameter, is-IS=Hver færsla í %1 verður að vera hlutur.';
        FormatNextStepLbl: Label 'Send the lines as an array of objects.', Comment = 'is-IS=Sendu línurnar sem fylki hluta.';
    begin
        Clear(LineObject);
        Lines.Get(Index, Token);
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, StrSubstNo(FormatLbl, ArrayName), LineParameter(ArrayName, Index, ''), '', 'object', FormatNextStepLbl);
            exit(false);
        end;
        LineObject := Token.AsObject();
        exit(true);
    end;

    /// <summary>Adds UnknownParameter for every key that is not in the allowed list.</summary>
    /// <param name="SourceJson">Request object or one line of it.</param>
    /// <param name="AllowedKeys">The declared keys.</param>
    /// <param name="Argument">Collects the errors.</param>
    /// <param name="ArrayName">Array name for a line, or empty for the request.</param>
    /// <param name="Index">Line index, or -1 for the request.</param>
    internal procedure RefuseUnknownKeys(SourceJson: JsonObject; AllowedKeys: List of [Text]; var Argument: Record "Message Argument ori"; ArrayName: Text; Index: Integer)
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in SourceJson.Keys() do
            if not AllowedKeys.Contains(KeyName) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), LineParameter(ArrayName, Index, KeyName), KeyName, '', UnknownNextStepLbl);
    end;

    /// <summary>Builds a parameter path such as lines[2].itemNo.</summary>
    /// <param name="ArrayName">Array name, or empty.</param>
    /// <param name="Index">Line index, or -1.</param>
    /// <param name="KeyName">Key name, or empty.</param>
    /// <returns>The parameter path.</returns>
    internal procedure LineParameter(ArrayName: Text; Index: Integer; KeyName: Text): Text
    var
        LinePathLbl: Label '%1[%2]', Locked = true;
        KeyPathLbl: Label '%1[%2].%3', Locked = true;
    begin
        if (ArrayName = '') or (Index < 0) then
            exit(KeyName);
        if KeyName = '' then
            exit(StrSubstNo(LinePathLbl, ArrayName, Index));
        exit(StrSubstNo(KeyPathLbl, ArrayName, Index, KeyName));
    end;

    /// <summary>Adds one declared error with its next step to an errors chapter.</summary>
    /// <param name="Errors">The errors chapter.</param>
    /// <param name="ErrorCode">The error code.</param>
    /// <param name="WhenText">When the error is answered.</param>
    /// <param name="NextStep">What the caller should do.</param>
    internal procedure AddDeclaredError(var Errors: JsonArray; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
    begin
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        if not Entry.Contains('nextStep') then
            Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;

    /// <summary>Returns true when the text is a GUID.</summary>
    /// <param name="Value">Text to test.</param>
    /// <returns>True for a GUID.</returns>
    internal procedure IsGuid(Value: Text): Boolean
    var
        Parsed: Guid;
    begin
        if Value = '' then
            exit(false);
        exit(Evaluate(Parsed, Value));
    end;

    /// <summary>Writes a date as YYYY-MM-DD, or an empty text for 0D.</summary>
    /// <param name="Value">The date.</param>
    /// <returns>The text.</returns>
    internal procedure DateText(Value: Date): Text
    begin
        if Value = 0D then
            exit('');
        exit(Format(Value, 0, 9));
    end;
}
