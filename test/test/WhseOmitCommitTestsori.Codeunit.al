namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Request;
using System.TestLibraries.Utilities;

/// <summary>Verifies preview refusal and posting-error isolation in both transaction modes.</summary>
codeunit 97028 "Whse Omit Commit Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
        NotReleasedErr: Label 'The source document %1 %2 is not released.', Locked = true;

    /// <summary>Shipment preview refuses Omit Commit and preserves a postable shipment.</summary>
    [Test]
    procedure PreviewShipment_OmitCommit_ReturnsPreconditionFailed()
    var
        Item: Record Item;
        Location: Record Location;
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
        QuantityToShip: Decimal;
    begin
        // The rollback-chain mode is an AL dispatcher option, not a Web Client action.
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        ShipmentLine.FindFirst();
        QuantityToShip := ShipmentLine."Qty. to Ship";
        Assert.IsTrue(QuantityToShip > 0, 'The shipment must be postable before preview is refused.');

        Assert.IsTrue(ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", ShipmentHeader."No.", '', ResponseJson, true), 'Response must parse.');
        AssertPreviewRefused(ResponseJson);
        Assert.IsTrue(ShipmentHeader.Get(ShipmentHeader."No."), 'Refused preview must preserve the shipment header.');
        ShipmentLine.Get(ShipmentLine."No.", ShipmentLine."Line No.");
        Assert.AreEqual(QuantityToShip, ShipmentLine."Qty. to Ship", 'Refused preview must preserve the quantity to ship.');
    end;

    /// <summary>Receipt preview refuses Omit Commit and preserves a postable receipt.</summary>
    [Test]
    procedure PreviewReceipt_OmitCommit_ReturnsPreconditionFailed()
    var
        Item: Record Item;
        Location: Record Location;
        PurchaseHeader: Record "Purchase Header";
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
        QuantityToReceive: Decimal;
    begin
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 10);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(ReceiptHeader, PurchaseHeader);
        ReceiptLine.SetRange("No.", ReceiptHeader."No.");
        ReceiptLine.FindFirst();
        QuantityToReceive := ReceiptLine."Qty. to Receive";
        Assert.IsTrue(QuantityToReceive > 0, 'The receipt must be postable before preview is refused.');

        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.PreviewPost", ReceiptHeader."No.", '', ResponseJson, true), 'Response must parse.');
        AssertPreviewRefused(ResponseJson);
        Assert.IsTrue(ReceiptHeader.Get(ReceiptHeader."No."), 'Refused preview must preserve the receipt header.');
        ReceiptLine.Get(ReceiptLine."No.", ReceiptLine."Line No.");
        Assert.AreEqual(QuantityToReceive, ReceiptLine."Qty. to Receive", 'Refused preview must preserve the quantity to receive.');
    end;

    /// <summary>Omit Commit raises the original posting error instead of a transaction error.</summary>
    [Test]
    procedure PostShipment_OmitCommit_PostingError_IsRaised()
    var
        ExpectedError: Text;
        ShipmentNo: Code[20];
        ResponseJson: JsonObject;
        ErrorText: Text;
    begin
        ShipmentNo := CreateShipmentWithOpenRequest(ExpectedError);
        asserterror ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.Post", ShipmentNo, '', ResponseJson, true);
        ErrorText := GetLastErrorText();
        Assert.AreEqual(ExpectedError, ErrorText, 'The original Business Central posting error must propagate unchanged.');
        Assert.IsFalse(ErrorText.Contains('transaction'), 'Posting must not fail on Codeunit.Run transaction rules.');
    end;

    /// <summary>The committing mode continues to return posting errors as JSON.</summary>
    [Test]
    procedure PostShipment_NoOmitCommit_PostingError_ReturnsError()
    var
        ExpectedError: Text;
        ShipmentNo: Code[20];
        ResponseJson: JsonObject;
        Token: JsonToken;
    begin
        ShipmentNo := CreateShipmentWithOpenRequest(ExpectedError);
        Assert.IsTrue(ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.Post", ShipmentNo, '', ResponseJson, false), 'Response must parse.');
        Assert.IsTrue(ResponseJson.Get('status', Token), 'status missing.');
        Assert.AreEqual('Error', Token.AsValue().AsText(), 'Posting failure must remain isolated.');
        Assert.IsTrue(ResponseJson.Get('error', Token), 'error missing.');
        Assert.AreEqual(ExpectedError, Token.AsValue().AsText(), 'The original Business Central posting error must remain in the JSON response.');
    end;

    local procedure AssertPreviewRefused(ResponseJson: JsonObject)
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(ResponseJson.Get('status', Token), 'status missing.');
        Assert.AreEqual('Error', Token.AsValue().AsText(), 'Preview must return Error.');
        Assert.IsTrue(ResponseJson.Get('code', Token), 'code missing.');
        Assert.AreEqual('PreconditionFailed', Token.AsValue().AsText(), 'Preview must explain its precondition.');
        Assert.IsTrue(ResponseJson.Get('nextStep', Token), 'nextStep missing.');
        Assert.IsTrue(Token.AsValue().AsText().Contains('OmitCommit = false'), 'Next step must identify the supported mode.');
    end;

    local procedure CreateShipmentWithOpenRequest(var ExpectedError: Text): Code[20]
    var
        Item: Record Item;
        Location: Record Location;
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        WarehouseRequest: Record "Warehouse Request";
    begin
        // Posting checks that the warehouse request is released. The request is reopened behind the shipment's
        // back, so posting fails in Business Central and not in the type's own validation (#54 refuses zero
        // quantities before posting).
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        ShipmentLine.FindFirst();
        WarehouseRequest.SetRange(Type, WarehouseRequest.Type::Outbound);
        WarehouseRequest.SetRange("Source No.", SalesHeader."No.");
        WarehouseRequest.ModifyAll("Document Status", WarehouseRequest."Document Status"::Open);
        ExpectedError := StrSubstNo(NotReleasedErr, ShipmentLine."Source Document", ShipmentLine."Source No.");
        exit(ShipmentHeader."No.");
    end;
}
