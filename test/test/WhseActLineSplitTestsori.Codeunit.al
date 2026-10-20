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
/// Tests Warehouse.ActivityLine.Split (#56): split through SplitLine, refusals, a line of another activity and the permission path.
/// </summary>
codeunit 97058 "Whse ActLine Split Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC01: a Take line with quantity to handle 3 of 5 is split and both lines are answered.</summary>
    [Test]
    procedure Split_PartialQtyToHandle_AnswersBothLines()
    var
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(5);
        Helper.FindLine(ActivityLine."Activity Type"::Movement, MovementNo, ActivityLine."Action Type"::Take, ActivityLine);
        ActivityLine.Validate("Qty. to Handle", 3);
        ActivityLine.Modify(true);

        ResponseJson := Send('{"activityType":"Movement","activityNo":"' + MovementNo + '","lineNo":' + Format(ActivityLine."Line No.", 0, 9) + '}');

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(3, Helper.DecimalValue(Helper.ObjectValue(ResponseJson, 'line'), 'qtyOutstanding'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(2, Helper.DecimalValue(Helper.ObjectValue(ResponseJson, 'newLine'), 'qtyOutstanding'), 'The new line takes the rest.');
        Assert.AreNotEqual(ActivityLine."Line No.", Helper.IntegerValue(Helper.ObjectValue(ResponseJson, 'newLine'), 'lineNo'), 'The new line has its own number.');
    end;

    /// <summary>AC04: quantity to handle equal to the outstanding quantity is refused and nothing is written.</summary>
    [Test]
    procedure Split_FullQtyToHandle_PreconditionFailed()
    var
        ActivityLine: Record "Warehouse Activity Line";
        MovementNo: Code[20];
        LineCount: Integer;
    begin
        MovementNo := CreateMovement(5);
        Helper.FindLine(ActivityLine."Activity Type"::Movement, MovementNo, ActivityLine."Action Type"::Take, ActivityLine);
        LineCount := CountLines(MovementNo);

        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lineNo":' + Format(ActivityLine."Line No.", 0, 9) + '}'), 'PreconditionFailed', 'Lower qtyToHandle first; BC splits the rest off.');
        Assert.AreEqual(LineCount, CountLines(MovementNo), 'Nothing is written.');
    end;

    /// <summary>AC06: a line SystemId of another activity is ConflictingIdentifiers.</summary>
    [Test]
    procedure Split_LineOfOtherActivity_ConflictingIdentifiers()
    var
        ActivityLine: Record "Warehouse Activity Line";
        MovementNo: Code[20];
        OtherMovementNo: Code[20];
    begin
        MovementNo := CreateMovement(2);
        OtherMovementNo := CreateMovement(2);
        Helper.FindLine(ActivityLine."Activity Type"::Movement, OtherMovementNo, ActivityLine."Action Type"::Take, ActivityLine);

        Helper.ExpectError(Send('{"activityType":"Movement","activityNo":"' + MovementNo + '","lineSystemId":"' + Format(ActivityLine.SystemId, 0, 4) + '"}'), 'ConflictingIdentifiers', 'Use the activity no. answered by Warehouse.Activity.Get.');
    end;

    /// <summary>AC07: missing activity, unknown line, wrong types, unknown key and an invalid activity type.</summary>
    [Test]
    procedure Split_CommonRefusals_AnswerCodesWithNextStep()
    var
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(2);

        Helper.ExpectError(Send('{"lineNo":10000}'), 'MissingParameter', 'Send activityType and activityNo, or the SystemId of the activity.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lineNo":999999}'), 'RecordNotFound', 'Read the lines with Warehouse.Activity.Get.');
        Helper.ExpectError(Send('{"activityNo":"NO-SUCH-ACT","lineNo":10000}'), 'RecordNotFound', 'Check the activity with Warehouse.Activity.Get.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lineNo":"first"}'), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lineNo":10000,"half":true}'), 'UnknownParameter', '');
        Helper.ExpectError(Send('{"activityType":"Shipment","activityNo":"' + MovementNo + '","lineNo":10000}'), 'InvalidParameter', '');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '"}'), 'MissingParameter', 'Send the line number of the activity line.');
    end;

    /// <summary>AC09: without activity write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Split_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        SplitImpl: Codeunit "Whse ActLine Split Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.ActivityLine.Split";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Split must be disabled without activity write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        SplitImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    local procedure CreateMovement(Quantity: Decimal): Code[20]
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, FromBin);
        Helper.FindPickBin(Location.Code, 2, ToBin);
        Helper.StockBin(FromBin, Item."No.", Quantity);
        exit(Helper.CreateMovement(Location.Code, Item."No.", FromBin.Code, ToBin.Code, Quantity));
    end;

    local procedure CountLines(MovementNo: Code[20]): Integer
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Movement);
        ActivityLine.SetRange("No.", MovementNo);
        exit(ActivityLine.Count());
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.ActivityLine.Split", '', RequestText));
    end;
}
