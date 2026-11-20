namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Finance.GeneralLedger.Account;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Finance.VAT.Setup;
using Microsoft.Foundation.NoSeries;
using Microsoft.Foundation.UOM;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Posting;
using Microsoft.Inventory.Setup;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Setup;
using Origo.Bifrost.Warehouse;
using Origo.Bifrost;
using System.TestLibraries.Utilities;
using System.Utilities;

/// <summary>Verifies issue 104 through the public dispatcher, including persisted refusals and real posting and picking.</summary>
codeunit 97006 "Whse Document Get Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>AC01: a self-created purchase receipt reports quantities before and after partial posting.</summary>
    [Test]
    procedure Receipt_PartialPost_ChangesQuantities()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        Header: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        Response: JsonObject;
        Line: JsonObject;
    begin
        // Story #104, AC01 | Time: WorkDate for source posting | Risk: real receipt posting, isolated by runner.
        SetupOwnedFixture(Location, Item, false);
        CreateOwnedPurchase(PurchaseHeader, Item, Location);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(Header, PurchaseHeader);
        ReceiptLine.SetRange("No.", Header."No.");
        ReceiptLine.FindFirst();

        Run('{"documentType":"receipt","documentNo":"' + Header."No." + '","includeLines":true}', 1033, Response);
        Success(Response);
        Line := First(First(Response, 'documents'), 'lines');
        Assert.AreEqual(10, Number(Line, 'qtyOutstanding'), 'All quantity is initially outstanding.');
        Assert.AreEqual(10, Number(Line, 'qtyToReceive'), 'All quantity is initially selected.');
        Assert.AreEqual(PurchaseHeader."No.", TextOf(Line, 'sourceNo'), 'The line refers to our purchase order.');

        ReceiptHelper.RunMessage("Message Type ori"::"Warehouse.Receipt.Post", '',
            '{"receiptNo":"' + Header."No." + '","lines":[{"lineNo":' + Format(ReceiptLine."Line No.", 0, 9) + ',"qtyToReceive":4}]}', Response, false);
        Success(Response);
        Run('{"documentType":"receipt","id":"' + Format(Header.SystemId, 0, 4) + '","includeLines":true}', 1033, Response);
        Success(Response);
        Line := First(First(Response, 'documents'), 'lines');
        Assert.AreEqual(4, Number(Line, 'qtyReceived'), 'Partial posting received four.');
        Assert.AreEqual(6, Number(Line, 'qtyOutstanding'), 'Six remain to receive.');
        Assert.AreEqual(10, Number(Line, 'quantity'), 'Original quantity is unchanged.');
    end;

    /// <summary>AC02: actual registered picking is reflected in the released shipment response.</summary>
    [Test]
    procedure Shipment_RegisteredPick_ReportsProgress()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        Header: Record "Warehouse Shipment Header";
        Pick: Record "Warehouse Activity Header";
        Response: JsonObject;
        Document: JsonObject;
        Line: JsonObject;
        Token: JsonToken;
    begin
        // Story #104, AC02 | Time: WorkDate for inventory | Risk: real pick registration, isolated by runner.
        SetupOwnedFixture(Location, Item, true);
        SeedOwnedStock(Item, Location);
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        CreateOwnedSale(SalesHeader, Item, Location);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(Header, SalesHeader);
        ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Pick.Create", Header."No.", '{}', Response, false);
        Success(Response);
        Assert.IsTrue(ShipmentHelper.FindPickForShipment(Header."No.", Pick), 'A pick was created for our shipment.');
        Run('{"documentType":"shipment","documentNo":"' + Header."No." + '","includeLines":true}', 1033, Response);
        Success(Response);
        Line := First(First(Response, 'documents'), 'lines');
        Assert.AreEqual(5, Number(Line, 'pickQty'), 'Outstanding pick FlowField is calculated.');
        Assert.AreEqual(0, Number(Line, 'qtyPicked'), 'No pick is registered yet.');

        ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Pick.Register", Pick."No.", '{}', Response, false);
        Success(Response);
        Run('{"documentType":"shipment","documentNo":"' + Header."No." + '","status":"released","includeLines":true}', 1033, Response);
        Success(Response);
        Document := First(Response, 'documents');
        Assert.AreEqual('Released', TextOf(Document, 'status'), 'Shipment is released.');
        Document.Get('completelyPicked', Token);
        Assert.IsTrue(Token.AsValue().AsBoolean(), 'All shipment quantities were picked.');
        Line := First(Document, 'lines');
        Assert.AreEqual(5, Number(Line, 'qtyPicked'), 'Registered quantity is reported.');
        Assert.AreEqual(0, Number(Line, 'pickQty'), 'There is no outstanding pick.');
    end;

    /// <summary>AC03: number, systemId and id select the same document and lines are opt-in.</summary>
    [Test]
    procedure Receipt_IdentifiersAndOptionalLines()
    var
        Header: Record "Warehouse Receipt Header";
        Response: JsonObject;
        Request: Text;
    begin
        // Story #104, AC03 | Time: fixed 2026-11-20 | Risk: raw isolated reader fixture.
        SeedReceipt(Header, NewCode(), NewCode());
        Request := '{"documentType":"receipt","documentNo":"' + Header."No." + '","systemId":"' + Format(Header.SystemId, 0, 4) + '","id":"' + Format(Header.SystemId, 0, 4) + '"}';
        Run(Request, 1033, Response);
        Success(Response);
        Assert.AreEqual(Header."No.", TextOf(First(Response, 'documents'), 'no'), 'All identifiers resolve the same receipt.');
        Assert.IsFalse(First(Response, 'documents').Contains('lines'), 'Lines are opt-in.');
        Run('{"documentType":"receipt","systemId":"' + Format(Header.SystemId, 0, 4) + '","includeLines":true}', 1039, Response);
        Success(Response);
        Assert.AreEqual(1, Count(First(Response, 'documents'), 'lines'), 'The line is returned in 1039.');
    end;

    /// <summary>AC03: paging counts before slicing and inclusive dates, assignment and location intersect.</summary>
    [Test]
    procedure Receipt_PagingAndHeaderFilters()
    var
        FirstHeader: Record "Warehouse Receipt Header";
        SecondHeader: Record "Warehouse Receipt Header";
        Response: JsonObject;
        LocationCode: Code[10];
        FilterText: Text;
    begin
        // Story #104, AC03 | Time: fixed 2026-11-20 | Risk: raw isolated reader fixtures.
        LocationCode := CopyStr(NewCode(), 1, 10);
        SeedReceipt(FirstHeader, LocationCode, NewCode());
        SeedReceipt(SecondHeader, LocationCode, NewCode());
        FilterText := '"documentType":"receipt","locationCode":"' + LocationCode + '","assignedUserId":"XASSIGNED","postingDateFrom":"2026-11-20","postingDateTo":"2026-11-20"';
        Run('{' + FilterText + ',"skip":1,"take":1}', 1033, Response);
        Success(Response);
        Assert.AreEqual(2, Number(Response, 'noOfRecords'), 'Count is before paging.');
        Assert.AreEqual(1, Count(Response, 'documents'), 'One result on page two.');
        if FirstHeader."No." > SecondHeader."No." then
            Assert.AreEqual(FirstHeader."No.", TextOf(First(Response, 'documents'), 'no'), 'Document number ordering.')
        else
            Assert.AreEqual(SecondHeader."No.", TextOf(First(Response, 'documents'), 'no'), 'Document number ordering.');
        Run('{' + FilterText + ',"skip":2,"take":1}', 1033, Response);
        Success(Response);
        Assert.AreEqual(2, Number(Response, 'noOfRecords'), 'Count is preserved beyond last result.');
        Assert.AreEqual(0, Count(Response, 'documents'), 'Skip at count returns empty.');
        Run('{"documentType":"receipt","documentNo":"' + FirstHeader."No." + '","postingDateFrom":"2026-11-21"}', 1033, Response);
        Success(Response);
        Assert.AreEqual(0, Count(Response, 'documents'), 'Other filters may exclude a named existing receipt.');
    end;

    /// <summary>AC03: the source type and number must match the same line; all lines are included.</summary>
    [Test]
    procedure Receipt_SourceFiltersMatchSameLine()
    var
        Header: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        Response: JsonObject;
        SourceNo: Code[20];
    begin
        // Story #104, AC03 | Time: fixed 2026-11-20 | Risk: raw isolated reader fixture.
        SourceNo := NewCode();
        SeedReceipt(Header, NewCode(), SourceNo);
        ReceiptLine.Get(Header."No.", 10000);
        ReceiptLine."Line No." := 20000;
        ReceiptLine."Source Type" := 37;
        ReceiptLine."Source No." := NewCode();
        ReceiptLine.Insert(false);
        Run('{"documentType":"receipt","sourceType":39,"sourceNo":"' + SourceNo + '","includeLines":true}', 1033, Response);
        Success(Response);
        Assert.AreEqual(1, Number(Response, 'noOfRecords'), 'Matching source line selects the header once.');
        Assert.AreEqual(2, Count(First(Response, 'documents'), 'lines'), 'Every document line is returned.');
        Run('{"documentType":"receipt","sourceType":37,"sourceNo":"' + SourceNo + '"}', 1033, Response);
        Success(Response);
        Assert.AreEqual(0, Count(Response, 'documents'), 'Filters cannot match different lines.');
    end;

    /// <summary>AC03: empty searches are successful in either language.</summary>
    [Test]
    procedure EmptySearch_BothLanguages()
    var
        Response: JsonObject;
        Languages: List of [Integer];
        LanguageId: Integer;
    begin
        // Story #104, AC03 | Time: independent | Risk: none.
        Languages.Add(1033);
        Languages.Add(1039);
        foreach LanguageId in Languages do begin
            Run('{"documentType":"shipment","sourceNo":"' + NewCode() + '"}', LanguageId, Response);
            Success(Response);
            Assert.AreEqual(0, Number(Response, 'noOfRecords'), 'Unmatched source returns zero.');
            Assert.AreEqual(0, Count(Response, 'documents'), 'Unmatched source returns empty list.');
        end;
    end;

    /// <summary>AC04: identifiers pointing to different existing receipts are refused without changing either.</summary>
    [Test]
    procedure ConflictingIdentifiers_AreLogged()
    var
        FirstHeader: Record "Warehouse Receipt Header";
        SecondHeader: Record "Warehouse Receipt Header";
        Languages: List of [Integer];
        LanguageId: Integer;
    begin
        // Story #104, AC04 | Time: fixed 2026-11-20 | Risk: raw isolated reader fixtures.
        SeedReceipt(FirstHeader, NewCode(), NewCode());
        SeedReceipt(SecondHeader, NewCode(), NewCode());
        Languages.Add(1033);
        Languages.Add(1039);
        foreach LanguageId in Languages do
            Refusal('{"documentType":"receipt","documentNo":"' + FirstHeader."No." + '","systemId":"' + Format(SecondHeader.SystemId, 0, 4) + '"}', 'ConflictingIdentifiers', LanguageId);
        FirstHeader.Get(FirstHeader."No.");
        SecondHeader.Get(SecondHeader."No.");
        Assert.AreEqual('XASSIGNED', FirstHeader."Assigned User ID", 'First document unchanged.');
        Assert.AreEqual('XASSIGNED', SecondHeader."Assigned User ID", 'Second document unchanged.');
    end;

    /// <summary>AC05: the dedicated no-read permission set receives PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure PermissionDenied_WithoutTableReads()
    var
        TempArgument: Record "Message Argument ori" temporary;
        Implementation: Codeunit "Whse Document Get Impl ori";
        LowerPermissions: Codeunit "Library - Lower Permissions";
        Response: JsonObject;
    begin
        // Story #104, AC05 | Time: independent | Risk: permissions restored by test runner.
        LowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        Assert.IsFalse(Implementation.IsEnabled(), 'All four table read rights are required.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        Implementation.ExecuteBifrostTask(TempArgument);
        Response := TempArgument.GetResponseJson();
        Assert.AreEqual('Error', TextOf(Response, 'status'), 'Denied request is an error.');
        Assert.AreEqual('PermissionDenied', TextOf(Response, 'code'), 'Structured permission refusal.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Read ori.', TextOf(Response, 'nextStep'), 'Actionable permission next step.');
    end;

    /// <summary>AC06: help chapters stay English and discovery is translated.</summary>
    [Test]
    procedure HelpEnglish_DiscoveryTranslated()
    var
        Implementation: Codeunit "Whse Document Get Impl ori";
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        EnglishContract: JsonObject;
        IcelandicContract: JsonObject;
        EnglishDescription: Text;
        EnglishSelection: Text;
        EnglishKeywords: Text;
        OriginalLanguage: Integer;
    begin
        // Story #104, AC06 | Time: independent | Risk: session language restored before assertions.
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        EnglishDescription := Implementation.GetDescription();
        EnglishSelection := Implementation.GetSelectionDescription();
        EnglishKeywords := Implementation.GetKeywords();
        ContractMgt.GetContract("Message Type ori"::"Warehouse.Document.Get", EnglishContract);
        GlobalLanguage(1039);
        ContractMgt.GetContract("Message Type ori"::"Warehouse.Document.Get", IcelandicContract);
        Assert.AreNotEqual(EnglishDescription, Implementation.GetDescription(), 'Description translated.');
        Assert.AreNotEqual(EnglishSelection, Implementation.GetSelectionDescription(), 'Selection translated.');
        Assert.AreNotEqual(EnglishKeywords, Implementation.GetKeywords(), 'Keywords translated.');
        GlobalLanguage(OriginalLanguage);
        Assert.AreEqual(TextOf(EnglishContract, 'overview'), TextOf(IcelandicContract, 'overview'), 'Overview remains English.');
        Assert.AreEqual(TextOf(EnglishContract, 'notes'), TextOf(IcelandicContract, 'notes'), 'Notes remain English.');
        Assert.IsTrue(EnglishContract.Contains('parameters'), 'Parameters chapter.');
        Assert.IsTrue(EnglishContract.Contains('response'), 'Response chapter.');
        Assert.IsTrue(EnglishContract.Contains('workflow'), 'Workflow chapter.');
        Assert.IsTrue(Count(EnglishContract, 'related') >= 5, 'All related operations.');
    end;

    /// <summary>AC04 and AC06: MissingDocumentType is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure MissingDocumentType_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{}', 'MissingParameter', 1033);
        Refusal('{}', 'MissingParameter', 1039);
    end;

    /// <summary>AC04 and AC06: InvalidDocumentType is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure InvalidDocumentType_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"invoice"}', 'InvalidParameter', 1033);
        Refusal('{"documentType":"invoice"}', 'InvalidParameter', 1039);
    end;

    /// <summary>AC04 and AC06: UnknownDocument is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure UnknownDocument_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","documentNo":"XUNKNOWN104"}', 'RecordNotFound', 1033);
        Refusal('{"documentType":"receipt","documentNo":"XUNKNOWN104"}', 'RecordNotFound', 1039);
    end;

    /// <summary>AC04 and AC06: UnknownSystemId is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure UnknownSystemId_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"shipment","systemId":"00000000-0000-0000-0000-000000000104"}', 'RecordNotFound', 1033);
        Refusal('{"documentType":"shipment","systemId":"00000000-0000-0000-0000-000000000104"}', 'RecordNotFound', 1039);
    end;

    /// <summary>AC04 and AC06: InvalidGuid is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure InvalidGuid_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","id":"not-a-guid"}', 'InvalidParameterFormat', 1033);
        Refusal('{"documentType":"receipt","id":"not-a-guid"}', 'InvalidParameterFormat', 1039);
    end;

    /// <summary>AC04 and AC06: NegativeSkip is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure NegativeSkip_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","skip":-1}', 'InvalidParameter', 1033);
        Refusal('{"documentType":"receipt","skip":-1}', 'InvalidParameter', 1039);
    end;

    /// <summary>AC04 and AC06: NegativeTake is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure NegativeTake_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"shipment","take":-1}', 'InvalidParameter', 1033);
        Refusal('{"documentType":"shipment","take":-1}', 'InvalidParameter', 1039);
    end;

    /// <summary>AC04 and AC06: NonNumericSkip is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure NonNumericSkip_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","skip":"one"}', 'InvalidParameterFormat', 1033);
        Refusal('{"documentType":"receipt","skip":"one"}', 'InvalidParameterFormat', 1039);
    end;

    /// <summary>AC04 and AC06: DecimalTake is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure DecimalTake_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","take":1.5}', 'InvalidParameterFormat', 1033);
        Refusal('{"documentType":"receipt","take":1.5}', 'InvalidParameterFormat', 1039);
    end;

    /// <summary>AC04 and AC06: UnknownKey is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure UnknownKey_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","typo":true}', 'UnknownParameter', 1033);
        Refusal('{"documentType":"receipt","typo":true}', 'UnknownParameter', 1039);
    end;

    /// <summary>AC04 and AC06: InvalidBoolean is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure InvalidBoolean_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","includeLines":"true"}', 'InvalidParameterFormat', 1033);
        Refusal('{"documentType":"receipt","includeLines":"true"}', 'InvalidParameterFormat', 1039);
    end;

    /// <summary>AC04 and AC06: InvalidStatus is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure InvalidStatus_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"shipment","status":"pending"}', 'InvalidParameter', 1033);
        Refusal('{"documentType":"shipment","status":"pending"}', 'InvalidParameter', 1039);
    end;

    /// <summary>AC04 and AC06: ReceiptStatus is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure ReceiptStatus_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","status":"open"}', 'InvalidParameter', 1033);
        Refusal('{"documentType":"receipt","status":"open"}', 'InvalidParameter', 1039);
    end;

    /// <summary>AC04 and AC06: ReversedDateRange is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure ReversedDateRange_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","postingDateFrom":"2026-11-21","postingDateTo":"2026-11-20"}', 'InvalidParameter', 1033);
        Refusal('{"documentType":"receipt","postingDateFrom":"2026-11-21","postingDateTo":"2026-11-20"}', 'InvalidParameter', 1039);
    end;

    /// <summary>AC04 and AC06: InvalidDate is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure InvalidDate_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","postingDateFrom":"bad"}', 'InvalidParameterFormat', 1033);
        Refusal('{"documentType":"receipt","postingDateFrom":"bad"}', 'InvalidParameterFormat', 1039);
    end;

    /// <summary>AC04 and AC06: NumericIdentifier is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure NumericIdentifier_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","documentNo":42}', 'InvalidParameterFormat', 1033);
        Refusal('{"documentType":"receipt","documentNo":42}', 'InvalidParameterFormat', 1039);
    end;

    /// <summary>AC04 and AC06: NegativeSourceType is a structured, logged refusal in both languages.</summary>
    [Test]
    procedure NegativeSourceType_BilingualRefusal()
    begin
        // Story #104, AC04/AC06 | Time: fixed request or independent | Risk: none.
        Refusal('{"documentType":"receipt","sourceType":-1}', 'InvalidParameter', 1033);
        Refusal('{"documentType":"receipt","sourceType":-1}', 'InvalidParameter', 1039);
    end;

    local procedure SetupOwnedFixture(var Location: Record Location; var Item: Record Item; Shipment: Boolean)
    var
        Account: Record "G/L Account";
        BusinessGroup: Record "Gen. Business Posting Group";
        ProductGroup: Record "Gen. Product Posting Group";
        GeneralPosting: Record "General Posting Setup";
        VATBusinessGroup: Record "VAT Business Posting Group";
        VATProductGroup: Record "VAT Product Posting Group";
        VATPosting: Record "VAT Posting Setup";
        InventoryGroup: Record "Inventory Posting Group";
        InventoryPosting: Record "Inventory Posting Setup";
        VendorGroup: Record "Vendor Posting Group";
        CustomerGroup: Record "Customer Posting Group";
        Unit: Record "Unit of Measure";
        ItemUnit: Record "Item Unit of Measure";
        WarehouseSetup: Record "Warehouse Setup";
        SetupCode: Code[10];
    begin
        SetupCode := CopyStr(NewCode(), 1, 10);
        Account.Init();
        Account."No." := NewCode();
        Account.Name := 'X Warehouse 104 account';
        Account."Account Type" := Account."Account Type"::Posting;
        Account."Direct Posting" := true;
        Account.Insert(false);
        BusinessGroup.Init();
        BusinessGroup.Code := SetupCode;
        BusinessGroup.Insert(false);
        ProductGroup.Init();
        ProductGroup.Code := SetupCode;
        ProductGroup.Insert(false);
        VATBusinessGroup.Init();
        VATBusinessGroup.Code := SetupCode;
        VATBusinessGroup.Insert(false);
        VATProductGroup.Init();
        VATProductGroup.Code := SetupCode;
        VATProductGroup.Insert(false);
        VATPosting.Init();
        VATPosting."VAT Bus. Posting Group" := SetupCode;
        VATPosting."VAT Prod. Posting Group" := SetupCode;
        VATPosting."VAT %" := 0;
        VATPosting."VAT Identifier" := SetupCode;
        VATPosting.Insert(false);
        GeneralPosting.Init();
        GeneralPosting."Gen. Bus. Posting Group" := SetupCode;
        GeneralPosting."Gen. Prod. Posting Group" := SetupCode;
        GeneralPosting."Sales Account" := Account."No.";
        GeneralPosting."Purch. Account" := Account."No.";
        GeneralPosting."COGS Account" := Account."No.";
        GeneralPosting."COGS Account (Interim)" := Account."No.";
        GeneralPosting."Inventory Adjmt. Account" := Account."No.";
        GeneralPosting."Invt. Accrual Acc. (Interim)" := Account."No.";
        GeneralPosting."Direct Cost Applied Account" := Account."No.";
        GeneralPosting.Insert(false);
        // Inventory journals have no business group.
        GeneralPosting."Gen. Bus. Posting Group" := '';
        GeneralPosting.Insert(false);
        InventoryGroup.Init();
        InventoryGroup.Code := SetupCode;
        InventoryGroup.Insert(false);
        Location.Init();
        Location.Code := SetupCode;
        Location.Name := 'X Warehouse 104 location';
        Location."Require Receive" := not Shipment;
        Location."Require Shipment" := Shipment;
        Location."Require Pick" := Shipment;
        Location.Insert(false);
        InventoryPosting.Init();
        InventoryPosting."Location Code" := Location.Code;
        InventoryPosting."Invt. Posting Group Code" := SetupCode;
        InventoryPosting."Inventory Account" := Account."No.";
        InventoryPosting."Inventory Account (Interim)" := Account."No.";
        InventoryPosting.Insert(false);
        VendorGroup.Init();
        VendorGroup.Code := SetupCode;
        VendorGroup."Payables Account" := Account."No.";
        VendorGroup.Insert(false);
        CustomerGroup.Init();
        CustomerGroup.Code := SetupCode;
        CustomerGroup."Receivables Account" := Account."No.";
        CustomerGroup.Insert(false);
        Unit.Init();
        Unit.Code := SetupCode;
        Unit.Description := 'X unit';
        Unit.Insert(false);
        Item.Init();
        Item."No." := NewCode();
        Item.Description := 'X Warehouse 104 item';
        Item."Gen. Prod. Posting Group" := SetupCode;
        Item."VAT Prod. Posting Group" := SetupCode;
        Item."Inventory Posting Group" := SetupCode;
        Item."Unit Cost" := 1;
        Item.Insert(false);
        ItemUnit.Init();
        ItemUnit."Item No." := Item."No.";
        ItemUnit.Code := Unit.Code;
        ItemUnit."Qty. per Unit of Measure" := 1;
        ItemUnit.Insert(false);
        Item.Validate("Base Unit of Measure", Unit.Code);
        Item.Modify(true);
        if not WarehouseSetup.Get() then
            WarehouseSetup.Insert();
        WarehouseSetup."Whse. Receipt Nos." := CreateSeries();
        WarehouseSetup."Posted Whse. Receipt Nos." := CreateSeries();
        WarehouseSetup."Whse. Ship Nos." := CreateSeries();
        WarehouseSetup."Posted Whse. Shipment Nos." := CreateSeries();
        WarehouseSetup."Whse. Pick Nos." := CreateSeries();
        WarehouseSetup."Registered Whse. Pick Nos." := CreateSeries();
        WarehouseSetup.Modify();
    end;

    local procedure CreateSeries(): Code[20]
    var
        Series: Record "No. Series";
        SeriesLine: Record "No. Series Line";
    begin
        Series.Init();
        Series.Code := NewCode();
        Series."Default Nos." := true;
        Series."Manual Nos." := true;
        Series.Insert(false);
        SeriesLine.Init();
        SeriesLine."Series Code" := Series.Code;
        SeriesLine."Line No." := 10000;
        SeriesLine."Starting No." := CopyStr(Series.Code, 1, 12) + '000001';
        SeriesLine."Ending No." := CopyStr(Series.Code, 1, 12) + '999999';
        SeriesLine."Increment-by No." := 1;
        SeriesLine.Open := true;
        SeriesLine.Insert(false);
        exit(Series.Code);
    end;

    local procedure CreateOwnedPurchase(var Header: Record "Purchase Header"; Item: Record Item; Location: Record Location)
    var
        Vendor: Record Vendor;
        Line: Record "Purchase Line";
        ReleasePurchase: Codeunit "Release Purchase Document";
    begin
        Vendor.Init();
        Vendor."No." := NewCode();
        Vendor.Name := 'X Warehouse 104 vendor';
        Vendor."Gen. Bus. Posting Group" := Location.Code;
        Vendor."VAT Bus. Posting Group" := Location.Code;
        Vendor."Vendor Posting Group" := Location.Code;
        Vendor.Insert(false);
        Header.Init();
        Header."Document Type" := Header."Document Type"::Order;
        Header."No." := NewCode();
        Header.Insert(true);
        Header.Validate("Buy-from Vendor No.", Vendor."No.");
        Header.Validate("Location Code", Location.Code);
        Header.Validate("Posting Date", WorkDate());
        Header."Receiving No." := NewCode();
        Header.Modify(true);
        Line.Init();
        Line."Document Type" := Header."Document Type";
        Line."Document No." := Header."No.";
        Line."Line No." := 10000;
        Line.Insert(true);
        Line.Validate(Type, Line.Type::Item);
        Line.Validate("No.", Item."No.");
        Line.Validate("Location Code", Location.Code);
        Line.Validate(Quantity, 10);
        Line.Validate("Direct Unit Cost", 1);
        Line.Modify(true);
        ReleasePurchase.PerformManualRelease(Header);
    end;

    local procedure CreateOwnedSale(var Header: Record "Sales Header"; Item: Record Item; Location: Record Location)
    var
        Customer: Record Customer;
        Line: Record "Sales Line";
        ReleaseSales: Codeunit "Release Sales Document";
    begin
        Customer.Init();
        Customer."No." := NewCode();
        Customer.Name := 'X Warehouse 104 customer';
        Customer."Gen. Bus. Posting Group" := Location.Code;
        Customer."VAT Bus. Posting Group" := Location.Code;
        Customer."Customer Posting Group" := Location.Code;
        Customer.Insert(false);
        Header.Init();
        Header."Document Type" := Header."Document Type"::Order;
        Header."No." := NewCode();
        Header.Insert(true);
        Header.Validate("Sell-to Customer No.", Customer."No.");
        Header.Validate("Location Code", Location.Code);
        Header.Validate("Posting Date", WorkDate());
        Header."Shipping No." := NewCode();
        Header.Modify(true);
        Line.Init();
        Line."Document Type" := Header."Document Type";
        Line."Document No." := Header."No.";
        Line."Line No." := 10000;
        Line.Insert(true);
        Line.Validate(Type, Line.Type::Item);
        Line.Validate("No.", Item."No.");
        Line.Validate("Location Code", Location.Code);
        Line.Validate(Quantity, 5);
        Line.Validate("Unit Price", 1);
        Line.Modify(true);
        ReleaseSales.PerformManualRelease(Header);
    end;

    local procedure SeedOwnedStock(Item: Record Item; Location: Record Location)
    var
        JournalTemplate: Record "Item Journal Template";
        Batch: Record "Item Journal Batch";
        Line: Record "Item Journal Line";
        PostLine: Codeunit "Item Jnl.-Post Line";
    begin
        JournalTemplate.Init();
        JournalTemplate.Name := CopyStr(NewCode(), 1, 10);
        JournalTemplate.Insert(true);
        Batch.Init();
        Batch."Journal Template Name" := JournalTemplate.Name;
        Batch.Name := CopyStr(NewCode(), 1, 10);
        Batch.Insert(true);
        Line.Init();
        Line."Journal Template Name" := JournalTemplate.Name;
        Line."Journal Batch Name" := Batch.Name;
        Line."Line No." := 10000;
        Line.Validate("Posting Date", WorkDate());
        Line.Validate("Entry Type", Line."Entry Type"::"Positive Adjmt.");
        Line."Document No." := NewCode();
        Line.Validate("Item No.", Item."No.");
        Line.Validate("Location Code", Location.Code);
        Line.Validate(Quantity, 10);
        Line.Validate("Unit Amount", 1);
        PostLine.RunWithCheck(Line);
    end;

    local procedure SeedReceipt(var Header: Record "Warehouse Receipt Header"; LocationCode: Text; SourceNo: Code[20])
    var
        ReceiptLine: Record "Warehouse Receipt Line";
    begin
        Header.Init();
        Header."No." := NewCode();
        Header."Location Code" := CopyStr(LocationCode, 1, 10);
        Header."Posting Date" := 20261120D;
        Header."Assigned User ID" := 'XASSIGNED';
        Header.Insert(false);
        ReceiptLine.Init();
        ReceiptLine."No." := Header."No.";
        ReceiptLine."Line No." := 10000;
        ReceiptLine."Source Type" := 39;
        ReceiptLine."Source No." := SourceNo;
        ReceiptLine."Source Line No." := 10000;
        ReceiptLine."Item No." := NewCode();
        ReceiptLine."Unit of Measure Code" := 'XPCS';
        ReceiptLine.Quantity := 10;
        ReceiptLine."Qty. Outstanding" := 10;
        ReceiptLine."Qty. to Receive" := 10;
        ReceiptLine.Insert(false);
    end;

    local procedure Run(RequestText: Text; LanguageId: Integer; var Response: JsonObject)
    var
        MessageId: Guid;
    begin
        Dispatch(RequestText, LanguageId, Response, MessageId);
    end;

    local procedure Dispatch(RequestText: Text; LanguageId: Integer; var Response: JsonObject; var MessageId: Guid)
    var
        Dispatcher: Codeunit "Dispatcher ori";
        RequestContent: BigText;
        ResponseContent: BigText;
        ResponseContentType: Text[100];
        ResponseText: Text;
        ResponseTime: Duration;
        EmptyTask: Guid;
    begin
        Clear(Response);
        RequestContent.AddText(RequestText);
        Commit();
        Dispatcher.EnqueueAndProcess("Message Type ori"::"Warehouse.Document.Get", "Message Version ori"::"1.0", '',
            'XWAREHOUSE104', 'application/json', RequestContent, EmptyTask, LanguageId, MessageId,
            ResponseContent, ResponseContentType, ResponseTime);
        ResponseContent.GetSubText(ResponseText, 1, ResponseContent.Length());
        Assert.IsTrue(Response.ReadFrom(ResponseText), 'Dispatcher returns JSON: ' + ResponseText);
    end;

    local procedure Refusal(RequestText: Text; ExpectedCode: Text; LanguageId: Integer)
    var
        TempBlob: Codeunit "Temp Blob";
        MessageRecord: RecordRef;
        Field: FieldRef;
        Response: JsonObject;
        LoggedResponse: JsonObject;
        MessageId: Guid;
        Content: InStream;
        LoggedText: Text;
    begin
        Dispatch(RequestText, LanguageId, Response, MessageId);
        Assert.AreEqual('Error', TextOf(Response, 'status'), JsonText(Response));
        Assert.AreEqual(ExpectedCode, TextOf(Response, 'code'), JsonText(Response));
        Assert.AreNotEqual('', TextOf(Response, 'nextStep'), 'Every refusal explains the next step.');
        // Foundation keeps its queue internal; inspect only this request through the record reference.
        MessageRecord.Open(10077897);
        Field := MessageRecord.Field(1);
        Field.SetRange(MessageId);
        Assert.IsTrue(MessageRecord.FindFirst(), 'Foundation persisted this request.');
        TempBlob.FromRecordRef(MessageRecord, 8);
        TempBlob.CreateInStream(Content, TextEncoding::UTF8);
        Content.ReadText(LoggedText);
        MessageRecord.Close();
        Assert.IsTrue(LoggedResponse.ReadFrom(LoggedText), 'Persisted response is JSON.');
        Assert.AreEqual('Error', TextOf(LoggedResponse, 'status'), 'Foundation entry records the refusal.');
        Assert.AreEqual(ExpectedCode, TextOf(LoggedResponse, 'code'), 'Foundation entry records the code.');
    end;

    local procedure Success(Response: JsonObject)
    begin
        Assert.AreEqual('Success', TextOf(Response, 'status'), JsonText(Response));
    end;

    local procedure First(Parent: JsonObject; Name: Text): JsonObject
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must exist.');
        Assert.IsTrue(Token.AsArray().Get(0, Token), Name + ' must have an entry.');
        exit(Token.AsObject());
    end;

    local procedure Count(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must exist.');
        exit(Token.AsArray().Count());
    end;

    local procedure Number(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(Parent.Get(Name, Token), Name + ' must exist.');
        exit(Token.AsValue().AsDecimal());
    end;

    local procedure TextOf(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if Parent.Get(Name, Token) then
            if Token.IsValue() then
                exit(Token.AsValue().AsText());
        exit('');
    end;

    local procedure JsonText(Value: JsonObject) Result: Text
    begin
        Value.WriteTo(Result);
    end;

    local procedure NewCode(): Code[20]
    begin
        exit(CopyStr('X' + DelChr(Format(CreateGuid(), 0, 4), '=', '{}-'), 1, 20));
    end;
}
