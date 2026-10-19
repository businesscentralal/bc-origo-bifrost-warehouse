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
/// Tests Warehouse.ActivityLine.ChangeBin (#56): Take and Place bins, the paired line, refusals and the permission path.
/// </summary>
codeunit 97059 "Whse ActLine ChgBin Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        OtherBin: Record Bin;
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC02 and AC08: the Take line gets a stocked bin and the Place line keeps its bin; the answer says so.</summary>
    [Test]
    procedure ChangeBin_TakeLineToStockedBin_LeavesPlaceLine()
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(3);
        Helper.StockBin(OtherBin, Item."No.", 5);
        Helper.FindLine(TakeLine."Activity Type"::Movement, MovementNo, TakeLine."Action Type"::Take, TakeLine);
        Helper.FindLine(PlaceLine."Activity Type"::Movement, MovementNo, PlaceLine."Action Type"::Place, PlaceLine);

        ResponseJson := Send(LineRequest(MovementNo, TakeLine."Line No.", OtherBin.Code));

        Helper.AssertSuccess(ResponseJson);
        Assert.IsTrue(Helper.BooleanValue(ResponseJson, 'changed'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(OtherBin.Code, Helper.TextValue(Helper.ObjectValue(ResponseJson, 'line'), 'binCode'), 'The Take line has the new bin.');
        Assert.AreEqual(1, Helper.ArrayValue(ResponseJson, 'unchangedPairedLineNos').Count(), 'The Place line is named.');
        Assert.AreNotEqual('', Helper.TextValue(ResponseJson, 'note'), 'The answer says the Place line is unchanged.');
        PlaceLine.Get(PlaceLine."Activity Type", PlaceLine."No.", PlaceLine."Line No.");
        Assert.AreEqual(ToBin.Code, PlaceLine."Bin Code", 'The Place line keeps its bin.');
    end;

    /// <summary>AC05: a Take bin without enough content is InvalidLine and nothing is written.</summary>
    [Test]
    procedure ChangeBin_TakeLineToEmptyBin_InvalidLine()
    var
        TakeLine: Record "Warehouse Activity Line";
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(3);
        Helper.FindLine(TakeLine."Activity Type"::Movement, MovementNo, TakeLine."Action Type"::Take, TakeLine);

        Helper.ExpectError(Send(LineRequest(MovementNo, TakeLine."Line No.", OtherBin.Code)), 'InvalidLine', 'Read Warehouse.BinContent.Get.');
        TakeLine.Get(TakeLine."Activity Type", TakeLine."No.", TakeLine."Line No.");
        Assert.AreEqual(FromBin.Code, TakeLine."Bin Code", 'Nothing is written.');
    end;

    /// <summary>AC05: the adjustment bin is not allowed on a Place line.</summary>
    [Test]
    procedure ChangeBin_PlaceLineToAdjustmentBin_InvalidLine()
    var
        PlaceLine: Record "Warehouse Activity Line";
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(3);
        Helper.FindLine(PlaceLine."Activity Type"::Movement, MovementNo, PlaceLine."Action Type"::Place, PlaceLine);

        Helper.ExpectError(Send(LineRequest(MovementNo, PlaceLine."Line No.", Location."Adjustment Bin Code")), 'InvalidLine', 'Read Warehouse.BinContent.Get.');
    end;

    /// <summary>Edge: the bin the line already has answers changed false.</summary>
    [Test]
    procedure ChangeBin_SameBin_ChangedFalse()
    var
        PlaceLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        MovementNo: Code[20];
    begin
        MovementNo := CreateMovement(3);
        Helper.FindLine(PlaceLine."Activity Type"::Movement, MovementNo, PlaceLine."Action Type"::Place, PlaceLine);

        ResponseJson := Send(LineRequest(MovementNo, PlaceLine."Line No.", ToBin.Code));

        Helper.AssertSuccess(ResponseJson);
        Assert.IsFalse(Helper.BooleanValue(ResponseJson, 'changed'), Helper.ResponseText(ResponseJson));
    end;

    /// <summary>AC06 and AC07: a line of another activity, unknown bin, missing binCode and unknown key.</summary>
    [Test]
    procedure ChangeBin_Refusals_AnswerCodesWithNextStep()
    var
        OtherLine: Record "Warehouse Activity Line";
        TakeLine: Record "Warehouse Activity Line";
        MovementNo: Code[20];
        OtherMovementNo: Code[20];
    begin
        MovementNo := CreateMovement(2);
        Helper.FindLine(TakeLine."Activity Type"::Movement, MovementNo, TakeLine."Action Type"::Take, TakeLine);
        Helper.StockBin(FromBin, Item."No.", 1);
        OtherMovementNo := Helper.CreateMovement(Location.Code, Item."No.", FromBin.Code, ToBin.Code, 1);
        Helper.FindLine(OtherLine."Activity Type"::Movement, OtherMovementNo, OtherLine."Action Type"::Place, OtherLine);

        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lineSystemId":"' + Format(OtherLine.SystemId, 0, 4) + '","binCode":"' + ToBin.Code + '"}'), 'ConflictingIdentifiers', 'Use the activity no. answered by Warehouse.Activity.Get.');
        Helper.ExpectError(Send(LineRequest(MovementNo, TakeLine."Line No.", 'NO-SUCH-BIN')), 'RecordNotFound', 'Check the bin with Warehouse.Bin.Get.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lineNo":10000}'), 'MissingParameter', 'Send the new bin in binCode.');
        Helper.ExpectError(Send('{"activityNo":"' + MovementNo + '","lineNo":10000,"binCode":"' + ToBin.Code + '","zone":"PICK"}'), 'UnknownParameter', '');
    end;

    /// <summary>AC09: without activity write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure ChangeBin_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        ChangeBinImpl: Codeunit "Whse ActLine ChgBin Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.ActivityLine.ChangeBin";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'ChangeBin must be disabled without activity write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        ChangeBinImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    local procedure CreateMovement(Quantity: Decimal): Code[20]
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, FromBin);
        Helper.FindPickBin(Location.Code, 2, ToBin);
        Helper.FindPickBin(Location.Code, 3, OtherBin);
        Helper.StockBin(FromBin, Item."No.", Quantity);
        exit(Helper.CreateMovement(Location.Code, Item."No.", FromBin.Code, ToBin.Code, Quantity));
    end;

    local procedure LineRequest(MovementNo: Code[20]; LineNo: Integer; BinCode: Code[20]): Text
    begin
        exit('{"activityType":"Movement","activityNo":"' + MovementNo + '","lineNo":' + Format(LineNo, 0, 9) + ',"binCode":"' + BinCode + '"}');
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.ActivityLine.ChangeBin", '', RequestText));
    end;
}
