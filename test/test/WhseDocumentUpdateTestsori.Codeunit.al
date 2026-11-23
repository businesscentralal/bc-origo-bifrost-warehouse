namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Document.Update (#105): receipt header and line bins, the released shipment refusal, all or nothing,
/// refusals, permission and help.
/// </summary>
codeunit 97009 "Whse Document Update Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Location: Record Location;
        Item: Record Item;
        LineBin: Record Bin;
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        UpdateRequest1Lbl: Label '{"documentType":"receipt","documentNo":"%1","header":{"postingDate":"%2","vendorShipmentNo":"VS-105"},"lines":[{"lineNo":%3,"binCode":"%4"}]}', Locked = true;
        UpdateRequest2Lbl: Label '{"documentType":"receipt","documentNo":"%1","header":{"vendorShipmentNo":"VS-BAD"},"lines":[{"lineNo":%2,"binCode":"NOBIN105"}]}', Locked = true;
        UpdateRequest3Lbl: Label '{"documentType":"shipment","documentNo":"%1","header":{"externalDocumentNo":"EXT-105"}}', Locked = true;
        UpdateRequest4Lbl: Label '{"documentNo":"%1","header":{"vendorShipmentNo":"X"}}', Locked = true;
        UpdateRequest5Lbl: Label '{"documentType":"invoice","documentNo":"%1","header":{"vendorShipmentNo":"X"}}', Locked = true;
        UpdateRequest6Lbl: Label '{"documentType":"receipt","documentNo":"%1","header":{"postingDate":"tomorrow-ish"}}', Locked = true;
        UpdateRequest7Lbl: Label '{"documentType":"receipt","documentNo":"%1","header":{"externalDocumentNo":"X"}}', Locked = true;
        UpdateRequest8Lbl: Label '{"documentType":"receipt","documentNo":"%1","lines":[{"lineNo":999999}]}', Locked = true;
        UpdateRequest9Lbl: Label '{"documentType":"receipt","documentNo":"%1","systemId":"%2","header":{"vendorShipmentNo":"X"}}', Locked = true;
        UpdateRequest10Lbl: Label '{"documentType":"shipment","documentNo":"%1","header":{"shipmentDate":"%2"}}', Locked = true;

    /// <summary>AC04: posting date, vendor shipment no. and a line bin are validated and stored on a receipt.</summary>
    [Test]
    procedure Update_Receipt_HeaderAndLineBin_Stored()
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
        NewDate: Date;
    begin
        CreateReceipt(ReceiptHeader, ReceiptLine);
        NewDate := CalcDate('<+3D>', WorkDate());

        ResponseJson := Send(StrSubstNo(UpdateRequest1Lbl, ReceiptHeader."No.", Format(NewDate, 0, 9), ReceiptLine."Line No.", LineBin.Code));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'updatedCount'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual('VS-105', Helper.TextValue(Helper.ObjectValue(ResponseJson, 'header'), 'vendorShipmentNo'), 'The stored value is echoed.');
        Assert.AreEqual(LineBin.Code, Helper.TextValue(Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0), 'binCode'), 'The line bin is echoed.');
        ReceiptHeader.Get(ReceiptHeader."No.");
        Assert.AreEqual(NewDate, ReceiptHeader."Posting Date", 'The posting date is stored.');
        Assert.AreEqual('VS-105', ReceiptHeader."Vendor Shipment No.", 'The vendor shipment no. is stored.');
        ReceiptLine.Get(ReceiptLine."No.", ReceiptLine."Line No.");
        Assert.AreEqual(LineBin.Code, ReceiptLine."Bin Code", 'The line bin is stored.');
    end;

    /// <summary>The shipment date of an open shipment with lines changes without a dialog and is copied to the lines in the write.</summary>
    [Test]
    procedure Update_OpenShipmentWithLines_ShipmentDate_CopiedToLines()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        NewDate: Date;
    begin
        CreateOpenShipment(ShipmentHeader);
        NewDate := CalcDate('<+4D>', WorkDate());

        Helper.AssertSuccess(Send(StrSubstNo(UpdateRequest10Lbl, ShipmentHeader."No.", Format(NewDate, 0, 9))));

        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(NewDate, ShipmentHeader."Shipment Date", 'The shipment date is stored on the header.');
        ShipmentLine.SetRange("No.", ShipmentHeader."No.");
        Assert.IsFalse(ShipmentLine.IsEmpty(), 'The shipment has lines.');
        ShipmentLine.FindSet();
        repeat
            Assert.AreEqual(NewDate, ShipmentLine."Shipment Date", 'The shipment date is copied to every line.');
        until ShipmentLine.Next() = 0;
    end;

    /// <summary>A line bin that company Field Access closes is refused with PermissionDenied before anything is written.</summary>
    [Test]
    procedure Update_ClosedLineBin_PermissionDenied_NothingChanged()
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        BinBefore: Code[20];
    begin
        CreateReceipt(ReceiptHeader, ReceiptLine);
        BinBefore := ReceiptLine."Bin Code";
        Helper.CloseFieldForWrite(Database::"Warehouse Receipt Line", ReceiptLine.FieldNo("Bin Code"));

        Helper.ExpectError(Send(StrSubstNo(UpdateRequest1Lbl, ReceiptHeader."No.", Format(CalcDate('<+3D>', WorkDate()), 0, 9), ReceiptLine."Line No.", LineBin.Code)), 'PermissionDenied', '');

        ReceiptHeader.Get(ReceiptHeader."No.");
        Assert.AreEqual('', ReceiptHeader."Vendor Shipment No.", 'The header is unchanged.');
        ReceiptLine.Get(ReceiptLine."No.", ReceiptLine."Line No.");
        Assert.AreEqual(BinBefore, ReceiptLine."Bin Code", 'The line bin is unchanged.');
    end;

    /// <summary>AC05: a bin that does not exist leaves the header unchanged although its fields were valid.</summary>
    [Test]
    procedure Update_Receipt_BadLineBin_NothingChanged()
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        CreateReceipt(ReceiptHeader, ReceiptLine);

        ResponseJson := Send(StrSubstNo(UpdateRequest2Lbl, ReceiptHeader."No.", ReceiptLine."Line No."));

        Helper.ExpectError(ResponseJson, 'PreconditionFailed', 'Correct the value Business Central refused and send the request again; nothing was changed.');
        ReceiptHeader.Get(ReceiptHeader."No.");
        Assert.AreEqual('', ReceiptHeader."Vendor Shipment No.", 'All or nothing: the header is unchanged.');
    end;

    /// <summary>AC04: a released shipment is refused with the reopen nextStep and is not reopened.</summary>
    [Test]
    procedure Update_ReleasedShipment_PreconditionFailed()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ExternalDocumentNo: Code[35];
    begin
        Helper.CreateReleasedShipment(Location, ShipmentHeader, 1);
        ExternalDocumentNo := ShipmentHeader."External Document No.";

        Helper.ExpectError(Send(StrSubstNo(UpdateRequest3Lbl, ShipmentHeader."No.")), 'PreconditionFailed', 'Reopen the shipment first with Warehouse.Shipment.Reopen.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Released, ShipmentHeader.Status, 'The shipment stays released.');
        Assert.AreEqual(ExternalDocumentNo, ShipmentHeader."External Document No.", 'Nothing is changed.');
    end;

    /// <summary>AC06: each refusal answers its code with a nextStep and changes nothing.</summary>
    [Test]
    procedure Update_Refusals_AnswerCodeAndNextStep()
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
    begin
        CreateReceipt(ReceiptHeader, ReceiptLine);
        Helper.ExpectError(Send(StrSubstNo(UpdateRequest4Lbl, ReceiptHeader."No.")), 'MissingParameter', '');
        Helper.ExpectError(Send(StrSubstNo(UpdateRequest5Lbl, ReceiptHeader."No.")), 'InvalidParameter', '');
        Helper.ExpectError(Send(StrSubstNo(UpdateRequest6Lbl, ReceiptHeader."No.")), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(StrSubstNo(UpdateRequest7Lbl, ReceiptHeader."No.")), 'UnknownParameter', 'Remove this key or consult Help.Implementation.Get for the declared parameters.');
        Helper.ExpectError(Send('{"documentType":"receipt","documentNo":"NORCPT105","header":{"vendorShipmentNo":"X"}}'), 'RecordNotFound', '');
        Helper.ExpectError(Send(StrSubstNo(UpdateRequest8Lbl, ReceiptHeader."No.")), 'RecordNotFound', '');
        ReceiptHeader.Get(ReceiptHeader."No.");
        Assert.AreEqual('', ReceiptHeader."Vendor Shipment No.", 'Nothing is changed by a refusal.');
    end;

    /// <summary>AC06: identifiers that name different documents are ConflictingIdentifiers.</summary>
    [Test]
    procedure Update_ConflictingIdentifiers_Refused()
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        OtherHeader: Record "Warehouse Receipt Header";
        OtherLine: Record "Warehouse Receipt Line";
    begin
        CreateReceipt(ReceiptHeader, ReceiptLine);
        CreateReceipt(OtherHeader, OtherLine);
        Helper.ExpectError(Send(StrSubstNo(UpdateRequest9Lbl, ReceiptHeader."No.", Format(OtherHeader.SystemId, 0, 4))), 'ConflictingIdentifiers', 'Send one identifier, or identifiers that name the same document.');
        ReceiptHeader.Get(ReceiptHeader."No.");
        Assert.AreEqual('', ReceiptHeader."Vendor Shipment No.", 'Nothing is changed.');
    end;

    /// <summary>AC07: without receipt and shipment write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Update_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        UpdateImpl: Codeunit "Whse Document Update Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Document.Update";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Update must be disabled without write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        UpdateImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori, or leave out a field that is closed to writes.');
    end;

    /// <summary>AC07: discovery text and refusals answer in English (1033) and Icelandic (1039).</summary>
    [Test]
    procedure Update_HelpAndRefusal_InEnglishAndIcelandic()
    var
        Discovery: Interface "Msg Interface ori";
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        Discovery := Enum::"Message Type ori"::"Warehouse.Document.Update";
        GlobalLanguage(1033);
        Assert.AreEqual('Changes header data and line bins on an open warehouse receipt or shipment.', Discovery.GetDescription(), 'English description.');
        GlobalLanguage(1039);
        Assert.AreEqual('Breytir hausgögnum og hólfum lína á opinni vöruhúsamóttöku eða -afhendingu.', Discovery.GetDescription(), 'Icelandic description.');
        GlobalLanguage(OriginalLanguage);
        Helper.ExpectError(Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Document.Update", '', '{"documentNo":"X","header":{}}', 1039), 'MissingParameter', 'Sendu gildið sem vantar; Help.Implementation.Get sýnir viðföngin.');
        Helper.ExpectError(Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Document.Update", '', '{"documentNo":"X","header":{}}', 1033), 'MissingParameter', 'Send the missing value; Help.Implementation.Get lists the parameters.');
    end;

    local procedure CreateReceipt(var ReceiptHeader: Record "Warehouse Receipt Header"; var ReceiptLine: Record "Warehouse Receipt Line")
    var
        PurchaseHeader: Record "Purchase Header";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Helper.SkipCommittedGuidAccounts();
        // Bin mandatory, receive required, no put-away or pick.
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, true, false);
        LibraryWarehouse.CreateBin(LineBin, Location.Code, CopyStr('B105' + Helper.NewCode(), 1, 20), '', '');
        Helper.CreateItem(Item);
        ReceiptHelper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 2);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(ReceiptHeader, PurchaseHeader);
        ReceiptLine.SetRange("No.", ReceiptHeader."No.");
        ReceiptLine.FindFirst();
    end;

    local procedure CreateOpenShipment(var ShipmentHeader: Record "Warehouse Shipment Header")
    var
        SalesHeader: Record "Sales Header";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
    begin
        Helper.SkipCommittedGuidAccounts();
        ShipmentHelper.SetupPickLocationAndItem(Location, Item, 20);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 1);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Document.Update", '', RequestText));
    end;
}
