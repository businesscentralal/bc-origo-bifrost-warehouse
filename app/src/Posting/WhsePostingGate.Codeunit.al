namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Posting gate for Bifrost Warehouse.
/// Warehouse shipment post, receipt post, pick register and put-away register require
/// write permission on Whse Posting ori. Warehouse.Shipment.Post with invoice = true
/// also requires write permission on Whse Invoice ori.
/// </summary>
codeunit 10078453 "Whse Posting Gate ori"
{
    Access = Internal;

    /// <summary>
    /// Returns false and writes the denial on Argument when the caller cannot post warehouse documents.
    /// Returns true and leaves Argument unchanged when the caller holds BIFROST WhsePost ori.
    /// </summary>
    /// <param name="Argument">The message argument. Receives the error response on denial.</param>
    /// <returns>True when the caller may post warehouse documents.</returns>
    procedure AssertCanPost(var Argument: Record "Message Argument ori"): Boolean
    var
        PostingDeniedErr: Label 'Posting denied: missing ''%1'' permission set.', Comment = '%1 = permission set name, is-IS=Bókun hafnað: vantar ''%1'' heimildasett.';
        PermissionSetNameTok: Label 'BIFROST WhsePost ori', Locked = true;
    begin
        if HasPostingPermission() then
            exit(true);

        Argument.RespondWithError(
            "Bifrost Error Code ori"::PermissionDenied,
            StrSubstNo(PostingDeniedErr, PermissionSetNameTok),
            '', '', '', '');
        exit(false);
    end;

    /// <summary>
    /// Returns false and writes the denial on Argument when the caller cannot invoice through a warehouse shipment.
    /// Returns true and leaves Argument unchanged when the caller holds BIFROST WhseInv ori.
    /// </summary>
    /// <param name="Argument">The message argument. Receives the error response on denial.</param>
    /// <returns>True when the caller may invoice.</returns>
    procedure AssertCanInvoice(var Argument: Record "Message Argument ori"): Boolean
    var
        PostingDeniedErr: Label 'Posting denied: missing ''%1'' permission set.', Comment = '%1 = permission set name, is-IS=Bókun hafnað: vantar ''%1'' heimildasett.';
        PermissionSetNameTok: Label 'BIFROST WhseInv ori', Locked = true;
    begin
        if HasInvoicePermission() then
            exit(true);

        Argument.RespondWithError(
            "Bifrost Error Code ori"::PermissionDenied,
            StrSubstNo(PostingDeniedErr, PermissionSetNameTok),
            '', '', '', '');
        exit(false);
    end;

    /// <summary>
    /// True when the current user has write permission on the warehouse posting token.
    /// </summary>
    /// <returns>True when BIFROST WhsePost ori is assigned.</returns>
    procedure HasPostingPermission(): Boolean
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(Database::"Whse Posting ori");
        exit(RecRef.WritePermission());
    end;

    /// <summary>
    /// True when the current user has write permission on the warehouse invoice token.
    /// </summary>
    /// <returns>True when BIFROST WhseInv ori is assigned.</returns>
    procedure HasInvoicePermission(): Boolean
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(Database::"Whse Invoice ori");
        exit(RecRef.WritePermission());
    end;
}
