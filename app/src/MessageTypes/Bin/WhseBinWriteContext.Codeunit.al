namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Holds the normalized write payload for an isolated bin write.
/// Codeunit.Run cannot take the request record, so the implementation stores the payload here.
/// </summary>
codeunit 10078465 "Whse Bin Write Context ori"
{
    Access = Internal;
    SingleInstance = true;

    var
        PayloadText: Text;

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

    /// <summary>Drops the payload so a later call cannot reuse it.</summary>
    internal procedure Clear()
    begin
        PayloadText := '';
    end;
}
