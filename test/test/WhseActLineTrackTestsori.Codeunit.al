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
/// Tests Warehouse.ActivityLine.AssignTracking (#57): lots split per entry, serial quantity, availability in the Take bin,
/// items without warehouse tracking, an unchanged lot and the permission path.
/// </summary>
codeunit 97061 "Whse ActLine Track Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";
        ContractAssert: Codeunit "Whse Contract Assert ori";
        LibraryItemTracking: Codeunit "Library - Item Tracking";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>AC01: two lot entries for one put-away line split it into two lines, one per lot.</summary>
    [Test]
    procedure AssignTracking_TwoLots_SplitsLinePerEntry()
    var
        Item: Record Item;
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        ActivityNo: Code[20];
    begin
        LibraryItemTracking.CreateLotItem(Item);
        ActivityNo := CreatePutAway(Item."No.", 5);

        ResponseJson := Send('{"activityType":"Put-away","activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"LOT-A","quantity":3},{"lineNo":10000,"lotNo":"LOT-B","quantity":2}]}');

        Helper.AssertSuccess(ResponseJson);
        Assert.IsTrue(Helper.BooleanValue(ResponseJson, 'changed'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(2, Helper.ArrayValue(ResponseJson, 'lines').Count(), 'The line is split per entry.');
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
        ActivityLine.SetRange("No.", ActivityNo);
        ActivityLine.SetRange("Lot No.", 'LOT-A');
        ActivityLine.FindFirst();
        Assert.AreEqual(3, ActivityLine."Qty. Outstanding", 'LOT-A quantity.');
        ActivityLine.SetRange("Lot No.", 'LOT-B');
        ActivityLine.FindFirst();
        Assert.AreEqual(2, ActivityLine."Qty. Outstanding", 'LOT-B quantity.');
    end;

    /// <summary>AC02: a serial entry for more than one unit is InvalidLine and nothing is written.</summary>
    [Test]
    procedure AssignTracking_SerialForTwoUnits_InvalidLine()
    var
        Item: Record Item;
        ActivityLine: Record "Warehouse Activity Line";
        ActivityNo: Code[20];
    begin
        LibraryItemTracking.CreateSerialItem(Item);
        ActivityNo := CreatePutAway(Item."No.", 2);

        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"serialNo":"SN-1","quantity":2}]}'), 'InvalidLine', 'One entry per serial no.');
        ActivityLine.Get(ActivityLine."Activity Type"::"Put-away", ActivityNo, 10000);
        Assert.AreEqual('', ActivityLine."Serial No.", 'Nothing is written.');
    end;

    /// <summary>AC03: a lot that the Take bin does not hold is InvalidLine.</summary>
    [Test]
    procedure AssignTracking_LotNotInTakeBin_InvalidLine()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        ActivityNo: Code[20];
    begin
        Helper.CreateDirectedLocation(Location);
        LibraryItemTracking.CreateLotItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        ActivityNo := Helper.CreateRawActivity("Warehouse Activity Type"::Movement, "Warehouse Action Type"::Take, Location.Code, Item."No.", Bin."Zone Code", Bin.Code, 2);

        Helper.ExpectError(Send('{"activityType":"Movement","activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"LOT-NONE"}]}'), 'InvalidLine', '');
    end;

    /// <summary>AC04: an item without warehouse tracking is PreconditionFailed.</summary>
    [Test]
    procedure AssignTracking_UntrackedItem_PreconditionFailed()
    var
        Item: Record Item;
        ActivityNo: Code[20];
    begin
        Helper.CreateItem(Item);
        ActivityNo := CreatePutAway(Item."No.", 2);

        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"LOT-A"}]}'), 'PreconditionFailed', 'No tracking is needed on this line.');
    end;

    /// <summary>AC06: the lot the line already has, for its whole quantity, answers changed false.</summary>
    [Test]
    procedure AssignTracking_SameLot_ChangedFalse()
    var
        Item: Record Item;
        ActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        ActivityNo: Code[20];
    begin
        LibraryItemTracking.CreateLotItem(Item);
        ActivityNo := CreatePutAway(Item."No.", 2);
        ActivityLine.Get(ActivityLine."Activity Type"::"Put-away", ActivityNo, 10000);
        ActivityLine."Lot No." := 'LOT-A';
        ActivityLine.Modify(false);

        ResponseJson := Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"LOT-A"}]}');

        Helper.AssertSuccess(ResponseJson);
        Assert.IsFalse(Helper.BooleanValue(ResponseJson, 'changed'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(1, Helper.ArrayValue(ResponseJson, 'lines').Count(), 'No line is split.');
    end;

    /// <summary>AC05: missing entries, an entry without a number, too much quantity, a line of another activity, unknown keys and wrong types.</summary>
    [Test]
    procedure AssignTracking_Refusals_AnswerCodesWithNextStep()
    var
        Item: Record Item;
        OtherLine: Record "Warehouse Activity Line";
        ActivityNo: Code[20];
        OtherActivityNo: Code[20];
    begin
        LibraryItemTracking.CreateLotItem(Item);
        ActivityNo := CreatePutAway(Item."No.", 2);
        OtherActivityNo := CreatePutAway(Item."No.", 2);
        OtherLine.Get(OtherLine."Activity Type"::"Put-away", OtherActivityNo, 10000);

        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '"}'), 'MissingParameter', 'Send at least one entry with lineNo and a lot, serial or package number.');
        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"quantity":1}]}'), 'InvalidParameter', 'Send lotNo, serialNo or packageNo on every entry.');
        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"A","quantity":2},{"lineNo":10000,"lotNo":"B","quantity":1}]}'), 'InvalidParameter', 'Send at most the outstanding quantity per line.');
        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineSystemId":"' + Format(OtherLine.SystemId, 0, 4) + '","lotNo":"A"}]}'), 'ConflictingIdentifiers', 'Use the activity no. answered by Warehouse.Activity.Get.');
        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"A","colour":"red"}]}'), 'UnknownParameter', '');
        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"A","quantity":"one"}]}'), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send('{"activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"A"},{"lineNo":10000,"lotNo":"B"}]}'), 'InvalidParameter', 'Send quantity on every entry of the line.');
    end;

    /// <summary>AC07: without activity write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure AssignTracking_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        TrackImpl: Codeunit "Whse ActLine Track Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.ActivityLine.AssignTracking";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'AssignTracking must be disabled without activity write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        TrackImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    /// <summary>#68 items 3 and 4: the availability refusal names only the sent numbers, counts entries from 1 and names a read that exists (1033).</summary>
    [Test]
    procedure AssignTracking_LotNotInTakeBin_TextAndNextStep()
    begin
        // Issue #68, AC1 (items 3, 4) | Time: none | Risk: none.
        AssertNotAvailableTexts(1033, 'Bin %1 holds 0 base units of item %2 with lot LOT-NONE that can be taken; entry 1 needs 2.', 'Entry 1 has no lot, serial or package number.',
            'Read Inventory.TrackingAvailability.Get for the item.', 'Read the warehouse entries of the bin and item with Data.Records.Get on table Warehouse Entry.');
    end;

    /// <summary>#68 items 3 and 4: the same in Icelandic (1039).</summary>
    [Test]
    procedure AssignTracking_LotNotInTakeBin_TextAndNextStepInIcelandic()
    begin
        // Issue #68, AC1 (items 3, 4) | Time: none | Risk: none.
        AssertNotAvailableTexts(1039, 'Hólf %1 geymir 0 grunneiningar af vöru %2 með lotu LOT-NONE sem má taka; færsla 1 þarf 2.', 'Færsla 1 hefur ekkert lotu-, rað- eða pakkanúmer.',
            'Lestu Inventory.TrackingAvailability.Get fyrir vöruna.', 'Lestu vöruhúsafærslur hólfsins og vörunnar með Data.Records.Get á töflunni Warehouse Entry.');
    end;

    /// <summary>#68 item 4: the roster check finds a type that exists and is enabled, and no type that is not installed.</summary>
    [Test]
    procedure IsTypeInRoster_KnownAndUnknownTypes()
    var
        Values: Codeunit "Whse Msg Values ori";
    begin
        // Issue #68, AC1 (item 4) | Time: none | Risk: none.
        Assert.IsTrue(Values.IsTypeInRoster('Warehouse.Bin.Get'), 'An installed, enabled type is in the roster.');
        Assert.IsFalse(Values.IsTypeInRoster('Warehouse.NoSuch.Type'), 'A type no app declares is not in the roster.');
    end;

    local procedure AssertNotAvailableTexts(LanguageId: Integer; ExpectedPattern: Text; NoNumberText: Text; InventoryNextStep: Text; EntriesNextStep: Text)
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        Values: Codeunit "Whse Msg Values ori";
        ResponseJson: JsonObject;
        ActivityNo: Code[20];
        ExpectedNextStep: Text;
    begin
        Helper.CreateDirectedLocation(Location);
        LibraryItemTracking.CreateLotItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        ActivityNo := Helper.CreateRawActivity("Warehouse Activity Type"::Movement, "Warehouse Action Type"::Take, Location.Code, Item."No.", Bin."Zone Code", Bin.Code, 2);
        // Warehouse does not depend on Bifrost Inventory: its type is named only when it is in the roster.
        if Values.IsTypeInRoster('Inventory.TrackingAvailability.Get') then
            ExpectedNextStep := InventoryNextStep
        else
            ExpectedNextStep := EntriesNextStep;

        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.ActivityLine.AssignTracking", '', '{"activityType":"Movement","activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"lotNo":"LOT-NONE"}]}', LanguageId);

        Helper.ExpectError(ResponseJson, 'InvalidLine', ExpectedNextStep);
        Assert.AreEqual(StrSubstNo(ExpectedPattern, Bin.Code, Item."No."), Helper.TextValue(ResponseJson, 'error'), 'Only the sent numbers, the entry counted from 1.');
        Assert.AreEqual('entries[0].lotNo', Helper.TextValue(ResponseJson, 'parameter'), 'The parameter names the key that was sent.');
        if LanguageId = 1033 then
            ContractAssert.AssertAnswerDeclared(Enum::"Message Type ori"::"Warehouse.ActivityLine.AssignTracking", ResponseJson);

        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.ActivityLine.AssignTracking", '', '{"activityType":"Movement","activityNo":"' + ActivityNo + '","entries":[{"lineNo":10000,"quantity":1}]}', LanguageId);

        Assert.AreEqual(NoNumberText, Helper.TextValue(ResponseJson, 'error'), 'The entry is counted from 1.');
    end;

    local procedure CreatePutAway(ItemNo: Code[20]; Quantity: Decimal): Code[20]
    var
        Location: Record Location;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, true, false, true, false);
        exit(Helper.CreateRawActivity("Warehouse Activity Type"::"Put-away", "Warehouse Action Type"::Place, Location.Code, ItemNo, '', '', Quantity));
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.ActivityLine.AssignTracking", '', RequestText));
    end;
}
