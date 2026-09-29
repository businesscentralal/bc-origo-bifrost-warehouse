namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Transfer;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Setup;

/// <summary>
/// Shared test helper for Warehouse Receipt tests.
/// Creates a location with Require Receive, seeds stock, builds released purchase / sales return /
/// inbound transfer orders, and creates Warehouse Receipts via BC's Get Source Doc. Inbound flow.
/// </summary>
codeunit 97022 "Whse Receipt Test Helper ori"
{
    Access = Internal;

    var
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryPurchase: Codeunit "Library - Purchase";
        LibrarySales: Codeunit "Library - Sales";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>
    /// Creates a Location with Require Receive = true (no put-away mandate) and seeds the item.
    /// </summary>
    internal procedure SetupLocationAndItem(var Location: Record Location; var Item: Record Item; InitialQty: Decimal)
    begin
        // BinMandatory=false, RequirePutAway=false, RequirePick=false, RequireReceive=true, RequireShipment=false
        LibraryWarehouse.CreateLocationWMS(Location, false, false, false, true, false);
        LibraryInventory.CreateItem(Item);
        if InitialQty > 0 then
            CreatePositiveAdjustment(Item."No.", Location.Code, InitialQty);
    end;

    /// <summary>
    /// Creates a second receive-enabled location (for transfer-to scenarios) with the same flags.
    /// </summary>
    internal procedure CreateReceiveLocation(var Location: Record Location)
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, false, true, false);
    end;

    /// <summary>
    /// Creates a shipment-enabled "from" location for transfer scenarios.
    /// </summary>
    internal procedure CreateShipmentLocation(var Location: Record Location)
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, false, false, true);
    end;

    /// <summary>
    /// Creates an in-transit location for transfer orders.
    /// </summary>
    internal procedure CreateInTransitLocation(var Location: Record Location)
    begin
        LibraryWarehouse.CreateInTransitLocation(Location);
    end;

    /// <summary>
    /// Posts a positive item-journal adjustment to seed inventory at a location.
    /// </summary>
    internal procedure CreatePositiveAdjustment(ItemNo: Code[20]; LocationCode: Code[10]; Qty: Decimal)
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        LibraryInventory.SelectItemJournalTemplateName(ItemJournalTemplate, ItemJournalTemplate.Type::Item);
        LibraryInventory.SelectItemJournalBatchName(ItemJournalBatch, ItemJournalTemplate.Type::Item, ItemJournalTemplate.Name);
        LibraryInventory.ClearItemJournal(ItemJournalTemplate, ItemJournalBatch);
        LibraryInventory.CreateItemJournalLine(
            ItemJournalLine, ItemJournalTemplate.Name, ItemJournalBatch.Name,
            "Item Ledger Entry Type"::"Positive Adjmt.", ItemNo, Qty);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Modify(true);
        LibraryInventory.PostItemJournalLine(ItemJournalTemplate.Name, ItemJournalBatch.Name);
    end;

    /// <summary>
    /// Creates and releases a Purchase Order with one item line at the given location.
    /// </summary>
    internal procedure CreateReleasedPurchaseOrder(var PurchaseHeader: Record "Purchase Header"; ItemNo: Code[20]; LocationCode: Code[10]; Qty: Decimal)
    var
        Vendor: Record Vendor;
        PurchaseLine: Record "Purchase Line";
        ReleasePurchaseDocument: Codeunit "Release Purchase Document";
    begin
        LibraryPurchase.CreateVendor(Vendor);
        LibraryPurchase.CreatePurchHeader(PurchaseHeader, PurchaseHeader."Document Type"::Order, Vendor."No.");
        PurchaseHeader.Validate("Location Code", LocationCode);
        PurchaseHeader.Modify(true);
        LibraryPurchase.CreatePurchaseLine(PurchaseLine, PurchaseHeader, PurchaseLine.Type::Item, ItemNo, Qty);
        PurchaseLine.Validate("Location Code", LocationCode);
        PurchaseLine.Validate("Direct Unit Cost", 100);
        PurchaseLine.Modify(true);
        ReleasePurchaseDocument.Run(PurchaseHeader);
        PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, PurchaseHeader."No.");
    end;

    /// <summary>
    /// Creates and releases a Sales Return Order with one item line at the given location.
    /// </summary>
    internal procedure CreateReleasedSalesReturnOrder(var SalesHeader: Record "Sales Header"; ItemNo: Code[20]; LocationCode: Code[10]; Qty: Decimal)
    var
        Customer: Record Customer;
        SalesLine: Record "Sales Line";
        ReleaseSalesDocument: Codeunit "Release Sales Document";
    begin
        LibrarySales.CreateCustomer(Customer);
        LibrarySales.CreateSalesHeader(SalesHeader, SalesHeader."Document Type"::"Return Order", Customer."No.");
        SalesHeader.Validate("Location Code", LocationCode);
        SalesHeader.Modify(true);
        LibrarySales.CreateSalesLine(SalesLine, SalesHeader, SalesLine.Type::Item, ItemNo, Qty);
        SalesLine.Validate("Location Code", LocationCode);
        SalesLine.Validate("Unit Price", 100);
        SalesLine.Modify(true);
        ReleaseSalesDocument.Run(SalesHeader);
        SalesHeader.Get(SalesHeader."Document Type"::"Return Order", SalesHeader."No.");
    end;

    /// <summary>
    /// Creates and releases a Transfer Order from FromLocationCode (with stock) to ToLocationCode.
    /// </summary>
    internal procedure CreateReleasedTransferOrder(var TransferHeader: Record "Transfer Header"; ItemNo: Code[20]; FromLocationCode: Code[10]; ToLocationCode: Code[10]; InTransitLocationCode: Code[10]; Qty: Decimal)
    var
        TransferLine: Record "Transfer Line";
    begin
        LibraryWarehouse.CreateTransferHeader(TransferHeader, FromLocationCode, ToLocationCode, InTransitLocationCode);
        LibraryWarehouse.CreateTransferLine(TransferHeader, TransferLine, ItemNo, Qty);
        LibraryWarehouse.ReleaseTransferOrder(TransferHeader);
        TransferHeader.Get(TransferHeader."No.");
    end;

    /// <summary>
    /// Creates a Warehouse Receipt for a released Purchase Order and returns the header.
    /// </summary>
    internal procedure CreateWhseReceiptFromPurchaseOrder(var WhseReceiptHeader: Record "Warehouse Receipt Header"; var PurchaseHeader: Record "Purchase Header")
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        GetSourceDocInbound: Codeunit "Get Source Doc. Inbound";
    begin
        GetSourceDocInbound.CreateFromPurchOrderHideDialog(PurchaseHeader);
        WhseReceiptLine.SetRange("Source Type", Database::"Purchase Line");
        WhseReceiptLine.SetRange("Source Subtype", PurchaseHeader."Document Type"::Order.AsInteger());
        WhseReceiptLine.SetRange("Source No.", PurchaseHeader."No.");
        WhseReceiptLine.FindLast();
        WhseReceiptHeader.Get(WhseReceiptLine."No.");
    end;

    /// <summary>
    /// Creates a Location with Require Receive + Require Put-away enabled and seeds the item.
    /// Used by Put-away test scenarios.
    ///
    /// "Use Put-away Worksheet" is enabled so posting the Warehouse Receipt does NOT
    /// auto-create the put-away (see base app "Whse.-Post Receipt": put-aways are only
    /// auto-created when Require Put-away AND NOT Use Put-away Worksheet). This leaves the
    /// put-away for the Warehouse.Putaway.Create message type (BC report 7305) to create;
    /// otherwise report 7305 finds the quantity already handled and errors with
    /// "There is nothing to handle."
    /// </summary>
    internal procedure SetupReceivePutawayLocationAndItem(var Location: Record Location; var Item: Record Item; InitialQty: Decimal)
    begin
        // BinMandatory=false, RequirePutAway=true, RequirePick=false, RequireReceive=true, RequireShipment=false
        LibraryWarehouse.CreateLocationWMS(Location, false, true, false, true, false);
        Location.Validate("Use Put-away Worksheet", true);
        Location.Modify(true);
        LibraryInventory.CreateItem(Item);
        if InitialQty > 0 then
            CreatePositiveAdjustment(Item."No.", Location.Code, InitialQty);
    end;

    /// <summary>
    /// Creates a Require Receive + Require Put-away location WITHOUT the put-away worksheet.
    /// Posting the Warehouse Receipt then auto-creates the put-away (base app "Whse.-Post
    /// Receipt": ShouldCreatePutAway = Require Put-away AND NOT Use Put-away Worksheet). Used to
    /// exercise the Warehouse.Putaway.Create idempotent "already existed" path, where the report
    /// finds nothing to handle but an open put-away is already on disk.
    /// </summary>
    internal procedure SetupAutoPutawayLocationAndItem(var Location: Record Location; var Item: Record Item; InitialQty: Decimal)
    begin
        // BinMandatory=false, RequirePutAway=true, RequirePick=false, RequireReceive=true, RequireShipment=false.
        // Use Put-away Worksheet is left at its default (false) so posting auto-creates the put-away.
        LibraryWarehouse.CreateLocationWMS(Location, false, true, false, true, false);
        LibraryInventory.CreateItem(Item);
        if InitialQty > 0 then
            CreatePositiveAdjustment(Item."No.", Location.Code, InitialQty);
    end;

    /// <summary>
    /// Posts the supplied (non-empty) Warehouse Receipt and returns the resulting Posted Whse.
    /// Receipt Header. Uses BC codeunit `Whse.-Post Receipt`.
    /// </summary>
    internal procedure PostWhseReceipt(var WhseReceiptHeader: Record "Warehouse Receipt Header"; var PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header")
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        WhsePostReceipt: Codeunit "Whse.-Post Receipt";
    begin
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        WhseReceiptLine.FindFirst();
        WhsePostReceipt.Run(WhseReceiptLine);

        PostedWhseReceiptHeader.SetCurrentKey("Whse. Receipt No.");
        PostedWhseReceiptHeader.SetRange("Whse. Receipt No.", WhseReceiptHeader."No.");
        PostedWhseReceiptHeader.FindLast();
    end;

    /// <summary>
    /// Registers the current session user as a Warehouse Employee at the supplied location
    /// (non-default) so BC will accept it as an "Assigned User ID" on warehouse activity headers.
    /// Returns the user id used.
    /// </summary>
    internal procedure RegisterCurrentUserAsWarehouseEmployee(LocationCode: Code[10]) AssignedUserId: Code[50]
    var
        WarehouseEmployee: Record "Warehouse Employee";
    begin
        AssignedUserId := CopyStr(UserId(), 1, MaxStrLen(AssignedUserId));
        if WarehouseEmployee.Get(AssignedUserId, LocationCode) then
            exit;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := AssignedUserId;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := false;
        WarehouseEmployee.Insert(true);
    end;

    /// <summary>
    /// Finds the latest Warehouse Put-away header created from the supplied Posted Whse. Receipt.
    /// </summary>
    internal procedure FindPutawayForPostedReceipt(PostedReceiptNo: Code[20]; var WarehouseActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        WarehouseActivityLine: Record "Warehouse Activity Line";
    begin
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::"Put-away");
        WarehouseActivityLine.SetRange("Whse. Document Type", WarehouseActivityLine."Whse. Document Type"::Receipt);
        WarehouseActivityLine.SetRange("Whse. Document No.", PostedReceiptNo);
        WarehouseActivityLine.SetCurrentKey("No.");
        if not WarehouseActivityLine.FindLast() then
            exit(false);
        WarehouseActivityHeader.SetRange(Type, WarehouseActivityHeader.Type::"Put-away");
        WarehouseActivityHeader.SetRange("No.", WarehouseActivityLine."No.");
        exit(WarehouseActivityHeader.FindFirst());
    end;


    /// <summary>
    /// Dispatches a message type through public Dispatcher ori and returns whether the response parsed.
    /// </summary>
    /// <param name="MessageType">The message type to run.</param>
    /// <param name="Subject">The message subject. Pass empty when the type does not read it.</param>
    /// <param name="RequestText">The request payload. Pass empty when no payload is required.</param>
    /// <param name="ResponseJson">Receives the parsed response JSON.</param>
    /// <returns>True when the response parsed as JSON.</returns>
    internal procedure RunMessage(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[50];
        ResponseText: Text;
        SubjectText: Text[250];
    begin
        Clear(ResponseJson);
        Commit();
        SubjectText := CopyStr(Subject, 1, MaxStrLen(SubjectText));
        if RequestText <> '' then
            RequestContent.AddText(RequestText);
        Dispatcher.Execute(
            MessageType,
            Enum::"Message Version ori"::"1.0",
            SubjectText,
            'Bifrost Warehouse Tests',
            'text/json',
            RequestContent,
            ResponseContent,
            ResponseContentType);
        if ResponseContent.Length() = 0 then
            exit(false);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        exit(ResponseJson.ReadFrom(ResponseText));
    end;
}
