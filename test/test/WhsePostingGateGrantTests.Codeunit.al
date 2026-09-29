namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
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
        Argument: Record "Message Argument ori";
        PostingGate: Codeunit "Whse Posting Gate ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToWhsePost(LibraryLowerPermissions);
        PrepareArgument(Argument);

        Assert.IsTrue(PostingGate.HasPostingPermission(), 'HasPostingPermission should be true with the token.');
        Assert.IsTrue(PostingGate.HasInvoicePermission(), 'HasInvoicePermission should be true with the token.');
        Assert.IsTrue(PostingGate.AssertCanPost(Argument), 'AssertCanPost should allow the token.');
        Assert.AreEqual(0, Argument.GetResponseContentLength(), 'AssertCanPost must not write an error.');
        Assert.IsTrue(PostingGate.AssertCanInvoice(Argument), 'AssertCanInvoice should allow the token.');
        Assert.AreEqual(0, Argument.GetResponseContentLength(), 'AssertCanInvoice must not write an error.');
    end;

    /// <summary>Warehouse.Shipment.Post with invoice = true passes both gates and reaches lookup.</summary>
    [Test]
    procedure ShipmentPost_InvoiceWithWhseInv_ReachesLookup()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        ResponseJson: JsonObject;
        CodeToken: JsonToken;
        ErrorToken: JsonToken;
    begin
        LowerToWhsePost(LibraryLowerPermissions);

        Assert.IsTrue(RunShipmentPost('{"invoice":true}', ResponseJson), 'The lookup response should be JSON.');
        Assert.IsTrue(ResponseJson.Get('code', CodeToken), 'code missing');
        Assert.AreEqual('MissingParameter', CodeToken.AsValue().AsText(), 'An empty subject should fail lookup, not the posting gate.');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.AreEqual(0, StrPos(ErrorToken.AsValue().AsText(), 'Posting denied'), ErrorToken.AsValue().AsText());
    end;

    local procedure LowerToWhsePost(var LibraryLowerPermissions: Codeunit "Library - Lower Permissions")
    begin
        // Restrictive tests start as D365 Full Access until this library replaces that set.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('BIFROST Full ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        LibraryLowerPermissions.AddPermissionSet('BIFROST WhsePost ori');
        LibraryLowerPermissions.AddPermissionSet('BIFROST WhseInv ori');
    end;

    local procedure PrepareArgument(var Argument: Record "Message Argument ori")
    begin
        Argument.Init();
        Argument.Version := "Message Version ori"::"1.0";
        Argument.Insert(true);
    end;

    local procedure RunShipmentPost(RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[50];
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
}
