namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Ledger;
using Microsoft.Warehouse.Tracking;
using Origo.Bifrost;

/// <summary>
/// Shared journal logic for Warehouse.Journal.Create, Warehouse.Journal.Register,
/// Warehouse.PhysInventory.Calculate and Warehouse.PhysInventory.Register (#48, #49).
/// The four types write Warehouse Journal Line and register through codeunit 7304 "Whse. Jnl.-Register Batch".
/// </summary>
codeunit 10078451 "Whse Journal Helper ori"
{
    Access = Internal;

    /// <summary>Reads journalTemplateName, journalBatchName and locationCode (or the subject) and collects format and missing errors.</summary>
    /// <param name="RequestJson">The request.</param>
    /// <param name="Argument">Collects the errors.</param>
    /// <param name="TemplateName">Receives the template name.</param>
    /// <param name="BatchName">Receives the batch name.</param>
    /// <param name="LocationCode">Receives the location code.</param>
    internal procedure ReadBatchKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var TemplateName: Code[10]; var BatchName: Code[10]; var LocationCode: Code[10])
    var
        Context: Codeunit "Whse Write Context ori";
        TemplateText: Text;
        BatchText: Text;
        LocationText: Text;
        SubjectText: Text;
        TemplatePresent: Boolean;
        BatchPresent: Boolean;
        LocationPresent: Boolean;
        Conflict: Boolean;
        ErrorCount: Integer;
        MissingLbl: Label '%1 is required.', Comment = '%1 = parameter, is-IS=%1 er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send journalTemplateName, journalBatchName and locationCode.', Comment = 'is-IS=Sendu journalTemplateName, journalBatchName og locationCode.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
    begin
        Clear(TemplateName);
        Clear(BatchName);
        Clear(LocationCode);
        // Only a format error of these keys stops here; problems collected before (an unknown key) do not (#68).
        ErrorCount := Argument.GetCollectedErrorsJson().Count();
        Context.ReadText(RequestJson, 'journalTemplateName', MaxStrLen(TemplateName), Argument, TemplateText, TemplatePresent, 'journalTemplateName');
        Context.ReadText(RequestJson, 'journalBatchName', MaxStrLen(BatchName), Argument, BatchText, BatchPresent, 'journalBatchName');
        Context.ReadText(RequestJson, 'locationCode', MaxStrLen(LocationCode), Argument, LocationText, LocationPresent, 'locationCode');
        if Argument.GetCollectedErrorsJson().Count() <> ErrorCount then
            exit;
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        Conflict := LocationPresent and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(LocationText));
        if Conflict then
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationText, SubjectText, ConflictNextStepLbl);
        if not LocationPresent then
            LocationText := SubjectText;
        if StrLen(LocationText) > MaxStrLen(LocationCode) then
            LocationText := '';
        if not TemplatePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'journalTemplateName'), 'journalTemplateName', '', '', MissingNextStepLbl);
        if not BatchPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'journalBatchName'), 'journalBatchName', '', '', MissingNextStepLbl);
        if LocationText = '' then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'locationCode'), 'locationCode', '', '', MissingNextStepLbl);
        TemplateName := CopyStr(TemplateText, 1, MaxStrLen(TemplateName));
        BatchName := CopyStr(BatchText, 1, MaxStrLen(BatchName));
        LocationCode := CopyStr(LocationText, 1, MaxStrLen(LocationCode));
        // Which location was meant is unclear, so the caller looks none up.
        if Conflict then
            Clear(LocationCode);
    end;

    /// <summary>
    /// Checks the location, the directed put-away and pick setup, the template and its type, and the batch.
    /// Writes the refusal on Argument and returns false on the first failure.
    /// </summary>
    /// <param name="Argument">Receives the refusal.</param>
    /// <param name="TemplateName">Journal template name.</param>
    /// <param name="BatchName">Journal batch name.</param>
    /// <param name="LocationCode">Location code.</param>
    /// <param name="PhysInventory">True for the physical inventory types, false for the item and reclassification types.</param>
    /// <param name="DirectedNextStep">The next step answered for a location without directed put-away and pick.</param>
    /// <param name="JournalTemplate">Receives the template.</param>
    /// <returns>True when the batch can be used.</returns>
    internal procedure ResolveBatch(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]; PhysInventory: Boolean; DirectedNextStep: Text; var JournalTemplate: Record "Warehouse Journal Template"): Boolean
    var
        TemplateFound: Boolean;
    begin
        exit(CheckBatch(Argument, TemplateName, BatchName, LocationCode, PhysInventory, DirectedNextStep, false, JournalTemplate, TemplateFound));
    end;

    /// <summary>
    /// Checks the batch like ResolveBatch, but adds every independent problem to the collected errors instead of
    /// answering the first one (#68). The template and batch are checked only at a directed location that exists.
    /// </summary>
    /// <param name="Argument">Collects the problems.</param>
    /// <param name="TemplateName">Journal template name.</param>
    /// <param name="BatchName">Journal batch name.</param>
    /// <param name="LocationCode">Location code.</param>
    /// <param name="PhysInventory">True for the physical inventory types, false for the item and reclassification types.</param>
    /// <param name="DirectedNextStep">The next step for a location without directed put-away and pick.</param>
    /// <param name="JournalTemplate">Receives the template.</param>
    /// <param name="TemplateFound">True when JournalTemplate holds a template of the right kind, so its type can be used.</param>
    /// <returns>True when the batch can be used.</returns>
    internal procedure CollectBatchProblems(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]; PhysInventory: Boolean; DirectedNextStep: Text; var JournalTemplate: Record "Warehouse Journal Template"; var TemplateFound: Boolean): Boolean
    begin
        exit(CheckBatch(Argument, TemplateName, BatchName, LocationCode, PhysInventory, DirectedNextStep, true, JournalTemplate, TemplateFound));
    end;

    local procedure CheckBatch(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]; PhysInventory: Boolean; DirectedNextStep: Text; Collect: Boolean; var JournalTemplate: Record "Warehouse Journal Template"; var TemplateFound: Boolean): Boolean
    var
        Location: Record Location;
        JournalBatch: Record "Warehouse Journal Batch";
        LocationNotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        LocationNextStepLbl: Label 'Check the location code and send the request again.', Comment = 'is-IS=Athugaðu staðsetningarkóðann og sendu beiðnina aftur.';
        DirectedLbl: Label 'Location %1 does not use directed put-away and pick.', Comment = '%1 = location, is-IS=Staðsetning %1 notar ekki beina frágangs- og tínsluvinnslu.';
        TemplateNotFoundLbl: Label 'Warehouse journal template %1 was not found.', Comment = '%1 = template, is-IS=Birgðabókarsniðmát vöruhúss %1 fannst ekki.';
        BatchNotFoundLbl: Label 'Warehouse journal batch %1 %2 was not found at location %3.', Comment = '%1 = template, %2 = batch, %3 = location, is-IS=Bókarkeyrsla vöruhúss %1 %2 fannst ekki á staðsetningu %3.';
        CreateBatchNextStepLbl: Label 'Create the batch first.', Comment = 'is-IS=Stofnaðu keyrsluna fyrst.';
        PhysTemplateLbl: Label 'Warehouse journal template %1 is a physical inventory template.', Comment = '%1 = template, is-IS=Birgðabókarsniðmát vöruhúss %1 er sniðmát fyrir birgðatalningu.';
        PhysTemplateNextStepLbl: Label 'Use Warehouse.PhysInventory.Calculate and Warehouse.PhysInventory.Register for a physical inventory journal.', Comment = 'is-IS=Notaðu Warehouse.PhysInventory.Calculate og Warehouse.PhysInventory.Register fyrir talningarbók.';
        NotPhysTemplateLbl: Label 'Warehouse journal template %1 is not a physical inventory template.', Comment = '%1 = template, is-IS=Birgðabókarsniðmát vöruhúss %1 er ekki sniðmát fyrir birgðatalningu.';
        NotPhysTemplateNextStepLbl: Label 'Use a physical inventory template, or Warehouse.Journal.Create for item and reclassification journals.', Comment = 'is-IS=Notaðu talningarsniðmát, eða Warehouse.Journal.Create fyrir birgða- og endurflokkunarbækur.';
    begin
        TemplateFound := false;
        // A warehouse journal batch belongs to a directed location, so nothing else is checked without one.
        Location.SetLoadFields(Code, "Directed Put-away and Pick");
        if not Location.Get(LocationCode) then begin
            Refuse(Argument, Collect, "Bifrost Error Code ori"::RecordNotFound, StrSubstNo(LocationNotFoundLbl, LocationCode), 'locationCode', LocationCode, '', LocationNextStepLbl);
            exit(false);
        end;
        if not Location."Directed Put-away and Pick" then begin
            Refuse(Argument, Collect, "Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(DirectedLbl, LocationCode), 'locationCode', LocationCode, '', DirectedNextStep);
            exit(false);
        end;
        JournalTemplate.SetLoadFields(Name, Type);
        if not JournalTemplate.Get(TemplateName) then begin
            Refuse(Argument, Collect, "Bifrost Error Code ori"::RecordNotFound, StrSubstNo(TemplateNotFoundLbl, TemplateName), 'journalTemplateName', TemplateName, '', CreateBatchNextStepLbl);
            exit(false);
        end;
        if PhysInventory and (JournalTemplate.Type <> JournalTemplate.Type::"Physical Inventory") then begin
            Refuse(Argument, Collect, "Bifrost Error Code ori"::InvalidParameter, StrSubstNo(NotPhysTemplateLbl, TemplateName), 'journalTemplateName', TemplateName, 'Physical Inventory', NotPhysTemplateNextStepLbl);
            exit(false);
        end;
        if (not PhysInventory) and (JournalTemplate.Type = JournalTemplate.Type::"Physical Inventory") then begin
            Refuse(Argument, Collect, "Bifrost Error Code ori"::InvalidParameter, StrSubstNo(PhysTemplateLbl, TemplateName), 'journalTemplateName', TemplateName, 'Item, Reclassification', PhysTemplateNextStepLbl);
            exit(false);
        end;
        TemplateFound := true;
        JournalBatch.SetLoadFields("Journal Template Name", Name, "Location Code");
        if not JournalBatch.Get(TemplateName, BatchName, LocationCode) then begin
            Refuse(Argument, Collect, "Bifrost Error Code ori"::RecordNotFound, StrSubstNo(BatchNotFoundLbl, TemplateName, BatchName, LocationCode), 'journalBatchName', BatchName, '', CreateBatchNextStepLbl);
            exit(false);
        end;
        exit(true);
    end;

    local procedure Refuse(var Argument: Record "Message Argument ori"; Collect: Boolean; ErrorCode: Enum "Bifrost Error Code ori"; Message: Text; ParameterName: Text; Received: Text; Expected: Text; NextStep: Text)
    begin
        if Collect then
            Argument.AddError(ErrorCode, Message, ParameterName, Received, Expected, NextStep)
        else
            Argument.RespondWithError(ErrorCode, Message, ParameterName, Received, Expected, NextStep);
    end;

    /// <summary>Returns the number of lines with an item in the batch. The empty line Business Central leaves after registering is not counted.</summary>
    /// <param name="TemplateName">Journal template name.</param>
    /// <param name="BatchName">Journal batch name.</param>
    /// <param name="LocationCode">Location code.</param>
    /// <returns>The line count.</returns>
    internal procedure CountLines(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]): Integer
    var
        JournalLine: Record "Warehouse Journal Line";
    begin
        FilterBatch(JournalLine, TemplateName, BatchName, LocationCode);
        JournalLine.SetFilter("Item No.", '<>%1', '');
        exit(JournalLine.Count());
    end;

    /// <summary>
    /// Deletes the empty lines of the batch (no item, no quantity). Business Central leaves one after registering a batch
    /// without a number series; registering it again would fail on its missing bin. Call it inside the isolated run.
    /// </summary>
    /// <param name="TemplateName">Journal template name.</param>
    /// <param name="BatchName">Journal batch name.</param>
    /// <param name="LocationCode">Location code.</param>
    internal procedure DeleteEmptyLines(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        JournalLine: Record "Warehouse Journal Line";
    begin
        FilterBatch(JournalLine, TemplateName, BatchName, LocationCode);
        JournalLine.SetRange("Item No.", '');
        JournalLine.SetRange(Quantity, 0);
        if not JournalLine.IsEmpty() then
            JournalLine.DeleteAll(true);
    end;

    /// <summary>Returns the highest line number in the batch, or zero.</summary>
    /// <param name="TemplateName">Journal template name.</param>
    /// <param name="BatchName">Journal batch name.</param>
    /// <param name="LocationCode">Location code.</param>
    /// <returns>The last line number.</returns>
    internal procedure LastLineNo(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]): Integer
    var
        JournalLine: Record "Warehouse Journal Line";
    begin
        FilterBatch(JournalLine, TemplateName, BatchName, LocationCode);
        JournalLine.SetLoadFields("Line No.");
        if JournalLine.FindLast() then
            exit(JournalLine."Line No.");
        exit(0);
    end;

    /// <summary>Filters a journal line record on one batch.</summary>
    /// <param name="JournalLine">The record to filter.</param>
    /// <param name="TemplateName">Journal template name.</param>
    /// <param name="BatchName">Journal batch name.</param>
    /// <param name="LocationCode">Location code.</param>
    internal procedure FilterBatch(var JournalLine: Record "Warehouse Journal Line"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    begin
        JournalLine.SetRange("Journal Template Name", TemplateName);
        JournalLine.SetRange("Journal Batch Name", BatchName);
        JournalLine.SetRange("Location Code", LocationCode);
    end;

    /// <summary>Registers the batch through codeunit 7304 "Whse. Jnl.-Register Batch". Call it inside the isolated run.</summary>
    /// <param name="TemplateName">Journal template name.</param>
    /// <param name="BatchName">Journal batch name.</param>
    /// <param name="LocationCode">Location code.</param>
    /// <returns>The warehouse register number, or zero when no entry was written.</returns>
    internal procedure RegisterBatch(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]): Integer
    var
        JournalLine: Record "Warehouse Journal Line";
        WarehouseRegister: Record "Warehouse Register";
        RegisterBatchCodeunit: Codeunit "Whse. Jnl.-Register Batch";
        LastRegisterNo: Integer;
        NothingErr: Label 'The warehouse journal batch has no lines to register.', Comment = 'is-IS=Bókarkeyrsla vöruhússins hefur engar línur til að skrá.';
    begin
        DeleteEmptyLines(TemplateName, BatchName, LocationCode);
        FilterBatch(JournalLine, TemplateName, BatchName, LocationCode);
        if not JournalLine.FindFirst() then
            Error(NothingErr);
        WarehouseRegister.SetLoadFields("No.");
        if WarehouseRegister.FindLast() then
            LastRegisterNo := WarehouseRegister."No.";
        RegisterBatchCodeunit.Run(JournalLine);
        // Codeunit 7304 does not hand the register number back reliably, so read the register it wrote.
        Clear(WarehouseRegister);
        WarehouseRegister.SetFilter("No.", '>%1', LastRegisterNo);
        WarehouseRegister.SetRange("Journal Batch Name", BatchName);
        WarehouseRegister.SetLoadFields("No.");
        if WarehouseRegister.FindLast() then
            exit(WarehouseRegister."No.");
        exit(0);
    end;

    /// <summary>Adds registerNo, fromEntryNo, toEntryNo and entryCount to a response.</summary>
    /// <param name="ResponseJson">The response.</param>
    /// <param name="RegisterNo">The warehouse register number, or zero.</param>
    internal procedure AddRegister(var ResponseJson: JsonObject; RegisterNo: Integer)
    var
        WarehouseRegister: Record "Warehouse Register";
        FromEntryNo: Integer;
        ToEntryNo: Integer;
    begin
        if RegisterNo <> 0 then begin
            WarehouseRegister.SetLoadFields("From Entry No.", "To Entry No.");
            if WarehouseRegister.Get(RegisterNo) then begin
                FromEntryNo := WarehouseRegister."From Entry No.";
                ToEntryNo := WarehouseRegister."To Entry No.";
            end;
        end;
        ResponseJson.Add('registerNo', RegisterNo);
        ResponseJson.Add('fromEntryNo', FromEntryNo);
        ResponseJson.Add('toEntryNo', ToEntryNo);
        if ToEntryNo >= FromEntryNo then
            if FromEntryNo <> 0 then
                ResponseJson.Add('entryCount', ToEntryNo - FromEntryNo + 1)
            else
                ResponseJson.Add('entryCount', 0)
        else
            ResponseJson.Add('entryCount', 0);
    end;

    /// <summary>Writes one journal line as JSON.</summary>
    /// <param name="JournalLine">The line.</param>
    /// <returns>The line object.</returns>
    internal procedure LineJson(JournalLine: Record "Warehouse Journal Line"): JsonObject
    var
        Values: Codeunit "Whse Msg Values ori";
        LineObject: JsonObject;
    begin
        // Warehouse.Journal.Create keeps the tracking numbers on Whse. Item Tracking Line, not on the line (#68).
        if (JournalLine."Lot No." = '') and (JournalLine."Serial No." = '') and (JournalLine."Package No." = '') then
            ReadTrackingLine(JournalLine);
        LineObject.Add('lineNo', JournalLine."Line No.");
        LineObject.Add('itemNo', JournalLine."Item No.");
        LineObject.Add('variantCode', JournalLine."Variant Code");
        LineObject.Add('unitOfMeasureCode', JournalLine."Unit of Measure Code");
        LineObject.Add('entryType', EntryTypeName(JournalLine));
        LineObject.Add('zoneCode', JournalLine."Zone Code");
        LineObject.Add('binCode', JournalLine."Bin Code");
        LineObject.Add('fromBin', JournalLine."From Bin Code");
        LineObject.Add('toBin', JournalLine."To Bin Code");
        LineObject.Add('quantity', JournalLine.Quantity);
        LineObject.Add('qtyCalculated', JournalLine."Qty. (Calculated)");
        LineObject.Add('qtyPhysInventory', JournalLine."Qty. (Phys. Inventory)");
        LineObject.Add('lotNo', JournalLine."Lot No.");
        LineObject.Add('serialNo', JournalLine."Serial No.");
        LineObject.Add('packageNo', JournalLine."Package No.");
        LineObject.Add('whseDocumentNo', JournalLine."Whse. Document No.");
        LineObject.Add('registeringDate', Values.DateText(JournalLine."Registering Date"));
        exit(LineObject);
    end;

    /// <summary>The warehouse journal flow: lines, register, item ledger adjustment.</summary>
    /// <param name="Workflow">Receives the workflow chapter.</param>
    internal procedure JournalWorkflow(var Workflow: JsonObject)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Journal.Create', 'Insert warehouse item or reclassification journal lines; or Warehouse.PhysInventory.Calculate for a count.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Journal.Register', 'Register the batch; or Warehouse.PhysInventory.Register with the counted quantities.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Adjustment.Calculate', 'Calculate the warehouse adjustment into an item journal batch.'));
        Steps.Add(ContractMgt.WorkflowStep('Inventory.ItemJournal.Post', 'Post the item journal so the item ledger matches the bins; send templateName and batchName.'));
        Workflow.Add('steps', Steps);
    end;

    /// <summary>The warehouse physical inventory flow: calculate, count, register.</summary>
    /// <param name="Workflow">Receives the workflow chapter.</param>
    internal procedure PhysInventoryWorkflow(var Workflow: JsonObject)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.PhysInventory.Calculate', 'Write the physical inventory lines with the calculated quantity per bin.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.PhysInventory.Register', 'Send the counted quantity per line and register the batch.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Adjustment.Calculate', 'Calculate the warehouse adjustment into an item journal batch.'));
        Steps.Add(ContractMgt.WorkflowStep('Inventory.ItemJournal.Post', 'Post the item journal so the item ledger matches the count; send templateName and batchName.'));
        Workflow.Add('steps', Steps);
    end;

    local procedure ReadTrackingLine(var JournalLine: Record "Warehouse Journal Line")
    var
        TrackingLine: Record "Whse. Item Tracking Line";
    begin
        if not TrackingLine.ReadPermission() then
            exit;
        TrackingLine.SetRange("Source Type", Database::"Warehouse Journal Line");
        TrackingLine.SetRange("Source ID", JournalLine."Journal Batch Name");
        TrackingLine.SetRange("Source Batch Name", JournalLine."Journal Template Name");
        TrackingLine.SetRange("Source Ref. No.", JournalLine."Line No.");
        TrackingLine.SetRange("Location Code", JournalLine."Location Code");
        TrackingLine.SetLoadFields("Lot No.", "Serial No.", "Package No.");
        if not TrackingLine.FindFirst() then
            exit;
        JournalLine."Lot No." := TrackingLine."Lot No.";
        JournalLine."Serial No." := TrackingLine."Serial No.";
        JournalLine."Package No." := TrackingLine."Package No.";
    end;

    local procedure EntryTypeName(JournalLine: Record "Warehouse Journal Line"): Text
    begin
        case JournalLine."Entry Type" of
            JournalLine."Entry Type"::"Negative Adjmt.":
                exit('Negative Adjmt.');
            JournalLine."Entry Type"::"Positive Adjmt.":
                exit('Positive Adjmt.');
            JournalLine."Entry Type"::Movement:
                exit('Movement');
        end;
        exit('');
    end;
}
