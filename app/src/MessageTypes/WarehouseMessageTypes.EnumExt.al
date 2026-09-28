namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Registers Bifrost Warehouse message types.
/// </summary>
enumextension 10078385 "Whse MsgType EnumExt ori" extends "Message Type ori"
{
    value(10078386; "Warehouse.BinContent.Get")
    {
        Caption = 'Warehouse.BinContent.Get', Locked = true;
        Implementation = "Msg Interface ori" = "Whse BinContent Get Impl ori";
    }

    value(10078387; "Warehouse.Activity.Get")
    {
        Caption = 'Warehouse.Activity.Get', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Activity Get Impl ori";
    }
}