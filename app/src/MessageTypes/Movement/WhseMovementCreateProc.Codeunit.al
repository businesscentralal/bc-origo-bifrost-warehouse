namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;

/// <summary>
/// Writes movement worksheet lines and creates the warehouse movement inside Codeunit.Run.
/// A platform error rolls the worksheet insert back when the report has not committed.
/// </summary>
codeunit 10078467 "Whse Movement Create Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Context: Codeunit "Whse Movement Context ori";
        Payload: JsonObject;
        MissingPayloadErr: Label 'The movement create payload was empty.', Comment = 'is-IS=Gögnin til að stofna færslu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        CreateMovement(Payload, ActivityHeader);
        Context.SetResult(ActivityHeader."No.", 0);
    end;

    local procedure CreateMovement(Payload: JsonObject; var ActivityHeader: Record "Warehouse Activity Header")
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        CreateDocument: Report "Whse.-Source - Create Document";
        MovementOption: Option " ","Put-away",Pick,Movement,"Invt. Put-away","Invt. Pick","Invt. Movement";
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        NothingErr: Label 'No warehouse movement was created.', Comment = 'is-IS=Engin vöruhúsafærsla var stofnuð.';
    begin
        TemplateName := CopyStr(TextValue(Payload, 'worksheetTemplateName'), 1, MaxStrLen(TemplateName));
        BatchName := CopyStr(TextValue(Payload, 'worksheetName'), 1, MaxStrLen(BatchName));
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        EnsureWorksheetName(TemplateName, BatchName, LocationCode);
        InsertInlineLines(Payload, TemplateName, BatchName, LocationCode);
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, BatchName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        WorksheetLine.SetFilter(Quantity, '>0');
        if not WorksheetLine.FindFirst() then
            Error(NothingErr);

        CreateDocument.SetHideValidationDialog(true);
        CreateDocument.UseRequestPage(false);
        CreateDocument.SetWhseWkshLine(WorksheetLine);
        CreateDocument.RunModal();
        CreateDocument.GetActivityHeader(ActivityHeader, MovementOption::Movement);
        if ActivityHeader."No." = '' then
            Error(NothingErr);
    end;

    local procedure EnsureWorksheetName(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        WorksheetName: Record "Whse. Worksheet Name";
    begin
        if WorksheetName.Get(TemplateName, BatchName, LocationCode) then
            exit;
        WorksheetName.Init();
        WorksheetName.Validate("Worksheet Template Name", TemplateName);
        WorksheetName.Validate(Name, BatchName);
        WorksheetName.Validate("Location Code", LocationCode);
        WorksheetName.Insert(true);
    end;

    local procedure InsertInlineLines(Payload: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
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
            InsertOneLine(LineObject, TemplateName, BatchName, LocationCode);
        end;
    end;

    local procedure InsertOneLine(LineObject: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        LineNo: Integer;
    begin
        LineNo := NextLineNo(TemplateName, BatchName, LocationCode);
        WorksheetLine.Init();
        WorksheetLine.Validate("Worksheet Template Name", TemplateName);
        WorksheetLine.Validate(Name, BatchName);
        WorksheetLine.Validate("Location Code", LocationCode);
        WorksheetLine.Validate("Line No.", LineNo);
        WorksheetLine.Insert(true);
        WorksheetLine.Validate("Whse. Document Type", WorksheetLine."Whse. Document Type"::" ");
        WorksheetLine.Validate("Item No.", CopyStr(TextValue(LineObject, 'itemNo'), 1, MaxStrLen(WorksheetLine."Item No.")));
        if TextValue(LineObject, 'variantCode') <> '' then
            WorksheetLine.Validate("Variant Code", CopyStr(TextValue(LineObject, 'variantCode'), 1, MaxStrLen(WorksheetLine."Variant Code")));
        if TextValue(LineObject, 'unitOfMeasureCode') <> '' then
            WorksheetLine.Validate("Unit of Measure Code", CopyStr(TextValue(LineObject, 'unitOfMeasureCode'), 1, MaxStrLen(WorksheetLine."Unit of Measure Code")));
        ApplyBin(WorksheetLine, LocationCode, TextValue(LineObject, 'fromBin'), true);
        ApplyBin(WorksheetLine, LocationCode, TextValue(LineObject, 'toBin'), false);
        WorksheetLine.Validate(Quantity, DecimalValue(LineObject, 'quantity'));
        WorksheetLine.Modify(true);
    end;

    local procedure ApplyBin(var WorksheetLine: Record "Whse. Worksheet Line"; LocationCode: Code[10]; BinCode: Text; FromBin: Boolean)
    var
        Bin: Record Bin;
    begin
        if not Bin.Get(LocationCode, CopyStr(BinCode, 1, MaxStrLen(Bin.Code))) then
            exit;
        if FromBin then begin
            WorksheetLine.Validate("From Zone Code", Bin."Zone Code");
            WorksheetLine.Validate("From Bin Code", Bin.Code);
        end else begin
            WorksheetLine.Validate("To Zone Code", Bin."Zone Code");
            WorksheetLine.Validate("To Bin Code", Bin.Code);
        end;
    end;

    local procedure NextLineNo(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]): Integer
    var
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, BatchName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        if WorksheetLine.FindLast() then
            exit(WorksheetLine."Line No." + 10000);
        exit(10000);
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
