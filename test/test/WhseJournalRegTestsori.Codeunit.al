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
/// Tests Warehouse.Journal.Register (#48): register number and entry range, refusals, the posting gate.
/// </summary>
codeunit 97052 "Whse Journal Reg Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC02: registering an item journal batch answers the register and its entry range and empties the batch.</summary>
    [Test]
    procedure Register_ItemJournal_AnswersRegisterAndEntries()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        JournalLine: Record "Warehouse Journal Line";
        WarehouseEntry: Record "Warehouse Entry";
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);
        Helper.AssertSuccess(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Journal.Create", '', '{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":5}]}'));

        ResponseJson := Send(BatchKeys(JournalBatch));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'registeredLineCount'), 'One line is registered.');
        Assert.IsTrue(Helper.IntegerValue(ResponseJson, 'registerNo') > 0, 'A warehouse register is answered.');
        Assert.IsTrue(Helper.IntegerValue(ResponseJson, 'fromEntryNo') > 0, 'The entry range starts.');
        Assert.IsTrue(Helper.IntegerValue(ResponseJson, 'toEntryNo') >= Helper.IntegerValue(ResponseJson, 'fromEntryNo'), 'The entry range ends.');
        Assert.AreEqual(2, Helper.IntegerValue(ResponseJson, 'entryCount'), 'A positive adjustment writes the bin entry and the adjustment bin entry.');
        JournalLine.SetRange("Journal Template Name", JournalBatch."Journal Template Name");
        JournalLine.SetRange("Journal Batch Name", JournalBatch.Name);
        JournalLine.SetFilter("Item No.", '<>%1', '');
        Assert.IsTrue(JournalLine.IsEmpty(), 'The registered lines are deleted.');
        WarehouseEntry.SetRange("Item No.", Item."No.");
        WarehouseEntry.SetRange("Bin Code", Bin.Code);
        WarehouseEntry.CalcSums(Quantity);
        Assert.AreEqual(5, WarehouseEntry.Quantity, 'The bin holds the quantity.');
    end;

    /// <summary>AC02: registering a reclassification batch moves the quantity between the bins.</summary>
    [Test]
    procedure Register_Reclassification_MovesBetweenBins()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        WarehouseEntry: Record "Warehouse Entry";
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, FromBin);
        Helper.FindPickBin(Location.Code, 2, ToBin);
        Helper.StockBin(FromBin, Item."No.", 5);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Reclassification, Location.Code, JournalBatch);
        Helper.AssertSuccess(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Journal.Create", '', '{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '","quantity":2}]}'));

        Helper.AssertSuccess(Send(BatchKeys(JournalBatch)));

        WarehouseEntry.SetRange("Item No.", Item."No.");
        WarehouseEntry.SetRange("Bin Code", ToBin.Code);
        WarehouseEntry.CalcSums(Quantity);
        Assert.AreEqual(2, WarehouseEntry.Quantity, 'The to bin receives the quantity.');
        WarehouseEntry.SetRange("Bin Code", FromBin.Code);
        WarehouseEntry.CalcSums(Quantity);
        Assert.AreEqual(3, WarehouseEntry.Quantity, 'The from bin keeps the rest.');
    end;

    /// <summary>AC07: an empty batch is PreconditionFailed with the add-lines next step.</summary>
    [Test]
    procedure Register_EmptyBatch_PreconditionFailed()
    var
        Location: Record Location;
        JournalBatch: Record "Warehouse Journal Batch";
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        Helper.ExpectError(Send(BatchKeys(JournalBatch)), 'PreconditionFailed', 'Add lines with Warehouse.Journal.Create.');
    end;

    /// <summary>AC03: a basic location is refused before anything is registered.</summary>
    [Test]
    procedure Register_BasicLocation_PreconditionFailed()
    var
        Location: Record Location;
    begin
        Helper.CreateBasicLocation(Location);

        Helper.ExpectError(Send('{"journalTemplateName":"ITEM","journalBatchName":"DEFAULT","locationCode":"' + Location.Code + '"}'), 'PreconditionFailed', 'Use Inventory.ItemJournal.* or Inventory.Reclassification.* for basic locations.');
    end;

    /// <summary>AC05 and AC06: unknown batch, missing key, unknown key and a physical inventory template.</summary>
    [Test]
    procedure Register_Refusals_AnswerCodesWithNextStep()
    var
        Location: Record Location;
        JournalBatch: Record "Warehouse Journal Batch";
        PhysBatch: Record "Warehouse Journal Batch";
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::"Physical Inventory", Location.Code, PhysBatch);

        Helper.ExpectError(Send('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"NOBATCH","locationCode":"' + Location.Code + '"}'), 'RecordNotFound', 'Create the batch first.');
        Helper.ExpectError(Send('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","locationCode":"' + Location.Code + '"}'), 'MissingParameter', '');
        Helper.ExpectError(Send('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + Location.Code + '","post":true}'), 'UnknownParameter', '');
        Helper.ExpectError(Send('{"journalTemplateName":7,"journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + Location.Code + '"}'), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(BatchKeys(PhysBatch)), 'InvalidParameter', 'Use Warehouse.PhysInventory.Calculate and Warehouse.PhysInventory.Register for a physical inventory journal.');
    end;

    /// <summary>AC08: without journal write permission the type is disabled and answers PermissionDenied naming the full set.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Register_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        RegisterImpl: Codeunit "Whse Journal Reg Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Journal.Register";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Register must be disabled without journal write permission.');
        PrepareArgument(TempArgument);
        RegisterImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    /// <summary>AC08: with journal write permission but without the posting gate the answer names BIFROST WhsePost ori.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Register_WithoutPostingGate_NamesWhsePost()
    var
        TempArgument: Record "Message Argument ori" temporary;
        RegisterImpl: Codeunit "Whse Journal Reg Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('BIFROST Full ori');
        LibraryLowerPermissions.AddPermissionSet('Whse JnlGate Tst ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Journal.Register";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Register must be disabled without BIFROST WhsePost ori.');
        PrepareArgument(TempArgument);
        RegisterImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign the BIFROST WhsePost ori permission set.');
    end;

    local procedure PrepareArgument(var TempArgument: Record "Message Argument ori" temporary)
    begin
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Journal.Register", '', RequestText));
    end;

    local procedure BatchKeys(JournalBatch: Record "Warehouse Journal Batch"): Text
    begin
        exit('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + JournalBatch."Location Code" + '"}');
    end;
}
