namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Document;

/// <summary>
/// Answers the Shipment Date confirmation of a warehouse shipment for Warehouse.Document.Update (#105), so the date
/// can change in a background or API session. Bound manually: during prevalidation it answers no, so the lines are
/// not touched; in the write transaction it answers yes, so Business Central copies the date to the lines.
/// </summary>
codeunit 10078443 "Whse Ship Date Confirm ori"
{
    Access = Internal;
    EventSubscriberInstance = Manual;

    var
        CopyToLines: Boolean;

    /// <summary>Sets the answer to the Shipment Date confirmation.</summary>
    /// <param name="NewCopyToLines">True to copy the new date to the shipment lines, false to change only the header.</param>
    internal procedure SetCopyToLines(NewCopyToLines: Boolean)
    begin
        CopyToLines := NewCopyToLines;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Shipment Header", 'OnBeforeConfirmModification', '', false, false)]
    local procedure AnswerConfirmModification(var Result: Boolean; var IsHandled: Boolean)
    begin
        Result := CopyToLines;
        IsHandled := true;
    end;
}
