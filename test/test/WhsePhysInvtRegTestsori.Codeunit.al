namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Ledger;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.PhysInventory.Register (#49): counted differences, a count without differences, refusals and the posting gate.
/// </summary>
codeunit 97054 "Whse PhysInvt Reg Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC02: a counted quantity below the calculated one registers a negative adjustment.</summary>
    [Test]
    procedure Register_CountedDifference_AnswersAdjustedLine()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        WarehouseEntry: Record "Warehouse Entry";
        ResponseJson: JsonObject;
        AdjustedJson: JsonObject;
        LineNo: Integer;
    begin
        LineNo := CalculateCount(Location, Item, Bin, JournalBatch);

        ResponseJson := Send(BatchKeys(JournalBatch, ',"lines":[{"lineNo":' + Format(LineNo, 0, 9) + ',"qtyPhysInventory":3}]'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'adjustmentCount'), Helper.ResponseText(ResponseJson));
        AdjustedJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'adjustedLines'), 0);
        Assert.AreEqual(5, Helper.DecimalValue(AdjustedJson, 'qtyCalculated'), 'Calculated quantity.');
        Assert.AreEqual(3, Helper.DecimalValue(AdjustedJson, 'qtyPhysInventory'), 'Counted quantity.');
        Assert.AreEqual(-2, Helper.DecimalValue(AdjustedJson, 'quantity'), 'The difference is registered.');
        Assert.IsTrue(Helper.IntegerValue(ResponseJson, 'registerNo') > 0, 'A warehouse register is answered.');
        WarehouseEntry.SetRange("Item No.", Item."No.");
        WarehouseEntry.SetRange("Bin Code", Bin.Code);
        WarehouseEntry.CalcSums(Quantity);
        Assert.AreEqual(3, WarehouseEntry.Quantity, 'The bin holds the counted quantity.');
    end;

    /// <summary>AC06: a count without differences registers with zero adjustments.</summary>
    [Test]
    procedure Register_NoDifferences_ZeroAdjustments()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        JournalLine: Record "Warehouse Journal Line";
        ResponseJson: JsonObject;
    begin
        CalculateCount(Location, Item, Bin, JournalBatch);

        ResponseJson := Send(BatchKeys(JournalBatch, ''));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(0, Helper.IntegerValue(ResponseJson, 'adjustmentCount'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'registeredLineCount'), 'The count line is registered.');
        JournalLine.SetRange("Journal Template Name", JournalBatch."Journal Template Name");
        JournalLine.SetRange("Journal Batch Name", JournalBatch.Name);
        Assert.IsTrue(JournalLine.IsEmpty(), 'The registered lines are deleted.');
    end;

    /// <summary>AC04: a counted line number that is not in the batch is InvalidLine and nothing is written.</summary>
    [Test]
    procedure Register_LineNotInBatch_InvalidLine()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        JournalLine: Record "Warehouse Journal Line";
        LineNo: Integer;
    begin
        LineNo := CalculateCount(Location, Item, Bin, JournalBatch);

        Helper.ExpectError(Send(BatchKeys(JournalBatch, ',"lines":[{"lineNo":999999,"qtyPhysInventory":3}]')), 'InvalidLine', 'Read the lines answered by Calculate.');
        JournalLine.Get(JournalBatch."Journal Template Name", JournalBatch.Name, Location.Code, LineNo);
        Assert.AreEqual(5, JournalLine."Qty. (Phys. Inventory)", 'The count is not written.');
    end;

    /// <summary>AC03: a basic location is PreconditionFailed.</summary>
    [Test]
    procedure Register_BasicLocation_PreconditionFailed()
    var
        Location: Record Location;
    begin
        Helper.CreateBasicLocation(Location);

        Helper.ExpectError(Send('{"journalTemplateName":"PHYS","journalBatchName":"DEFAULT","locationCode":"' + Location.Code + '"}'), 'PreconditionFailed', 'Use Inventory.PhysInventory.* for basic locations.');
    end;

    /// <summary>AC05: empty batch, negative count, missing key, wrong type and unknown key.</summary>
    [Test]
    procedure Register_Refusals_AnswerCodesWithNextStep()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        EmptyBatch: Record "Warehouse Journal Batch";
        LineNo: Integer;
    begin
        LineNo := CalculateCount(Location, Item, Bin, JournalBatch);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::"Physical Inventory", Location.Code, EmptyBatch);

        Helper.ExpectError(Send(BatchKeys(EmptyBatch, '')), 'PreconditionFailed', 'Write the lines with Warehouse.PhysInventory.Calculate first.');
        Helper.ExpectError(Send(BatchKeys(JournalBatch, ',"lines":[{"lineNo":' + Format(LineNo, 0, 9) + ',"qtyPhysInventory":-1}]')), 'InvalidParameter', 'Send the counted quantity, zero or more.');
        Helper.ExpectError(Send(BatchKeys(JournalBatch, ',"lines":[{"lineNo":' + Format(LineNo, 0, 9) + '}]')), 'MissingParameter', 'Send lineNo and qtyPhysInventory on every line.');
        Helper.ExpectError(Send(BatchKeys(JournalBatch, ',"lines":[{"lineNo":"one","qtyPhysInventory":1}]')), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(BatchKeys(JournalBatch, ',"lines":[{"lineNo":' + Format(LineNo, 0, 9) + ',"qtyPhysInventory":1,"note":"x"}]')), 'UnknownParameter', '');
    end;

    /// <summary>AC07: without journal write permission the type answers PermissionDenied naming the full set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Register_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        RegisterImpl: Codeunit "Whse PhysInvt Reg Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.PhysInventory.Register";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Register must be disabled without journal write permission.');
        PrepareArgument(TempArgument);
        RegisterImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    /// <summary>AC07: without the posting gate the answer names BIFROST WhsePost ori.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Register_WithoutPostingGate_NamesWhsePost()
    var
        TempArgument: Record "Message Argument ori" temporary;
        RegisterImpl: Codeunit "Whse PhysInvt Reg Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('BIFROST Full ori');
        LibraryLowerPermissions.AddPermissionSet('Whse JnlGate Tst ori');
        Assert.IsFalse(RegisterImpl.IsEnabled(), 'Register must be disabled without BIFROST WhsePost ori.');
        PrepareArgument(TempArgument);
        RegisterImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign the BIFROST WhsePost ori permission set.');
    end;

    local procedure CalculateCount(var Location: Record Location; var Item: Record Item; var Bin: Record Bin; var JournalBatch: Record "Warehouse Journal Batch"): Integer
    var
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.StockBin(Bin, Item."No.", 5);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::"Physical Inventory", Location.Code, JournalBatch);
        ResponseJson := Helper.RunType(Enum::"Message Type ori"::"Warehouse.PhysInventory.Calculate", '', BatchKeys(JournalBatch, ',"itemNo":"' + Item."No." + '","documentNo":"COUNT-R"'));
        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'lineCount'), Helper.ResponseText(ResponseJson));
        exit(Helper.IntegerValue(Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0), 'lineNo'));
    end;

    local procedure PrepareArgument(var TempArgument: Record "Message Argument ori" temporary)
    begin
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.PhysInventory.Register", '', RequestText));
    end;

    local procedure BatchKeys(JournalBatch: Record "Warehouse Journal Batch"; Extra: Text): Text
    begin
        exit('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + JournalBatch."Location Code" + '"' + Extra + '}');
    end;
}
