namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Contract, help and write-restriction tests of the journal, worksheet and activity line types (#48-#50, #55-#57).
/// </summary>
codeunit 97062 "Whse Jnl Contract Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";

    /// <summary>AC13/AC14: every new type has a contract with parameters, a discovery text and the expected effect.</summary>
    [Test]
    procedure EveryNewType_HasContractAndDiscovery()
    begin
        AssertContract("Message Type ori"::"Warehouse.Journal.Create", 'write');
        AssertContract("Message Type ori"::"Warehouse.Journal.Register", 'irreversible');
        AssertContract("Message Type ori"::"Warehouse.PhysInventory.Calculate", 'write');
        AssertContract("Message Type ori"::"Warehouse.PhysInventory.Register", 'irreversible');
        AssertContract("Message Type ori"::"Warehouse.Adjustment.Calculate", 'write');
        AssertContract("Message Type ori"::"Warehouse.Worksheet.GetDocuments", 'write');
        AssertContract("Message Type ori"::"Warehouse.Worksheet.CreateActivities", 'irreversible');
        AssertContract("Message Type ori"::"Warehouse.ActivityLine.Split", 'write');
        AssertContract("Message Type ori"::"Warehouse.ActivityLine.ChangeBin", 'write');
        AssertContract("Message Type ori"::"Warehouse.ActivityLine.SetQtyToHandle", 'write');
        AssertContract("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'write');
    end;

    /// <summary>AC11/AC12: the selection description and keywords answer in English (1033) and Icelandic (1039).</summary>
    [Test]
    procedure EveryNewType_HelpInEnglishAndIcelandic()
    var
        MessageType: Enum "Message Type ori";
    begin
        foreach MessageType in NewTypes() do
            AssertBilingual(MessageType);
        GlobalLanguage(1039);
        AssertDiscovery("Message Type ori"::"Warehouse.Journal.Register", 'Óafturkræft. Skráir allar línur keyrslu í birgðabók eða endurflokkunarbók vöruhúss og Business Central staðfestir vöruhúsafærslurnar. Þarf BIFROST WhsePost ori. Notaðu Warehouse.PhysInventory.Register fyrir talningarkeyrslu.');
        GlobalLanguage(1033);
        AssertDiscovery("Message Type ori"::"Warehouse.Journal.Register", 'Irreversible. Registers every line of a warehouse item or reclassification journal batch and Business Central commits the warehouse entries. Needs BIFROST WhsePost ori. Use Warehouse.PhysInventory.Register for a physical inventory batch.');
    end;

    /// <summary>AC03-AC07 of each issue: the errors chapters declare the refusals with the next steps the code answers.</summary>
    [Test]
    procedure ErrorsChapters_DeclareTheAnsweredNextSteps()
    begin
        AssertDeclaredError("Message Type ori"::"Warehouse.Journal.Create", 'PreconditionFailed', 'Use Inventory.ItemJournal.* or Inventory.Reclassification.* for basic locations.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Journal.Create", 'InvalidLine', 'Read Warehouse.BinContent.Get.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Journal.Create", 'RecordNotFound', 'Create the batch first.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Journal.Register", 'PreconditionFailed', 'Add lines with Warehouse.Journal.Create.');
        AssertDeclaredError("Message Type ori"::"Warehouse.PhysInventory.Calculate", 'PreconditionFailed', 'Use Inventory.PhysInventory.* for basic locations.');
        AssertDeclaredError("Message Type ori"::"Warehouse.PhysInventory.Register", 'InvalidLine', 'Read the lines answered by Calculate.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Adjustment.Calculate", 'RecordNotFound', 'Create the batch first.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Adjustment.Calculate", 'PreconditionFailed', 'Post the lines with Inventory.ItemJournal.Post (templateName, batchName), or delete them first.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Worksheet.GetDocuments", 'PreconditionFailed', 'Use the inventory activities instead.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Worksheet.CreateActivities", 'RecordNotFound', 'Create the worksheet name first, and use the line numbers answered by Warehouse.Worksheet.GetDocuments.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.Split", 'PreconditionFailed', 'Lower qtyToHandle first; BC splits the rest off.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.ChangeBin", 'InvalidLine', 'Read Warehouse.BinContent.Get.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.ChangeBin", 'ConflictingIdentifiers', 'Use the activity no. answered by Warehouse.Activity.Get.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'InvalidLine', 'One entry per serial no.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'InvalidLine', 'Read Inventory.TrackingAvailability.Get for the item.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'InvalidLine', 'Read the warehouse entries of the bin and item with Data.Records.Get on table Warehouse Entry.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Worksheet.CreateActivities", 'InvalidParameter', 'Send one of "None", "Item", "Document", "Shelf or Bin", "Due Date", "Ship-To", "Bin Ranking" or "Action Type".');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'PreconditionFailed', 'No tracking is needed on this line.');
    end;

    /// <summary>
    /// AC11 here, extended by #71 AC1 to every Warehouse type: no contract chapter, description, selection description or
    /// keyword list names an AL object, an object number or an internal procedure, in English (1033) or Icelandic (1039).
    /// </summary>
    [Test]
    procedure Help_NamesNoAlObjects()
    var
        ContractAssert: Codeunit "Whse Contract Assert ori";
        MessageType: Enum "Message Type ori";
        TypeCount: Integer;
    begin
        // #74 AC3: the contract is checked in both languages too, and the guard also rejects issue references.
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            AssertContractNamesNoAlObject(MessageType, 1033);
            AssertContractNamesNoAlObject(MessageType, 1039);
            AssertCatalogueNamesNoAlObject(MessageType, 1033);
            AssertCatalogueNamesNoAlObject(MessageType, 1039);
            TypeCount += 1;
        end;
        Assert.IsTrue(TypeCount >= 42, 'Every Warehouse type is checked.');
    end;

    /// <summary>#71 AC1: the guard itself finds object numbers and internal procedure names.</summary>
    [Test]
    procedure Help_Guard_FindsAlReferences()
    var
        ContractAssert: Codeunit "Whse Contract Assert ori";
    begin
        Assert.AreNotEqual('', ContractAssert.FindAlReference('Registers a Warehouse Pick (BC codeunit 7307 "Whse.-Activity-Register").'), 'A codeunit number is found.');
        Assert.AreNotEqual('', ContractAssert.FindAlReference('Creates a pick using report 7318.'), 'A report number is found.');
        Assert.AreNotEqual('', ContractAssert.FindAlReference('Call Dispatcher.Execute with OmitCommit = false.'), 'An internal procedure is found.');
        Assert.AreNotEqual('', ContractAssert.FindAlReference('Handled by Whse Pick Create Impl ori.'), 'An implementation codeunit is found.');
        Assert.AreEqual('', ContractAssert.FindAlReference('Check the number with Data.Records.Get on table Warehouse Shipment Header. It reports 4 tables.'), 'A table caption and plain words are allowed.');
        Assert.AreNotEqual('', ContractAssert.FindAlReference('Registration commits (core#985).'), 'A Foundation issue reference is found.');
        Assert.AreNotEqual('', ContractAssert.FindAlReference('Fixed in #71.'), 'An issue reference is found.');
        Assert.AreEqual('', ContractAssert.FindAlReference('Resend <parameter> as YYYY-MM-DD. A # sign alone is allowed.'), 'A # without a number is allowed.');
    end;

    /// <summary>#74 AC2: a declared nextStep with placeholders matches the answer that fills them in, and nothing else.</summary>
    [Test]
    procedure Help_NextStepPattern_MatchesTheAnswer()
    var
        ContractAssert: Codeunit "Whse Contract Assert ori";
    begin
        // Issue #74, AC2 | Time: none | Risk: none.
        Assert.IsTrue(ContractAssert.NextStepMatches('Resend <parameter> as YYYY-MM-DD.', 'Resend shipmentDateFrom as 2026-10-20.'), 'The date pattern matches.');
        Assert.IsTrue(ContractAssert.NextStepMatches('Resend <parameter> as YYYY-MM-DD.', 'Resend lines[0].expirationDate as 2026-01-05.'), 'A line parameter matches.');
        Assert.IsTrue(ContractAssert.NextStepMatches('Sendu <parameter> aftur sem YYYY-MM-DD.', 'Sendu shipmentDateFrom aftur sem 2026-10-20.'), 'The Icelandic pattern matches.');
        Assert.IsFalse(ContractAssert.NextStepMatches('Resend <parameter> as YYYY-MM-DD.', 'Resend  as 2026-10-20.'), 'An empty parameter does not match.');
        Assert.IsFalse(ContractAssert.NextStepMatches('Resend <parameter> as YYYY-MM-DD.', 'Send the date as text, for example 2026-10-19.'), 'Another nextStep does not match.');
        Assert.IsFalse(ContractAssert.NextStepMatches('Check the bin with Warehouse.Bin.Get.', 'Check the activity with Warehouse.Activity.Get.'), 'Plain texts must be equal.');
    end;

    /// <summary>
    /// #74 AC2: every type that reads skip and take declares the paging refusals, and every type that reads a date declares
    /// the "Resend &lt;parameter&gt; as YYYY-MM-DD." nextStep; the read types also declare the fallback and the reversed range.
    /// </summary>
    [Test]
    procedure ErrorsChapters_DeclarePagingAndDateNextSteps()
    var
        ContractAssert: Codeunit "Whse Contract Assert ori";
        Context: Codeunit "Whse Write Context ori";
        MessageType: Enum "Message Type ori";
        FormatNextStep: Text;
    begin
        // Issue #74, AC2 | Time: none | Risk: none.
        foreach MessageType in PagedTypes() do begin
            Assert.IsTrue(ContractAssert.IsDeclared(MessageType, 'InvalidParameter', Context.PagingNextStep()), TypeName(MessageType) + ' declares a negative skip or take.');
            // #79: these two reads now use the collecting reader for single as well as multiple paging problems.
            if MessageType in ["Message Type ori"::"Warehouse.Activity.Get", "Message Type ori"::"Warehouse.BinContent.Get"] then
                FormatNextStep := Context.PagingNextStep()
            else
                FormatNextStep := 'Send the value as an integer.';
            Assert.IsTrue(ContractAssert.IsDeclared(MessageType, 'InvalidParameterFormat', FormatNextStep), TypeName(MessageType) + ' declares the actual reader nextStep for a skip or take that is not a whole number.');
        end;
        foreach MessageType in DatedTypes() do
            Assert.IsTrue(ContractAssert.IsDeclared(MessageType, 'InvalidParameterFormat', 'Resend registeringDate as 2026-10-20.'), TypeName(MessageType) + ' declares the date to resend.');
        foreach MessageType in TextDateTypes() do begin
            Assert.IsTrue(ContractAssert.IsDeclared(MessageType, 'InvalidParameterFormat', Context.TextDateNextStep()), TypeName(MessageType) + ' declares the date fallback.');
            Assert.IsTrue(ContractAssert.IsDeclared(MessageType, 'InvalidParameter', Context.DateRangeNextStep()), TypeName(MessageType) + ' declares the reversed date range.');
        end;
    end;

    /// <summary>#74 AC4: the catalogue description of every Warehouse type is translated: the 1039 text differs from 1033.</summary>
    [Test]
    procedure EveryWarehouseType_DescriptionIsTranslated()
    var
        ContractAssert: Codeunit "Whse Contract Assert ori";
        MessageType: Enum "Message Type ori";
        Implementation: Interface "Msg Interface ori";
        EnglishDescription: Text;
        IcelandicDescription: Text;
        OriginalLanguage: Integer;
        TypeCount: Integer;
    begin
        // Issue #74, AC4 | Time: none | Risk: none.
        OriginalLanguage := GlobalLanguage();
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            Implementation := MessageType;
            GlobalLanguage(1033);
            EnglishDescription := Implementation.GetDescription();
            GlobalLanguage(1039);
            IcelandicDescription := Implementation.GetDescription();
            GlobalLanguage(OriginalLanguage);
            Assert.AreNotEqual('', IcelandicDescription, ContractAssert.TypeName(MessageType) + ' has an Icelandic description.');
            Assert.AreNotEqual(EnglishDescription, IcelandicDescription, ContractAssert.TypeName(MessageType) + ' description is translated.');
            TypeCount += 1;
        end;
        Assert.IsTrue(TypeCount >= 42, 'Every Warehouse type is checked.');
    end;

    /// <summary>#68 item 7: the help and catalogue texts name no internal procedure, in English and Icelandic.</summary>
    [Test]
    procedure Help_DoesNotNameValidate()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        MessageType: Enum "Message Type ori";
        Discovery: Interface "Msg Discovery ori";
        Contract: JsonObject;
        Languages: List of [Integer];
        ContractText: Text;
        LanguageId: Integer;
        OriginalLanguage: Integer;
    begin
        // Issue #68, AC2 (item 7) | Time: none | Risk: none.
        OriginalLanguage := GlobalLanguage();
        Languages.Add(1033);
        Languages.Add(1039);
        foreach LanguageId in Languages do begin
            GlobalLanguage(LanguageId);
            foreach MessageType in NewTypes() do begin
                Clear(Contract);
                Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), 'Contract exists.');
                Contract.WriteTo(ContractText);
                Discovery := MessageType;
                ContractText += Discovery.GetSelectionDescription();
                Assert.IsFalse(ContractText.Contains('through Validate'), TypeName(MessageType) + ' names Validate.');
                Assert.IsFalse(ContractText.Contains('með Validate'), TypeName(MessageType) + ' names Validate in Icelandic.');
                Assert.IsFalse(ContractText.Contains('efnislega birgðatalningu'), TypeName(MessageType) + ' uses birgðatalning.');
            end;
        end;
        GlobalLanguage(OriginalLanguage);
    end;

    /// <summary>#48 AC09: Warehouse Journal Line is closed to generic writes, including force, and the hint names the journal types.</summary>
    [Test]
    procedure GenericWrite_WarehouseJournalLine_IsRefusedAndHinted()
    var
        TempArgument: Record "Message Argument ori" temporary;
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Journal Line", true), 'Force must not reopen the journal line.');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Journal Line"), 'Reads stay allowed.');
        Assert.AreEqual(JournalHint(), TempArgument.GetDedicatedMessageTypeHintForWrite(Database::"Warehouse Journal Line"), 'Table hint.');
        AssertGenericSetRefused('Warehouse Journal Line', '{"tableName":"Warehouse Journal Line","force":true,"data":[{"primaryKey":{"Journal Template Name":"ITEM","Journal Batch Name":"DEFAULT","Location Code":"LOC","Line No.":10000},"fields":{"Quantity":5}}]}', JournalHint());
    end;

    /// <summary>#49 AC08: Qty. (Phys. Inventory) is a restricted field and its hint names the physical inventory types.</summary>
    [Test]
    procedure GenericWrite_QtyPhysInventory_IsHinted()
    var
        JournalLine: Record "Warehouse Journal Line";
        TempArgument: Record "Message Argument ori" temporary;
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.AreEqual('Warehouse.PhysInventory.Calculate, Warehouse.PhysInventory.Register', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Journal Line", JournalLine.FieldNo("Qty. (Phys. Inventory)")), 'Field hint.');
    end;

    /// <summary>#55 AC08: worksheet Qty. to Handle is restricted and its hint names the worksheet types.</summary>
    [Test]
    procedure GenericWrite_WorksheetQtyToHandle_IsRefusedAndHinted()
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        TempArgument: Record "Message Argument ori" temporary;
        Hint: Text;
    begin
        TempArgument.Init();
        TempArgument.Insert(true);
        Hint := 'Warehouse.BinReplenishment.Calculate, Warehouse.Movement.Create, Warehouse.Worksheet.GetDocuments, Warehouse.Worksheet.CreateActivities';

        Assert.AreEqual(Hint, TempArgument.GetDedicatedMessageTypeHintForField(Database::"Whse. Worksheet Line", WorksheetLine.FieldNo("Qty. to Handle")), 'Field hint.');
        AssertGenericSetRefused('Whse. Worksheet Line', '{"tableName":"Whse. Worksheet Line","force":true,"data":[{"primaryKey":{"Worksheet Template Name":"PICK","Name":"DEFAULT","Location Code":"LOC","Line No.":10000},"fields":{"Qty. to Handle":1}}]}', Hint);
    end;

    /// <summary>#56 AC10 and #57 AC08: activity line fields point at the activity line types; the table stays closed.</summary>
    [Test]
    procedure GenericWrite_ActivityLineFields_PointAtActivityLineTypes()
    var
        ActivityLine: Record "Warehouse Activity Line";
        TempArgument: Record "Message Argument ori" temporary;
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.IsTrue(TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Qty. to Handle")).Contains('Warehouse.ActivityLine.SetQtyToHandle'), 'Qty. to Handle hint.');
        Assert.IsTrue(TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Bin Code")).Contains('Warehouse.ActivityLine.ChangeBin'), 'Bin Code hint.');
        Assert.IsTrue(TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Zone Code")).Contains('Warehouse.ActivityLine.ChangeBin'), 'Zone Code hint.');
        Assert.IsTrue(TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Lot No.")).Contains('Warehouse.ActivityLine.AssignTracking'), 'Lot No. hint.');
        Assert.IsTrue(TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Serial No.")).Contains('Warehouse.ActivityLine.AssignTracking'), 'Serial No. hint.');
        Assert.IsTrue(TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Expiration Date")).Contains('Warehouse.ActivityLine.AssignTracking'), 'Expiration Date hint.');
        Assert.AreEqual('Warehouse.ActivityLine.AssignTracking', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Package No.")), 'Package No. hint.');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Activity Line", true), 'The activity line table stays closed.');
        Assert.IsTrue(TempArgument.GetDedicatedMessageTypeHintForWrite(Database::"Warehouse Activity Line").Contains('Warehouse.ActivityLine.Split, Warehouse.ActivityLine.ChangeBin, Warehouse.ActivityLine.SetQtyToHandle, Warehouse.ActivityLine.AssignTracking'), 'Table hint names the activity line types.');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Activity Line"), 'Reads stay allowed.');
    end;

    /// <summary>#88 AC02: every declared unknown-key next step matches Foundation in English.</summary>
    [Test]
    procedure UnknownParameterHelp_MatchesFoundationEnglish()
    begin
        AssertUnknownParameterHelp(1033, 'Remove this key or consult Help.Implementation.Get for the declared parameters.');
    end;

    /// <summary>#88 AC02: every declared unknown-key next step matches Foundation in Icelandic.</summary>
    [Test]
    procedure UnknownParameterHelp_MatchesFoundationIcelandic()
    begin
        AssertUnknownParameterHelp(1039, 'Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.');
    end;

    local procedure AssertUnknownParameterHelp(LanguageId: Integer; ExpectedNextStep: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        ContractAssert: Codeunit "Whse Contract Assert ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        ErrorsToken: JsonToken;
        Entry: JsonToken;
        OriginalLanguage: Integer;
        Checked: Integer;
        HasContract: Boolean;
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            Clear(Contract);
            OriginalLanguage := GlobalLanguage();
            GlobalLanguage(LanguageId);
            HasContract := ContractMgt.GetContract(MessageType, Contract);
            GlobalLanguage(OriginalLanguage);
            Assert.IsTrue(HasContract, ContractAssert.TypeName(MessageType) + ' has a contract.');
            if Contract.Get('errors', ErrorsToken) then
                foreach Entry in ErrorsToken.AsArray() do
                    if Helper.TextValue(Entry.AsObject(), 'code') = 'UnknownParameter' then begin
                        Assert.AreEqual(ExpectedNextStep, Helper.TextValue(Entry.AsObject(), 'nextStep'), ContractAssert.TypeName(MessageType) + ' unknown-key next step.');
                        Checked += 1;
                    end;
        end;
        Assert.IsTrue(Checked >= 30, 'All Warehouse declarations of UnknownParameter are checked.');
    end;

    local procedure AssertContractNamesNoAlObject(MessageType: Enum "Message Type ori"; LanguageId: Integer)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        ContractAssert: Codeunit "Whse Contract Assert ori";
        Contract: JsonObject;
        ContractText: Text;
        OriginalLanguage: Integer;
        HasContract: Boolean;
    begin
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(LanguageId);
        HasContract := ContractMgt.GetContract(MessageType, Contract);
        Contract.WriteTo(ContractText);
        GlobalLanguage(OriginalLanguage);
        Assert.IsTrue(HasContract, ContractAssert.TypeName(MessageType) + ' has a contract.');
        ContractAssert.AssertNamesNoAlObject(ContractText, ContractAssert.TypeName(MessageType) + ' contract (' + Format(LanguageId, 0, 9) + ')');
    end;

    local procedure PagedTypes() Types: List of [Enum "Message Type ori"]
    begin
        Types.Add("Message Type ori"::"Warehouse.Activity.Get");
        Types.Add("Message Type ori"::"Warehouse.BinContent.Get");
        Types.Add("Message Type ori"::"Warehouse.Bin.Get");
        Types.Add("Message Type ori"::"Warehouse.PostedDocument.Get");
        Types.Add("Message Type ori"::"Warehouse.RegisteredActivity.Get");
        Types.Add("Message Type ori"::"Warehouse.Request.Get");
    end;

    local procedure TextDateTypes() Types: List of [Enum "Message Type ori"]
    begin
        Types.Add("Message Type ori"::"Warehouse.PostedDocument.Get");
        Types.Add("Message Type ori"::"Warehouse.RegisteredActivity.Get");
        Types.Add("Message Type ori"::"Warehouse.Request.Get");
        Types.Add("Message Type ori"::"Warehouse.Receipt.GetSourceDocuments");
        Types.Add("Message Type ori"::"Warehouse.Shipment.GetSourceDocuments");
    end;

    local procedure DatedTypes() Types: List of [Enum "Message Type ori"]
    begin
        Types := TextDateTypes();
        Types.Add("Message Type ori"::"Warehouse.Journal.Create");
        Types.Add("Message Type ori"::"Warehouse.PhysInventory.Calculate");
        Types.Add("Message Type ori"::"Warehouse.Adjustment.Calculate");
        Types.Add("Message Type ori"::"Warehouse.ActivityLine.AssignTracking");
        Types.Add("Message Type ori"::"Warehouse.Receipt.Create");
        Types.Add("Message Type ori"::"Warehouse.Shipment.Create");
    end;

    local procedure AssertCatalogueNamesNoAlObject(MessageType: Enum "Message Type ori"; LanguageId: Integer)
    var
        ContractAssert: Codeunit "Whse Contract Assert ori";
        Discovery: Interface "Msg Discovery ori";
        Implementation: Interface "Msg Interface ori";
        OriginalLanguage: Integer;
        Context: Text;
    begin
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(LanguageId);
        Discovery := MessageType;
        Implementation := MessageType;
        Context := ContractAssert.TypeName(MessageType) + ' (' + Format(LanguageId, 0, 9) + ')';
        ContractAssert.AssertNamesNoAlObject(Implementation.GetDescription(), Context + ' description');
        ContractAssert.AssertNamesNoAlObject(Discovery.GetSelectionDescription(), Context + ' selection description');
        ContractAssert.AssertNamesNoAlObject(Discovery.GetKeywords(), Context + ' keywords');
        GlobalLanguage(OriginalLanguage);
    end;

    local procedure JournalHint(): Text
    begin
        exit('Warehouse.Journal.Create, Warehouse.Journal.Register, Warehouse.PhysInventory.Calculate, Warehouse.PhysInventory.Register');
    end;

    local procedure NewTypes() Types: List of [Enum "Message Type ori"]
    begin
        Types.Add("Message Type ori"::"Warehouse.Journal.Create");
        Types.Add("Message Type ori"::"Warehouse.Journal.Register");
        Types.Add("Message Type ori"::"Warehouse.PhysInventory.Calculate");
        Types.Add("Message Type ori"::"Warehouse.PhysInventory.Register");
        Types.Add("Message Type ori"::"Warehouse.Adjustment.Calculate");
        Types.Add("Message Type ori"::"Warehouse.Worksheet.GetDocuments");
        Types.Add("Message Type ori"::"Warehouse.Worksheet.CreateActivities");
        Types.Add("Message Type ori"::"Warehouse.ActivityLine.Split");
        Types.Add("Message Type ori"::"Warehouse.ActivityLine.ChangeBin");
        Types.Add("Message Type ori"::"Warehouse.ActivityLine.SetQtyToHandle");
        Types.Add("Message Type ori"::"Warehouse.ActivityLine.AssignTracking");
    end;

    local procedure AssertContract(MessageType: Enum "Message Type ori"; ExpectedEffect: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Token: JsonToken;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), TypeName(MessageType) + ' has a contract.');
        Assert.IsTrue(Contract.Contains('parameters'), TypeName(MessageType) + ' parameters.');
        Assert.IsTrue(Contract.Contains('errors'), TypeName(MessageType) + ' errors.');
        Assert.IsTrue(Contract.Contains('response'), TypeName(MessageType) + ' response.');
        Assert.IsTrue(Contract.Contains('examples'), TypeName(MessageType) + ' examples.');
        Assert.IsTrue(Contract.Get('effect', Token), TypeName(MessageType) + ' effect.');
        Assert.IsTrue(Token.AsObject().Get('effect', Token), TypeName(MessageType) + ' effect kind.');
        Assert.AreEqual(ExpectedEffect, Token.AsValue().AsText(), TypeName(MessageType) + ' effect kind.');
        Assert.AreEqual(3, TypeName(MessageType).Split('.').Count(), TypeName(MessageType) + ' has three name parts.');
    end;

    local procedure AssertBilingual(MessageType: Enum "Message Type ori")
    var
        Discovery: Interface "Msg Discovery ori";
        EnglishDescription: Text;
        IcelandicDescription: Text;
        EnglishKeywords: Text;
        IcelandicKeywords: Text;
        OriginalLanguage: Integer;
    begin
        OriginalLanguage := GlobalLanguage();
        Discovery := MessageType;
        GlobalLanguage(1033);
        EnglishDescription := Discovery.GetSelectionDescription();
        EnglishKeywords := Discovery.GetKeywords();
        GlobalLanguage(1039);
        IcelandicDescription := Discovery.GetSelectionDescription();
        IcelandicKeywords := Discovery.GetKeywords();
        GlobalLanguage(OriginalLanguage);
        Assert.AreNotEqual('', EnglishDescription, TypeName(MessageType) + ' English selection description.');
        Assert.AreNotEqual('', IcelandicDescription, TypeName(MessageType) + ' Icelandic selection description.');
        Assert.AreNotEqual(EnglishDescription, IcelandicDescription, TypeName(MessageType) + ' selection description is translated.');
        Assert.AreNotEqual(EnglishKeywords, IcelandicKeywords, TypeName(MessageType) + ' keywords are translated.');
    end;

    local procedure AssertDiscovery(MessageType: Enum "Message Type ori"; Expected: Text)
    var
        Discovery: Interface "Msg Discovery ori";
    begin
        Discovery := MessageType;
        Assert.AreEqual(Expected, Discovery.GetSelectionDescription(), TypeName(MessageType) + ' selection description.');
    end;

    local procedure AssertDeclaredError(MessageType: Enum "Message Type ori"; ErrorCode: Text; NextStep: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Contract: JsonObject;
        Token: JsonToken;
        Entry: JsonToken;
        Found: Boolean;
    begin
        Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), 'Contract exists.');
        Contract.Get('errors', Token);
        foreach Entry in Token.AsArray() do
            if (Helper.TextValue(Entry.AsObject(), 'code') = ErrorCode) and (Helper.TextValue(Entry.AsObject(), 'nextStep') = NextStep) then
                Found := true;
        Assert.IsTrue(Found, TypeName(MessageType) + ' declares ' + ErrorCode + ' with ' + NextStep);
    end;

    local procedure AssertGenericSetRefused(Subject: Text; RequestText: Text; ExpectedHint: Text)
    var
        ResponseJson: JsonObject;
    begin
        ResponseJson := Helper.RunType(Enum::"Message Type ori"::"Data.Records.Set", Subject, RequestText);
        Assert.AreEqual('PermissionDenied', Helper.TextValue(ResponseJson, 'code'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(ExpectedHint, Helper.TextValue(ResponseJson, 'nextStep'), Helper.ResponseText(ResponseJson));
    end;

    local procedure TypeName(MessageType: Enum "Message Type ori"): Text
    begin
        exit(Enum::"Message Type ori".Names().Get(Enum::"Message Type ori".Ordinals().IndexOf(MessageType.AsInteger())));
    end;
}
