namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.CrossDock;
using Microsoft.Warehouse.Document;

/// <summary>Applies validated receipt-line scope only while explicitly bound to one cross-dock calculation.</summary>
codeunit 10078445 "Whse CrossDock Scope ori"
{
    Access = Internal;
    EventSubscriberInstance = Manual;

    var
        ReceiptNo: Code[20];
        LineFilter: Text;

    /// <summary>Sets the validated receipt and numeric line filter before binding.</summary>
    /// <param name="NewReceiptNo">Receipt number.</param>
    /// <param name="NewLineFilter">Validated integer line numbers joined with a pipe, or empty for all lines.</param>
    internal procedure SetScope(NewReceiptNo: Code[20]; NewLineFilter: Text)
    begin
        ReceiptNo := NewReceiptNo;
        LineFilter := NewLineFilter;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse. Cross-Dock Management", 'OnAfterFilterWhseRcptLine', '', false, false)]
    local procedure FilterSelectedLines(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; NameNo: Code[20]; LocationCode: Code[10])
    begin
        if (NameNo = ReceiptNo) and (LineFilter <> '') then
            WarehouseReceiptLine.SetFilter("Line No.", LineFilter);
    end;
}
