namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Receipt.GetSourceDocuments (#51) through the public dispatcher.
/// </summary>
codeunit 97040 "Whse Rcpt GetSrcDocs Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";

    /// <summary>AC01: two released purchase orders go onto one new receipt at the location, with lines per source document.</summary>
    [Test]
    procedure NewReceipt_TwoPurchaseOrders_AreAdded()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Purchase Header";
        SecondOrder: Record "Purchase Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
        ReceiptNo: Code[20];
    begin
        // Story #51, AC01 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(FirstOrder, Item."No.", Location.Code, 3);
        ReceiptHelper.CreateReleasedPurchaseOrder(SecondOrder, Item."No.", Location.Code, 4);

        Run('{"locationCode":"' + Location.Code + '","sourceDocument":"Purchase Order","sourceNos":["' + FirstOrder."No." + '","' + SecondOrder."No." + '"]}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsTrue(BoolValue(ResponseJson, 'created'), 'A new receipt must be created.');
        Assert.AreEqual(2, IntegerValue(ResponseJson, 'linesAdded'), 'One line per purchase order.');
        Assert.AreEqual(2, ArrayCount(ResponseJson, 'sourceDocuments'), 'Two source documents.');
        Assert.AreEqual(0, ArrayCount(ResponseJson, 'skipped'), 'Nothing is skipped.');
        ReceiptNo := CopyStr(TextValue(ResponseJson, 'receiptNo'), 1, MaxStrLen(ReceiptNo));
        ReceiptLine.SetRange("No.", ReceiptNo);
        ReceiptLine.SetRange("Source No.", FirstOrder."No.");
        Assert.RecordCount(ReceiptLine, 1);
        ReceiptLine.SetRange("Source No.", SecondOrder."No.");
        Assert.RecordCount(ReceiptLine, 1);
    end;

    /// <summary>AC01: an existing receipt gets the lines of a further purchase order.</summary>
    [Test]
    procedure ExistingReceipt_SecondOrder_IsAdded()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Purchase Header";
        SecondOrder: Record "Purchase Header";
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        // Story #51, AC01 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(FirstOrder, Item."No.", Location.Code, 3);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(ReceiptHeader, FirstOrder);
        ReceiptHelper.CreateReleasedPurchaseOrder(SecondOrder, Item."No.", Location.Code, 4);

        Run('{"sourceNos":["' + SecondOrder."No." + '"]}', ReceiptHeader."No.", ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(ReceiptHeader."No.", TextValue(ResponseJson, 'receiptNo'), 'The existing receipt is used.');
        Assert.IsFalse(BoolValue(ResponseJson, 'created'), 'No new receipt.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'linesAdded'), 'One line is added.');
        ReceiptLine.SetRange("No.", ReceiptHeader."No.");
        Assert.RecordCount(ReceiptLine, 2);
    end;

    /// <summary>AC06: a source line already on another receipt is skipped and listed with that receipt number.</summary>
    [Test]
    procedure SourceLineOnOtherReceipt_IsSkipped()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Purchase Header";
        SecondOrder: Record "Purchase Header";
        OtherReceipt: Record "Warehouse Receipt Header";
        ResponseJson: JsonObject;
        Skipped: JsonObject;
    begin
        // Story #51, AC06 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(FirstOrder, Item."No.", Location.Code, 3);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(OtherReceipt, FirstOrder);
        ReceiptHelper.CreateReleasedPurchaseOrder(SecondOrder, Item."No.", Location.Code, 4);

        Run('{"locationCode":"' + Location.Code + '","sourceNos":["' + FirstOrder."No." + '","' + SecondOrder."No." + '"]}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'linesAdded'), 'Only the second order is added.');
        Assert.AreEqual(1, ArrayCount(ResponseJson, 'skipped'), 'The first order line is skipped.');
        Skipped := FirstEntry(ResponseJson, 'skipped');
        Assert.AreEqual(FirstOrder."No.", TextValue(Skipped, 'sourceNo'), 'The skipped source document.');
        Assert.AreEqual(OtherReceipt."No.", TextValue(Skipped, 'otherReceiptNo'), 'The skipped line names the other receipt.');
    end;

    /// <summary>AC02: an unknown receipt answers RecordNotFound with the create next step and writes nothing.</summary>
    [Test]
    procedure UnknownReceipt_IsNotFound()
    var
        ResponseJson: JsonObject;
    begin
        // Story #51, AC02 | Time: independent of WorkDate | Risk: none.
        Run('{"receiptNo":"NO-SUCH-RCPT"}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Create it with Warehouse.Receipt.Create or pass locationCode.', TextValue(ResponseJson, 'nextStep'), 'The next step must name Receipt.Create.');
    end;

    /// <summary>AC03: no released warehouse request for the filters answers PreconditionFailed and creates no receipt.</summary>
    [Test]
    procedure NoReleasedRequest_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        // Story #51, AC03 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);

        Run('{"locationCode":"' + Location.Code + '"}', '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Release the source documents first; read Warehouse.Request.Get.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the release and Request.Get.');
        Assert.AreEqual('', TextValue(ResponseJson, 'parameter'), 'No filter was sent, so no key is named.');
        AssertNoReceiptAt(Location.Code);
    end;

    /// <summary>#71 item 4: when no released request matches the filters, the refusal names the filters that were sent.</summary>
    [Test]
    procedure NoReleasedRequest_NamesTheFilter()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        // Issue #71, AC3 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);

        Run('{"locationCode":"' + Location.Code + '","vendorNo":"NO-VENDOR"}', '', ResponseJson);
        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('vendorNo', TextValue(ResponseJson, 'parameter'), 'The refusal names vendorNo, not sourceNos.');

        Run('{"locationCode":"' + Location.Code + '","sourceDocument":"Purchase Order","vendorNo":"NO-VENDOR"}', '', ResponseJson);
        Assert.AreEqual('sourceDocument, vendorNo', TextValue(ResponseJson, 'parameter'), 'The refusal names every filter that was sent.');
        AssertNoReceiptAt(Location.Code);
    end;

    /// <summary>AC04: a named source document at another location answers ConflictingIdentifiers and writes nothing.</summary>
    [Test]
    procedure SourceAtOtherLocation_IsRefused()
    var
        Location: Record Location;
        OtherLocation: Record Location;
        Item: Record Item;
        OtherItem: Record Item;
        ReceiptOrder: Record "Purchase Header";
        OtherOrder: Record "Purchase Header";
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ResponseJson: JsonObject;
    begin
        // Story #51, AC04 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.SetupLocationAndItem(OtherLocation, OtherItem, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(ReceiptOrder, Item."No.", Location.Code, 1);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(ReceiptHeader, ReceiptOrder);
        ReceiptHelper.CreateReleasedPurchaseOrder(OtherOrder, OtherItem."No.", OtherLocation.Code, 1);

        Run('{"receiptNo":"' + ReceiptHeader."No." + '","sourceNos":["' + OtherOrder."No." + '"]}', '', ResponseJson);

        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use a receipt at the same location.', TextValue(ResponseJson, 'nextStep'), 'The next step must ask for the same location.');
        ReceiptLine.SetRange("No.", ReceiptHeader."No.");
        Assert.RecordCount(ReceiptLine, 1);
    end;

    /// <summary>AC05: missing, wrong-typed, unknown and conflicting keys are refused with their codes and next steps.</summary>
    [Test]
    procedure CommonRefusals()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        // Story #51, AC05 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);

        Run('{}', '', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Send receiptNo for an existing receipt or locationCode for a new one.', TextValue(ResponseJson, 'nextStep'), 'MissingParameter next step.');

        Run('{"locationCode":12}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"locationCode":"' + Location.Code + '","sourceNos":"PO1"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceNos', TextValue(ResponseJson, 'parameter'), 'sourceNos must be an array.');

        Run('{"locationCode":"' + Location.Code + '","bin":"A"}', '', ResponseJson);
        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('bin', TextValue(ResponseJson, 'parameter'), 'The unknown key must be named.');

        Run('{"receiptNo":"A-1"}', 'B-2', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Send one receipt.', TextValue(ResponseJson, 'nextStep'), 'ConflictingIdentifiers next step.');

        Run('{"locationCode":"' + Location.Code + '","sourceDocument":"Sales Order"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use one of the values listed in the help.', TextValue(ResponseJson, 'nextStep'), 'InvalidParameter next step.');

        Run('{"locationCode":"NOLOC-X"}', '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        AssertNoReceiptAt(Location.Code);
    end;

    /// <summary>AC07: without write permission the type is disabled and answers PermissionDenied naming the permission set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        GetSourceDocsImpl: Codeunit "Whse Rcpt GetSrcDocs Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Story #51, AC07 | Time: independent of WorkDate | Risk: none.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Receipt.GetSourceDocuments";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'The type must be disabled without write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        GetSourceDocsImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    /// <summary>#67 item 3: a missing key no longer hides the other bad values; all are answered together (1033).</summary>
    [Test]
    procedure IndependentProblems_AreCollected()
    begin
        // Issue #67, AC1 (item 3) | Time: fixed dates in the request | Risk: none.
        AssertIndependentProblems(1033, 'Nothing was added.');
    end;

    /// <summary>#67 item 3: the same problems are answered together in Icelandic (1039).</summary>
    [Test]
    procedure IndependentProblems_AreCollectedInIcelandic()
    begin
        // Issue #67, AC1 (item 3) | Time: fixed dates in the request | Risk: none.
        AssertIndependentProblems(1039, 'Engu var bætt við.');
    end;

    local procedure AssertIndependentProblems(LanguageId: Integer; Summary: Text)
    var
        ResponseJson: JsonObject;
    begin
        Assert.IsTrue(ReceiptHelper.RunMessageInLanguage(Enum::"Message Type ori"::"Warehouse.Receipt.GetSourceDocuments", '', '{"sourceDocument":"Sales Order","sourceNos":"PO1","expectedReceiptDateFrom":"20.10.2026"}', ResponseJson, LanguageId), 'The response should be JSON.');
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(Summary, TextValue(ResponseJson, 'error'), 'The summary is in the caller language.');
        Assert.AreEqual('receiptNo:MissingParameter,sourceNos:InvalidParameterFormat,expectedReceiptDateFrom:InvalidParameterFormat,sourceDocument:InvalidParameter', ErrorList(ResponseJson), 'Every problem is listed.');
    end;

    local procedure ErrorList(ResponseJson: JsonObject): Text
    var
        Token: JsonToken;
        Entry: JsonToken;
        Entries: TextBuilder;
    begin
        if not ResponseJson.Get('errors', Token) then
            exit('');
        foreach Entry in Token.AsArray() do begin
            if Entries.Length() > 0 then
                Entries.Append(',');
            Entries.Append(TextValue(Entry.AsObject(), 'parameter') + ':' + TextValue(Entry.AsObject(), 'code'));
        end;
        exit(Entries.ToText());
    end;

    local procedure AssertNoReceiptAt(LocationCode: Code[10])
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
    begin
        ReceiptHeader.SetRange("Location Code", LocationCode);
        Assert.RecordIsEmpty(ReceiptHeader);
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.GetSourceDocuments", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstEntry(Parent: JsonObject; Name: Text): JsonObject
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        Assert.IsTrue(Token.AsArray().Get(0, Token), Name + ' must have an entry.');
        exit(Token.AsObject());
    end;

    local procedure ArrayCount(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        exit(Token.AsArray().Count());
    end;

    local procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
    end;

    local procedure BoolValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must be in the response.');
        exit(Token.AsValue().AsInteger());
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        exit(Token.AsValue().AsText());
    end;
}
