namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Extends Foundation read permissions with Warehouse message-type execution rights.
/// </summary>
permissionsetextension 10078394 "BIFROST Whse - Read ori" extends "BIFROST Read ori"
{
    Permissions =
        codeunit "Warehouse Install ori" = X,
        codeunit "Warehouse Upgrade ori" = X;
}