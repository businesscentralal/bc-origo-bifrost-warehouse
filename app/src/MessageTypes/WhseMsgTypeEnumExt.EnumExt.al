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
    value(10078401; "Warehouse.Receipt.PreviewPost")
    {
        Caption = 'Warehouse.Receipt.PreviewPost', Locked = true;
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

    /// <summary>
    /// Reads bin master data, optionally with bin content.
    /// </summary>
    value(10078418; "Warehouse.Bin.Get")
    {
        Caption = 'Warehouse.Bin.Get', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Bin Get Impl ori", "Msg Contract ori" = "Whse Bin Get Impl ori", "Msg Discovery ori" = "Whse Bin Get Impl ori";
    }

    /// <summary>
    /// Creates bins at a bin-mandatory location.
    /// </summary>
    value(10078419; "Warehouse.Bin.Create")
    {
        Caption = 'Warehouse.Bin.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Bin Create Impl ori", "Msg Contract ori" = "Whse Bin Create Impl ori", "Msg Discovery ori" = "Whse Bin Create Impl ori";
    }

    /// <summary>
    /// Sets the default bin for an item at a location.
    /// </summary>
    value(10078420; "Warehouse.DefaultBin.Set")
    {
        Caption = 'Warehouse.DefaultBin.Set', Locked = true;
        Implementation = "Msg Interface ori" = "Whse DefaultBin Set Impl ori", "Msg Contract ori" = "Whse DefaultBin Set Impl ori", "Msg Discovery ori" = "Whse DefaultBin Set Impl ori";
    }

    /// <summary>
    /// Creates a warehouse movement at a directed put-away and pick location.
    /// </summary>
    value(10078421; "Warehouse.Movement.Create")
    {
        Caption = 'Warehouse.Movement.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Movement Create Impl ori", "Msg Contract ori" = "Whse Movement Create Impl ori", "Msg Discovery ori" = "Whse Movement Create Impl ori";
    }

    /// <summary>
    /// Registers a warehouse movement.
    /// </summary>
    value(10078422; "Warehouse.Movement.Register")
    {
        Caption = 'Warehouse.Movement.Register', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Movement Reg Impl ori", "Msg Contract ori" = "Whse Movement Reg Impl ori", "Msg Discovery ori" = "Whse Movement Reg Impl ori";
    }

    /// <summary>
    /// Creates an inventory pick from a released source document at a basic location that requires pick.
    /// </summary>
    value(10078423; "Warehouse.InventoryPick.Create")
    {
        Caption = 'Warehouse.InventoryPick.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse InvtPick Create Impl ori", "Msg Contract ori" = "Whse InvtPick Create Impl ori", "Msg Discovery ori" = "Whse InvtPick Create Impl ori";
    }

    /// <summary>
    /// Posts an inventory pick and ships the source document.
    /// </summary>
    value(10078424; "Warehouse.InventoryPick.Post")
    {
        Caption = 'Warehouse.InventoryPick.Post', Locked = true;
        Implementation = "Msg Interface ori" = "Whse InvtPick Post Impl ori", "Msg Contract ori" = "Whse InvtPick Post Impl ori", "Msg Discovery ori" = "Whse InvtPick Post Impl ori";
    }

    /// <summary>
    /// Creates an inventory put-away from a released inbound source document at a basic location that requires put-away.
    /// </summary>
    value(10078425; "Warehouse.InventoryPutAway.Create")
    {
        Caption = 'Warehouse.InventoryPutAway.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse InvtPut Create Impl ori", "Msg Contract ori" = "Whse InvtPut Create Impl ori", "Msg Discovery ori" = "Whse InvtPut Create Impl ori";
    }

    /// <summary>
    /// Posts an inventory put-away and receives the source document.
    /// </summary>
    value(10078426; "Warehouse.InventoryPutAway.Post")
    {
        Caption = 'Warehouse.InventoryPutAway.Post', Locked = true;
        Implementation = "Msg Interface ori" = "Whse InvtPut Post Impl ori", "Msg Contract ori" = "Whse InvtPut Post Impl ori", "Msg Discovery ori" = "Whse InvtPut Post Impl ori";
    }

    /// <summary>
    /// Creates an inventory movement at a basic location with bins.
    /// </summary>
    value(10078427; "Warehouse.InventoryMovement.Create")
    {
        Caption = 'Warehouse.InventoryMovement.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse InvtMove Create Impl ori", "Msg Contract ori" = "Whse InvtMove Create Impl ori", "Msg Discovery ori" = "Whse InvtMove Create Impl ori";
    }

    /// <summary>
    /// Registers an inventory movement.
    /// </summary>
    value(10078428; "Warehouse.InventoryMovement.Register")
    {
        Caption = 'Warehouse.InventoryMovement.Register', Locked = true;
        Implementation = "Msg Interface ori" = "Whse InvtMove Reg Impl ori", "Msg Contract ori" = "Whse InvtMove Reg Impl ori", "Msg Discovery ori" = "Whse InvtMove Reg Impl ori";
    }

    /// <summary>
    /// Calculates bin replenishment into a movement worksheet.
    /// </summary>
    value(10078429; "Warehouse.BinReplenishment.Calculate")
    {
        Caption = 'Warehouse.BinReplenishment.Calculate', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Bin Repl Calc Impl ori", "Msg Contract ori" = "Whse Bin Repl Calc Impl ori", "Msg Discovery ori" = "Whse Bin Repl Calc Impl ori";
    }

    /// <summary>
    /// Inserts warehouse item or reclassification journal lines at a directed location.
    /// </summary>
    value(10078446; "Warehouse.Journal.Create")
    {
        Caption = 'Warehouse.Journal.Create', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Journal Create Impl ori", "Msg Contract ori" = "Whse Journal Create Impl ori", "Msg Discovery ori" = "Whse Journal Create Impl ori";
    }

    /// <summary>
    /// Registers a warehouse item or reclassification journal batch.
    /// </summary>
    value(10078447; "Warehouse.Journal.Register")
    {
        Caption = 'Warehouse.Journal.Register', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Journal Reg Impl ori", "Msg Contract ori" = "Whse Journal Reg Impl ori", "Msg Discovery ori" = "Whse Journal Reg Impl ori";
    }

    /// <summary>
    /// Calculates a warehouse physical inventory into a physical inventory journal batch.
    /// </summary>
    value(10078448; "Warehouse.PhysInventory.Calculate")
    {
        Caption = 'Warehouse.PhysInventory.Calculate', Locked = true;
        Implementation = "Msg Interface ori" = "Whse PhysInvt Calc Impl ori", "Msg Contract ori" = "Whse PhysInvt Calc Impl ori", "Msg Discovery ori" = "Whse PhysInvt Calc Impl ori";
    }

    /// <summary>
    /// Writes counted quantities and registers a warehouse physical inventory journal batch.
    /// </summary>
    value(10078449; "Warehouse.PhysInventory.Register")
    {
        Caption = 'Warehouse.PhysInventory.Register', Locked = true;
        Implementation = "Msg Interface ori" = "Whse PhysInvt Reg Impl ori", "Msg Contract ori" = "Whse PhysInvt Reg Impl ori", "Msg Discovery ori" = "Whse PhysInvt Reg Impl ori";
    }

    /// <summary>
    /// Calculates the warehouse adjustment into an item journal batch.
    /// </summary>
    value(10078450; "Warehouse.Adjustment.Calculate")
    {
        Caption = 'Warehouse.Adjustment.Calculate', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Adjustment Calc Impl ori", "Msg Contract ori" = "Whse Adjustment Calc Impl ori", "Msg Discovery ori" = "Whse Adjustment Calc Impl ori";
    }

    /// <summary>
    /// Fills a pick or put-away worksheet from released warehouse documents.
    /// </summary>
    value(10078460; "Warehouse.Worksheet.GetDocuments")
    {
        Caption = 'Warehouse.Worksheet.GetDocuments', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Wksh GetDocs Impl ori", "Msg Contract ori" = "Whse Wksh GetDocs Impl ori", "Msg Discovery ori" = "Whse Wksh GetDocs Impl ori";
    }

    /// <summary>
    /// Creates picks or put-aways from a pick or put-away worksheet.
    /// </summary>
    value(10078461; "Warehouse.Worksheet.CreateActivities")
    {
        Caption = 'Warehouse.Worksheet.CreateActivities', Locked = true;
        Implementation = "Msg Interface ori" = "Whse Wksh CreateAct Impl ori", "Msg Contract ori" = "Whse Wksh CreateAct Impl ori", "Msg Discovery ori" = "Whse Wksh CreateAct Impl ori";
    }

    /// <summary>
    /// Splits a warehouse activity line.
    /// </summary>
    value(10078462; "Warehouse.ActivityLine.Split")
    {
        Caption = 'Warehouse.ActivityLine.Split', Locked = true;
        Implementation = "Msg Interface ori" = "Whse ActLine Split Impl ori", "Msg Contract ori" = "Whse ActLine Split Impl ori", "Msg Discovery ori" = "Whse ActLine Split Impl ori";
    }

    /// <summary>
    /// Changes the bin of a warehouse activity line.
    /// </summary>
    value(10078463; "Warehouse.ActivityLine.ChangeBin")
    {
        Caption = 'Warehouse.ActivityLine.ChangeBin', Locked = true;
        Implementation = "Msg Interface ori" = "Whse ActLine ChgBin Impl ori", "Msg Contract ori" = "Whse ActLine ChgBin Impl ori", "Msg Discovery ori" = "Whse ActLine ChgBin Impl ori";
    }

    /// <summary>
    /// Sets the quantity to handle on warehouse activity lines.
    /// </summary>
    value(10078464; "Warehouse.ActivityLine.SetQtyToHandle")
    {
        Caption = 'Warehouse.ActivityLine.SetQtyToHandle', Locked = true;
        Implementation = "Msg Interface ori" = "Whse ActLine SetQty Impl ori", "Msg Contract ori" = "Whse ActLine SetQty Impl ori", "Msg Discovery ori" = "Whse ActLine SetQty Impl ori";
    }

    /// <summary>
    /// Assigns lot, serial and package numbers on warehouse activity lines.
    /// </summary>
    value(10078465; "Warehouse.ActivityLine.AssignTracking")
    {
        Caption = 'Warehouse.ActivityLine.AssignTracking', Locked = true;
        Implementation = "Msg Interface ori" = "Whse ActLine Track Impl ori", "Msg Contract ori" = "Whse ActLine Track Impl ori", "Msg Discovery ori" = "Whse ActLine Track Impl ori";
    }
}