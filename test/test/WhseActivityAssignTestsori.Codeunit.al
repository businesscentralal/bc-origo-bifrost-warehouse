namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Activity.Assign (#105): assign, unassign, re-sort, all or nothing, refusals, permission and help.
/// </summary>
codeunit 97008 "Whse Activity Assign Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Location: Record Location;
        Item: Record Item;
        FirstBin: Record Bin;
        SecondBin: Record Bin;
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC01: another warehouse employee is assigned with today's date, Activity.Get finds it, and an empty user unassigns.</summary>
    [Test]
    procedure Assign_OtherWarehouseEmployee_SetsUserAndDate_EmptyUnassigns()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        Entry: JsonObject;
        PickNo: Code[20];
        Employee: Code[50];
    begin
        PickNo := CreatePick();
        Employee := CreateEmployee(Location.Code);

        ResponseJson := Send(AssignRequest(PickNo, Employee, ''));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'updatedCount'), Helper.ResponseText(ResponseJson));
        Entry := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'activities'), 0);
        Assert.AreEqual(Employee, Helper.TextValue(Entry, 'assignedUserId'), 'The stored user is echoed.');
        ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo);
        Assert.AreEqual(Employee, ActivityHeader."Assigned User ID", 'The user is stored.');
        Assert.AreEqual(Today(), ActivityHeader."Assignment Date", 'The assignment date is today.');

        ResponseJson := Helper.RunType(Enum::"Message Type ori"::"Warehouse.Activity.Get", '', StrSubstNo('{"activityType":"Pick","assignedUserId":"%1"}', Employee));
        Assert.IsTrue(Helper.ResponseText(ResponseJson).Contains(PickNo), 'Activity.Get with assignedUserId finds the pick. ' + Helper.ResponseText(ResponseJson));

        Helper.AssertSuccess(Send(AssignRequest(PickNo, '', '')));
        ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo);
        Assert.AreEqual('', ActivityHeader."Assigned User ID", 'An empty user unassigns.');
        Assert.AreEqual(0D, ActivityHeader."Assignment Date", 'Unassigning clears the date.');
    end;

    /// <summary>AC02: a user who is not a warehouse employee at the location is refused with Business Central's reason.</summary>
    [Test]
    procedure Assign_NotWarehouseEmployee_PreconditionFailed_NothingChanged()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PickNo := CreatePick();

        ResponseJson := Send(AssignRequest(PickNo, 'NOEMPLOYEE105', ''));

        Helper.ExpectError(ResponseJson, 'PreconditionFailed', '');
        Assert.IsTrue(Helper.TextValue(ResponseJson, 'error').Contains('NOEMPLOYEE105'), 'The answer carries Business Central''s reason. ' + Helper.ResponseText(ResponseJson));
        ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo);
        Assert.AreEqual('', ActivityHeader."Assigned User ID", 'Nothing is changed.');
    end;

    /// <summary>AC05: one refused activity leaves every named activity unchanged.</summary>
    [Test]
    procedure Assign_OneActivityRefused_NoActivityChanged()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        OtherLocation: Record Location;
        PickNo: Code[20];
        OtherPickNo: Code[20];
        Employee: Code[50];
    begin
        PickNo := CreatePick();
        Employee := CreateEmployee(Location.Code);
        Helper.CreateBasicLocation(OtherLocation);
        OtherPickNo := Helper.CreateRawActivity(Enum::"Warehouse Activity Type"::Pick, Enum::"Warehouse Action Type"::" ", OtherLocation.Code, Item."No.", '', '', 1);

        Helper.ExpectError(Send(StrSubstNo('{"activities":[{"activityType":"Pick","activityNo":"%1"},{"activityType":"Pick","activityNo":"%2"}],"assignedUserId":"%3"}', PickNo, OtherPickNo, Employee)), 'PreconditionFailed', '');

        ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo);
        Assert.AreEqual('', ActivityHeader."Assigned User ID", 'The first pick is rolled back too.');
    end;

    /// <summary>AC03: changing the sorting method re-sorts the lines.</summary>
    [Test]
    procedure Assign_SortingMethod_ReSortsLines()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PickNo := CreatePick();
        Helper.AddRawLine(Enum::"Warehouse Activity Type"::Pick, PickNo, 20000, Enum::"Warehouse Action Type"::Take, Location.Code, Item."No.", FirstBin."Zone Code", FirstBin.Code, 1);

        ResponseJson := Send(AssignRequest(PickNo, CreateEmployee(Location.Code), 'Shelf or Bin'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual('Shelf or Bin', Helper.TextValue(Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'activities'), 0), 'sortingMethod'), Helper.ResponseText(ResponseJson));
        ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo);
        Assert.AreEqual(ActivityHeader."Sorting Method"::"Shelf or Bin", ActivityHeader."Sorting Method", 'The sorting method is stored.');
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        ActivityLine.SetRange("No.", PickNo);
        ActivityLine.SetCurrentKey("Activity Type", "No.", "Sorting Sequence No.");
        ActivityLine.FindFirst();
        Assert.AreEqual(FirstBin.Code, ActivityLine."Bin Code", 'The line of the first bin sorts first after re-sorting.');
    end;

    /// <summary>AC06: each refusal answers its code with a nextStep and changes nothing.</summary>
    [Test]
    procedure Assign_Refusals_AnswerCodeAndNextStep()
    var
        PickNo: Code[20];
    begin
        PickNo := CreatePick();
        Helper.ExpectError(Send(StrSubstNo('{"activities":[{"activityType":"Pick","activityNo":"%1"}]}', PickNo)), 'MissingParameter', '');
        Helper.ExpectError(Send(StrSubstNo('{"activities":[{"activityType":"Pick","activityNo":"%1"}],"assignedUserId":"","colour":"red"}', PickNo)), 'UnknownParameter', 'Remove this key or consult Help.Implementation.Get for the declared parameters.');
        Helper.ExpectError(Send('{"activities":[{"activityType":"Pick","activityNo":"NOPICK105"}],"assignedUserId":""}'), 'RecordNotFound', '');
        Helper.ExpectError(Send('{"activities":[{"systemId":"not-a-guid"}],"assignedUserId":""}'), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(StrSubstNo('{"activities":[{"activityType":"Pick","activityNo":"%1","systemId":"%2"}],"assignedUserId":""}', PickNo, Format(CreateGuid(), 0, 4))), 'RecordNotFound', '');
        Helper.ExpectError(Send(StrSubstNo('{"activities":[{"activityType":"Pick","activityNo":"%1"}],"assignedUserId":"","sortingMethod":"Colour"}', PickNo)), 'InvalidParameter', '');
        Helper.ExpectError(Send(StrSubstNo('{"activities":[{"activityType":"Put-away","activityNo":"%1","systemId":"%2"}],"assignedUserId":""}', PickNo, PickSystemId(PickNo))), 'ConflictingIdentifiers', '');
    end;

    /// <summary>AC07: without activity write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Assign_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        AssignImpl: Codeunit "Whse Activity Assign Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Activity.Assign";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Assign must be disabled without activity write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        AssignImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    /// <summary>AC07: discovery text and refusals answer in English (1033) and Icelandic (1039).</summary>
    [Test]
    procedure Assign_HelpAndRefusal_InEnglishAndIcelandic()
    var
        Discovery: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
        English: Text;
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        Discovery := Enum::"Message Type ori"::"Warehouse.Activity.Assign";
        GlobalLanguage(1033);
        English := Discovery.GetDescription();
        Assert.AreEqual('Assigns picks, put-aways and movements to a warehouse employee and re-sorts them.', English, 'English description.');
        GlobalLanguage(1039);
        Assert.AreEqual('Úthlutar tínslum, frágangi og tilfærslum til starfsmanns vöruhúss og raðar þeim upp á nýtt.', Discovery.GetDescription(), 'Icelandic description.');
        GlobalLanguage(OriginalLanguage);
        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Activity.Assign", '', '{"activities":[{"activityType":"Pick","activityNo":"X"}]}', 1039);
        Helper.ExpectError(ResponseJson, 'MissingParameter', 'Sendu gildið sem vantar; Help.Implementation.Get sýnir viðföngin.');
        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Activity.Assign", '', '{"activities":[{"activityType":"Pick","activityNo":"X"}]}', 1033);
        Helper.ExpectError(ResponseJson, 'MissingParameter', 'Send the missing value; Help.Implementation.Get lists the parameters.');
    end;

    local procedure CreatePick(): Code[20]
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, FirstBin);
        Helper.FindPickBin(Location.Code, 2, SecondBin);
        exit(Helper.CreateRawActivity(Enum::"Warehouse Activity Type"::Pick, Enum::"Warehouse Action Type"::Take, Location.Code, Item."No.", SecondBin."Zone Code", SecondBin.Code, 1));
    end;

    local procedure CreateEmployee(LocationCode: Code[10]) Employee: Code[50]
    var
        WarehouseEmployee: Record "Warehouse Employee";
    begin
        Employee := 'WHSE105' + Helper.NewCode();
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := Employee;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Insert(false);
    end;

    local procedure PickSystemId(PickNo: Code[20]): Text
    var
        ActivityHeader: Record "Warehouse Activity Header";
    begin
        ActivityHeader.Get(ActivityHeader.Type::Pick, PickNo);
        exit(Format(ActivityHeader.SystemId, 0, 4));
    end;

    local procedure AssignRequest(PickNo: Code[20]; UserCode: Text; SortingMethod: Text): Text
    begin
        if SortingMethod = '' then
            exit(StrSubstNo('{"activities":[{"activityType":"Pick","activityNo":"%1"}],"assignedUserId":"%2"}', PickNo, UserCode));
        exit(StrSubstNo('{"activities":[{"activityType":"Pick","activityNo":"%1"}],"assignedUserId":"%2","sortingMethod":"%3"}', PickNo, UserCode, SortingMethod));
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Activity.Assign", '', RequestText));
    end;
}
