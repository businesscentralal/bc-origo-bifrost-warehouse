namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Structure;

/// <summary>
/// Sets the default bin content inside Codeunit.Run so a platform error rolls the write back.
/// The previous default is cleared first. Bin Content OnValidate rejects a second default.
/// </summary>
codeunit 10078464 "Whse Def. Bin Set Proc. ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Bin Write Context ori";
        Payload: JsonObject;
        LocationCode: Code[10];
        ItemNo: Code[20];
        VariantCode: Code[10];
        PreviousBinCode: Code[20];
        MissingPayloadErr: Label 'The default bin payload was empty.', Comment = 'is-IS=Gögnin fyrir sjálfgefið hólf voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        ItemNo := CopyStr(TextValue(Payload, 'itemNo'), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(TextValue(Payload, 'variantCode'), 1, MaxStrLen(VariantCode));
        PreviousBinCode := CopyStr(TextValue(Payload, 'previousBinCode'), 1, MaxStrLen(PreviousBinCode));
        ClearPreviousDefault(LocationCode, ItemNo, VariantCode, PreviousBinCode);
        SetDefault(Payload);
    end;

    local procedure ClearPreviousDefault(LocationCode: Code[10]; ItemNo: Code[20]; VariantCode: Code[10]; PreviousBinCode: Code[20])
    var
        BinContent: Record "Bin Content";
    begin
        if PreviousBinCode = '' then
            exit;
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Variant Code", VariantCode);
        BinContent.SetRange(Default, true);
        if BinContent.FindSet(true) then
            repeat
                BinContent.Validate(Default, false);
                BinContent.Modify(true);
            until BinContent.Next() = 0;
    end;

    local procedure SetDefault(Payload: JsonObject)
    var
        BinContent: Record "Bin Content";
        LocationCode: Code[10];
        BinCode: Code[20];
        ItemNo: Code[20];
        VariantCode: Code[10];
        UnitOfMeasureCode: Code[10];
    begin
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        BinCode := CopyStr(TextValue(Payload, 'binCode'), 1, MaxStrLen(BinCode));
        ItemNo := CopyStr(TextValue(Payload, 'itemNo'), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(TextValue(Payload, 'variantCode'), 1, MaxStrLen(VariantCode));
        UnitOfMeasureCode := CopyStr(TextValue(Payload, 'unitOfMeasureCode'), 1, MaxStrLen(UnitOfMeasureCode));
        if not BinContent.Get(LocationCode, BinCode, ItemNo, VariantCode, UnitOfMeasureCode) then
            InsertBinContent(BinContent, LocationCode, BinCode, ItemNo, VariantCode, UnitOfMeasureCode);
        BinContent.Validate(Default, true);
        BinContent.Modify(true);
    end;

    local procedure InsertBinContent(var BinContent: Record "Bin Content"; LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UnitOfMeasureCode: Code[10])
    begin
        BinContent.Init();
        BinContent.Validate("Location Code", LocationCode);
        BinContent.Validate("Bin Code", BinCode);
        BinContent.SetUpNewLine();
        BinContent.Validate("Item No.", ItemNo);
        if VariantCode <> '' then
            BinContent.Validate("Variant Code", VariantCode);
        if BinContent."Unit of Measure Code" <> UnitOfMeasureCode then
            BinContent.Validate("Unit of Measure Code", UnitOfMeasureCode);
        BinContent.Validate(Fixed, true);
        BinContent.Insert(true);
    end;

    local procedure TextValue(Payload: JsonObject; KeyName: Text): Text
    var
        Token: JsonToken;
    begin
        if not Payload.Get(KeyName, Token) then
            exit('');
        if not Token.IsValue() or Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;
}
