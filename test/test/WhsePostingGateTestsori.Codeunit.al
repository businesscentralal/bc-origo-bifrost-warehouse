namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.Apps;
using System.Environment.Configuration;
using System.TestLibraries.Utilities;

/// <summary>
/// Deny path for the warehouse posting gate.
/// The session is lowered to BIFROST Full ori plus document-table write, without BIFROST WhsePost ori
/// or BIFROST WhseInv ori. Post and register implementations are then disabled, and the invoice path
/// of Warehouse.Shipment.Post names BIFROST WhseInv ori once warehouse posting is granted.
/// Preview types stay enabled and do not return a posting denial.
/// </summary>
codeunit 97023 "Whse Posting Gate Tests ori"
{
    Subtype = Test;
    TestPermissions = Restrictive;

    var
        Assert: Codeunit "Library Assert";

    /// <summary>Warehouse.Shipment.Post is disabled when the caller cannot write the warehouse posting token.</summary>
    [Test]
    procedure ShipmentPost_WithoutWhsePost_IsDisabled()
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        PostImpl: Codeunit "Whse Shipment Post Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        Assert.IsTrue(WhseShipmentHeader.WritePermission(), 'Warehouse Shipment Header write must be present so IsEnabled tests the gate.');
        Assert.IsFalse(PostImpl.IsEnabled(), 'Shipment post should be disabled without BIFROST WhsePost ori.');
    end;

    /// <summary>Warehouse.Receipt.Post is disabled when the caller cannot write the warehouse posting token.</summary>
    [Test]
    procedure ReceiptPost_WithoutWhsePost_IsDisabled()
    var
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        PostImpl: Codeunit "Whse Receipt Post Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        Assert.IsTrue(WarehouseReceiptHeader.WritePermission(), 'Warehouse Receipt Header write must be present so IsEnabled tests the gate.');
        Assert.IsFalse(PostImpl.IsEnabled(), 'Receipt post should be disabled without BIFROST WhsePost ori.');
    end;

    /// <summary>Warehouse.Pick.Register is disabled when the caller cannot write the warehouse posting token.</summary>
    [Test]
    procedure PickRegister_WithoutWhsePost_IsDisabled()
    var
        PostImpl: Codeunit "Whse Pick Register Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        Assert.IsFalse(PostImpl.IsEnabled(), 'Pick register should be disabled without BIFROST WhsePost ori.');
    end;

    /// <summary>Warehouse.Putaway.Register is disabled when the caller cannot write the warehouse posting token.</summary>
    [Test]
    procedure PutawayRegister_WithoutWhsePost_IsDisabled()
    var
        PostImpl: Codeunit "Whse Putaway Register Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        Assert.IsFalse(PostImpl.IsEnabled(), 'Put-away register should be disabled without BIFROST WhsePost ori.');
    end;

    /// <summary>Denial names BIFROST WhsePost ori and carries PermissionDenied.</summary>
    [Test]
    procedure AssertCanPost_WithoutWhsePost_NamesWhsePostSet()
    var
        TempArgument: Record "Message Argument ori" temporary;
        PostingGate: Codeunit "Whse Posting Gate ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        ResponseJson: JsonObject;
        CodeToken: JsonToken;
        ErrorToken: JsonToken;
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        PrepareArgument(TempArgument);

        Assert.IsFalse(PostingGate.AssertCanPost(TempArgument), 'AssertCanPost should deny without the token.');
        Assert.IsFalse(PostingGate.HasPostingPermission(), 'HasPostingPermission should be false without the token.');

        ResponseJson := TempArgument.GetResponseJson();
        Assert.IsTrue(ResponseJson.Get('code', CodeToken), 'code missing');
        Assert.AreEqual('PermissionDenied', CodeToken.AsValue().AsText(), 'code');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.AreNotEqual(0, StrPos(ErrorToken.AsValue().AsText(), 'BIFROST WhsePost ori'), ErrorToken.AsValue().AsText());
    end;

    /// <summary>The invoice check names BIFROST WhseInv ori when that set is absent.</summary>
    [Test]
    procedure AssertCanInvoice_WithoutWhseInv_NamesWhseInvSet()
    var
        TempArgument: Record "Message Argument ori" temporary;
        PostingGate: Codeunit "Whse Posting Gate ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        ResponseJson: JsonObject;
        CodeToken: JsonToken;
        ErrorToken: JsonToken;
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        PrepareArgument(TempArgument);

        Assert.IsFalse(PostingGate.AssertCanInvoice(TempArgument), 'AssertCanInvoice should deny without the token.');
        Assert.IsFalse(PostingGate.HasInvoicePermission(), 'HasInvoicePermission should be false without the token.');

        ResponseJson := TempArgument.GetResponseJson();
        Assert.IsTrue(ResponseJson.Get('code', CodeToken), 'code missing');
        Assert.AreEqual('PermissionDenied', CodeToken.AsValue().AsText(), 'code');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.AreNotEqual(0, StrPos(ErrorToken.AsValue().AsText(), 'BIFROST WhseInv ori'), ErrorToken.AsValue().AsText());
    end;

    /// <summary>Warehouse.Shipment.Post with invoice = true is refused when warehouse posting is held and invoicing is not.</summary>
    [Test]
    procedure ShipmentPost_InvoiceWithoutWhseInv_NamesWhseInvSet()
    var
        AppSetting: Record "NAV App Setting";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        ResponseJson: JsonObject;
        CodeToken: JsonToken;
        ResponseText: Text;
        ErrorToken: JsonToken;
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        Assert.IsFalse(AppSetting.WritePermission(), 'The caller must not retain HTTP setup write permission.');
        LibraryLowerPermissions.AddPermissionSet('BIFROST WhsePost ori');

        Assert.IsTrue(RunShipmentPost('{"invoice":true}', ResponseJson), 'The invoice denial should return JSON.');
        ResponseJson.WriteTo(ResponseText);
        Assert.IsTrue(ResponseJson.Get('code', CodeToken), 'code missing: ' + ResponseText);
        Assert.AreEqual('PermissionDenied', CodeToken.AsValue().AsText(), 'code');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.AreNotEqual(0, StrPos(ErrorToken.AsValue().AsText(), 'BIFROST WhseInv ori'), ErrorToken.AsValue().AsText());
        Assert.AreEqual(0, StrPos(ErrorToken.AsValue().AsText(), 'BIFROST WhsePost ori'), ErrorToken.AsValue().AsText());
    end;

    /// <summary>Warehouse.Shipment.PreviewPost stays enabled and does not return a posting denial.</summary>
    [Test]
    procedure ShipmentPreview_WithoutWhsePost_StaysEnabled()
    var
        TempArgument: Record "Message Argument ori" temporary;
        PreviewImpl: Codeunit "Whse Ship. Prev. Post Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        Assert.IsTrue(PreviewImpl.IsEnabled(), 'Shipment preview should stay enabled without BIFROST WhsePost ori.');

        PrepareArgument(TempArgument);
        asserterror PreviewImpl.ExecuteBifrostTask(TempArgument);
        AssertPreviewWasNotDeniedByPostingGate(TempArgument);
    end;

    /// <summary>Warehouse.Receipt.PreviewPost stays enabled and does not return a posting denial.</summary>
    [Test]
    procedure ReceiptPreview_WithoutWhsePost_StaysEnabled()
    var
        TempArgument: Record "Message Argument ori" temporary;
        PreviewImpl: Codeunit "Whse Rcpt Post Prev. Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LowerToDocumentWrite(LibraryLowerPermissions);
        Assert.IsTrue(PreviewImpl.IsEnabled(), 'Receipt preview should stay enabled without BIFROST WhsePost ori.');

        PrepareArgument(TempArgument);
        asserterror PreviewImpl.ExecuteBifrostTask(TempArgument);
        AssertPreviewWasNotDeniedByPostingGate(TempArgument);
    end;

    local procedure AssertPreviewWasNotDeniedByPostingGate(TempArgument: Record "Message Argument ori")
    var
        ResponseJson: JsonObject;
        ErrorToken: JsonToken;
    begin
        Assert.AreEqual(0, StrPos(GetLastErrorText(), 'Posting denied'), 'Preview must not be blocked by the posting gate.');
        if TempArgument.GetResponseContentLength() = 0 then
            exit;
        ResponseJson := TempArgument.GetResponseJson();
        if not ResponseJson.Get('error', ErrorToken) then
            exit;
        Assert.AreEqual(0, StrPos(ErrorToken.AsValue().AsText(), 'Posting denied'), 'Preview response must not be a posting denial.');
        if ResponseJson.Get('code', ErrorToken) then
            Assert.AreNotEqual('PermissionDenied', ErrorToken.AsValue().AsText(), 'Preview must not return PermissionDenied.');
    end;

    local procedure LowerToDocumentWrite(var LibraryLowerPermissions: Codeunit "Library - Lower Permissions")
    begin
        // Restrictive tests start as D365 Full Access until this library replaces that set.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('BIFROST Full ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
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
}
