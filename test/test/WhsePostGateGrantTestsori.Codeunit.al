namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.Apps;
using System.Environment.Configuration;
using System.TestLibraries.Utilities;

/// <summary>
/// Grant path for the warehouse posting gate.
/// Same lowered sets as the deny path, plus BIFROST WhsePost ori and BIFROST WhseInv ori.
/// Post and register implementations are then enabled, and Warehouse.Shipment.Post with
/// invoice = true passes both checks and reaches record lookup.
/// </summary>
codeunit 97024 "Whse Post Gate Grant Tests ori"
{
    Subtype = Test;
    TestPermissions = Restrictive;

    var
        Assert: Codeunit "Library Assert";

    /// <summary>Warehouse.Shipment.Post is enabled when the caller can write the warehouse posting token.</summary>
    [Test]
    procedure ShipmentPost_WithWhsePost_IsEnabled()
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        PostImpl: Codeunit "Whse Shipment Post Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        Assert.IsTrue(WhseShipmentHeader.WritePermission(), 'Warehouse Shipment Header write must be present so IsEnabled tests the gate.');
        Assert.IsTrue(PostImpl.IsEnabled(), 'Shipment post should be enabled with BIFROST WhsePost ori.');
    end;

    /// <summary>Warehouse.Receipt.Post is enabled when the caller can write the warehouse posting token.</summary>
    [Test]
    procedure ReceiptPost_WithWhsePost_IsEnabled()
    var
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        PostImpl: Codeunit "Whse Receipt Post Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        Assert.IsTrue(WarehouseReceiptHeader.WritePermission(), 'Warehouse Receipt Header write must be present so IsEnabled tests the gate.');
        Assert.IsTrue(PostImpl.IsEnabled(), 'Receipt post should be enabled with BIFROST WhsePost ori.');
    end;

    /// <summary>Warehouse.Pick.Register is enabled when the caller can write the warehouse posting token.</summary>
    [Test]
    procedure PickRegister_WithWhsePost_IsEnabled()
    var
        PostImpl: Codeunit "Whse Pick Register Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        Assert.IsTrue(PostImpl.IsEnabled(), 'Pick register should be enabled with BIFROST WhsePost ori.');
    end;

    /// <summary>Warehouse.Putaway.Register is enabled when the caller can write the warehouse posting token.</summary>
    [Test]
    procedure PutawayRegister_WithWhsePost_IsEnabled()
    var
        PostImpl: Codeunit "Whse Putaway Register Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        Assert.IsTrue(PostImpl.IsEnabled(), 'Put-away register should be enabled with BIFROST WhsePost ori.');
    end;

    /// <summary>A granted caller passes both gate checks and the argument is left unchanged.</summary>
    [Test]
    procedure AssertCanPost_WithBothSets_WritesNoError()
    var
        TempArgument: Record "Message Argument ori" temporary;
        PostingGate: Codeunit "Whse Posting Gate ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        PrepareArgument(TempArgument);

        Assert.IsTrue(PostingGate.HasPostingPermission(), 'HasPostingPermission should be true with the token.');
        Assert.IsTrue(PostingGate.HasInvoicePermission(), 'HasInvoicePermission should be true with the token.');
        Assert.IsTrue(PostingGate.AssertCanPost(TempArgument), 'AssertCanPost should allow the token.');
        Assert.AreEqual(0, TempArgument.GetResponseContentLength(), 'AssertCanPost must not write an error.');
        Assert.IsTrue(PostingGate.AssertCanInvoice(TempArgument), 'AssertCanInvoice should allow the token.');
        Assert.AreEqual(0, TempArgument.GetResponseContentLength(), 'AssertCanInvoice must not write an error.');
    end;

    /// <summary>Warehouse.Shipment.Post with invoice = true passes both gates and reaches lookup.</summary>
    [Test]
    procedure ShipmentPost_InvoiceWithWhseInv_ReachesLookup()
    var
        AppSetting: Record "NAV App Setting";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        ResponseJson: JsonObject;
        CodeToken: JsonToken;
        ResponseText: Text;
        ErrorToken: JsonToken;
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        Assert.IsFalse(AppSetting.WritePermission(), 'The caller must not retain HTTP setup write permission.');

        Assert.IsTrue(RunShipmentPost('{"invoice":true}', ResponseJson), 'The lookup response should be JSON.');
        ResponseJson.WriteTo(ResponseText);
        Assert.IsTrue(ResponseJson.Get('code', CodeToken), 'code missing: ' + ResponseText);
        Assert.AreEqual('MissingParameter', CodeToken.AsValue().AsText(), 'An empty subject should fail lookup, not the posting gate.');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.AreEqual(0, StrPos(ErrorToken.AsValue().AsText(), 'Posting denied'), ErrorToken.AsValue().AsText());
    end;

    /// <summary>The new post and register types are enabled with BIFROST WhsePost ori.</summary>
    [Test]
    procedure NewPostAndRegisterTypes_WithWhsePost_AreEnabled()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        AssertEnabled(Enum::"Message Type ori"::"Warehouse.Movement.Register");
        AssertEnabled(Enum::"Message Type ori"::"Warehouse.InventoryPick.Post");
        AssertEnabled(Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Post");
        AssertEnabled(Enum::"Message Type ori"::"Warehouse.InventoryMovement.Register");
    end;

    /// <summary>Warehouse.InventoryPick.Post with invoice = true passes both gates and reaches lookup.</summary>
    [Test]
    procedure InventoryPickPost_InvoiceWithWhseInv_ReachesLookup()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        ResponseJson: JsonObject;
        CodeToken: JsonToken;
        ResponseText: Text;
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        Assert.IsTrue(RunMessageType(Enum::"Message Type ori"::"Warehouse.InventoryPick.Post", '{"invoice":true}', ResponseJson), 'The lookup response should be JSON.');
        ResponseJson.WriteTo(ResponseText);
        Assert.IsTrue(ResponseJson.Get('code', CodeToken), 'code missing: ' + ResponseText);
        Assert.AreNotEqual('PermissionDenied', CodeToken.AsValue().AsText(), ResponseText);
        Assert.AreEqual(0, StrPos(ResponseText, 'Posting denied'), ResponseText);
    end;

    local procedure LowerToWhsePost(var LibraryLowerPermissions: Codeunit "Library - Lower Permissions")
    begin
        // Restrictive tests start as D365 Full Access until this library replaces that set.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('BIFROST Full ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        LibraryLowerPermissions.AddPermissionSet('BIFROST WhsePost ori');
        LibraryLowerPermissions.AddPermissionSet('BIFROST WhseInv ori');
    end;

    local procedure PrepareArgument(var TempArgument: Record "Message Argument ori")
    begin
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
    end;

    local procedure RunShipmentPost(RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
        ResponseText: Text;
    begin
        Clear(ResponseJson);
        RequestContent.AddText(RequestText);
        Dispatcher.Execute(
            Enum::"Message Type ori"::"Warehouse.Shipment.Post",
            Enum::"Message Version ori"::"1.0",
            '',
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

    local procedure AssertEnabled(MessageType: Enum "Message Type ori")
    var
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := MessageType;
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'The post or register type should be enabled with BIFROST WhsePost ori.');
    end;

    local procedure RunMessageType(MessageType: Enum "Message Type ori"; RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
        ResponseText: Text;
    begin
        Clear(ResponseJson);
        RequestContent.AddText(RequestText);
        Dispatcher.Execute(
            MessageType,
            Enum::"Message Version ori"::"1.0",
            '',
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
