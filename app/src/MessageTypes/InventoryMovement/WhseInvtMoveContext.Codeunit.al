namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Holds the normalized inventory-movement payload and the number written by an isolated run.
/// Codeunit.Run cannot take the request record, so the implementation stores it here.
/// </summary>
codeunit 10078440 "Whse InvtMove Context ori"
{
    Access = Internal;
    SingleInstance = true;

    var
        PayloadText: Text;
        ResultNo: Code[20];
        ResultQty: Decimal;
        HasResult: Boolean;

    /// <summary>Stores the payload the isolated process will write.</summary>
    /// <param name="Payload">Normalized request that already passed validation.</param>
    internal procedure SetPayload(Payload: JsonObject)
    begin
        PayloadText := '';
        Payload.WriteTo(PayloadText);
    end;

    /// <summary>Reads the payload stored for the isolated process.</summary>
    /// <param name="Payload">Receives the payload.</param>
    /// <returns>True when a payload is present and parses.</returns>
    internal procedure TryGetPayload(var Payload: JsonObject): Boolean
    begin
        if PayloadText = '' then
            exit(false);
        exit(Payload.ReadFrom(PayloadText));
    end;

    /// <summary>Stores the document number and quantity produced by the isolated run.</summary>
    /// <param name="DocumentNo">Inventory movement or registered movement number.</param>
    /// <param name="Quantity">Registered quantity, or zero for a create.</param>
    internal procedure SetResult(DocumentNo: Code[20]; Quantity: Decimal)
    begin
        ResultNo := DocumentNo;
        ResultQty := Quantity;
        HasResult := DocumentNo <> '';
    end;

    /// <summary>Reads the result of the isolated run.</summary>
    /// <param name="DocumentNo">Receives the document number.</param>
    /// <param name="Quantity">Receives the quantity.</param>
    /// <returns>True when the run stored a document number.</returns>
    internal procedure TryGetResult(var DocumentNo: Code[20]; var Quantity: Decimal): Boolean
    begin
        DocumentNo := ResultNo;
        Quantity := ResultQty;
        exit(HasResult);
    end;

    /// <summary>Drops the payload and result so a later call cannot reuse them.</summary>
    internal procedure Reset()
    begin
        PayloadText := '';
        ResultNo := '';
        ResultQty := 0;
        HasResult := false;
    end;
}
