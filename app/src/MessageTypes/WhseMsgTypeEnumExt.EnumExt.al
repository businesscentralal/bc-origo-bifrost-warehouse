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
        Implementation = "Msg Interface ori" = "Whse BinContent Get Impl ori", "Msg Contract ori" = "Whse BinContent Get Impl ori", "Msg Discovery ori" = "Whse BinContent Get Impl ori";
    }

    value(10078387; "Warehouse.Activity.Get")
    {
        Caption = 'Warehouse.Activity.Get', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Activity Get Impl ori", "Msg Contract ori" = "Whse Activity Get Impl ori", "Msg Discovery ori" = "Whse Activity Get Impl ori";
    }

    /// <summary>
    /// Creates one Warehouse Shipment per supplied source document (Sales Order, Outbound Transfer Order).
    /// </summary>
    value(10078396; "Warehouse.Shipment.Create")
    {
        Caption = 'Warehouse.Shipment.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Shipment Create Impl ori", "Msg Discovery ori" = "Whse Shipment Create Impl ori", "Msg Contract ori" = "Whse Shipment Create Impl ori";
    }

    /// <summary>
    /// Posts a Warehouse Shipment (ship, optionally invoice). Gated by BIFROST WhsePost ori
    /// and, when invoice is true, by BIFROST WhseInv ori.
    /// </summary>
    value(10078397; "Warehouse.Shipment.Post")
    {
        Caption = 'Warehouse.Shipment.Post', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Shipment Post Impl ori", "Msg Discovery ori" = "Whse Shipment Post Impl ori", "Msg Contract ori" = "Whse Shipment Post Impl ori";
    }

    /// <summary>
    /// Simulates posting a Warehouse Shipment (Ship + Invoice) and returns the resulting
    /// ledger entries without committing changes (preview is rolled back).
    /// </summary>
    value(10078398; "Warehouse.Shipment.PreviewPost")
    {
        Caption = 'Warehouse.Shipment.PreviewPost', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Ship. Prev. Post Impl ori", "Msg Discovery ori" = "Whse Ship. Prev. Post Impl ori", "Msg Contract ori" = "Whse Ship. Prev. Post Impl ori";
    }

    /// <summary>
    /// Creates one Warehouse Receipt per supplied source document (Sales Return Order,
    /// Purchase Order, Inbound Transfer Order).
    /// </summary>
    value(10078399; "Warehouse.Receipt.Create")
    {
        Caption = 'Warehouse.Receipt.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Receipt Create Impl ori", "Msg Discovery ori" = "Whse Receipt Create Impl ori", "Msg Contract ori" = "Whse Receipt Create Impl ori";
    }

    /// <summary>
    /// Posts a Warehouse Receipt. Gated by BIFROST WhsePost ori. Unlike Warehouse Shipment,
    /// there is no invoice step.
    /// </summary>
    value(10078400; "Warehouse.Receipt.Post")
    {
        Caption = 'Warehouse.Receipt.Post', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Receipt Post Impl ori", "Msg Discovery ori" = "Whse Receipt Post Impl ori", "Msg Contract ori" = "Whse Receipt Post Impl ori";
    }

    /// <summary>
    /// Simulates posting a Warehouse Receipt and returns the captured ledger entries
    /// without committing. Rolls back the transaction after capture.
    /// </summary>
    value(10078401; "Warehouse.Receipt.Post.Preview")
    {
        Caption = 'Warehouse.Receipt.Post.Preview', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Rcpt Post Prev. Impl ori", "Msg Discovery ori" = "Whse Rcpt Post Prev. Impl ori", "Msg Contract ori" = "Whse Rcpt Post Prev. Impl ori";
    }

    /// <summary>
    /// Creates a Warehouse Pick from a Warehouse Shipment.
    /// </summary>
    value(10078402; "Warehouse.Pick.Create")
    {
        Caption = 'Warehouse.Pick.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Pick Create Impl ori", "Msg Discovery ori" = "Whse Pick Create Impl ori", "Msg Contract ori" = "Whse Pick Create Impl ori";
    }

    /// <summary>
    /// Registers a Warehouse Pick. Gated by BIFROST WhsePost ori.
    /// </summary>
    value(10078403; "Warehouse.Pick.Register")
    {
        Caption = 'Warehouse.Pick.Register', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Pick Register Impl ori", "Msg Discovery ori" = "Whse Pick Register Impl ori", "Msg Contract ori" = "Whse Pick Register Impl ori";
    }

    /// <summary>
    /// Creates a Warehouse Put-away from a Posted Whse. Receipt.
    /// </summary>
    value(10078404; "Warehouse.Putaway.Create")
    {
        Caption = 'Warehouse.Putaway.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Putaway Create Impl ori", "Msg Discovery ori" = "Whse Putaway Create Impl ori", "Msg Contract ori" = "Whse Putaway Create Impl ori";
    }

    /// <summary>
    /// Registers a Warehouse Put-away. Gated by BIFROST WhsePost ori.
    /// </summary>
    value(10078405; "Warehouse.Putaway.Register")
    {
        Caption = 'Warehouse.Putaway.Register', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Putaway Register Impl ori", "Msg Discovery ori" = "Whse Putaway Register Impl ori", "Msg Contract ori" = "Whse Putaway Register Impl ori";
    }
}