namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Tracking;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Availability.Get through the public dispatcher: totals, bins, tracking, refusals, permissions and help in 1033 and 1039.
/// </summary>
codeunit 97006 "Whse Availability Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryItemTracking: Codeunit "Library - Item Tracking";
        Helper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>A location without bins answers inventory, an empty bins list and a note.</summary>
    [Test]
    procedure Availability_LocationWithoutBins_AnswersInventoryWithNote()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        Helper.SetupPickLocationAndItem(Location, Item, 12);

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","includeBins":true}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'The read should succeed.');
        Assert.AreEqual(12, DecimalValue(ResponseJson, 'qtyInWarehouse'), 'The inventory of the location is the quantity.');
        Assert.AreEqual(12, DecimalValue(ResponseJson, 'qtyAvailableToPick'), 'All inventory is available.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'note'), 'A location without bins gets a note.');
        Assert.AreEqual(0, ArrayOf(ResponseJson, 'bins').Count(), 'bins is empty.');
    end;

    /// <summary>An item without stock is success with zeros.</summary>
    [Test]
    procedure Availability_NoStock_IsSuccessWithZeros()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        CreateBinLocation(Location);
        LibraryInventory.CreateItem(Item);

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '"}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'No stock is not an error.');
        Assert.AreEqual(0, DecimalValue(ResponseJson, 'qtyInWarehouse'), 'No stock.');
        Assert.AreEqual(0, DecimalValue(ResponseJson, 'qtyAvailableToPick'), 'Nothing to pick.');
    end;

    /// <summary>AC01: a blocked bin and an open pick reduce availability, and the pick then takes that quantity.</summary>
    [Test]
    procedure Availability_BlockedBinAndOpenPick_MatchesWhatPickCreatePicks()
    var
        Location: Record Location;
        Item: Record Item;
        BinA: Record Bin;
        BinB: Record Bin;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        ResponseJson: JsonObject;
        PickedQty: Decimal;
    begin
        CreateBinLocation(Location);
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.CreateBin(BinA, Location.Code, 'A-01', '', '');
        LibraryWarehouse.CreateBin(BinB, Location.Code, 'B-01', '', '');
        PostStock(Item."No.", Location.Code, BinA.Code, 10, '', 0D);
        PostStock(Item."No.", Location.Code, BinB.Code, 6, '', 0D);
        BinB.Get(Location.Code, 'B-01');
        BinB.Validate("Block Movement", BinB."Block Movement"::Outbound);
        BinB.Modify(true);
        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '"}', ResponseJson);
        Assert.AreEqual(10, DecimalValue(ResponseJson, 'qtyAvailableToPick'), 'Before any pick only the open bin counts: ' + Format(ResponseJson));
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 3);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);
        Helper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        RunPickCreate(WhseShipmentHeader."No.");

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","includeBins":true}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'The read should succeed.');
        Assert.AreEqual(16, DecimalValue(ResponseJson, 'qtyInWarehouse'), 'Both bins count in the warehouse.');
        Assert.AreEqual(3, DecimalValue(ResponseJson, 'qtyOnPicks'), 'The open pick holds 3.');
        Assert.AreEqual(6, DecimalValue(ResponseJson, 'qtyOnBlockedBins'), 'The blocked bin holds 6.');
        Assert.AreEqual(7, DecimalValue(ResponseJson, 'qtyAvailableToPick'), 'Availability is 10 - 3 on the open bin.');
        Assert.AreEqual(2, ArrayOf(ResponseJson, 'bins').Count(), 'Two bins hold the item.');

        // A second shipment asking for more than is available picks exactly the available quantity.
        Clear(SalesHeader);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 50);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);
        RunPickCreate(WhseShipmentHeader."No.");
        WarehouseActivityLine.SetRange("Whse. Document Type", WarehouseActivityLine."Whse. Document Type"::Shipment);
        WarehouseActivityLine.SetRange("Whse. Document No.", WhseShipmentHeader."No.");
        WarehouseActivityLine.SetRange("Action Type", WarehouseActivityLine."Action Type"::Take);
        WarehouseActivityLine.CalcSums("Qty. (Base)");
        PickedQty := WarehouseActivityLine."Qty. (Base)";
        Assert.AreEqual(7, PickedQty, 'The pick takes what the availability said.');
    end;

    /// <summary>AC02: a dedicated bin and a reservation on inventory reduce availability.</summary>
    [Test]
    procedure Availability_DedicatedBinAndReservation_ReduceAvailability()
    var
        Location: Record Location;
        Item: Record Item;
        BinA: Record Bin;
        BinD: Record Bin;
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ResponseJson: JsonObject;
    begin
        CreateBinLocation(Location);
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.CreateBin(BinA, Location.Code, 'A-01', '', '');
        LibraryWarehouse.CreateBin(BinD, Location.Code, 'D-01', '', '');
        BinD.Validate(Dedicated, true);
        BinD.Modify(true);
        PostStock(Item."No.", Location.Code, BinA.Code, 10, '', 0D);
        PostStock(Item."No.", Location.Code, BinD.Code, 5, '', 0D);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 4);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.FindFirst();
        SalesLine.AutoReserve();

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '"}', ResponseJson);

        Assert.AreEqual(15, DecimalValue(ResponseJson, 'qtyInWarehouse'), 'Both bins count in the warehouse.');
        Assert.AreEqual(5, DecimalValue(ResponseJson, 'qtyOnDedicatedBins'), 'The dedicated bin holds 5.');
        Assert.AreEqual(4, DecimalValue(ResponseJson, 'qtyReservedOnInventory'), 'The order reserves 4.');
        Assert.AreEqual(6, DecimalValue(ResponseJson, 'qtyAvailableToPick'), 'Availability is 15 - 5 dedicated - 4 reserved.');
    end;

    /// <summary>AC03: includeTracking splits by lot with expiration date and leaves blocked lots out.</summary>
    [Test]
    procedure Availability_IncludeTracking_SplitsByLotAndExcludesBlockedLot()
    var
        Location: Record Location;
        Item: Record Item;
        ItemTrackingCode: Record "Item Tracking Code";
        BinA: Record Bin;
        LotNoInformation: Record "Lot No. Information";
        ResponseJson: JsonObject;
        Rows: JsonArray;
        Row: JsonObject;
        Token: JsonToken;
        ExpirationDate: Date;
    begin
        CreateBinLocation(Location);
        LibraryItemTracking.CreateLotItem(Item);
        ItemTrackingCode.Get(Item."Item Tracking Code");
        ItemTrackingCode.Validate("Lot Warehouse Tracking", true);
        ItemTrackingCode.Validate("Use Expiration Dates", true);
        ItemTrackingCode.Modify(true);
        LibraryWarehouse.CreateBin(BinA, Location.Code, 'A-01', '', '');
        ExpirationDate := CalcDate('<+1Y>', WorkDate());
        PostStock(Item."No.", Location.Code, BinA.Code, 4, 'LOT-OK', ExpirationDate);
        PostStock(Item."No.", Location.Code, BinA.Code, 3, 'LOT-BAD', ExpirationDate);
        LibraryItemTracking.CreateLotNoInformation(LotNoInformation, Item."No.", '', 'LOT-BAD');
        LotNoInformation.Validate(Blocked, true);
        LotNoInformation.Modify(true);

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","includeTracking":true}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'The read should succeed.');
        Rows := ArrayOf(ResponseJson, 'tracking');
        Assert.AreEqual(1, Rows.Count(), 'The blocked lot is left out.');
        Rows.Get(0, Token);
        Row := Token.AsObject();
        Assert.AreEqual('LOT-OK', TextValue(Row, 'lotNo'), 'The open lot is listed.');
        Assert.AreEqual(4, DecimalValue(Row, 'quantity'), 'The lot quantity.');
        Assert.AreEqual(4, DecimalValue(Row, 'qtyAvailableToPick'), 'The lot is available.');
        Assert.AreEqual(Format(ExpirationDate, 0, '<Year4>-<Month,2>-<Day,2>'), TextValue(Row, 'expirationDate'), 'The expiration date is returned.');
        Assert.AreEqual(4, DecimalValue(ResponseJson, 'qtyAvailableToPick'), 'The blocked lot is not available to pick.');
    end;

    /// <summary>AC04: refusals answer Error with the Foundation code and a next step.</summary>
    [Test]
    procedure Availability_Refusals_AnswerCodeAndNextStep()
    var
        Location: Record Location;
        Item: Record Item;
        ResponseJson: JsonObject;
    begin
        CreateBinLocation(Location);
        LibraryInventory.CreateItem(Item);

        RunGet('{"locationCode":"' + Location.Code + '"}', ResponseJson);
        AssertRefusal(ResponseJson, 'MissingParameter', 'itemNo');

        RunGet('{"locationCode":"NOSUCH","itemNo":"' + Item."No." + '"}', ResponseJson);
        AssertRefusal(ResponseJson, 'RecordNotFound', 'locationCode');
        Assert.AreEqual('Check the location code and try again.', TextValue(ResponseJson, 'nextStep'), 'The next step says to check the location.');

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"NOSUCH-ITEM"}', ResponseJson);
        AssertRefusal(ResponseJson, 'RecordNotFound', 'itemNo');

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","colour":"red"}', ResponseJson);
        AssertRefusal(ResponseJson, 'UnknownParameter', 'colour');

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","includeBins":"yes"}', ResponseJson);
        AssertRefusal(ResponseJson, 'InvalidParameterFormat', 'includeBins');
    end;

    /// <summary>AC05: a BIFROST reader without SUPER succeeds.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Availability_ReaderWithoutSuper_Succeeds()
    var
        Location: Record Location;
        Item: Record Item;
        BinA: Record Bin;
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        ResponseJson: JsonObject;
    begin
        CreateBinLocation(Location);
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.CreateBin(BinA, Location.Code, 'A-01', '', '');
        PostStock(Item."No.", Location.Code, BinA.Code, 8, '', 0D);
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('BIFROST Read ori');
        LibraryLowerPermissions.AddPermissionSet('Whse AvRead Tst ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');

        RunGet('{"locationCode":"' + Location.Code + '","itemNo":"' + Item."No." + '","includeBins":true,"includeTracking":true}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'A reader without SUPER can read availability: ' + TextValue(ResponseJson, 'message') + ' ' + TextValue(ResponseJson, 'code'));
        Assert.AreEqual(8, DecimalValue(ResponseJson, 'qtyAvailableToPick'), 'The reader sees the quantity.');
    end;

    /// <summary>AC05: without bin read permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Availability_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        GetImpl: Codeunit "Whse Availability Get Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Availability.Get";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'The type is disabled without bin read permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        GetImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial uses PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Read ori.', TextValue(ResponseJson, 'nextStep'), 'The next step names the read permission set.');
    end;

    /// <summary>AC06: help is declared, names the related Inventory types and translates the next steps.</summary>
    [Test]
    procedure Availability_Help_IsDeclaredInBothLanguages()
    var
        Contract: Interface "Msg Contract ori";
        Related: JsonArray;
        Errors: JsonArray;
        Entry: JsonToken;
        RelatedText: Text;
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        Contract := Enum::"Message Type ori"::"Warehouse.Availability.Get";
        GlobalLanguage(1033);
        Assert.IsTrue(Contract.GetRelated(Related), 'Related types are declared.');
        Related.WriteTo(RelatedText);
        Assert.IsTrue(RelatedText.Contains('Inventory.AvailableToPromise.Get'), 'Inventory.AvailableToPromise.Get is related.');
        Assert.IsTrue(RelatedText.Contains('Inventory.AvailabilityByEvent.Get'), 'Inventory.AvailabilityByEvent.Get is related.');
        Assert.IsTrue(RelatedText.Contains('Inventory.AvailabilityByPeriod.Get'), 'Inventory.AvailabilityByPeriod.Get is related.');
        Assert.IsTrue(RelatedText.Contains('Inventory.TrackingAvailability.Get'), 'Inventory.TrackingAvailability.Get is related.');
        Assert.AreEqual('Check the code named in the error and try again.', NotFoundNextStep(Contract), 'English next step.');
        GlobalLanguage(1039);
        Assert.AreEqual('Athugaðu kóðann sem villan nefnir og reyndu aftur.', NotFoundNextStep(Contract), 'Icelandic next step.');
        Assert.IsTrue(Contract.GetErrors(Errors), 'Errors are declared.');
        Assert.AreEqual(5, Errors.Count(), 'Five refusals are declared.');
        foreach Entry in Errors do
            Assert.AreNotEqual('', TextValue(Entry.AsObject(), 'nextStep'), 'Every refusal has a next step.');
        GlobalLanguage(OriginalLanguage);
    end;

    /// <summary>AC06: the Icelandic discovery text differs from the English one.</summary>
    [Test]
    procedure Availability_Description_IsTranslated()
    var
        Discovery: Interface "Msg Discovery ori";
        Interface2: Interface "Msg Interface ori";
        English: Text;
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        Discovery := Enum::"Message Type ori"::"Warehouse.Availability.Get";
        Interface2 := Enum::"Message Type ori"::"Warehouse.Availability.Get";
        GlobalLanguage(1033);
        English := Interface2.GetDescription();
        GlobalLanguage(1039);
        Assert.AreNotEqual(English, Interface2.GetDescription(), 'The description is translated.');
        Assert.AreEqual('Lesaðgangur. Sýnir hversu mikið af einni vöru er hægt að tína á einni staðsetningu og hvers vegna afgangurinn er ekki tiltækur. Notaðu Inventory.AvailableToPromise.Get fyrir loforðsframboð.', Discovery.GetSelectionDescription(), 'The selection text is translated.');
        GlobalLanguage(OriginalLanguage);
    end;

    /// <summary>Answers in 1039 carry the Icelandic next step.</summary>
    [Test]
    procedure Availability_RefusalInIcelandic_IsTranslated()
    var
        Location: Record Location;
        Item: Record Item;
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
        ResponseJson: JsonObject;
    begin
        CreateBinLocation(Location);
        LibraryInventory.CreateItem(Item);

        ReceiptHelper.RunMessageInLanguage(Enum::"Message Type ori"::"Warehouse.Availability.Get", '', '{"locationCode":"NOSUCH","itemNo":"' + Item."No." + '"}', ResponseJson, 1039);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), 'The code stays the same.');
        Assert.AreEqual('Athugaðu kóða staðsetningar og reyndu aftur.', TextValue(ResponseJson, 'nextStep'), 'The next step is Icelandic.');
    end;

    local procedure NotFoundNextStep(Contract: Interface "Msg Contract ori"): Text
    var
        Errors: JsonArray;
        Entry: JsonToken;
    begin
        Contract.GetErrors(Errors);
        foreach Entry in Errors do
            if TextValue(Entry.AsObject(), 'code') = 'RecordNotFound' then
                exit(TextValue(Entry.AsObject(), 'nextStep'));
        exit('');
    end;

    local procedure AssertRefusal(ResponseJson: JsonObject; ExpectedCode: Text; ExpectedParameter: Text)
    begin
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), 'A refusal answers status Error for ' + ExpectedParameter + '.');
        Assert.AreEqual(ExpectedCode, TextValue(ResponseJson, 'code'), 'Code for ' + ExpectedParameter + '.');
        Assert.AreEqual(ExpectedParameter, TextValue(ResponseJson, 'parameter'), 'Parameter for ' + ExpectedCode + '.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'nextStep'), 'A refusal carries a next step.');
    end;

    local procedure CreateBinLocation(var Location: Record Location)
    var
        ShipBin: Record Bin;
    begin
        // Bin mandatory, require pick and shipment; not directed.
        LibraryWarehouse.CreateLocationWMS(Location, true, false, true, false, true);
        LibraryWarehouse.CreateBin(ShipBin, Location.Code, 'SHIP-01', '', '');
        Location.Validate("Shipment Bin Code", ShipBin.Code);
        Location.Modify(true);
    end;

    local procedure PostStock(ItemNo: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; Qty: Decimal; LotNo: Code[50]; ExpirationDate: Date)
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
        ReservationEntry: Record "Reservation Entry";
    begin
        LibraryInventory.SelectItemJournalTemplateName(ItemJournalTemplate, ItemJournalTemplate.Type::Item);
        LibraryInventory.SelectItemJournalBatchName(ItemJournalBatch, ItemJournalTemplate.Type::Item, ItemJournalTemplate.Name);
        LibraryInventory.ClearItemJournal(ItemJournalTemplate, ItemJournalBatch);
        LibraryInventory.CreateItemJournalLine(
            ItemJournalLine, ItemJournalTemplate.Name, ItemJournalBatch.Name,
            Enum::"Item Ledger Entry Type"::"Positive Adjmt.", ItemNo, Qty);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Validate("Bin Code", BinCode);
        ItemJournalLine.Modify(true);
        if LotNo <> '' then begin
            LibraryItemTracking.CreateItemJournalLineItemTracking(ReservationEntry, ItemJournalLine, '', LotNo, Qty);
            if ExpirationDate <> 0D then begin
                ReservationEntry."Expiration Date" := ExpirationDate;
                ReservationEntry.Modify();
            end;
        end;
        LibraryInventory.PostItemJournalLine(ItemJournalTemplate.Name, ItemJournalBatch.Name);
    end;

    local procedure RunPickCreate(WhseShipmentNo: Code[20])
    var
        ResponseJson: JsonObject;
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Create", WhseShipmentNo, '{}', ResponseJson), 'Pick.Create response should be JSON.');
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), 'Pick.Create should succeed.');
    end;

    local procedure RunGet(RequestText: Text; var ResponseJson: JsonObject)
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Availability.Get", '', RequestText, ResponseJson), 'Availability response should be JSON.');
    end;

    local procedure ArrayOf(Parent: JsonObject; Name: Text) Result: JsonArray
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' should be present.');
        Result := Token.AsArray();
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(-1);
        if not Token.IsValue() then
            exit(-1);
        exit(Token.AsValue().AsDecimal());
    end;
}
