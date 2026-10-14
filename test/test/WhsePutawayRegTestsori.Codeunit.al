namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Putaway.Register message type.
/// </summary>
codeunit 97020 "Whse Putaway Reg Tests ori"
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
    procedure PutawayRegister_HappyPath_ReturnsRegisteredPutawayNo()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        StatusToken, LinesToken, RegisteredNoToken : JsonToken;
    begin
        // [SCENARIO] Registering a freshly-created put-away returns Success and a registeredPutawayNo
        Initialize();
        ArrangePutawayReadyForRegister(Location, Item, PurchaseHeader, WhseReceiptHeader, PostedWhseReceiptHeader, WarehouseActivityHeader);

        CreateRegisterMessage(ResponseJson, WarehouseActivityHeader."No.");
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');
        Assert.IsTrue(ResponseJson.Get('linesRegistered', LinesToken), 'linesRegistered missing');
        Assert.IsTrue(LinesToken.AsValue().AsInteger() >= 1, 'linesRegistered should be at least 1');
        Assert.IsTrue(ResponseJson.Get('registeredPutawayNo', RegisteredNoToken), 'registeredPutawayNo missing');
        Assert.AreNotEqual('', RegisteredNoToken.AsValue().AsText(), 'registeredPutawayNo should be populated');
    end;

    [Test]
    procedure PutawayRegister_HappyPath_UpdatesPostedReceiptQtyPutAway()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        ResponseJson: JsonObject;
    begin
        // [SCENARIO] After register, the source Posted Whse. Receipt Line has Qty. Put Away > 0
        Initialize();
        ArrangePutawayReadyForRegister(Location, Item, PurchaseHeader, WhseReceiptHeader, PostedWhseReceiptHeader, WarehouseActivityHeader);

        CreateRegisterMessage(ResponseJson, WarehouseActivityHeader."No.");

        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.IsTrue(PostedWhseReceiptLine."Qty. Put Away" > 0, 'Posted Whse. Receipt Line Qty. Put Away should be > 0 after register');
    end;

    [Test]
    procedure PutawayRegister_ResponseIncludesReceiptLines()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        ReceiptLinesToken: JsonToken;
    begin
        // [SCENARIO] Response includes a non-empty receiptLines array
        Initialize();
        ArrangePutawayReadyForRegister(Location, Item, PurchaseHeader, WhseReceiptHeader, PostedWhseReceiptHeader, WarehouseActivityHeader);

        CreateRegisterMessage(ResponseJson, WarehouseActivityHeader."No.");
        Assert.IsTrue(ResponseJson.Get('receiptLines', ReceiptLinesToken), 'receiptLines missing');
        Assert.IsTrue(ReceiptLinesToken.IsArray(), 'receiptLines should be a JSON array');
        Assert.IsTrue(ReceiptLinesToken.AsArray().Count() >= 1, 'receiptLines should contain at least one row');
    end;

    [Test]
    procedure PutawayRegister_PutawayNotFound_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Non-existent put-away No. returns Error
        Initialize();

        CreateRegisterMessage(ResponseJson, 'NO-SUCH-PUTAWAY');
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        // [THEN] #135 amended AC6: RecordNotFound in the shared wording, with parameter and received.
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('RecordNotFound', StatusToken.AsValue().AsText(), 'code');
        ResponseJson.Get('error', StatusToken);
        Assert.AreEqual('Warehouse Activity Header "NO-SUCH-PUTAWAY" was not found (from subject).', StatusToken.AsValue().AsText(), 'error');
        ResponseJson.Get('parameter', StatusToken);
        Assert.AreEqual('subject', StatusToken.AsValue().AsText(), 'parameter');
        ResponseJson.Get('received', StatusToken);
        Assert.AreEqual('NO-SUCH-PUTAWAY', StatusToken.AsValue().AsText(), 'received');
    end;

    [Test]
    procedure PutawayRegister_MissingIdentifier_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] No Subject and no identifier key returns Error
        Initialize();

        CreateRegisterMessage(ResponseJson, '');
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('MissingParameter', StatusToken.AsValue().AsText(), 'code');
    end;

    local procedure ArrangePutawayReadyForRegister(var Location: Record Location; var Item: Record Item; var PurchaseHeader: Record "Purchase Header"; var WhseReceiptHeader: Record "Warehouse Receipt Header"; var PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header"; var WarehouseActivityHeader: Record "Warehouse Activity Header")
    var
        ResponseJson: JsonObject;
    begin
        Helper.SetupReceivePutawayLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        Helper.PostWhseReceipt(WhseReceiptHeader, PostedWhseReceiptHeader);

        // Use the Bifrost Putaway.Create message type to build the put-away (mirrors customer usage).
        CreatePutawayCreateMessage(ResponseJson, PostedWhseReceiptHeader."No.");

        Assert.IsTrue(Helper.FindPutawayForPostedReceipt(PostedWhseReceiptHeader."No.", WarehouseActivityHeader), 'Put-away should have been created for posted receipt ' + PostedWhseReceiptHeader."No.");
    end;

    local procedure CreatePutawayCreateMessage(var ResponseJson: JsonObject; PostedWhseReceiptNo: Code[20])
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Putaway.Create", PostedWhseReceiptNo, RequestText, ResponseJson);
    end;

    local procedure CreateRegisterMessage(var ResponseJson: JsonObject; PutawayNo: Code[20])
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Putaway.Register", PutawayNo, RequestText, ResponseJson);
    end;
}
