namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Tracking;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Journal.Create (#48): item and reclassification lines, refusals and the permission path.
/// </summary>
codeunit 97051 "Whse Journal Create Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC01: an item journal line is inserted through Validate against the adjustment bin.</summary>
    [Test]
    procedure Create_ItemJournalLine_InsertedThroughValidate()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        JournalLine: Record "Warehouse Journal Line";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":5}]'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.ArrayValue(ResponseJson, 'lineNos').Count(), 'One line number should be answered.');
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual('Positive Adjmt.', Helper.TextValue(LineJson, 'entryType'), 'A positive quantity is a positive adjustment.');
        Assert.AreEqual(Bin.Code, Helper.TextValue(LineJson, 'toBin'), 'The bin receives the quantity.');
        Assert.AreEqual(Location."Adjustment Bin Code", Helper.TextValue(LineJson, 'fromBin'), 'The adjustment bin gives the quantity.');
        JournalLine.Get(JournalBatch."Journal Template Name", JournalBatch.Name, Location.Code, Helper.IntegerValue(LineJson, 'lineNo'));
        Assert.AreEqual(5, JournalLine.Quantity, 'The line holds the quantity.');
        Assert.AreEqual(Bin."Zone Code", JournalLine."Zone Code", 'Validate fills the zone of the bin.');
    end;

    /// <summary>AC01: a reclassification line moves a lot between two bins and carries a tracking line.</summary>
    [Test]
    procedure Create_ReclassLineWithLot_InsertsTrackingLine()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        StockBatch: Record "Warehouse Journal Batch";
        JournalBatch: Record "Warehouse Journal Batch";
        TrackingLine: Record "Whse. Item Tracking Line";
        LibraryItemTracking: Codeunit "Library - Item Tracking";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        LibraryItemTracking.CreateLotItem(Item);
        Helper.FindPickBin(Location.Code, 1, FromBin);
        Helper.FindPickBin(Location.Code, 2, ToBin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, StockBatch);
        Helper.AssertSuccess(Send(BatchRequest(StockBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + FromBin.Code + '","quantity":4,"lotNo":"LOT-R1"}]')));
        Helper.AssertSuccess(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Journal.Register", '', BatchKeys(StockBatch)));
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Reclassification, Location.Code, JournalBatch);

        ResponseJson := Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '","quantity":3,"lotNo":"LOT-R1"}]'));

        Helper.AssertSuccess(ResponseJson);
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual('Movement', Helper.TextValue(LineJson, 'entryType'), 'A reclassification line is a movement.');
        Assert.AreEqual(FromBin.Code, Helper.TextValue(LineJson, 'fromBin'), 'From bin.');
        Assert.AreEqual(ToBin.Code, Helper.TextValue(LineJson, 'toBin'), 'To bin.');
        TrackingLine.SetRange("Source Type", Database::"Warehouse Journal Line");
        TrackingLine.SetRange("Source ID", JournalBatch.Name);
        TrackingLine.SetRange("Source Batch Name", JournalBatch."Journal Template Name");
        TrackingLine.SetRange("Source Ref. No.", Helper.IntegerValue(LineJson, 'lineNo'));
        Assert.IsTrue(TrackingLine.FindFirst(), 'The lot goes on a warehouse item tracking line.');
        Assert.AreEqual('LOT-R1', TrackingLine."Lot No.", 'Lot.');
        Assert.AreEqual('LOT-R1', TrackingLine."New Lot No.", 'A reclassification keeps the lot.');
        Assert.AreEqual(3, TrackingLine."Quantity (Base)", 'Tracked quantity.');
    end;

    /// <summary>AC03: a location without directed put-away and pick is refused and nothing is written.</summary>
    [Test]
    procedure Create_BasicLocation_PreconditionFailed()
    var
        Location: Record Location;
        Item: Record Item;
        JournalLine: Record "Warehouse Journal Line";
        ResponseJson: JsonObject;
    begin
        Helper.CreateBasicLocation(Location);
        Helper.CreateItem(Item);
        JournalLine.SetRange("Location Code", Location.Code);

        ResponseJson := Send('{"journalTemplateName":"ITEM","journalBatchName":"DEFAULT","locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","binCode":"B1","quantity":1}]}');

        Helper.ExpectError(ResponseJson, 'PreconditionFailed', 'Use Inventory.ItemJournal.* or Inventory.Reclassification.* for basic locations.');
        Assert.IsTrue(JournalLine.IsEmpty(), 'Nothing is written.');
    end;

    /// <summary>AC04: a negative adjustment larger than the bin content is refused and nothing is written.</summary>
    [Test]
    procedure Create_NegativeAboveBinContent_InvalidLine()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        JournalLine: Record "Warehouse Journal Line";
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.StockBin(Bin, Item."No.", 2);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":-5}]'));

        Helper.ExpectError(ResponseJson, 'InvalidLine', 'Read Warehouse.BinContent.Get.');
        JournalLine.SetRange("Journal Template Name", JournalBatch."Journal Template Name");
        JournalLine.SetRange("Journal Batch Name", JournalBatch.Name);
        Assert.IsTrue(JournalLine.IsEmpty(), 'Nothing is written.');
    end;

    /// <summary>Edge: a negative adjustment within the bin content is a negative adjustment line.</summary>
    [Test]
    procedure Create_NegativeWithinBinContent_IsNegativeAdjustment()
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
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":-2}]'));

        Helper.AssertSuccess(ResponseJson);
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual('Negative Adjmt.', Helper.TextValue(LineJson, 'entryType'), 'A negative quantity is a negative adjustment.');
        Assert.AreEqual(Bin.Code, Helper.TextValue(LineJson, 'fromBin'), 'The bin gives the quantity.');
    end;

    /// <summary>AC05: an unknown batch is RecordNotFound with the create-the-batch next step.</summary>
    [Test]
    procedure Create_UnknownBatch_RecordNotFound()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Send('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"NOBATCH","locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":1}]}');

        Helper.ExpectError(ResponseJson, 'RecordNotFound', 'Create the batch first.');
    end;

    /// <summary>AC06: missing, wrongly typed and unknown keys answer their codes with a next step.</summary>
    [Test]
    procedure Create_CommonRefusals_AnswerCodesWithNextStep()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        Helper.ExpectError(Send('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":1}]}'), 'MissingParameter', '');
        Helper.ExpectError(Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":"five"}]')), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":1,"colour":"red"}]')), 'UnknownParameter', '');
        Helper.ExpectError(Send(BatchRequest(JournalBatch, '[{"itemNo":"NO-SUCH-ITEM","binCode":"' + Bin.Code + '","quantity":1}]')), 'RecordNotFound', '');
        Helper.ExpectError(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Journal.Create", 'OTHERLOC', BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":1}]')), 'ConflictingIdentifiers', '');
        Helper.ExpectError(Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","zoneCode":"BULK","quantity":1}]')), 'ConflictingIdentifiers', 'Send a zone that holds the bin, or omit zoneCode.');
    end;

    /// <summary>Edge: one failing line among valid ones writes nothing.</summary>
    [Test]
    procedure Create_OneFailingLine_WritesNothing()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        JournalLine: Record "Warehouse Journal Line";
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":1},{"itemNo":"' + Item."No." + '","binCode":"NO-SUCH-BIN","quantity":1}]'));

        Helper.ExpectError(ResponseJson, 'RecordNotFound', 'Check the bin with Warehouse.Bin.Get.');
        JournalLine.SetRange("Journal Template Name", JournalBatch."Journal Template Name");
        JournalLine.SetRange("Journal Batch Name", JournalBatch.Name);
        Assert.IsTrue(JournalLine.IsEmpty(), 'Nothing is written when one line fails.');
    end;

    /// <summary>Edge: a serial number for more than one base unit is InvalidLine.</summary>
    [Test]
    procedure Create_SerialForTwoUnits_InvalidLine()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        LibraryItemTracking: Codeunit "Library - Item Tracking";
    begin
        Helper.CreateDirectedLocation(Location);
        LibraryItemTracking.CreateSerialItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        Helper.ExpectError(Send(BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":2,"serialNo":"SN-1"}]')), 'InvalidLine', 'Send one line per serial number with quantity 1.');
    end;

    /// <summary>AC08: without warehouse journal write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CreateImpl: Codeunit "Whse Journal Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Journal.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without journal write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    /// <summary>#68 item 2: the answer echoes the lot that went on the warehouse item tracking line (1033).</summary>
    [Test]
    procedure Create_LineWithLot_EchoesLotNo()
    begin
        // Issue #68, AC1 (item 2) | Time: none | Risk: none.
        AssertLotEchoed(1033);
    end;

    /// <summary>#68 item 2: the same in Icelandic (1039).</summary>
    [Test]
    procedure Create_LineWithLot_EchoesLotNoInIcelandic()
    begin
        // Issue #68, AC1 (item 2) | Time: none | Risk: none.
        AssertLotEchoed(1039);
    end;

    /// <summary>#68 item 3: a refusal names the request line counted from 1 (1033).</summary>
    [Test]
    procedure Create_NegativeAboveBinContent_CountsLinesFromOne()
    begin
        // Issue #68, AC1 (item 3) | Time: none | Risk: none.
        AssertLineCountedFromOne(1033, 'Bin %1 holds 2 base units of item %2 that can be taken; line 1 asks for 5.');
    end;

    /// <summary>#68 item 3: the same in Icelandic (1039).</summary>
    [Test]
    procedure Create_NegativeAboveBinContent_CountsLinesFromOneInIcelandic()
    begin
        // Issue #68, AC1 (item 3) | Time: none | Risk: none.
        AssertLineCountedFromOne(1039, 'Hólf %1 geymir 2 grunneiningar af vöru %2 sem má taka; lína 1 biður um 5.');
    end;

    /// <summary>#68 item 5: an unknown batch no longer hides an unknown key, a format error and a missing bin (1033).</summary>
    [Test]
    procedure Create_IndependentProblems_AreCollected()
    begin
        // Issue #68, AC1 (item 5) | Time: none | Risk: none.
        AssertIndependentProblems(1033, 'Nothing was written.', 'Line 1 is missing binCode.');
    end;

    /// <summary>#68 item 5: the same in Icelandic (1039).</summary>
    [Test]
    procedure Create_IndependentProblems_AreCollectedInIcelandic()
    begin
        // Issue #68, AC1 (item 5) | Time: none | Risk: none.
        AssertIndependentProblems(1039, 'Ekkert var skrifað.', 'Línu 1 vantar binCode.');
    end;

    /// <summary>#68 item 7: the physical inventory template refusal says "birgðatalning" in Icelandic.</summary>
    [Test]
    procedure Create_PhysInventoryTemplate_IcelandicWording()
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        ResponseJson: JsonObject;
        PhysTemplateTxt: Label 'Birgðabókarsniðmát vöruhúss %1 er sniðmát fyrir birgðatalningu.', Locked = true;
    begin
        // Issue #68, AC2 (item 7) | Time: none | Risk: none.
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::"Physical Inventory", Location.Code, JournalBatch);

        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Journal.Create", '', BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":1}]'), 1039);

        Assert.AreEqual('InvalidParameter', Helper.TextValue(ResponseJson, 'code'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(StrSubstNo(PhysTemplateTxt, JournalBatch."Journal Template Name"), Helper.TextValue(ResponseJson, 'error'), 'Icelandic wording.');
    end;

    local procedure AssertLotEchoed(LanguageId: Integer)
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        LibraryItemTracking: Codeunit "Library - Item Tracking";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        LibraryItemTracking.CreateLotItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Journal.Create", '', BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":2,"lotNo":"LOT-E68"}]'), LanguageId);

        Helper.AssertSuccess(ResponseJson);
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual('LOT-E68', Helper.TextValue(LineJson, 'lotNo'), 'The answer echoes the lot that was written.');
        Assert.AreEqual('', Helper.TextValue(LineJson, 'serialNo'), 'No serial number was sent.');
    end;

    local procedure AssertLineCountedFromOne(LanguageId: Integer; ExpectedPattern: Text)
    var
        Location: Record Location;
        Item: Record Item;
        Bin: Record Bin;
        JournalBatch: Record "Warehouse Journal Batch";
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.FindPickBin(Location.Code, 1, Bin);
        Helper.StockBin(Bin, Item."No.", 2);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Journal.Create", '', BatchRequest(JournalBatch, '[{"itemNo":"' + Item."No." + '","binCode":"' + Bin.Code + '","quantity":-5}]'), LanguageId);

        Assert.AreEqual('InvalidLine', Helper.TextValue(ResponseJson, 'code'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(StrSubstNo(ExpectedPattern, Bin.Code, Item."No."), Helper.TextValue(ResponseJson, 'error'), 'The line is counted from 1.');
        Assert.AreEqual('lines[0].quantity', Helper.TextValue(ResponseJson, 'parameter'), 'The parameter path stays zero-based JSON.');
    end;

    local procedure AssertIndependentProblems(LanguageId: Integer; Summary: Text; MissingBinText: Text)
    var
        Location: Record Location;
        Item: Record Item;
        JournalBatch: Record "Warehouse Journal Batch";
        ResponseJson: JsonObject;
    begin
        Helper.CreateDirectedLocation(Location);
        Helper.CreateItem(Item);
        Helper.CreateWhseJournalBatch("Warehouse Journal Template Type"::Item, Location.Code, JournalBatch);

        ResponseJson := Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Journal.Create", '', '{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"NOBATCH","locationCode":"' + Location.Code + '","colour":"red","lines":[{"itemNo":"' + Item."No." + '","quantity":"five"}]}', LanguageId);

        Assert.AreEqual('MultipleErrors', Helper.TextValue(ResponseJson, 'code'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(Summary, Helper.TextValue(ResponseJson, 'error'), 'The summary is in the caller language.');
        Assert.AreEqual('colour:UnknownParameter,journalBatchName:RecordNotFound,lines[0].quantity:InvalidParameterFormat,lines[0].binCode:MissingParameter', Helper.ErrorList(ResponseJson), 'Every problem is listed.');
        Assert.AreEqual(MissingBinText, Helper.ErrorFor(ResponseJson, 'lines[0].binCode'), 'The missing bin counts the line from 1.');
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Journal.Create", '', RequestText));
    end;

    local procedure BatchRequest(JournalBatch: Record "Warehouse Journal Batch"; LinesText: Text): Text
    begin
        exit('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + JournalBatch."Location Code" + '","lines":' + LinesText + '}');
    end;

    local procedure BatchKeys(JournalBatch: Record "Warehouse Journal Batch"): Text
    begin
        exit('{"journalTemplateName":"' + JournalBatch."Journal Template Name" + '","journalBatchName":"' + JournalBatch.Name + '","locationCode":"' + JournalBatch."Location Code" + '"}');
    end;
}
