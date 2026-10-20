namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Ledger;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.PhysInventory.Register (#49).
/// Writes the counted quantities through Validate of Qty. (Phys. Inventory) and registers the warehouse physical
/// inventory journal batch through codeunit 7304 "Whse. Jnl.-Register Batch", which commits. Requires the warehouse
/// posting gate.
/// </summary>
codeunit 10078449 "Whse PhysInvt Reg Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        JournalLine: Record "Warehouse Journal Line";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Journal Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        LineObject: JsonObject;
        Result: JsonObject;
        Token: JsonToken;
        Adjusted: JsonArray;
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        MissingPayloadErr: Label 'The physical inventory register payload was empty.', Comment = 'is-IS=Gögnin til að skrá talningu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        TemplateName := CopyStr(Values.TextValue(Payload, 'journalTemplateName'), 1, MaxStrLen(TemplateName));
        BatchName := CopyStr(Values.TextValue(Payload, 'journalBatchName'), 1, MaxStrLen(BatchName));
        LocationCode := CopyStr(Values.TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        foreach Token in Values.ArrayValue(Payload, 'lines') do begin
            LineObject := Token.AsObject();
            JournalLine.Get(TemplateName, BatchName, LocationCode, Values.IntegerValue(LineObject, 'lineNo'));
            JournalLine.Validate("Qty. (Phys. Inventory)", Values.DecimalValue(LineObject, 'qtyPhysInventory'));
            JournalLine.Modify(true);
        end;
        Clear(JournalLine);
        Helper.FilterBatch(JournalLine, TemplateName, BatchName, LocationCode);
        JournalLine.SetFilter(Quantity, '<>0');
        if JournalLine.FindSet() then
            repeat
                Adjusted.Add(Helper.LineJson(JournalLine));
            until JournalLine.Next() = 0;
        Result.Add('adjustedLines', Adjusted);
        Result.Add('registerNo', Helper.RegisterBatch(TemplateName, BatchName, LocationCode));
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can register warehouse journals and holds the warehouse posting gate.</summary>
    /// <returns>True when the caller can write the journal and holds BIFROST WhsePost ori.</returns>
    procedure IsEnabled(): Boolean
    var
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
    begin
        if not HasWritePermission() then
            exit(false);
        exit(WhsePostingGate.HasPostingPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse journal line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Journal Line");
    end;

    /// <summary>Returns a short description of Warehouse.PhysInventory.Register.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Writes counted quantities and registers a warehouse physical inventory journal batch.', Comment = 'is-IS=Skrifar talið magn og skráir keyrslu talningarbókar vöruhúss.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'register physical inventory, counted quantity, stock count result, warehouse count, register count', Comment = 'is-IS=skrá talningu, talið magn, niðurstaða birgðatalningar, vöruhúsatalning, skrá talningu vöruhúss';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Writes the counted quantities on the lines that Warehouse.PhysInventory.Calculate wrote and registers the whole batch; Business Central commits the warehouse entries. Needs BIFROST WhsePost ori.', Comment = 'is-IS=Óafturkræft. Skrifar talið magn á línurnar sem Warehouse.PhysInventory.Calculate skrifaði og skráir alla keyrsluna; Business Central staðfestir vöruhúsafærslurnar. Þarf BIFROST WhsePost ori.';
    begin
        exit(SelectionLbl);
    end;

    /// <summary>Returns the subject envelope.</summary>
    /// <param name="Envelope">Receives the envelope.</param>
    /// <returns>True when the envelope is used.</returns>
    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('location code');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. The directed location of the batch. Do not send a different location in subject and locationCode.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The directed location. Optional when locationCode is sent.'));
        Target.Add(ContractMgt.TargetEntry('data.journalTemplateName + data.journalBatchName + data.locationCode', 'journal batch', 'The warehouse physical inventory journal batch to register.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('journalTemplateName', 'string', true, 'Warehouse journal template of type Physical Inventory.'));
        Parameters.Add(ContractMgt.Parameter('journalBatchName', 'string', true, 'Warehouse physical inventory journal batch name.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Directed location of the batch. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Optional counted quantities. A line that is not sent keeps the quantity it has (the calculated quantity unless it was changed).'));
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Line number answered by Warehouse.PhysInventory.Calculate.'));
        Parameters.Add(ContractMgt.Parameter('qtyPhysInventory', 'number', true, 'Counted quantity in the line unit of measure, zero or more.'));
        exit(true);
    end;

    /// <summary>Returns the response chapter.</summary>
    /// <param name="Response">Receives the response.</param>
    /// <returns>True when a response is declared.</returns>
    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
        LineFields: JsonArray;
        Lines: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('journalTemplateName', 'string', 'Warehouse journal template.'));
        Fields.Add(ContractMgt.ResponseField('journalBatchName', 'string', 'Warehouse journal batch.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location of the batch.'));
        Fields.Add(ContractMgt.ResponseField('registeredLineCount', 'integer', 'Journal lines registered.'));
        Fields.Add(ContractMgt.ResponseField('adjustmentCount', 'integer', 'Lines whose counted quantity differs from the calculated one. Zero when the count matches.'));
        Fields.Add(ContractMgt.ResponseField('registerNo', 'integer', 'Warehouse register number.'));
        Fields.Add(ContractMgt.ResponseField('fromEntryNo', 'integer', 'First warehouse entry number of the register.'));
        Fields.Add(ContractMgt.ResponseField('toEntryNo', 'integer', 'Last warehouse entry number of the register.'));
        Fields.Add(ContractMgt.ResponseField('entryCount', 'integer', 'Number of warehouse entries written.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Journal line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin.'));
        LineFields.Add(ContractMgt.ResponseField('qtyCalculated', 'number', 'Calculated quantity.'));
        LineFields.Add(ContractMgt.ResponseField('qtyPhysInventory', 'number', 'Counted quantity.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Difference that was registered.'));
        LineFields.Add(ContractMgt.ResponseField('entryType', 'string', 'Positive Adjmt. or Negative Adjmt.'));
        Lines.Add('name', 'adjustedLines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Lines with a difference, as they were registered.');
        Lines.Add('children', LineFields);
        Fields.Add(Lines);
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use directed put-away and pick.', 'Use Inventory.PhysInventory.* for basic locations.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The batch has no lines.', 'Write the lines with Warehouse.PhysInventory.Calculate first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidLine, 'A counted line number is not in the batch.', 'Read the lines answered by Calculate.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The journal template or batch was not found at the location.', 'Create the batch first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The location was not found.', 'Check the location code and send the request again.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'A batch key is missing, or a line misses lineNo or qtyPhysInventory.', 'Send the batch keys, and lineNo and qtyPhysInventory on every line.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for the batch keys, an integer lineNo and a number for qtyPhysInventory.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'The template is not a physical inventory template, or a counted quantity is negative.', 'Use a physical inventory batch and send counted quantities of zero or more.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request or a line contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations.', 'Send one location: subject or locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write the warehouse journal, or does not hold the warehouse posting gate.', 'Ask an administrator to assign BIFROST Whse - Full ori and BIFROST WhsePost ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was registered.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the count or the registration.', 'Read the returned text and correct the line. Nothing was registered and no count was written.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Writes the counted quantities and registers the warehouse physical inventory journal batch: warehouse entries for every difference, a warehouse register, and the registered lines are deleted. Business Central commits the registration.', 'BIFROST Whse - Full ori and BIFROST WhsePost ori');
        exit(true);
    end;

    /// <summary>Returns the metering chapter.</summary>
    /// <param name="Metering">Receives the metering.</param>
    /// <returns>False. This type is not metered.</returns>
    procedure GetMetering(var Metering: JsonObject): Boolean
    begin
        exit(false);
    end;

    /// <summary>Returns related message types.</summary>
    /// <param name="Related">Receives the related types.</param>
    /// <returns>True when related types are declared.</returns>
    procedure GetRelated(var Related: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PhysInventory.Calculate', 'Use it to write the lines and their calculated quantities first.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Adjustment.Calculate', 'Use it after registering to bring the item ledger in line with the count.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True when a workflow is declared.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Helper: Codeunit "Whse Journal Helper ori";
    begin
        Helper.PhysInventoryWorkflow(Workflow);
        exit(true);
    end;

    /// <summary>Returns an example request and response.</summary>
    /// <param name="Examples">Receives the examples.</param>
    /// <returns>True when an example is declared.</returns>
    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Register a count with one difference',
            '{"journalTemplateName":"PHYS. INV.","journalBatchName":"DEFAULT","locationCode":"WHITE","lines":[{"lineNo":10000,"qtyPhysInventory":4}]}',
            '{"status":"Success","journalTemplateName":"PHYS. INV.","journalBatchName":"DEFAULT","locationCode":"WHITE","registeredLineCount":1,"adjustmentCount":1,"adjustedLines":[{"lineNo":10000,"itemNo":"1896-S","binCode":"W-01-0001","qtyCalculated":5,"qtyPhysInventory":4,"quantity":-1,"entryType":"Negative Adjmt."}],"registerNo":13,"fromEntryNo":303,"toEntryNo":304,"entryCount":2}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Writes the counted quantity on lines of a warehouse physical inventory batch and registers the whole batch. Business Central commits the registration. A count without differences registers with zero adjustments.', Comment = 'is-IS=Skrifar talið magn á línur í keyrslu talningarbókar vöruhúss og skráir alla keyrsluna. Business Central staðfestir skráninguna. Talning án mismunar er skráð með núll leiðréttingum.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Registration commits (core#985). The counted quantities are written and registered in one isolated run: a rejected registration also leaves the counts unwritten. The warehouse entries move the difference to and from the adjustment bin; run Warehouse.Adjustment.Calculate and Inventory.ItemJournal.Post so the item ledger follows.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the batch and the counted lines, then writes the counts and registers.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        JournalTemplate: Record "Warehouse Journal Template";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        Helper: Codeunit "Whse Journal Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        Lines: JsonArray;
        PlannedLines: JsonArray;
        AllowedKeys: List of [Text];
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        LineCount: Integer;
        LinesPresent: Boolean;
        DeniedLbl: Label 'You do not have permission to register a warehouse physical inventory.', Comment = 'is-IS=Þú hefur ekki heimild til að skrá talningu vöruhúss.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was registered.', Comment = 'is-IS=Ekkert var skráð.';
        DirectedNextStepLbl: Label 'Use Inventory.PhysInventory.* for basic locations.', Comment = 'is-IS=Notaðu Inventory.PhysInventory.* fyrir einfaldar staðsetningar.';
        EmptyLbl: Label 'Warehouse physical inventory batch %1 %2 has no lines.', Comment = '%1 = template, %2 = batch, is-IS=Talningarkeyrsla vöruhúss %1 %2 hefur engar línur.';
        EmptyNextStepLbl: Label 'Write the lines with Warehouse.PhysInventory.Calculate first.', Comment = 'is-IS=Skrifaðu línurnar með Warehouse.PhysInventory.Calculate fyrst.';
    begin
        Context.Reset();
        if not HasWritePermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        AllowedKeys.Add('journalTemplateName');
        AllowedKeys.Add('journalBatchName');
        AllowedKeys.Add('locationCode');
        AllowedKeys.Add('lines');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Helper.ReadBatchKeys(RequestJson, Argument, TemplateName, BatchName, LocationCode);
        Values.ReadArray(RequestJson, 'lines', Argument, Lines, LinesPresent);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not Helper.ResolveBatch(Argument, TemplateName, BatchName, LocationCode, true, DirectedNextStepLbl, JournalTemplate) then
            exit;
        LineCount := Helper.CountLines(TemplateName, BatchName, LocationCode);
        if LineCount = 0 then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(EmptyLbl, TemplateName, BatchName), 'journalBatchName', BatchName, '', EmptyNextStepLbl);
            exit;
        end;
        ReadLines(Lines, Argument, TemplateName, BatchName, LocationCode, PlannedLines);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('journalTemplateName', TemplateName);
        Payload.Add('journalBatchName', BatchName);
        Payload.Add('locationCode', LocationCode);
        Payload.Add('lines', PlannedLines);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse PhysInvt Reg Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse PhysInvt Reg Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        WriteResponse(Argument, TemplateName, BatchName, LocationCode, LineCount);
        Context.Reset();
    end;

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]; LineCount: Integer)
    var
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Journal Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Result: JsonObject;
        ResponseJson: JsonObject;
        Adjusted: JsonArray;
    begin
        Context.TryGetResult(Result);
        Adjusted := Values.ArrayValue(Result, 'adjustedLines');
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('journalTemplateName', TemplateName);
        ResponseJson.Add('journalBatchName', BatchName);
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('registeredLineCount', LineCount);
        ResponseJson.Add('adjustmentCount', Adjusted.Count());
        ResponseJson.Add('adjustedLines', Adjusted);
        Helper.AddRegister(ResponseJson, Values.IntegerValue(Result, 'registerNo'));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ReadLines(Lines: JsonArray; var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]; var PlannedLines: JsonArray)
    var
        JournalLine: Record "Warehouse Journal Line";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        LineObject: JsonObject;
        Planned: JsonObject;
        AllowedKeys: List of [Text];
        Index: Integer;
        ErrorCount: Integer;
        LineNo: Integer;
        Quantity: Decimal;
        LinePresent: Boolean;
        QuantityPresent: Boolean;
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line position in the request, counted from 1, %2 = parameter, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send lineNo and qtyPhysInventory on every line.', Comment = 'is-IS=Sendu lineNo og qtyPhysInventory á hverri línu.';
        NotInBatchLbl: Label 'Line %1 is not in warehouse physical inventory batch %2.', Comment = '%1 = line no., %2 = batch, is-IS=Lína %1 er ekki í talningarkeyrslu vöruhúss %2.';
        NotInBatchNextStepLbl: Label 'Read the lines answered by Calculate.', Comment = 'is-IS=Lestu línurnar sem Calculate skilaði.';
        NegativeLbl: Label 'qtyPhysInventory on line %1 must be zero or more.', Comment = '%1 = line no., is-IS=qtyPhysInventory á línu %1 verður að vera núll eða meira.';
        NegativeNextStepLbl: Label 'Send the counted quantity, zero or more.', Comment = 'is-IS=Sendu talið magn, núll eða meira.';
    begin
        AllowedKeys.Add('lineNo');
        AllowedKeys.Add('qtyPhysInventory');
        for Index := 0 to Lines.Count() - 1 do
            if Values.TryGetLineObject(Lines, Index, 'lines', Argument, LineObject) then begin
                ErrorCount := Argument.GetCollectedErrorsJson().Count();
                Values.RefuseUnknownKeys(LineObject, AllowedKeys, Argument, 'lines', Index);
                Context.ReadInteger(LineObject, 'lineNo', Argument, LineNo, LinePresent, Values.LineParameter('lines', Index, 'lineNo'));
                Context.ReadDecimal(LineObject, 'qtyPhysInventory', Argument, Quantity, QuantityPresent, Values.LineParameter('lines', Index, 'qtyPhysInventory'));
                if Argument.GetCollectedErrorsJson().Count() = ErrorCount then begin
                    if not LinePresent then
                        Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'lineNo'), Values.LineParameter('lines', Index, 'lineNo'), '', '', MissingNextStepLbl);
                    if not QuantityPresent then
                        Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'qtyPhysInventory'), Values.LineParameter('lines', Index, 'qtyPhysInventory'), '', '', MissingNextStepLbl);
                    if LinePresent and QuantityPresent then
                        if not JournalLine.Get(TemplateName, BatchName, LocationCode, LineNo) then
                            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(NotInBatchLbl, LineNo, BatchName), Values.LineParameter('lines', Index, 'lineNo'), Format(LineNo, 0, 9), '', NotInBatchNextStepLbl)
                        else
                            if Quantity < 0 then
                                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(NegativeLbl, LineNo), Values.LineParameter('lines', Index, 'qtyPhysInventory'), Format(Quantity, 0, 9), '', NegativeNextStepLbl)
                            else begin
                                Clear(Planned);
                                Planned.Add('lineNo', LineNo);
                                Planned.Add('qtyPhysInventory', Quantity);
                                PlannedLines.Add(Planned);
                            end;
                end;
            end;
    end;

    local procedure HasWritePermission(): Boolean
    var
        JournalLine: Record "Warehouse Journal Line";
        WarehouseEntry: Record "Warehouse Entry";
        WarehouseRegister: Record "Warehouse Register";
    begin
        exit(JournalLine.WritePermission() and WarehouseEntry.ReadPermission() and WarehouseRegister.ReadPermission());
    end;
}
