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
/// Unit tests for Warehouse.Putaway.Create message type.
/// </summary>
codeunit 97019 "Whse Putaway Create Tests ori"
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
    procedure PutawayCreate_HappyPath_ReturnsPutawayNo()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        ResponseJson: JsonObject;
        StatusToken, PutawayNoToken, TotalLinesToken, AlreadyExistedToken : JsonToken;
        ResponseDebug: Text;
    begin
        // [SCENARIO] Putaway.Create against a Posted Whse. Receipt at a Use Put-away Worksheet
        // location (posting does NOT auto-create) freshly creates a put-away (alreadyExisted = false).
        Initialize();
        Helper.SetupReceivePutawayLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        Helper.PostWhseReceipt(WhseReceiptHeader, PostedWhseReceiptHeader);

        CreateMessage(ResponseJson, PostedWhseReceiptHeader."No.", '', '', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        if StatusToken.AsValue().AsText() <> 'Success' then begin
            ResponseJson.WriteTo(ResponseDebug);
            Assert.Fail('Expected Success but got: ' + ResponseDebug);
        end;
        Assert.IsTrue(ResponseJson.Get('putawayNo', PutawayNoToken), 'putawayNo missing');
        Assert.AreNotEqual('', PutawayNoToken.AsValue().AsText(), 'putawayNo should be populated');
        Assert.IsTrue(ResponseJson.Get('totalPutawayLines', TotalLinesToken), 'totalPutawayLines missing');
        Assert.IsTrue(TotalLinesToken.AsValue().AsInteger() >= 1, 'totalPutawayLines should be at least 1');
        Assert.IsTrue(ResponseJson.Get('alreadyExisted', AlreadyExistedToken), 'alreadyExisted missing');
        Assert.IsFalse(AlreadyExistedToken.AsValue().AsBoolean(), 'Worksheet location: put-away should be freshly created, not pre-existing');
    end;

    [Test]
    procedure PutawayCreate_AutoCreatedOnPosting_ReturnsExisting()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        ResponseJson: JsonObject;
        StatusToken, PutawayNoToken, AlreadyExistedToken : JsonToken;
        ResponseDebug: Text;
    begin
        // [SCENARIO] On a Require Put-away location WITHOUT the put-away worksheet, posting the
        // receipt auto-creates the put-away. BC report 7305 then raises "There is nothing to
        // handle." The implementation recovers by returning the existing put-away as an
        // idempotent Success with alreadyExisted = true.
        Initialize();
        Helper.SetupAutoPutawayLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        Helper.PostWhseReceipt(WhseReceiptHeader, PostedWhseReceiptHeader);

        CreateMessage(ResponseJson, PostedWhseReceiptHeader."No.", '', '', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        if StatusToken.AsValue().AsText() <> 'Success' then begin
            ResponseJson.WriteTo(ResponseDebug);
            Assert.Fail('Expected Success (existing put-away returned) but got: ' + ResponseDebug);
        end;
        Assert.IsTrue(ResponseJson.Get('alreadyExisted', AlreadyExistedToken), 'alreadyExisted missing');
        Assert.IsTrue(AlreadyExistedToken.AsValue().AsBoolean(), 'Non-worksheet location: posting auto-created the put-away, so alreadyExisted should be true');
        Assert.IsTrue(ResponseJson.Get('putawayNo', PutawayNoToken), 'putawayNo missing');
        Assert.AreNotEqual('', PutawayNoToken.AsValue().AsText(), 'putawayNo should be populated');
    end;

    [Test]
    procedure PutawayCreate_WithAssignedUserId_AppliesToHeader()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        AssignedUserToken: JsonToken;
        AssignedUser: Code[50];
    begin
        // [SCENARIO] assignedUserId is applied to the created Warehouse Put-away header
        Initialize();
        Helper.SetupReceivePutawayLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        Helper.PostWhseReceipt(WhseReceiptHeader, PostedWhseReceiptHeader);

        AssignedUser := Helper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        CreateMessage(ResponseJson, PostedWhseReceiptHeader."No.", AssignedUser, '', false, false);
        Assert.IsTrue(ResponseJson.Get('assignedUserId', AssignedUserToken), 'assignedUserId missing');
        Assert.AreEqual(AssignedUser, AssignedUserToken.AsValue().AsText(), 'assignedUserId mismatch');

        Assert.IsTrue(Helper.FindPutawayForPostedReceipt(PostedWhseReceiptHeader."No.", WarehouseActivityHeader), 'Put-away header not found');
        Assert.AreEqual(AssignedUser, WarehouseActivityHeader."Assigned User ID", 'Assigned User ID not persisted on header');
    end;

    [Test]
    procedure PutawayCreate_InvalidSortingMethod_ReturnsError()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        ResponseJson: JsonObject;
        StatusToken, ErrorToken : JsonToken;
    begin
        // [SCENARIO] An unknown sortingMethod returns Error and the supplied value appears in the error message
        Initialize();
        Helper.SetupReceivePutawayLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        Helper.PostWhseReceipt(WhseReceiptHeader, PostedWhseReceiptHeader);

        CreateMessage(ResponseJson, PostedWhseReceiptHeader."No.", '', 'NotAMethod', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.IsTrue(ErrorToken.AsValue().AsText().Contains('NotAMethod'), 'Error should mention supplied sortingMethod value');
    end;

    [Test]
    procedure PutawayCreate_ReceiptNotFound_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Non-existent Posted Whse. Receipt No. returns Error
        Initialize();

        CreateMessage(ResponseJson, 'DOES-NOT-EXIST', '', '', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        // [THEN] #135 amended AC6: RecordNotFound in the shared wording, with parameter and received.
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('RecordNotFound', StatusToken.AsValue().AsText(), 'code');
        ResponseJson.Get('error', StatusToken);
        Assert.AreEqual('Posted Whse. Receipt Header "DOES-NOT-EXIST" was not found (from subject).', StatusToken.AsValue().AsText(), 'error');
        ResponseJson.Get('parameter', StatusToken);
        Assert.AreEqual('subject', StatusToken.AsValue().AsText(), 'parameter');
        ResponseJson.Get('received', StatusToken);
        Assert.AreEqual('DOES-NOT-EXIST', StatusToken.AsValue().AsText(), 'received');
    end;

    [Test]
    procedure PutawayCreate_MissingIdentifier_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] No Subject and no identifier key in request returns Error
        Initialize();

        CreateMessage(ResponseJson, '', '', '', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('MissingParameter', StatusToken.AsValue().AsText(), 'code');
    end;

    [Test]
    procedure PutawayCreate_SetBreakbulkFilterTrue_ReturnsError()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        ResponseJson: JsonObject;
        StatusToken, ErrorToken : JsonToken;
    begin
        // [SCENARIO] setBreakbulkFilter = true is not supported by this API version
        Initialize();
        Helper.SetupReceivePutawayLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);
        Helper.PostWhseReceipt(WhseReceiptHeader, PostedWhseReceiptHeader);

        CreateMessage(ResponseJson, PostedWhseReceiptHeader."No.", '', '', true, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.IsTrue(ErrorToken.AsValue().AsText().Contains('setBreakbulkFilter'), 'Error should mention setBreakbulkFilter');
    end;

    local procedure CreateMessage(var ResponseJson: JsonObject; PostedWhseReceiptNo: Code[20]; AssignedUserId: Code[50]; SortingMethod: Text; SetBreakbulkFilter: Boolean; DoNotFillQtyToHandle: Boolean)
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        if AssignedUserId <> '' then
            RequestJson.Add('assignedUserId', AssignedUserId);
        if SortingMethod <> '' then
            RequestJson.Add('sortingMethod', SortingMethod);
        if SetBreakbulkFilter then
            RequestJson.Add('setBreakbulkFilter', true);
        if DoNotFillQtyToHandle then
            RequestJson.Add('doNotFillQtyToHandle', true);
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Putaway.Create", PostedWhseReceiptNo, RequestText, ResponseJson);
    end;

    /// <summary>Verifies that Warehouse.Putaway.Create is enabled when write permission is present.</summary>
    [Test]
    procedure IsEnabledWithWritePermission()
    var
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Putaway.Create";
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'Warehouse.Putaway.Create must be enabled when the caller can write Posted Whse. Receipt Header.');
    end;

    /// <summary>Verifies that Warehouse.Putaway.Create is disabled without write permission on Posted Whse. Receipt Header.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutWritePermission()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Putaway.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Putaway.Create must be disabled without write permission on Posted Whse. Receipt Header.');
    end;
}
