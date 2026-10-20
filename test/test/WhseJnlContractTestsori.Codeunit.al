namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
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
        AssertDeclaredError("Message Type ori"::"Warehouse.Adjustment.Calculate", 'PreconditionFailed', 'Post or delete the existing lines first.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Worksheet.GetDocuments", 'PreconditionFailed', 'Use the inventory activities instead.');
        AssertDeclaredError("Message Type ori"::"Warehouse.Worksheet.CreateActivities", 'RecordNotFound', 'Create the worksheet name first, and use the line numbers answered by Warehouse.Worksheet.GetDocuments.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.Split", 'PreconditionFailed', 'Lower qtyToHandle first; BC splits the rest off.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.ChangeBin", 'InvalidLine', 'Read Warehouse.BinContent.Get.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.ChangeBin", 'ConflictingIdentifiers', 'Use the activity no. answered by Warehouse.Activity.Get.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'InvalidLine', 'One entry per serial no.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'InvalidLine', 'Read Inventory.TrackingAvailability.Get for the item.');
        AssertDeclaredError("Message Type ori"::"Warehouse.ActivityLine.AssignTracking", 'PreconditionFailed', 'No tracking is needed on this line.');
    end;

    /// <summary>
    /// AC11 here, extended by #71 AC1 to every Warehouse type: no contract chapter, description, selection description or
    /// keyword list names an AL object, an object number or an internal procedure, in English (1033) or Icelandic (1039).
    /// </summary>
    [Test]
    procedure Help_NamesNoAlObjects()
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        ContractAssert: Codeunit "Whse Contract Assert ori";
        MessageType: Enum "Message Type ori";
        Contract: JsonObject;
        ContractText: Text;
        TypeCount: Integer;
    begin
        foreach MessageType in ContractAssert.WarehouseTypes() do begin
            Clear(Contract);
            Assert.IsTrue(ContractMgt.GetContract(MessageType, Contract), ContractAssert.TypeName(MessageType) + ' has a contract.');
            Contract.WriteTo(ContractText);
            ContractAssert.AssertNamesNoAlObject(ContractText, ContractAssert.TypeName(MessageType) + ' contract');
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
