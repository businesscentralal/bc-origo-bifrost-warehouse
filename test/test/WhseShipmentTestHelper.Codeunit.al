namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Setup;

/// <summary>
/// Shared test helper for Warehouse Shipment tests.
/// Creates a location with Require Shipment, seeds stock, builds released sales orders,
/// and creates Warehouse Shipments via BC's Get Source Doc. Outbound flow.
/// </summary>
codeunit 97021 "Whse Shipment Test Helper ori"
{
    Access = Internal;

    var
        LibraryInventory: Codeunit "Library - Inventory";
        LibrarySales: Codeunit "Library - Sales";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>
    /// Creates a Location with Require Shipment = true and seeds stock for an item.
    /// </summary>
    internal procedure SetupLocationAndItem(var Location: Record Location; var Item: Record Item; InitialQty: Decimal)
    begin
        // BinMandatory=false, RequirePutAway=false, RequirePick=false, RequireReceive=false, RequireShipment=true
        LibraryWarehouse.CreateLocationWMS(Location, false, false, false, false, true);
        LibraryInventory.CreateItem(Item);
        if InitialQty > 0 then
            CreatePositiveAdjustment(Item."No.", Location.Code, InitialQty);
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
    /// Creates and releases a Sales Order with one item line at the given location.
    /// </summary>
    internal procedure CreateReleasedSalesOrder(var SalesHeader: Record "Sales Header"; ItemNo: Code[20]; LocationCode: Code[10]; Qty: Decimal)
    var
        Customer: Record Customer;
        SalesLine: Record "Sales Line";
        ReleaseSalesDocument: Codeunit "Release Sales Document";
    begin
        LibrarySales.CreateCustomer(Customer);
        LibrarySales.CreateSalesHeader(SalesHeader, SalesHeader."Document Type"::Order, Customer."No.");
        SalesHeader.Validate("Location Code", LocationCode);
        SalesHeader.Modify(true);
        LibrarySales.CreateSalesLine(SalesLine, SalesHeader, SalesLine.Type::Item, ItemNo, Qty);
        SalesLine.Validate("Location Code", LocationCode);
        SalesLine.Validate("Unit Price", 100);
        SalesLine.Modify(true);
        ReleaseSalesDocument.Run(SalesHeader);
        SalesHeader.Get(SalesHeader."Document Type"::Order, SalesHeader."No.");
    end;

    /// <summary>
    /// Creates a Warehouse Shipment for a released Sales Order and returns the header.
    /// </summary>
    internal procedure CreateWhseShipmentFromSalesOrder(var WhseShipmentHeader: Record "Warehouse Shipment Header"; var SalesHeader: Record "Sales Header")
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
        GetSourceDocOutbound: Codeunit "Get Source Doc. Outbound";
    begin
        GetSourceDocOutbound.CreateFromSalesOrderHideDialog(SalesHeader);
        WhseShipmentLine.SetRange("Source Type", Database::"Sales Line");
        WhseShipmentLine.SetRange("Source Subtype", SalesHeader."Document Type"::Order.AsInteger());
        WhseShipmentLine.SetRange("Source No.", SalesHeader."No.");
        WhseShipmentLine.FindLast();
        WhseShipmentHeader.Get(WhseShipmentLine."No.");
    end;



    /// <summary>
    /// Creates a Location with Require Pick = true + Require Shipment = true (no bins) and
    /// seeds stock. Suitable for testing Warehouse.Pick.Create / Warehouse.Pick.Register.
    /// </summary>
    internal procedure SetupPickLocationAndItem(var Location: Record Location; var Item: Record Item; InitialQty: Decimal)
    begin
        // BinMandatory=false, RequirePutAway=false, RequirePick=true, RequireReceive=false, RequireShipment=true
        LibraryWarehouse.CreateLocationWMS(Location, false, false, true, false, true);
        LibraryInventory.CreateItem(Item);
        if InitialQty > 0 then
            CreatePositiveAdjustment(Item."No.", Location.Code, InitialQty);
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
    /// Finds the latest Warehouse Pick header created from the supplied Warehouse Shipment.
    /// </summary>
    internal procedure FindPickForShipment(WhseShipmentNo: Code[20]; var WarehouseActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        WarehouseActivityLine: Record "Warehouse Activity Line";
    begin
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::Pick);
        WarehouseActivityLine.SetRange("Whse. Document Type", WarehouseActivityLine."Whse. Document Type"::Shipment);
        WarehouseActivityLine.SetRange("Whse. Document No.", WhseShipmentNo);
        WarehouseActivityLine.SetCurrentKey("No.");
        if not WarehouseActivityLine.FindLast() then
            exit(false);
        WarehouseActivityHeader.SetRange(Type, WarehouseActivityHeader.Type::Pick);
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
        ResponseContentType: Text[100];
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
            ResponseContentType,
            false);
        if ResponseContent.Length() = 0 then
            exit(false);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        exit(ResponseJson.ReadFrom(ResponseText));
    end;
}
