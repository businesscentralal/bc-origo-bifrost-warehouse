namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InternalDocument;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InternalPick.Create (#106) through the public dispatcher, its refusals and the permission denial.
/// </summary>
codeunit 97099 "Whse IntPick Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        JnlHelper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC03: an internal pick to a to-bin with createActivity gives a pick that Warehouse.Pick.Register registers.</summary>
    [Test]
    procedure Create_WithActivity_PickRegisters()
    var
        Location: Record Location;
        Item: Record Item;
        ToBin: Record Bin;
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        RegisterJson: JsonObject;
        ActivityNo: Code[20];
    begin
        PreparePickStock(Location, Item, ToBin, 5);

        Run('{"locationCode":"' + Location.Code + '","toBinCode":"' + ToBin.Code + '","dueDate":"' + Format(WorkDate(), 0, 9) + '","lines":[{"itemNo":"' + Item."No." + '","quantity":2}],"createActivity":true}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Released', TextValue(ResponseJson, 'documentStatus'), 'The internal pick should be released.');
        Assert.AreEqual('Pick', TextValue(ResponseJson, 'activityType'), 'A pick should be created.');
        Assert.AreEqual(ToBin.Code, TextValue(FirstLine(ResponseJson), 'toBinCode'), 'The to-bin should be on the line.');
        ActivityNo := CopyStr(TextValue(ResponseJson, 'activityNo'), 1, MaxStrLen(ActivityNo));
        Assert.AreNotEqual('', ActivityNo, 'The pick number should be returned.');

        Assert.IsTrue(RunType(Enum::"Message Type ori"::"Warehouse.Pick.Register", ActivityNo, '{"expectedCount":1}', RegisterJson), 'The register response should be JSON.');
        Assert.AreEqual('Success', TextValue(RegisterJson, 'status'), ResponseText(RegisterJson));
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("No.", ActivityNo);
        Assert.IsTrue(ActivityLine.IsEmpty(), 'The registered pick should be gone.');
    end;

    /// <summary>AC03: without createActivity the released internal pick is offered to the pick worksheet.</summary>
    [Test]
    procedure Create_WithoutActivity_IsAPickWorksheetSource()
    var
        Location: Record Location;
        Item: Record Item;
        ToBin: Record Bin;
        PickRequest: Record "Whse. Pick Request";
        ResponseJson: JsonObject;
    begin
        PreparePickStock(Location, Item, ToBin, 5);

        Run('{"locationCode":"' + Location.Code + '","toBinCode":"' + ToBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1}]}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('', TextValue(ResponseJson, 'activityNo'), 'No pick without createActivity.');
        PickRequest.SetRange("Document Type", PickRequest."Document Type"::"Internal Pick");
        PickRequest.SetRange("Document No.", CopyStr(TextValue(ResponseJson, 'internalDocumentNo'), 1, MaxStrLen(PickRequest."Document No.")));
        PickRequest.SetRange(Status, PickRequest.Status::Released);
        Assert.IsFalse(PickRequest.IsEmpty(), 'The released internal pick should be a pick worksheet source.');
    end;

    /// <summary>AC04: a basic location is refused with PreconditionFailed.</summary>
    [Test]
    procedure Create_BasicLocation_IsRefused()
    var
        Location: Record Location;
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        Run('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"X","quantity":1}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', 'Use Warehouse.InventoryMovement.Create for basic warehouse locations.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: a to-bin blocked for inbound movement is refused, and createActivity with release false is invalid.</summary>
    [Test]
    procedure Create_BlockedToBinAndActivityWithoutRelease_AreRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ToBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PreparePickStock(Location, Item, ToBin, 5);
        Run('{"locationCode":"' + Location.Code + '","toBinCode":"' + ToBin.Code + '","release":false,"createActivity":true,"lines":[{"itemNo":"' + Item."No." + '","quantity":1}]}', ResponseJson);
        AssertRefused(ResponseJson, 'InvalidParameter', 'Send release true, or leave createActivity out.');
        ToBin.Get(ToBin."Location Code", ToBin.Code);
        ToBin."Block Movement" := ToBin."Block Movement"::Inbound;
        ToBin.Modify();
        Run('{"locationCode":"' + Location.Code + '","toBinCode":"' + ToBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1}]}', ResponseJson);
        AssertRefused(ResponseJson, 'PreconditionFailed', '');
        Run('{"locationCode":"' + Location.Code + '","toBinCode":"' + ToBin.Code + '"}', ResponseJson);
        AssertRefused(ResponseJson, 'MissingParameter', 'Send at least one line.');
        AssertNothingWritten(Location.Code);
    end;

    /// <summary>AC04: more than the location holds is refused instead of a partial pick.</summary>
    [Test]
    procedure Create_MoreThanAvailable_IsRefusedAndRolledBack()
    var
        Location: Record Location;
        Item: Record Item;
        ToBin: Record Bin;
        ResponseJson: JsonObject;
    begin
        PreparePickStock(Location, Item, ToBin, 1);
        // The test dispatcher runs in the caller's write transaction, so Business Central's refusal surfaces as an error here.
        // The removal of what Business Central committed before refusing runs on the isolated path and is checked live through MCP.
        asserterror Run('{"locationCode":"' + Location.Code + '","toBinCode":"' + ToBin.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":50}],"createActivity":true}', ResponseJson);
        Assert.ExpectedError('is available to pick. Nothing was written.');
    end;

    /// <summary>AC06: without write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CreateImpl: Codeunit "Whse IntPick Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InternalPick.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
    end;

    /// <summary>AC06: discovery text is English in 1033 and Icelandic in 1039.</summary>
    [Test]
    procedure Help_DiscoveryText_IsTranslated()
    var
        Discovery: Interface "Msg Discovery ori";
        PreviousLanguage: Integer;
    begin
        Discovery := Enum::"Message Type ori"::"Warehouse.InternalPick.Create";
        PreviousLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        Assert.IsTrue(Discovery.GetSelectionDescription().StartsWith('Creates and releases an internal pick'), Discovery.GetSelectionDescription());
        GlobalLanguage(1039);
        Assert.IsTrue(Discovery.GetSelectionDescription().StartsWith('Stofnar og gefur út innri tínslu'), Discovery.GetSelectionDescription());
        GlobalLanguage(PreviousLanguage);
    end;

    local procedure EnsureInternalDocumentNos()
    var
        WarehouseSetup: Record "Warehouse Setup";
        LibraryUtility: Codeunit "Library - Utility";
    begin
        // A fresh CRONUS company has no internal pick and put-away number series; Business Central needs them to insert the documents.
        WarehouseSetup.Get();
        if WarehouseSetup."Whse. Internal Pick Nos." = '' then
            WarehouseSetup.Validate("Whse. Internal Pick Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        if WarehouseSetup."Whse. Internal Put-away Nos." = '' then
            WarehouseSetup.Validate("Whse. Internal Put-away Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        WarehouseSetup.Modify(true);
    end;

    local procedure PreparePickStock(var Location: Record Location; var Item: Record Item; var ToBin: Record Bin; Quantity: Decimal)
    begin
        EnsureInternalDocumentNos();
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);
        EnsureDefaultDirectedEmployee(Location.Code);
        LibraryInventory.CreateItem(Item);
        JnlHelper.StockDirectedPickBin(Location, Item."No.", Quantity);
        ToBin.Get(Location.Code, Location."Shipment Bin Code");
    end;

    local procedure EnsureDefaultDirectedEmployee(LocationCode: Code[10])
    var
        WarehouseEmployee: Record "Warehouse Employee";
        Existing: Record "Warehouse Employee";
        UserCode: Code[50];
    begin
        UserCode := CopyStr(UserId(), 1, MaxStrLen(UserCode));
        if UserCode = '' then
            exit;
        Existing.SetRange("User ID", UserCode);
        Existing.SetRange(Default, true);
        Existing.SetFilter("Location Code", '<>%1', LocationCode);
        Existing.ModifyAll(Default, false);
        if WarehouseEmployee.Get(UserCode, LocationCode) then begin
            WarehouseEmployee.Default := true;
            WarehouseEmployee.Modify(true);
            exit;
        end;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := UserCode;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := true;
        WarehouseEmployee.Insert(true);
    end;

    local procedure AssertRefused(ResponseJson: JsonObject; ExpectedCode: Text; ExpectedNextStep: Text)
    begin
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.IsTrue(StrPos(ResponseText(ResponseJson), '"' + ExpectedCode + '"') > 0, 'Expected ' + ExpectedCode + ': ' + ResponseText(ResponseJson));
        if ExpectedNextStep <> '' then
            Assert.IsTrue(StrPos(ResponseText(ResponseJson), ExpectedNextStep) > 0, 'Expected next step ' + ExpectedNextStep + ': ' + ResponseText(ResponseJson));
        Assert.IsTrue(StrPos(ResponseText(ResponseJson), 'nextStep') > 0, 'Every refusal carries a nextStep: ' + ResponseText(ResponseJson));
    end;

    local procedure AssertNothingWritten(LocationCode: Code[10])
    var
        Header: Record "Whse. Internal Pick Header";
    begin
        Header.SetRange("Location Code", LocationCode);
        Assert.IsTrue(Header.IsEmpty(), 'A refusal must not leave an internal pick.');
    end;

    local procedure Run(RequestText: Text; var ResponseJson: JsonObject)
    begin
        RunWithSubject(RequestText, '', ResponseJson);
    end;

    local procedure RunWithSubject(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(RunType(Enum::"Message Type ori"::"Warehouse.InternalPick.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure RunType(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text; var ResponseJson: JsonObject): Boolean
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Clear(ResponseJson);
        exit(Helper.RunMessage(MessageType, Subject, RequestText, ResponseJson));
    end;

    local procedure FirstLine(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(ResponseJson.Get('lines', Token), 'The response should list lines.');
        Token.AsArray().Get(0, Token);
        exit(Token.AsObject());
    end;

    local procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
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
