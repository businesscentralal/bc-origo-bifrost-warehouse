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
/// Tests Warehouse.ActivityLine.SetQtyToHandle (#56): named lines, all and none, refusals and the permission path.
/// </summary>
codeunit 97060 "Whse ActLine SetQty Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC03: named Take and Place lines get the quantity to handle.</summary>
    [Test]
    procedure SetQty_NamedLines_WritesQuantity()
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(5);
        Helper.FindLine(TakeLine."Activity Type"::Movement, MovementNo, TakeLine."Action Type"::Take, TakeLine);
        Helper.FindLine(PlaceLine."Activity Type"::Movement, MovementNo, PlaceLine."Action Type"::Place, PlaceLine);

        ResponseJson := Send('{"activityType":"Movement","activityNo":"' + MovementNo + '","lines":[{"lineNo":' + Format(TakeLine."Line No.", 0, 9) + ',"qtyToHandle":2},{"lineSystemId":"' + Format(PlaceLine.SystemId, 0, 4) + '","qtyToHandle":2}]}');

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(2, Helper.ArrayValue(ResponseJson, 'lines').Count(), Helper.ResponseText(ResponseJson));
        TakeLine.Get(TakeLine."Activity Type", TakeLine."No.", TakeLine."Line No.");
        PlaceLine.Get(PlaceLine."Activity Type", PlaceLine."No.", PlaceLine."Line No.");
        Assert.AreEqual(2, TakeLine."Qty. to Handle", 'Take line.');
        Assert.AreEqual(2, PlaceLine."Qty. to Handle", 'Place line.');
    end;

    /// <summary>AC03: none clears and all fills the quantity to handle on every line.</summary>
    [Test]
    procedure SetQty_NoneThenAll_ClearsAndFills()
    var
        ActivityLine: Record "Warehouse Activity Line";
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(4);
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Movement);
        ActivityLine.SetRange("No.", MovementNo);

        Helper.AssertSuccess(Send('{"activityNo":"' + MovementNo + '","none":true}'));
        ActivityLine.SetFilter("Qty. to Handle", '<>0');
        Assert.IsTrue(ActivityLine.IsEmpty(), 'none clears every line.');

        Helper.AssertSuccess(Send('{"activityNo":"' + MovementNo + '","all":true}'));
        ActivityLine.SetFilter("Qty. to Handle", '<>4');
        Assert.IsTrue(ActivityLine.IsEmpty(), 'all fills every line with its outstanding quantity.');
    end;

    /// <summary>AC07: combined choices, no choice, quantity above outstanding, wrong type and a missing quantity.</summary>
    [Test]
    procedure SetQty_Refusals_AnswerCodesWithNextStep()
    var
        TakeLine: Record "Warehouse Activity Line";
        MovementNo: Code[20];
        LineText: Text;
    begin
        MovementNo := CreateMovement(3);
        Helper.FindLine(TakeLine."Activity Type"::Movement, MovementNo, TakeLine."Action Type"::Take, TakeLine);
        LineText := Format(TakeLine."Line No.", 0, 9);

        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","all":true,"none":true}'), 'InvalidParameter', 'Send exactly one of lines, all: true or none: true.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '"}'), 'MissingParameter', 'Send exactly one of lines, all: true or none: true.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lines":[{"lineNo":' + LineText + ',"qtyToHandle":9}]}'), 'InvalidParameter', 'Send a quantity from zero up to the outstanding quantity.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lines":[{"lineNo":' + LineText + ',"qtyToHandle":"two"}]}'), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lines":[{"lineNo":' + LineText + '}]}'), 'MissingParameter', 'Send qtyToHandle on every line.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","all":true,"extra":1}'), 'UnknownParameter', '');
        Helper.ExpectError(Send('{"activityNo":"NO-SUCH-ACT","all":true}'), 'RecordNotFound', 'Check the activity with Warehouse.Activity.Get.');
        TakeLine.Get(TakeLine."Activity Type", TakeLine."No.", TakeLine."Line No.");
        Assert.AreEqual(3, TakeLine."Qty. to Handle", 'Nothing is written.');
    end;

    /// <summary>AC09: without activity write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure SetQty_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        SetQtyImpl: Codeunit "Whse ActLine SetQty Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.ActivityLine.SetQtyToHandle";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'SetQtyToHandle must be disabled without activity write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        SetQtyImpl.ExecuteBifrostTask(TempArgument);
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

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.ActivityLine.SetQtyToHandle", '', RequestText));
    end;
}
