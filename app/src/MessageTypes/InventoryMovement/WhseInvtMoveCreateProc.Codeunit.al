namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InternalDocument;
using Microsoft.Warehouse.Request;

/// <summary>
/// Creates an inventory movement inside Codeunit.Run.
/// Inline lines go through an internal movement. Assembly consumption uses report 7323, which commits.
/// </summary>
codeunit 10078442 "Whse InvtMove Create Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse InvtMove Context ori";
        Payload: JsonObject;
        MovementNo: Code[20];
        MissingPayloadErr: Label 'The inventory movement create payload was empty.', Comment = 'is-IS=Gögnin til að stofna birgðafærslu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        if TextValue(Payload, 'sourceDocument') <> '' then
            MovementNo := CreateFromSource(Payload)
        else
            MovementNo := CreateFromLines(Payload);
        FillQtyToHandle(MovementNo);
        Context.SetResult(MovementNo, 0);
    end;

    local procedure CreateFromLines(Payload: JsonObject): Code[20]
    var
        InternalHeader: Record "Internal Movement Header";
        CreateMovement: Codeunit "Create Inventory Pick/Movement";
        LocationCode: Code[10];
        FirstToBin: Code[20];
        BeforeNos: Text;
        MovementNo: Code[20];
        NothingErr: Label 'No inventory movement was created.', Comment = 'is-IS=Engin birgðafærsla var stofnuð.';
    begin
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        FirstToBin := CopyStr(FirstToBinCode(Payload), 1, MaxStrLen(FirstToBin));
        BeforeNos := Snapshot(LocationCode);
        InternalHeader.Init();
        InternalHeader.Validate("Location Code", LocationCode);
        InternalHeader.Validate("To Bin Code", FirstToBin);
        InternalHeader.Insert(true);
        InsertLines(Payload, InternalHeader);
        CreateMovement.SetHideDialog(true);
        CreateMovement.CreateInvtMvntWithoutSource(InternalHeader);
        MovementNo := FindNewMovement(LocationCode, BeforeNos);
        if MovementNo = '' then
            Error(NothingErr);
        exit(MovementNo);
    end;

    local procedure CreateFromSource(Payload: JsonObject): Code[20]
    var
        WarehouseRequest: Record "Warehouse Request";
        ActivityHeader: Record "Warehouse Activity Header";
        CreateReport: Report "Create Invt Put-away/Pick/Mvmt";
        SourceNo: Code[20];
        NothingErr: Label 'No inventory movement was created.', Comment = 'is-IS=Engin birgðafærsla var stofnuð.';
    begin
        SourceNo := CopyStr(TextValue(Payload, 'sourceNo'), 1, MaxStrLen(SourceNo));
        WarehouseRequest.SetRange("Source Document", WarehouseRequest."Source Document"::"Assembly Consumption");
        WarehouseRequest.SetRange("Source No.", SourceNo);
        CreateReport.UseRequestPage(false);
        CreateReport.InitializeRequest(false, false, true, false, true);
        CreateReport.SuppressMessages(true);
        CreateReport.SetTableView(WarehouseRequest);
        CreateReport.RunModal();
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Movement");
        ActivityHeader.SetRange("Source Document", ActivityHeader."Source Document"::"Assembly Consumption");
        ActivityHeader.SetRange("Source No.", SourceNo);
        if not ActivityHeader.FindLast() then
            Error(NothingErr);
        exit(ActivityHeader."No.");
    end;

    local procedure InsertLines(Payload: JsonObject; InternalHeader: Record "Internal Movement Header")
    var
        Token: JsonToken;
        Lines: JsonArray;
        LineObject: JsonObject;
        LineNo: Integer;
    begin
        if not Payload.Get('lines', Token) then
            exit;
        Lines := Token.AsArray();
        LineNo := 0;
        foreach Token in Lines do begin
            LineNo += 10000;
            LineObject := Token.AsObject();
            InsertOneLine(InternalHeader, LineObject, LineNo);
        end;
    end;

    local procedure InsertOneLine(InternalHeader: Record "Internal Movement Header"; LineObject: JsonObject; LineNo: Integer)
    var
        InternalLine: Record "Internal Movement Line";
    begin
        InternalLine.Init();
        InternalLine.Validate("No.", InternalHeader."No.");
        InternalLine.Validate("Line No.", LineNo);
        InternalLine.Validate("Item No.", CopyStr(TextValue(LineObject, 'itemNo'), 1, MaxStrLen(InternalLine."Item No.")));
        if TextValue(LineObject, 'variantCode') <> '' then
            InternalLine.Validate("Variant Code", CopyStr(TextValue(LineObject, 'variantCode'), 1, MaxStrLen(InternalLine."Variant Code")));
        if TextValue(LineObject, 'unitOfMeasureCode') <> '' then
            InternalLine.Validate("Unit of Measure Code", CopyStr(TextValue(LineObject, 'unitOfMeasureCode'), 1, MaxStrLen(InternalLine."Unit of Measure Code")));
        InternalLine.Validate("From Bin Code", CopyStr(TextValue(LineObject, 'fromBin'), 1, MaxStrLen(InternalLine."From Bin Code")));
        InternalLine.Validate("To Bin Code", CopyStr(TextValue(LineObject, 'toBin'), 1, MaxStrLen(InternalLine."To Bin Code")));
        InternalLine.Validate(Quantity, DecimalValue(LineObject, 'quantity'));
        InternalLine.Insert(true);
    end;

    local procedure FillQtyToHandle(MovementNo: Code[20])
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Invt. Movement");
        ActivityLine.SetRange("No.", MovementNo);
        if not ActivityLine.FindSet() then
            exit;
        repeat
            if (ActivityLine."Qty. to Handle" = 0) and (ActivityLine."Qty. Outstanding" > 0) then begin
                // Assign without Validate. A tracked line without a lot rejects Validate,
                // and a try function cannot write the quantity afterwards.
                ActivityLine."Qty. to Handle" := ActivityLine."Qty. Outstanding";
                ActivityLine."Qty. to Handle (Base)" := ActivityLine."Qty. Outstanding (Base)";
                ActivityLine.Modify(true);
            end;
        until ActivityLine.Next() = 0;
    end;

    local procedure Snapshot(LocationCode: Code[10]): Text
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Nos: Text;
    begin
        Nos := '|';
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Movement");
        ActivityHeader.SetRange("Location Code", LocationCode);
        if ActivityHeader.FindSet() then
            repeat
                Nos += ActivityHeader."No." + '|';
            until ActivityHeader.Next() = 0;
        exit(Nos);
    end;

    local procedure FindNewMovement(LocationCode: Code[10]; BeforeNos: Text): Code[20]
    var
        ActivityHeader: Record "Warehouse Activity Header";
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Movement");
        ActivityHeader.SetRange("Location Code", LocationCode);
        if ActivityHeader.FindSet() then
            repeat
                if StrPos(BeforeNos, '|' + ActivityHeader."No." + '|') = 0 then
                    exit(ActivityHeader."No.");
            until ActivityHeader.Next() = 0;
        exit('');
    end;

    local procedure FirstToBinCode(Payload: JsonObject): Text
    var
        Token: JsonToken;
        Lines: JsonArray;
    begin
        if not Payload.Get('lines', Token) then
            exit('');
        Lines := Token.AsArray();
        if Lines.Count() = 0 then
            exit('');
        Lines.Get(0, Token);
        exit(TextValue(Token.AsObject(), 'toBin'));
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
        if not Token.IsValue() then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;
}
