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
        if IsMovementCreateField(TableNo, FieldNo) or IsActivityQuantityOrBinField(TableNo, FieldNo) or IsActivityZoneField(TableNo, FieldNo) or IsInventoryPickTrackingField(TableNo, FieldNo) or IsInventoryPutAwayExpirationField(TableNo, FieldNo) then
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
            Hint := 'Warehouse.Pick.Register, Warehouse.Putaway.Register, Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post, Warehouse.InventoryMovement.Create, Warehouse.InventoryMovement.Register';
    end;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnGetDedicatedMessageTypeHintForField', '', false, false)]
    local procedure HintDefaultBinField(TableNo: Integer; FieldNo: Integer; var Hint: Text)
    var
        BinContent: Record "Bin Content";
    begin
        if (TableNo = Database::"Bin Content") and (FieldNo = BinContent.FieldNo(Default)) then
            Hint := 'Warehouse.DefaultBin.Set';
        if IsMovementCreateField(TableNo, FieldNo) then
            Hint := 'Warehouse.BinReplenishment.Calculate, Warehouse.Movement.Create';
        if IsActivityQuantityOrBinField(TableNo, FieldNo) then
            Hint := 'Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post, Warehouse.InventoryMovement.Create, Warehouse.InventoryMovement.Register';
        if IsActivityZoneField(TableNo, FieldNo) then
            Hint := 'Warehouse.Movement.Register';
        if IsInventoryPickTrackingField(TableNo, FieldNo) then
            Hint := 'Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post';
        if IsInventoryPutAwayExpirationField(TableNo, FieldNo) then
            Hint := 'Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post';
    end;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnAfterIsFieldWriteRestrictedForDataRecords', '', false, false)]
    local procedure RestrictDocumentFlowFieldsFromWrite(TableNo: Integer; FieldNo: Integer; var IsRestricted: Boolean)
    begin
        // Shipment status and the receipt and shipment quantities belong to the release, reopen and post types (#53, #54).
        if IsShipmentStatusField(TableNo, FieldNo) or IsReceiptQuantityField(TableNo, FieldNo) or IsShipmentQuantityField(TableNo, FieldNo) then
            IsRestricted := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnGetDedicatedMessageTypeHintForWrite', '', false, false)]
    local procedure HintDocumentFlowTableWrite(TableNo: Integer; var Hint: Text)
    begin
        // These tables stay wholly write-restricted, so the table hint names the dedicated types that change them.
        case TableNo of
            Database::"Warehouse Shipment Header":
                Hint := 'Warehouse.Shipment.Release, Warehouse.Shipment.Reopen, Warehouse.Shipment.GetSourceDocuments';
            Database::"Warehouse Receipt Line":
                Hint := 'Warehouse.Receipt.Post, Warehouse.Receipt.GetSourceDocuments';
            Database::"Warehouse Shipment Line":
                Hint := 'Warehouse.Shipment.Post, Warehouse.Shipment.GetSourceDocuments';
        end;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Message Argument ori", 'OnGetDedicatedMessageTypeHintForField', '', false, false)]
    local procedure HintDocumentFlowField(TableNo: Integer; FieldNo: Integer; var Hint: Text)
    begin
        if IsShipmentStatusField(TableNo, FieldNo) then
            Hint := 'Warehouse.Shipment.Release, Warehouse.Shipment.Reopen';
        if IsReceiptQuantityField(TableNo, FieldNo) then
            Hint := 'Warehouse.Receipt.Post';
        if IsShipmentQuantityField(TableNo, FieldNo) then
            Hint := 'Warehouse.Shipment.Post';
    end;

    local procedure IsShipmentStatusField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
    begin
        exit((TableNo = Database::"Warehouse Shipment Header") and (FieldNo = ShipmentHeader.FieldNo(Status)));
    end;

    local procedure IsReceiptQuantityField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        ReceiptLine: Record "Warehouse Receipt Line";
    begin
        exit((TableNo = Database::"Warehouse Receipt Line") and (FieldNo = ReceiptLine.FieldNo("Qty. to Receive")));
    end;

    local procedure IsShipmentQuantityField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        exit((TableNo = Database::"Warehouse Shipment Line") and (FieldNo = ShipmentLine.FieldNo("Qty. to Ship")));
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

    local procedure IsInventoryPutAwayExpirationField(TableNo: Integer; FieldNo: Integer): Boolean
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        if TableNo <> Database::"Warehouse Activity Line" then
            exit(false);
        exit(FieldNo = ActivityLine.FieldNo("Expiration Date"));
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
