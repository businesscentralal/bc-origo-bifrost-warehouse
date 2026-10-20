namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Adjustment.Calculate (#50): item journal lines for registered warehouse adjustments, refusals and the permission path.
/// </summary>
codeunit 97055 "Whse Adjustment Calc Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>AC01: a registered warehouse adjustment becomes a positive item journal line.</summary>
    [Test]
    procedure Calculate_RegisteredAdjustment_AnswersItemJournalLine()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        ItemJournalBatch: Record "Item Journal Batch";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        LibraryWarehouse.UpdateWarehouseStockOnBin(Bin, Item."No.", 5, false);
        CreateItemJournalBatch(ItemJournalBatch);

        ResponseJson := Send(Request(ItemJournalBatch, ',"itemNo":"' + Item."No." + '","locationCode":"' + Location.Code + '","documentNo":"ADJ-01","postingDate":"2026-10-19"'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'lineCount'), Helper.ResponseText(ResponseJson));
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual(Item."No.", Helper.TextValue(LineJson, 'itemNo'), 'Item.');
        Assert.AreEqual(Location.Code, Helper.TextValue(LineJson, 'locationCode'), 'Location.');
        Assert.AreEqual('Positive Adjmt.', Helper.TextValue(LineJson, 'entryType'), 'Entry type.');
        Assert.AreEqual(5, Helper.DecimalValue(LineJson, 'quantity'), 'Quantity.');
        Assert.AreEqual('ADJ-01', Helper.TextValue(LineJson, 'documentNo'), 'Document number.');
        Assert.AreEqual('2026-10-19', Helper.TextValue(LineJson, 'postingDate'), 'Posting date.');
    end;

    /// <summary>AC05: nothing to adjust answers success with an empty list.</summary>
    [Test]
    procedure Calculate_NothingToAdjust_AnswersEmptyList()
    var
        Item: Record Item;
        ItemJournalBatch: Record "Item Journal Batch";
        ItemJournalLine: Record "Item Journal Line";
        ResponseJson: JsonObject;
    begin
        Helper.CreateItem(Item);
        CreateItemJournalBatch(ItemJournalBatch);

        ResponseJson := Send(Request(ItemJournalBatch, ',"itemNo":"' + Item."No." + '","documentNo":"ADJ-02"'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(0, Helper.IntegerValue(ResponseJson, 'lineCount'), 'Nothing to adjust writes no line.');
        ItemJournalLine.SetRange("Journal Template Name", ItemJournalBatch."Journal Template Name");
        ItemJournalLine.SetRange("Journal Batch Name", ItemJournalBatch.Name);
        Assert.IsTrue(ItemJournalLine.IsEmpty(), 'The batch stays empty.');
    end;

    /// <summary>AC02: an unknown template or batch is RecordNotFound with the create-the-batch next step.</summary>
    [Test]
    procedure Calculate_UnknownBatch_RecordNotFound()
    var
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        CreateItemJournalBatch(ItemJournalBatch);

        Helper.ExpectError(Send('{"journalTemplateName":"' + ItemJournalBatch."Journal Template Name" + '","journalBatchName":"NOBATCH","documentNo":"X"}'), 'RecordNotFound', 'Create the batch first.');
        Helper.ExpectError(Send('{"journalTemplateName":"NOTEMPLATE","journalBatchName":"NOBATCH","documentNo":"X"}'), 'RecordNotFound', 'Create the batch first.');
    end;

    /// <summary>AC03: a batch that already has lines is PreconditionFailed and nothing is written.</summary>
    [Test]
    procedure Calculate_BatchWithLines_PreconditionFailed()
    var
        Item: Record Item;
        ItemJournalBatch: Record "Item Journal Batch";
        ItemJournalLine: Record "Item Journal Line";
    begin
        Helper.CreateItem(Item);
        CreateItemJournalBatch(ItemJournalBatch);
        LibraryInventory.CreateItemJournalLine(ItemJournalLine, ItemJournalBatch."Journal Template Name", ItemJournalBatch.Name, ItemJournalLine."Entry Type"::"Positive Adjmt.", Item."No.", 1);

        Helper.ExpectError(Send(Request(ItemJournalBatch, ',"documentNo":"X"')), 'PreconditionFailed', 'Post or delete the existing lines first.');
        ItemJournalLine.SetRange("Journal Template Name", ItemJournalBatch."Journal Template Name");
        ItemJournalLine.SetRange("Journal Batch Name", ItemJournalBatch.Name);
        Assert.AreEqual(1, ItemJournalLine.Count(), 'Nothing is written.');
    end;

    /// <summary>AC04: missing, wrongly typed and unknown keys, an unknown item and a basic location.</summary>
    [Test]
    procedure Calculate_CommonRefusals_AnswerCodesWithNextStep()
    var
        Location: Record Location;
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        CreateItemJournalBatch(ItemJournalBatch);
        Helper.CreateBasicLocation(Location);

        Helper.ExpectError(Send('{"journalBatchName":"' + ItemJournalBatch.Name + '"}'), 'MissingParameter', 'Send journalTemplateName and journalBatchName.');
        Helper.ExpectError(Send(Request(ItemJournalBatch, ',"documentNo":"X","postingDate":20261019')), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(Request(ItemJournalBatch, ',"documentNo":"X","variantCode":"A"')), 'UnknownParameter', '');
        Helper.ExpectError(Send(Request(ItemJournalBatch, ',"documentNo":"X","itemNo":"NO-SUCH-ITEM"')), 'RecordNotFound', 'Check the value and send the request again.');
        Helper.ExpectError(Send(Request(ItemJournalBatch, ',"documentNo":"X","locationCode":"' + Location.Code + '"')), 'PreconditionFailed', 'Send a directed location, or omit locationCode.');
        Helper.ExpectError(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Adjustment.Calculate", 'OTHERLOC', Request(ItemJournalBatch, ',"documentNo":"X","locationCode":"' + Location.Code + '"')), 'ConflictingIdentifiers', '');
    end;

    /// <summary>AC06: without item journal write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Calculate_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CalcImpl: Codeunit "Whse Adjustment Calc Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Adjustment.Calculate";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Calculate must be disabled without item journal write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CalcImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    local procedure CreateItemJournalBatch(var ItemJournalBatch: Record "Item Journal Batch")
    var
        ItemJournalTemplate: Record "Item Journal Template";
    begin
        LibraryInventory.SelectItemJournalTemplateName(ItemJournalTemplate, ItemJournalTemplate.Type::Item);
        LibraryInventory.CreateItemJournalBatch(ItemJournalBatch, ItemJournalTemplate.Name);
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Adjustment.Calculate", '', RequestText));
    end;

    local procedure Request(ItemJournalBatch: Record "Item Journal Batch"; Extra: Text): Text
    begin
        exit('{"journalTemplateName":"' + ItemJournalBatch."Journal Template Name" + '","journalBatchName":"' + ItemJournalBatch.Name + '"' + Extra + '}');
    end;
}
