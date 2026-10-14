namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Warehouse.Document;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Receipt.Post.Preview message type.
/// </summary>
codeunit 97016 "Whse Rcpt Post Prev Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Receipt Test Helper ori";
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        if IsInitialized then exit;
        IsInitialized := true;
    end;

    [Test]
    procedure PreviewPost_PurchaseReceipt_ReturnsPreviewAndRollsBack()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader, AfterWhseReceiptHeader : Record "Warehouse Receipt Header";
        RequestJson, ResponseJson : JsonObject;
        StatusToken, PredictedToken : JsonToken;
        RequestText: Text;
        ReceiptNoBefore: Code[20];
        CountToken: JsonToken;
    begin
        // [SCENARIO] PreviewPost returns predicted numbers and does not actually post (header still exists)
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 10);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        ReceiptNoBefore := WhseReceiptHeader."No.";

        RequestJson.WriteTo(RequestText);
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.Post.Preview", WhseReceiptHeader."No.", RequestText, ResponseJson), 'Response JSON should parse');
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');
        Assert.IsTrue(ResponseJson.Get('predictedNumbers', PredictedToken), 'predictedNumbers missing');

        // [THEN] Public preview helper preserves populated ledger counts.
        Assert.IsTrue(ResponseJson.Get('entryCount', CountToken), 'entryCount missing');
        Assert.IsTrue(CountToken.AsValue().AsInteger() > 0, 'Preview must count captured entries');
        Assert.IsTrue(ResponseJson.Get('glEntryCount', CountToken), 'glEntryCount missing');
        Assert.IsTrue(CountToken.AsValue().AsInteger() >= 0, 'Receipt preview may receive without invoicing; G/L count cannot be negative');

        // [THEN] Warehouse Receipt Header should still exist (preview rolled back — post would have deleted it)
        Assert.IsTrue(AfterWhseReceiptHeader.Get(ReceiptNoBefore), 'Preview should not have consumed the Warehouse Receipt Header');
    end;

    [Test]
    procedure PreviewPost_MissingReceipt_ReturnsError()
    var
        RequestJson, ResponseJson : JsonObject;
        StatusToken: JsonToken;
        RequestText: Text;
    begin
        // [SCENARIO] Preview with no receipt identifier returns Error
        Initialize();

        RequestJson.WriteTo(RequestText);
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.Post.Preview", '', RequestText, ResponseJson), 'Response JSON should parse');
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    [Test]
    procedure PreviewPost_NothingToReceive_ReturnsNothingToPreview()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        WhseReceiptLine: Record "Warehouse Receipt Line";
        RequestJson, ResponseJson : JsonObject;
        Token: JsonToken;
        RequestText: Text;
    begin
        // [SCENARIO] #140: a receipt with no Qty. to Receive never previews as Success.
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 10);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        WhseReceiptLine.SetRange("No.", WhseReceiptHeader."No.");
        WhseReceiptLine.FindSet(true);
        repeat
            WhseReceiptLine.Validate("Qty. to Receive", 0);
            WhseReceiptLine.Modify(true);
        until WhseReceiptLine.Next() = 0;
        Commit();

        RequestJson.WriteTo(RequestText);
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.Post.Preview", WhseReceiptHeader."No.", RequestText, ResponseJson), 'Response JSON should parse');
        Assert.IsTrue(ResponseJson.Get('status', Token), 'status missing');
        Assert.AreEqual('Error', Token.AsValue().AsText(), 'Never Success when nothing would be received');
        Assert.IsTrue(ResponseJson.Get('code', Token), 'code');
        Assert.AreEqual('NothingToPreview', Token.AsValue().AsText(), 'code');
        Assert.IsTrue(ResponseJson.Get('nextStep', Token), 'nextStep');
        Assert.IsTrue(Token.AsValue().AsText().Contains('Qty. to Receive'), 'nextStep names Qty. to Receive');
    end;
}
