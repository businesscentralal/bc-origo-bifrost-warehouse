namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Refuses generic Data.Records.Set against warehouse tables that have a dedicated message type.
/// Reads via Data.Records.Get stay allowed. Force does not reopen these blocks.
/// </summary>
codeunit 10078458 "Whse Data Restrict ori"
{
    Access = Internal;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnAfterIsTableWriteRestrictedForDataRecords', '', false, false)]
    local procedure RestrictWarehouseDocumentTablesFromWrite(TableNo: Integer; var IsRestricted: Boolean)
    begin
        if IsWarehouseDocumentTable(TableNo) then
            IsRestricted := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnAfterIsFieldWriteRestrictedForDataRecords', '', false, false)]
    local procedure RestrictDefaultBinFieldFromWrite(TableNo: Integer; FieldNo: Integer; var IsRestricted: Boolean)
    var
        BinContent: Record "Bin Content";
    begin
        if (TableNo = Database::"Bin Content") and (FieldNo = BinContent.FieldNo(Default)) then
            IsRestricted := true;
        if IsMovementCreateField(TableNo, FieldNo) or IsActivityQuantityOrBinField(TableNo, FieldNo) or IsActivityZoneField(TableNo, FieldNo) or IsInventoryPickTrackingField(TableNo, FieldNo) then
            IsRestricted := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnGetDedicatedMessageTypeHintForWrite', '', false, false)]
    local procedure HintBinTableWrite(TableNo: Integer; var Hint: Text)
    begin
        if TableNo = Database::Bin then
            Hint := 'Warehouse.Bin.Create, Warehouse.Bin.Get';
        // The activity line stays wholly write-restricted. Foundation answers that table block before a field hint,
        // so the generic write names every dedicated activity type. The field hint below stays the precise pointer.
        if TableNo = Database::"Warehouse Activity Line" then
            Hint := 'Warehouse.Pick.Register, Warehouse.Putaway.Register, Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post';
    end;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnGetDedicatedMessageTypeHintForField', '', false, false)]
    local procedure HintDefaultBinField(TableNo: Integer; FieldNo: Integer; var Hint: Text)
    var
        BinContent: Record "Bin Content";
    begin
        if (TableNo = Database::"Bin Content") and (FieldNo = BinContent.FieldNo(Default)) then
            Hint := 'Warehouse.DefaultBin.Set';
        if IsMovementCreateField(TableNo, FieldNo) then
            Hint := 'Warehouse.Movement.Create';
        if IsActivityQuantityOrBinField(TableNo, FieldNo) then
            Hint := 'Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post';
        if IsActivityZoneField(TableNo, FieldNo) then
            Hint := 'Warehouse.Movement.Register';
        if IsInventoryPickTrackingField(TableNo, FieldNo) then
            Hint := 'Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post';
    end;

    local procedure IsMovementCreateField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        if TableNo <> Database::"Whse. Worksheet Line" then
            exit(false);
        exit(FieldNo in [
            WorksheetLine.FieldNo("Qty. to Handle"),
            WorksheetLine.FieldNo("From Bin Code"),
            WorksheetLine.FieldNo("To Bin Code")]);
    end;

    local procedure IsActivityQuantityOrBinField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        if TableNo <> Database::"Warehouse Activity Line" then
            exit(false);
        exit(FieldNo in [
            ActivityLine.FieldNo("Qty. to Handle"),
            ActivityLine.FieldNo("Bin Code")]);
    end;

    local procedure IsActivityZoneField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        if TableNo <> Database::"Warehouse Activity Line" then
            exit(false);
        exit(FieldNo = ActivityLine.FieldNo("Zone Code"));
    end;

    local procedure IsInventoryPickTrackingField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        if TableNo <> Database::"Warehouse Activity Line" then
            exit(false);
        exit(FieldNo in [
            ActivityLine.FieldNo("Lot No."),
            ActivityLine.FieldNo("Serial No.")]);
    end;

    local procedure IsWarehouseDocumentTable(TableNo: Integer): Boolean
    begin
        exit(TableNo in [
            Database::"Warehouse Shipment Header",
            Database::"Warehouse Shipment Line",
            Database::"Warehouse Receipt Header",
            Database::"Warehouse Receipt Line",
            Database::"Warehouse Activity Header",
            Database::"Warehouse Activity Line",
            Database::Bin]);
    end;
}
