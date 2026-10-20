namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Request.Get (#58) through the public dispatcher.
/// </summary>
codeunit 97043 "Whse Request Get Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";

    /// <summary>AC01: released inbound requests at a location are answered with source, destination and dates, paged.</summary>
    [Test]
    procedure Get_ReleasedInboundRequests_AreAnswered()
    var
        Location: Record Location;
        Item: Record Item;
        FirstOrder: Record "Purchase Header";
        SecondOrder: Record "Purchase Header";
        ResponseJson: JsonObject;
        Entry: JsonObject;
    begin
        // Story #58, AC01 + AC03 (paging) | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(FirstOrder, Item."No.", Location.Code, 1);
        ReceiptHelper.CreateReleasedPurchaseOrder(SecondOrder, Item."No.", Location.Code, 1);

        Run('{"locationCode":"' + Location.Code + '","type":"Inbound","status":"Released","sourceDocument":"PurchaseOrder","take":1}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(2, IntegerValue(ResponseJson, 'noOfRecords'), 'Both purchase orders match.');
        Assert.AreEqual(1, ArrayCount(ResponseJson, 'result'), 'take 1 answers one request.');
        Entry := FirstEntry(ResponseJson, 'result');
        Assert.AreEqual('Inbound', TextValue(Entry, 'type'), 'type');
        Assert.AreEqual('Purchase Order', TextValue(Entry, 'sourceDocument'), 'sourceDocument');
        Assert.AreEqual('Released', TextValue(Entry, 'documentStatus'), 'documentStatus');
        Assert.AreEqual('Vendor', TextValue(Entry, 'destinationType'), 'destinationType');
        Assert.AreNotEqual('', TextValue(Entry, 'destinationNo'), 'destinationNo');
        Assert.AreEqual(Location.Code, TextValue(Entry, 'locationCode'), 'locationCode');

        Run('{"locationCode":"' + Location.Code + '","sourceNo":"' + SecondOrder."No." + '"}', '', ResponseJson);
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'noOfRecords'), 'sourceNo narrows to one request.');
        Assert.AreEqual(SecondOrder."No.", TextValue(FirstEntry(ResponseJson, 'result'), 'sourceNo'), 'sourceNo');
    end;

    /// <summary>AC07: filters that match nothing answer success with an empty list.</summary>
    [Test]
    procedure Get_NoMatch_AnswersEmptyList()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ResponseJson: JsonObject;
    begin
        // Story #58, AC07 | Time: the date filter is far before the order dates | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 1);

        Run('{"locationCode":"' + Location.Code + '","type":"Outbound"}', '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(0, ArrayCount(ResponseJson, 'result'), 'No outbound request.');

        Run('{"locationCode":"' + Location.Code + '","expectedReceiptDateFrom":"2999-01-01"}', '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(0, IntegerValue(ResponseJson, 'noOfRecords'), 'No request expected after 2999.');
    end;

    /// <summary>AC04 and AC06: an unknown type value, a missing location, an unknown key and a bad date are refused.</summary>
    [Test]
    procedure Get_Refusals()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        // Story #58, AC04 + AC06 | Time: independent of WorkDate | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);

        Run('{"locationCode":"' + Location.Code + '","type":"Sideways"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use one of the values listed in the help.', TextValue(ResponseJson, 'nextStep'), 'InvalidParameter next step.');

        Run('{}', '', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreNotEqual('', TextValue(ResponseJson, 'nextStep'), 'MissingParameter next step.');

        Run('{"locationCode":"' + Location.Code + '","colour":"red"}', '', ResponseJson);
        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"19.10.2026"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"locationCode":"NOLOC-X"}', '', ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run('{"locationCode":"' + Location.Code + '"}', 'OTHER', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
    end;

    /// <summary>AC08: without read permission the type is disabled and answers PermissionDenied naming the read set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Get_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        RequestGetImpl: Codeunit "Whse Request Get Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Story #58, AC08 | Time: independent of WorkDate | Risk: none.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Request.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'The type must be disabled without read permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        RequestGetImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Read ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the read permission set.');
    end;

    /// <summary>#67 item 2: an unambiguous local date gets the value to resend; anything else keeps the example (1033 and 1039).</summary>
    [Test]
    procedure Get_DateNextStep_GivesTheValueToResend()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        // Issue #67, AC1 (item 2) | Time: fixed dates in the request | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"20.10.2026"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Resend shipmentDateFrom as 2026-10-20.', TextValue(ResponseJson, 'nextStep'), 'The value to resend.');

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"5-1-2026"}', '', ResponseJson);
        Assert.AreEqual('Resend shipmentDateFrom as 2026-01-05.', TextValue(ResponseJson, 'nextStep'), 'A dash date with the year last is day-month-year.');

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"10/20/2026"}', '', ResponseJson);
        Assert.AreEqual('Send the date as text, for example 2026-10-19.', TextValue(ResponseJson, 'nextStep'), 'An ambiguous form keeps the example.');

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"31.02.2026"}', '', ResponseJson);
        Assert.AreEqual('Send the date as text, for example 2026-10-19.', TextValue(ResponseJson, 'nextStep'), 'A date that does not exist keeps the example.');

        Assert.IsTrue(ReceiptHelper.RunMessageInLanguage(Enum::"Message Type ori"::"Warehouse.Request.Get", '', '{"locationCode":"' + Location.Code + '","shipmentDateFrom":"20.10.2026"}', ResponseJson, 1039), 'The response should be JSON.');
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Sendu shipmentDateFrom aftur sem 2026-10-20.', TextValue(ResponseJson, 'nextStep'), 'The value to resend, in Icelandic.');
    end;

    /// <summary>
    /// #74 AC2: a negative take, a local date and the collected answer of both are declared in the errors chapter, each with
    /// the nextStep the runtime answers.
    /// </summary>
    [Test]
    procedure Get_PagingAndDateAnswers_AreDeclared()
    var
        Location: Record Location;
        Item: Record Item;
        ContractAssert: Codeunit "Whse Contract Assert ori";
        ResponseJson: JsonObject;
    begin
        // Issue #74, AC2 | Time: fixed dates in the request | Risk: none.
        ReceiptHelper.SetupLocationAndItem(Location, Item, 0);

        Run('{"locationCode":"' + Location.Code + '","take":-1}', '', ResponseJson);
        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Send a whole number of zero or more, or leave it out.', TextValue(ResponseJson, 'nextStep'), ResponseText(ResponseJson));
        ContractAssert.AssertAnswerDeclared(Enum::"Message Type ori"::"Warehouse.Request.Get", ResponseJson);

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"20.10.2026"}', '', ResponseJson);
        Assert.AreEqual('Resend shipmentDateFrom as 2026-10-20.', TextValue(ResponseJson, 'nextStep'), ResponseText(ResponseJson));
        ContractAssert.AssertAnswerDeclared(Enum::"Message Type ori"::"Warehouse.Request.Get", ResponseJson);

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"10/20/2026"}', '', ResponseJson);
        ContractAssert.AssertAnswerDeclared(Enum::"Message Type ori"::"Warehouse.Request.Get", ResponseJson);

        Run('{"locationCode":"' + Location.Code + '","shipmentDateFrom":"2026-10-20","shipmentDateTo":"2026-10-19"}', '', ResponseJson);
        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        ContractAssert.AssertAnswerDeclared(Enum::"Message Type ori"::"Warehouse.Request.Get", ResponseJson);

        Run('{"locationCode":"NOLOC-X","shipmentDateFrom":"20.10.2026","take":-1}', '', ResponseJson);
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        ContractAssert.AssertAnswerAndErrorsDeclared(Enum::"Message Type ori"::"Warehouse.Request.Get", ResponseJson);
    end;

    /// <summary>#67 item 3: a bad date, a bad take and an unknown location are answered together (1033).</summary>
    [Test]
    procedure Get_IndependentProblems_AreCollected()
    begin
        // Issue #67, AC1 (item 3) | Time: fixed dates in the request | Risk: none.
        AssertIndependentProblems(1033, 'The request has invalid values.');
    end;

    /// <summary>#67 item 3: the same problems are answered together in Icelandic (1039).</summary>
    [Test]
    procedure Get_IndependentProblems_AreCollectedInIcelandic()
    begin
        // Issue #67, AC1 (item 3) | Time: fixed dates in the request | Risk: none.
        AssertIndependentProblems(1039, 'Beiðnin hefur ógild gildi.');
    end;

    local procedure AssertIndependentProblems(LanguageId: Integer; Summary: Text)
    var
        ResponseJson: JsonObject;
    begin
        Assert.IsTrue(ReceiptHelper.RunMessageInLanguage(Enum::"Message Type ori"::"Warehouse.Request.Get", '', '{"locationCode":"NOLOC-X","shipmentDateFrom":"20.10.2026","take":-1}', ResponseJson, LanguageId), 'The response should be JSON.');
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(Summary, TextValue(ResponseJson, 'error'), 'The summary is in the caller language.');
        Assert.AreEqual('shipmentDateFrom:InvalidParameterFormat,locationCode:RecordNotFound,take:InvalidParameter', ErrorList(ResponseJson), 'Every problem is listed.');
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

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(Enum::"Message Type ori"::"Warehouse.Request.Get", Subject, RequestText, ResponseJson), 'The response should be JSON.');
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
