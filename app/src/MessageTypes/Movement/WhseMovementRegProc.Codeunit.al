namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Activity.History;

/// <summary>
/// Applies optional quantities and registers a warehouse movement.
/// Codeunit.Run keeps a failure from escaping as a raw runtime error.
/// </summary>
codeunit 10078469 "Whse Movement Reg Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Movement Context ori";
        Payload: JsonObject;
        MovementNo: Code[20];
        RegisteredQty: Decimal;
        MissingPayloadErr: Label 'The movement register payload was empty.', Comment = 'is-IS=Gögnin til að skrá færslu voru tóm.';
        NothingErr: Label 'There is nothing to register.', Comment = 'is-IS=Ekkert er til að skrá.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        MovementNo := CopyStr(TextValue(Payload, 'movementNo'), 1, MaxStrLen(MovementNo));
        ApplyQuantities(Payload, MovementNo);
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Movement);
        ActivityLine.SetRange("No.", MovementNo);
        if not ActivityLine.FindSet() then
            Error(NothingErr);
        RegisteredQty := 0;
        repeat
            RegisteredQty += ActivityLine."Qty. to Handle";
        until ActivityLine.Next() = 0;
        if RegisteredQty = 0 then
            Error(NothingErr);
        ActivityLine.FindFirst();
        if not Codeunit.Run(Codeunit::"Whse.-Activity-Register", ActivityLine) then
            Error(GetLastErrorText());
        Context.SetResult(RegisteredNo(MovementNo), RegisteredQty);
    end;

    local procedure ApplyQuantities(Payload: JsonObject; MovementNo: Code[20])
    var
        Token: JsonToken;
        Lines: JsonArray;
        LineObject: JsonObject;
    begin
        if not Payload.Get('lines', Token) then
            exit;
        if not Token.IsArray() then
            exit;
        Lines := Token.AsArray();
        foreach Token in Lines do begin
            LineObject := Token.AsObject();
            ApplyOneQuantity(LineObject, MovementNo);
        end;
    end;

    local procedure ApplyOneQuantity(LineObject: JsonObject; MovementNo: Code[20])
    var
        ActivityLine: Record "Warehouse Activity Line";
        Sibling: Record "Warehouse Activity Line";
        Outstanding: Decimal;
        MatchCount: Integer;
        MatchLineNo: Integer;
    begin
        ActivityLine.Get(ActivityLine."Activity Type"::Movement, MovementNo, IntegerValue(LineObject, 'lineNo'));
        Outstanding := ActivityLine."Qty. Outstanding";
        ActivityLine.Validate("Qty. to Handle", DecimalValue(LineObject, 'qtyToHandle'));
        ActivityLine.Modify(true);
        Sibling.SetRange("Activity Type", ActivityLine."Activity Type");
        Sibling.SetRange("No.", ActivityLine."No.");
        Sibling.SetRange("Item No.", ActivityLine."Item No.");
        Sibling.SetRange("Variant Code", ActivityLine."Variant Code");
        Sibling.SetRange("Unit of Measure Code", ActivityLine."Unit of Measure Code");
        if not Sibling.FindSet() then
            exit;
        repeat
            if (Sibling."Line No." <> ActivityLine."Line No.") and (Sibling."Qty. Outstanding" = Outstanding) then begin
                MatchCount += 1;
                MatchLineNo := Sibling."Line No.";
            end;
        until Sibling.Next() = 0;
        if MatchCount <> 1 then
            exit;
        Sibling.Get(ActivityLine."Activity Type", ActivityLine."No.", MatchLineNo);
        Sibling.Validate("Qty. to Handle", ActivityLine."Qty. to Handle");
        Sibling.Modify(true);
    end;

    local procedure RegisteredNo(MovementNo: Code[20]): Code[20]
    var
        RegisteredHeader: Record "Registered Whse. Activity Hdr.";
    begin
        RegisteredHeader.SetRange("Whse. Activity No.", MovementNo);
        if RegisteredHeader.FindLast() then
            exit(RegisteredHeader."No.");
        exit('');
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
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

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;
}
