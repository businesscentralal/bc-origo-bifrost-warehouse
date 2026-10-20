namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.PhysInventory.Calculate (#49): calculated lines, refusals and the permission path.
/// </summary>
codeunit 97053 "Whse PhysInvt Calc Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC01: the calculation answers one line per bin content with the calculated quantity.</summary>
    [Test]
    procedure Calculate_StockedBin_AnswersCalculatedLine()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.StockBin(Bin, Item."No.", 5);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::"Physical Inventory", Location.Code, JournalBatch);

        ResponseJson := Send(Request(JournalBatch, ',"itemNo":"' + Item."No." + '","documentNo":"COUNT-01","registeringDate":"2026-10-19"'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'lineCount'), Helper.ResponseText(ResponseJson));
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual(Item."No.", Helper.TextValue(LineJson, 'itemNo'), 'Item.');
        Assert.AreEqual(Bin.Code, Helper.TextValue(LineJson, 'binCode'), 'Bin.');
        Assert.AreEqual(5, Helper.DecimalValue(LineJson, 'qtyCalculated'), 'Calculated quantity.');
        Assert.AreEqual('COUNT-01', Helper.TextValue(LineJson, 'whseDocumentNo'), 'Document number.');
        Assert.AreEqual('2026-10-19', Helper.TextValue(LineJson, 'registeringDate'), 'Registering date.');
    end;

    /// <summary>Edge: nothing to count answers success with an empty list.</summary>
    [Test]
    procedure Calculate_NothingToCount_AnswersEmptyList()
    var
        Location: Record Location;
        Item: Record Item;
        JournalBatch: Record "Warehouse Journal Batch";
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::"Physical Inventory", Location.Code, JournalBatch);

        ResponseJson := Send(Request(JournalBatch, ',"itemNo":"' + Item."No." + '","documentNo":"COUNT-02"'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(0, Helper.IntegerValue(ResponseJson, 'lineCount'), 'Nothing to count writes no line.');
    end;

    /// <summary>AC03: a basic location is PreconditionFailed with the Inventory.PhysInventory next step.</summary>
    [Test]
    procedure Calculate_BasicLocation_PreconditionFailed()
    var
        Location: Record Location;
    begin
        Helper.CreateBasicLocation(Location);

        Helper.ExpectError(Send('{"journalTemplateName":"PHYS","journalBatchName":"DEFAULT","locationCode":"' + Location.Code + '","documentNo":"X"}'), 'PreconditionFailed', 'Use Inventory.PhysInventory.* for basic locations.');
    end;

    /// <summary>AC05: unknown batch, missing documentNo, wrong template type, bad date and unknown key.</summary>
    [Test]
    procedure Calculate_Refusals_AnswerCodesWithNextStep()
    var
        Location: Record Location;
        JournalBatch: Record "Warehouse Journal Batch";
        ItemBatch: Record "Warehouse Journal Batch";
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::"Physical Inventory", Location.Code, JournalBatch);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, ItemBatch);

        Helper.ExpectError(Send('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"NOBATCH","locationCode":"' + Location.Code + '","documentNo":"X"}'), 'RecordNotFound', 'Create the batch first.');
        Helper.ExpectError(Send(Request(JournalBatch, '')), 'MissingParameter', 'Send documentNo, or give the batch a number series.');
        Helper.ExpectError(Send(Request(ItemBatch, ',"documentNo":"X"')), 'InvalidParameter', 'Use a physical inventory template, or Warehouse.Journal.Create for item and reclassification journals.');
        Helper.ExpectError(Send(Request(JournalBatch, ',"documentNo":"X","registeringDate":"19.10.2026"')), 'InvalidParameterFormat', 'Send the date as YYYY-MM-DD.');
        Helper.ExpectError(Send(Request(JournalBatch, ',"documentNo":"X","shelf":"A"')), 'UnknownParameter', '');
        Helper.ExpectError(Send(Request(JournalBatch, ',"documentNo":"X","itemNo":"NO-SUCH-ITEM"')), 'RecordNotFound', '');
        Helper.ExpectError(Helper.RunType(Enum::"Message Type ori"::"Warehouse.PhysInventory.Calculate", 'OTHERLOC', Request(JournalBatch, ',"documentNo":"X"')), 'ConflictingIdentifiers', '');
    end;

    /// <summary>AC07: without journal write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Calculate_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CalcImpl: Codeunit "Whse PhysInvt Calc Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.PhysInventory.Calculate";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Calculate must be disabled without journal write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CalcImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.PhysInventory.Calculate", '', RequestText));
    end;

    local procedure Request(JournalBatch: Record "Warehouse Journal Batch"; Extra: Text): Text
    begin
        exit('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + JournalBatch."Location Code" + '"' + Extra + '}');
    end;
}
