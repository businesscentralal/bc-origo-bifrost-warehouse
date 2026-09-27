namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Registers Bifrost Warehouse message types.
/// </summary>
enumextension 10036935 "Whse MsgType EnumExt ori" extends "Message Type ori"
{
    value(10036936; "Warehouse.BinContent.Get")
    {
        Caption = 'Warehouse.BinContent.Get', Locked = true;
        Implementation = "Msg Interface ori" = "Whse BinContent Get Impl ori";
    }

    value(10036937; "Warehouse.Activity.Get")
    {
        Caption = 'Warehouse.Activity.Get', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Activity Get Impl ori";
    }
}