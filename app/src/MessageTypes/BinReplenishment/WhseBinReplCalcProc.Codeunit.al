namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;

/// <summary>
/// Runs Calculate Bin Replenishment inside Codeunit.Run.
/// The report writes movement worksheet lines and does not create a warehouse movement.
/// </summary>
codeunit 10078449 "Whse Bin Repl Calc Proc ori"
{
    Access = Internal;

    trigger OnRun()
    var
        BinContent: Record "Bin Content";
        WorksheetLine: Record "Whse. Worksheet Line";
        CalculateReplenishment: Report "Calculate Bin Replenishment";
        Context: Codeunit "Whse Bin Repl Context ori";
        Payload: JsonObject;
        LocationCode: Code[10];
        TemplateName: Code[10];
        WorksheetName: Code[10];
        ZoneCode: Code[10];
        BinCode: Code[20];
        ItemNo: Code[20];
        SnapshotLineNo: Integer;
        MissingPayloadErr: Label 'The bin replenishment payload was empty.', Comment = 'is-IS=Gögnin fyrir endurnýjun hólfa voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        TemplateName := CopyStr(TextValue(Payload, 'worksheetTemplateName'), 1, MaxStrLen(TemplateName));
        WorksheetName := CopyStr(TextValue(Payload, 'worksheetName'), 1, MaxStrLen(WorksheetName));
        ZoneCode := CopyStr(TextValue(Payload, 'zoneCode'), 1, MaxStrLen(ZoneCode));
        BinCode := CopyStr(TextValue(Payload, 'binCode'), 1, MaxStrLen(BinCode));
        ItemNo := CopyStr(TextValue(Payload, 'itemNo'), 1, MaxStrLen(ItemNo));
        SnapshotLineNo := Snapshot(TemplateName, WorksheetName, LocationCode, WorksheetLine);
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange(Fixed, true);
        if ZoneCode <> '' then
            BinContent.SetRange("Zone Code", ZoneCode);
        if BinCode <> '' then
            BinContent.SetRange("Bin Code", BinCode);
        if ItemNo <> '' then
            BinContent.SetRange("Item No.", ItemNo);
        CalculateReplenishment.UseRequestPage(false);
        CalculateReplenishment.InitializeRequest(TemplateName, WorksheetName, LocationCode, BooleanValue(Payload, 'allowBreakbulk'), true, BooleanValue(Payload, 'doNotFillQtyToHandle'));
        CalculateReplenishment.SetTableView(BinContent);
        CalculateReplenishment.Run();
        Context.SetSnapshot(SnapshotLineNo);
    end;

    local procedure Snapshot(TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]; var WorksheetLine: Record "Whse. Worksheet Line"): Integer
    begin
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, WorksheetName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        if WorksheetLine.FindLast() then
            exit(WorksheetLine."Line No.");
        exit(0);
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

    local procedure BooleanValue(Parent: JsonObject; Name: Text): Boolean
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
}
