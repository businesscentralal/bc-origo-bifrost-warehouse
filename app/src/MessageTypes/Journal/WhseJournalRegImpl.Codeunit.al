namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Ledger;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Journal.Register (#48).
/// Registers a warehouse item or reclassification journal batch through codeunit 7304 "Whse. Jnl.-Register Batch",
/// which commits. Requires the warehouse posting gate.
/// </summary>
codeunit 10078447 "Whse Journal Reg Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Journal Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The warehouse journal register payload was empty.', Comment = 'is-IS=Gögnin til að skrá birgðabók vöruhússins voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        Result.Add('registerNo', Helper.RegisterBatch(
            CopyStr(Values.TextValue(Payload, 'journalTemplateName'), 1, 10),
            CopyStr(Values.TextValue(Payload, 'journalBatchName'), 1, 10),
            CopyStr(Values.TextValue(Payload, 'locationCode'), 1, 10)));
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can register warehouse journals and holds the warehouse posting gate.</summary>
    /// <returns>True when the caller can write the journal and the warehouse register and holds BIFROST WhsePost ori.</returns>
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

    /// <summary>Returns a short description of Warehouse.Journal.Register.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Registers a warehouse item or reclassification journal batch and returns the warehouse register.', Comment = 'is-IS=Skráir keyrslu í birgðabók eða endurflokkunarbók vöruhúss og skilar vöruhúsaskránni.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'register warehouse journal, register bin adjustment, register reclassification, warehouse register, post warehouse journal', Comment = 'is-IS=skrá birgðabók vöruhúss, skrá leiðréttingu hólfs, skrá endurflokkun, vöruhúsaskrá, bóka birgðabók vöruhúss';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Registers every line of a warehouse item or reclassification journal batch and Business Central commits the warehouse entries. Needs BIFROST WhsePost ori. Use Warehouse.PhysInventory.Register for a physical inventory batch.', Comment = 'is-IS=Óafturkræft. Skráir allar línur keyrslu í birgðabók eða endurflokkunarbók vöruhúss og Business Central staðfestir vöruhúsafærslurnar. Þarf BIFROST WhsePost ori. Notaðu Warehouse.PhysInventory.Register fyrir talningarkeyrslu.';
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
        Target.Add(ContractMgt.TargetEntry('data.journalTemplateName + data.journalBatchName + data.locationCode', 'journal batch', 'The warehouse item or reclassification journal batch to register.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('journalTemplateName', 'string', true, 'Warehouse journal template of type Item or Reclassification.'));
        Parameters.Add(ContractMgt.Parameter('journalBatchName', 'string', true, 'Warehouse journal batch name.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Directed location of the batch. Required when subject is empty.'));
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
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('journalTemplateName', 'string', 'Warehouse journal template.'));
        Fields.Add(ContractMgt.ResponseField('journalBatchName', 'string', 'Warehouse journal batch.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location of the batch.'));
        Fields.Add(ContractMgt.ResponseField('registeredLineCount', 'integer', 'Journal lines registered.'));
        Fields.Add(ContractMgt.ResponseField('registerNo', 'integer', 'Warehouse register number.'));
        Fields.Add(ContractMgt.ResponseField('fromEntryNo', 'integer', 'First warehouse entry number of the register.'));
        Fields.Add(ContractMgt.ResponseField('toEntryNo', 'integer', 'Last warehouse entry number of the register.'));
        Fields.Add(ContractMgt.ResponseField('entryCount', 'integer', 'Number of warehouse entries written.'));
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
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use directed put-away and pick.', 'Use Inventory.ItemJournal.* or Inventory.Reclassification.* for basic locations.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The batch has no lines.', 'Add lines with Warehouse.Journal.Create.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The journal template or batch was not found at the location.', 'Create the batch first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The location was not found.', 'Check the location code and send the request again.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'journalTemplateName, journalBatchName or locationCode is missing.', 'Send journalTemplateName, journalBatchName and locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for the batch keys.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'The template is a physical inventory template.', 'Use Warehouse.PhysInventory.Calculate and Warehouse.PhysInventory.Register for a physical inventory journal.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations.', 'Send one location: subject or locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write the warehouse journal and register, or does not hold the warehouse posting gate.', 'Ask an administrator to assign BIFROST Whse - Full ori and BIFROST WhsePost ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was registered.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the registration, for example a negative adjustment above the bin content or missing item tracking.', 'Read the returned text, correct the lines with Warehouse.Journal.Create or Data.Records.Get, and register again. Nothing was registered.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Registers the warehouse journal batch: writes warehouse entries and a warehouse register, posts the item ledger for reclassification lines and deletes the registered lines. Business Central commits the registration.', 'BIFROST Whse - Full ori and BIFROST WhsePost ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Journal.Create', 'Use it to add the lines before registering.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Adjustment.Calculate', 'Use it after registering an item journal to bring the item ledger in line.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PhysInventory.Register', 'Use it for a physical inventory batch.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True when a workflow is declared.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Helper: Codeunit "Whse Journal Helper ori";
    begin
        Helper.JournalWorkflow(Workflow);
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
            'Register a warehouse item journal batch',
            '{"journalTemplateName":"ITEM","journalBatchName":"DEFAULT","locationCode":"WHITE"}',
            '{"status":"Success","journalTemplateName":"ITEM","journalBatchName":"DEFAULT","locationCode":"WHITE","registeredLineCount":1,"registerNo":12,"fromEntryNo":301,"toEntryNo":302,"entryCount":2}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Registers a warehouse item or reclassification journal batch at a directed location and returns the warehouse register and its entry range. Business Central commits the registration. An empty batch is refused.', Comment = 'is-IS=Skráir keyrslu í birgðabók eða endurflokkunarbók vöruhúss á beinni staðsetningu og skilar vöruhúsaskránni og færslubili hennar. Business Central staðfestir skráninguna. Tómri keyrslu er hafnað.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Registration commits, also when the template increments the batch name. Item journal lines only change the warehouse: run Warehouse.Adjustment.Calculate and Inventory.ItemJournal.Post afterwards so the item ledger follows. Reclassification lines post their item ledger entries during registration.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the batch and registers it.</summary>
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
        AllowedKeys: List of [Text];
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        LineCount: Integer;
        DeniedLbl: Label 'You do not have permission to register a warehouse journal.', Comment = 'is-IS=Þú hefur ekki heimild til að skrá birgðabók vöruhúss.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was registered.', Comment = 'is-IS=Ekkert var skráð.';
        DirectedNextStepLbl: Label 'Use Inventory.ItemJournal.* or Inventory.Reclassification.* for basic locations.', Comment = 'is-IS=Notaðu Inventory.ItemJournal.* eða Inventory.Reclassification.* fyrir einfaldar staðsetningar.';
        EmptyLbl: Label 'Warehouse journal batch %1 %2 has no lines.', Comment = '%1 = template, %2 = batch, is-IS=Bókarkeyrsla vöruhúss %1 %2 hefur engar línur.';
        EmptyNextStepLbl: Label 'Add lines with Warehouse.Journal.Create.', Comment = 'is-IS=Bættu við línum með Warehouse.Journal.Create.';
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
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Helper.ReadBatchKeys(RequestJson, Argument, TemplateName, BatchName, LocationCode);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not Helper.ResolveBatch(Argument, TemplateName, BatchName, LocationCode, false, DirectedNextStepLbl, JournalTemplate) then
            exit;
        LineCount := Helper.CountLines(TemplateName, BatchName, LocationCode);
        if LineCount = 0 then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(EmptyLbl, TemplateName, BatchName), 'journalBatchName', BatchName, '', EmptyNextStepLbl);
            exit;
        end;
        Payload.Add('journalTemplateName', TemplateName);
        Payload.Add('journalBatchName', BatchName);
        Payload.Add('locationCode', LocationCode);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Journal Reg Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Journal Reg Impl ori") then begin
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
    begin
        Context.TryGetResult(Result);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('journalTemplateName', TemplateName);
        ResponseJson.Add('journalBatchName', BatchName);
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('registeredLineCount', LineCount);
        Helper.AddRegister(ResponseJson, Values.IntegerValue(Result, 'registerNo'));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
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
