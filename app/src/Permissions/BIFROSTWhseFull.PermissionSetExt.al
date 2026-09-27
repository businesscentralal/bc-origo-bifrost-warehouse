namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Extends Foundation full permissions with Warehouse message-type execution rights.
/// </summary>
permissionsetextension 10036945 "BIFROST Whse - Full ori" extends "BIFROST Full ori"
{
    Permissions =
        codeunit "Warehouse Install ori" = X,
        codeunit "Warehouse Upgrade ori" = X,
        codeunit "Whse BinContent Get Impl ori" = X,
        codeunit "Whse BinContent Get Help ori" = X,
        codeunit "Whse Activity Get Impl ori" = X,
        codeunit "Whse Activity Get Help ori" = X;
}