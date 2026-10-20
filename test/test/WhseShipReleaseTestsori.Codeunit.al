namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Shipment.Release and Warehouse.Shipment.Reopen (#53) through the public dispatcher.
/// </summary>
codeunit 97042 "Whse Ship Release Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";

    /// <summary>AC01: releasing an open shipment with lines answers Released and changes the status.</summary>
    [Test]
    procedure Release_OpenShipment_IsReleased()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
    begin
        // Story #53, AC01 | Time: independent of WorkDate | Risk: none.
        ShipmentNo := CreateShipment();

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Released', TextValue(ResponseJson, 'shipmentStatus'), 'The answer must say Released.');
        Assert.IsTrue(BoolValue(ResponseJson, 'changed'), 'The release changed the shipment.');
        ShipmentHeader.Get(ShipmentNo);
        Assert.AreEqual(ShipmentHeader.Status::Released, ShipmentHeader.Status, 'The shipment must be released.');
    end;

    /// <summary>AC07: releasing a released shipment answers success with changed false.</summary>
    [Test]
    procedure Release_AlreadyReleased_AnswersUnchanged()
    var
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
    begin
        // Story #53, AC07 | Time: independent of WorkDate | Risk: none.
        ShipmentNo := CreateShipment();
        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{}', ShipmentNo, ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsFalse(BoolValue(ResponseJson, 'changed'), 'A second release changes nothing.');
        Assert.AreEqual('Released', TextValue(ResponseJson, 'shipmentStatus'), 'The shipment stays released.');
    end;

    /// <summary>AC03: a shipment without lines is refused with the get source documents next step, and stays open.</summary>
    [Test]
    procedure Release_NoLines_IsRefused()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
    begin
        // Story #53, AC03 | Time: independent of WorkDate | Risk: none.
        CreateEmptyShipment(ShipmentHeader);

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentHeader."No." + '"}', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Add lines with Warehouse.Shipment.GetSourceDocuments.', TextValue(ResponseJson, 'nextStep'), 'The next step must name GetSourceDocuments.');
        ShipmentHeader.Get(ShipmentHeader."No.");
        Assert.AreEqual(ShipmentHeader.Status::Open, ShipmentHeader.Status, 'Nothing is written.');
    end;

    /// <summary>AC05: an unknown shipment number answers RecordNotFound with the Data.Records.Get next step.</summary>
    [Test]
    procedure Release_UnknownShipment_IsNotFound()
    var
        ResponseJson: JsonObject;
    begin
        // Story #53, AC05 | Time: independent of WorkDate | Risk: none.
        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"NO-SUCH-SHIP"}', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.IsTrue(TextValue(ResponseJson, 'nextStep').Contains('Data.Records.Get'), 'The next step must name Data.Records.Get.');
        Assert.IsTrue(TextValue(ResponseJson, 'nextStep').Contains('Warehouse Shipment Header'), 'The next step must name the table.');
    end;

    /// <summary>AC06: missing, wrong-typed, unknown and conflicting identifiers are refused with their codes.</summary>
    [Test]
    procedure Release_CommonRefusals()
    var
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
        OtherNo: Code[20];
    begin
        // Story #53, AC06 | Time: independent of WorkDate | Risk: none.
        ShipmentNo := CreateShipment();
        OtherNo := CreateShipment();

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{}', ResponseJson);
        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreNotEqual('', TextValue(ResponseJson, 'nextStep'), 'MissingParameter needs a next step.');

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":12}', ResponseJson);
        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentNo + '","note":"x"}', ResponseJson);
        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The unknown key must be named.');

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentNo + '","no":"' + OtherNo + '"}', ResponseJson);
        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreNotEqual('', TextValue(ResponseJson, 'nextStep'), 'ConflictingIdentifiers needs a next step.');
        AssertStatus(ShipmentNo, false);
        AssertStatus(OtherNo, false);
    end;

    /// <summary>AC02: reopening a released shipment answers Open.</summary>
    [Test]
    procedure Reopen_ReleasedShipment_IsOpen()
    var
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
    begin
        // Story #53, AC02 | Time: independent of WorkDate | Risk: none.
        ShipmentNo := CreateShipment();
        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Reopen", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Open', TextValue(ResponseJson, 'shipmentStatus'), 'The answer must say Open.');
        Assert.IsTrue(BoolValue(ResponseJson, 'changed'), 'The reopen changed the shipment.');
        AssertStatus(ShipmentNo, false);
    end;

    /// <summary>Edge: reopening an open shipment answers success with changed false.</summary>
    [Test]
    procedure Reopen_AlreadyOpen_AnswersUnchanged()
    var
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
    begin
        // Story #53, AC07 (reopen counterpart) | Time: independent of WorkDate | Risk: none.
        ShipmentNo := CreateShipment();

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Reopen", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsFalse(BoolValue(ResponseJson, 'changed'), 'An open shipment is not changed.');
    end;

    /// <summary>AC04: reopening while an open pick exists is refused and the shipment stays released.</summary>
    [Test]
    procedure Reopen_OpenPick_IsRefused()
    var
        TestData: Codeunit "Whse Test Data ori";
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
        PickNo: Code[20];
    begin
        // Story #53, AC04 | Time: independent of WorkDate | Risk: the pick is a fixture line, not a created pick.
        ShipmentNo := CreateShipment();
        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);
        PickNo := CopyStr('PI-' + ShipmentNo, 1, MaxStrLen(PickNo));
        TestData.CreateActivity(Enum::"Warehouse Activity Type"::Pick, PickNo, '', '', ShipmentNo);

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Reopen", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Register or delete the picks first.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the picks.');
        AssertStatus(ShipmentNo, true);
    end;

    /// <summary>AC06 for reopen: an unknown key is refused and the shipment stays released.</summary>
    [Test]
    procedure Reopen_UnknownKey_IsRefused()
    var
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
    begin
        // Story #53, AC06 | Time: independent of WorkDate | Risk: none.
        ShipmentNo := CreateShipment();
        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"' + ShipmentNo + '"}', ResponseJson);

        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Reopen", '{"shipmentNo":"' + ShipmentNo + '","force":true}', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        AssertStatus(ShipmentNo, true);
    end;

    /// <summary>AC08: without write permission both types are disabled and answer PermissionDenied naming the permission set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure ReleaseReopen_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        ReleaseImpl: Codeunit "Whse Shipment Release Impl ori";
        ReopenImpl: Codeunit "Whse Shipment Reopen Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Story #53, AC08 | Time: independent of WorkDate | Risk: none.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Shipment.Release";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Release must be disabled without write permission.');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Shipment.Reopen";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Reopen must be disabled without write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        ReleaseImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'Release denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');

        TempArgument.Delete();
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        ReopenImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'Reopen denial must use PermissionDenied.');
    end;

    /// <summary>#67 item 1: every identifier sent must find the shipment; a stray one is RecordNotFound, not Success (1033).</summary>
    [Test]
    procedure Reopen_StrayIdentifier_IsRecordNotFound()
    begin
        // Issue #67, AC1 (item 1) | Time: independent of WorkDate | Risk: none.
        AssertStrayIdentifierRefused(1033, 'was not found');
    end;

    /// <summary>#67 item 1: the same refusal answers in Icelandic (1039).</summary>
    [Test]
    procedure Reopen_StrayIdentifier_IsRecordNotFoundInIcelandic()
    begin
        // Issue #67, AC1 (item 1) | Time: independent of WorkDate | Risk: none.
        AssertStrayIdentifierRefused(1039, 'fannst ekki');
    end;

    /// <summary>#67 item 3: an unknown key and an unknown shipment are answered together as MultipleErrors.</summary>
    [Test]
    procedure Release_UnknownKeyAndUnknownShipment_AreCollected()
    var
        ResponseJson: JsonObject;
    begin
        // Issue #67, AC1 (item 3) | Time: independent of WorkDate | Risk: none.
        Run(Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"NO-SUCH-SHIP","note":"x"}', ResponseJson);
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('UnknownParameter,RecordNotFound', ErrorCodes(ResponseJson), 'Both problems are listed in order.');

        RunIn(1039, Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"shipmentNo":"NO-SUCH-SHIP","note":"x"}', '', ResponseJson);
        Assert.AreEqual('MultipleErrors', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('UnknownParameter,RecordNotFound', ErrorCodes(ResponseJson), 'Both problems are listed in Icelandic too.');
        Assert.AreEqual('Beiðnin hefur nokkur vandamál; errors telur hvert þeirra upp.', TextValue(ResponseJson, 'error'), 'The summary is Icelandic.');
    end;

    local procedure AssertStrayIdentifierRefused(LanguageId: Integer; NotFoundText: Text)
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        ShipmentNo: Code[20];
        StraySystemId: Text;
    begin
        ShipmentNo := CreateShipment();
        ShipmentHeader.Get(ShipmentNo);
        StraySystemId := Format(CreateGuid(), 0, 4);
        // [WHEN] A valid shipmentNo comes with a systemId that matches nothing.
        RunIn(LanguageId, Enum::"Message Type ori"::"Warehouse.Shipment.Reopen", '{"shipmentNo":"' + ShipmentNo + '","systemId":"' + StraySystemId + '"}', '', ResponseJson);
        // [THEN] The stray identifier is refused and named.
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('systemId', TextValue(ResponseJson, 'parameter'), 'The stray key is named.');
        Assert.IsTrue(TextValue(ResponseJson, 'error').Contains(NotFoundText), 'The error is in the caller language: ' + ResponseText(ResponseJson));
        Assert.IsTrue(TextValue(ResponseJson, 'nextStep').Contains('Data.Records.Get'), 'The next step names Data.Records.Get.');

        // [WHEN] A valid SystemId as the subject comes with a number that matches nothing.
        RunIn(LanguageId, Enum::"Message Type ori"::"Warehouse.Shipment.Release", '{"no":"NO-SUCH-SHIP"}', Format(ShipmentHeader.SystemId, 0, 4), ResponseJson);
        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('no', TextValue(ResponseJson, 'parameter'), 'The stray number is named.');

        // [THEN] A single valid identifier keeps today's answer.
        RunIn(LanguageId, Enum::"Message Type ori"::"Warehouse.Shipment.Reopen", '{"shipmentNo":"' + ShipmentNo + '","systemId":"' + Format(ShipmentHeader.SystemId, 0, 4) + '"}', '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        AssertStatus(ShipmentNo, false);
    end;

    local procedure RunIn(LanguageId: Integer; MessageType: Enum "Message Type ori"; RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ReceiptHelper.RunMessageInLanguage(MessageType, Subject, RequestText, ResponseJson, LanguageId), 'The response should be JSON.');
    end;

    local procedure ErrorCodes(ResponseJson: JsonObject): Text
    var
        Token: JsonToken;
        Entry: JsonToken;
        Codes: TextBuilder;
    begin
        if not ResponseJson.Get('errors', Token) then
            exit('');
        foreach Entry in Token.AsArray() do begin
            if Codes.Length() > 0 then
                Codes.Append(',');
            Codes.Append(TextValue(Entry.AsObject(), 'code'));
        end;
        exit(Codes.ToText());
    end;

    local procedure CreateShipment(): Code[20]
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
    begin
        ShipmentHelper.SetupLocationAndItem(Location, Item, 20);
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 2);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
        exit(ShipmentHeader."No.");
    end;

    local procedure CreateEmptyShipment(var ShipmentHeader: Record "Warehouse Shipment Header")
    var
        Location: Record Location;
        Item: Record Item;
    begin
        ShipmentHelper.SetupLocationAndItem(Location, Item, 0);
        ShipmentHeader.Init();
        ShipmentHeader."No." := '';
        ShipmentHeader."Location Code" := Location.Code;
        ShipmentHeader.Insert(true);
    end;

    local procedure AssertStatus(ShipmentNo: Code[20]; Released: Boolean)
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
    begin
        ShipmentHeader.Get(ShipmentNo);
        if Released then
            Assert.AreEqual(ShipmentHeader.Status::Released, ShipmentHeader.Status, 'The shipment must stay released.')
        else
            Assert.AreEqual(ShipmentHeader.Status::Open, ShipmentHeader.Status, 'The shipment must be open.');
    end;

    local procedure Run(MessageType: Enum "Message Type ori"; RequestText: Text; var ResponseJson: JsonObject)
    begin
        Run(MessageType, RequestText, '', ResponseJson);
    end;

    local procedure Run(MessageType: Enum "Message Type ori"; RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(ShipmentHelper.RunMessage(MessageType, Subject, RequestText, ResponseJson), 'The response should be JSON.');
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
