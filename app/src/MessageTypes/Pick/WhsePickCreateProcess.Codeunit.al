namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Isolated runner for BC's "Whse.-Shipment - Create Pick" report (7318).
/// Invoked from "Whse Pick Create Impl ori" via Codeunit.Run so report-time errors can
/// be caught and returned as Bifrost Error responses without rolling back the
/// outer message-task transaction.
/// </summary>

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;

codeunit 10078413 "Whse Pick Create Process ori"
{
    Access = Internal;
    TableNo = "Warehouse Shipment Header";

    trigger OnRun()
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        WhseShipmentCreatePickReport: Report "Whse.-Shipment - Create Pick";
        NoLinesErr: Label 'Warehouse Shipment %1 has no lines to pick.', Comment = '%1 = shipment no.', Locked = true;
    begin
        WhseShipmentHeader := Rec;
        WhseShipmentHeader.Find();

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if not WhseShipmentLine.FindFirst() then
            Error(NoLinesErr, WhseShipmentHeader."No.");

        WhseShipmentCreatePickReport.SetWhseShipmentLine(WhseShipmentLine, WhseShipmentHeader);
        WhseShipmentCreatePickReport.SetHideValidationDialog(true);
        WhseShipmentCreatePickReport.UseRequestPage(false);
        WhseShipmentCreatePickReport.RunModal();
    end;
}
