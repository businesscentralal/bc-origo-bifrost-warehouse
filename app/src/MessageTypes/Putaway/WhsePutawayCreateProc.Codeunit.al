namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Isolated runner for BC's "Whse.-Source - Create Document" report (7305) applied to a
/// Posted Whse. Receipt. Invoked from "Whse Putaway Create Impl ori" via Codeunit.Run so
/// report-time errors can be caught and returned as Bifrost Error responses without
/// rolling back the outer message-task transaction.
/// </summary>

using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Request;

codeunit 10078416 "Whse Putaway Create Proc. ori"
{
    Access = Internal;
    TableNo = "Posted Whse. Receipt Header";

    trigger OnRun()
    var
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        CreatePutawayDoc: Report "Whse.-Source - Create Document";
        NoLinesErr: Label 'Posted Whse. Receipt %1 has no lines to put away.', Comment = '%1 = posted receipt no.', Locked = true;
    begin
        PostedWhseReceiptHeader := Rec;
#pragma warning disable AA0181
        PostedWhseReceiptHeader.Find('=');
#pragma warning restore AA0181

        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.SetFilter(Quantity, '>0');
        PostedWhseReceiptLine.SetFilter(Status, '<>%1', PostedWhseReceiptLine.Status::"Completely Put Away");
        if not PostedWhseReceiptLine.FindFirst() then
            Error(NoLinesErr, PostedWhseReceiptHeader."No.");

        CreatePutawayDoc.SetPostedWhseReceiptLine(PostedWhseReceiptLine, '');
        CreatePutawayDoc.SetHideValidationDialog(true);
        CreatePutawayDoc.UseRequestPage(false);
        CreatePutawayDoc.RunModal();
    end;
}
