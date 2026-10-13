namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
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
        NoQuantityErr: Label 'There is nothing to post because the document does not contain a quantity or amount.', Locked = true;

    /// <summary>Shipment preview refuses Omit Commit before reading a document.</summary>
    [Test]
    procedure PreviewShipment_OmitCommit_ReturnsPreconditionFailed()
    var
        ResponseJson: JsonObject;
    begin
        Assert.IsTrue(ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", '', '', ResponseJson, true), 'Response must parse.');
        AssertPreviewRefused(ResponseJson);
    end;

    /// <summary>Receipt preview refuses Omit Commit before reading a document.</summary>
    [Test]
    procedure PreviewReceipt_OmitCommit_ReturnsPreconditionFailed()
    var
        ResponseJson: JsonObject;
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.Post.Preview", '', '', ResponseJson, true), 'Response must parse.');
        AssertPreviewRefused(ResponseJson);
    end;

    /// <summary>Omit Commit raises the original posting error instead of a transaction error.</summary>
    [Test]
    procedure PostShipment_OmitCommit_PostingError_IsRaised()
    var
        ShipmentNo: Code[20];
        ResponseJson: JsonObject;
        ErrorText: Text;
    begin
        ShipmentNo := CreateShipmentWithoutQuantity();
        asserterror ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.Post", ShipmentNo, '', ResponseJson, true);
        ErrorText := GetLastErrorText();
        Assert.AreEqual(NoQuantityErr, ErrorText, 'The original Business Central quantity error must propagate unchanged.');
        Assert.IsFalse(ErrorText.Contains('transaction'), 'Posting must not fail on Codeunit.Run transaction rules.');
    end;

    /// <summary>The committing mode continues to return posting errors as JSON.</summary>
    [Test]
    procedure PostShipment_NoOmitCommit_PostingError_ReturnsError()
    var
        ShipmentNo: Code[20];
        ResponseJson: JsonObject;
        Token: JsonToken;
    begin
        ShipmentNo := CreateShipmentWithoutQuantity();
        Assert.IsTrue(ShipmentHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.Post", ShipmentNo, '', ResponseJson, false), 'Response must parse.');
        Assert.IsTrue(ResponseJson.Get('status', Token), 'status missing.');
        Assert.AreEqual('Error', Token.AsValue().AsText(), 'Posting failure must remain isolated.');
        Assert.IsTrue(ResponseJson.Get('error', Token), 'error missing.');
        Assert.AreEqual(NoQuantityErr, Token.AsValue().AsText(), 'The original Business Central quantity error must remain in the JSON response.');
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

    local procedure CreateShipmentWithoutQuantity(): Code[20]
    var
        Item: Record Item;
        Location: Record Location;
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        ShipmentHelper.SetupLocationAndItem(Location, Item, 100);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
        ShipmentLine.SetLoadFields("No.", "Line No.", "Qty. to Ship");
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        ShipmentLine.FindSet(true);
        repeat
            ShipmentLine.Validate("Qty. to Ship", 0);
            ShipmentLine.Modify(true);
        until ShipmentLine.Next() = 0;
        exit(ShipmentHeader."No.");
    end;
}
