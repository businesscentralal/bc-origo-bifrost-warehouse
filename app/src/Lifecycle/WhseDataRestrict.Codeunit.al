namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;

/// <summary>
/// Refuses generic Data.Records.Set against warehouse document tables so callers use the
/// dedicated Warehouse.* message types. Reads via Data.Records.Get stay allowed.
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

    local procedure IsWarehouseDocumentTable(TableNo: Integer): Boolean
    begin
        exit(TableNo in [
            Database::"Warehouse Shipment Header",
            Database::"Warehouse Shipment Line",
            Database::"Warehouse Receipt Header",
            Database::"Warehouse Receipt Line",
            Database::"Warehouse Activity Header",
            Database::"Warehouse Activity Line"]);
    end;
}
