namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Journal;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Adjustment.Calculate (#50).
/// Runs report 7315 "Calculate Whse. Adjustment" into an empty item journal batch. Posting stays with Foundation's
/// Inventory.ItemJournal.Post.
/// </summary>
codeunit 10078450 "Whse Adjustment Calc Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ItemJournalLine: Record "Item Journal Line";
        Item: Record Item;
        CalculateAdjustment: Report "Calculate Whse. Adjustment";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        PostingDate: Date;
        MissingPayloadErr: Label 'The warehouse adjustment payload was empty.', Comment = 'is-IS=Gögnin fyrir leiðréttingu vöruhúss voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        DeleteEmptyLines(CopyStr(Values.TextValue(Payload, 'journalTemplateName'), 1, 10), CopyStr(Values.TextValue(Payload, 'journalBatchName'), 1, 10));
        ItemJournalLine.Init();
        ItemJournalLine."Journal Template Name" := CopyStr(Values.TextValue(Payload, 'journalTemplateName'), 1, MaxStrLen(ItemJournalLine."Journal Template Name"));
        ItemJournalLine."Journal Batch Name" := CopyStr(Values.TextValue(Payload, 'journalBatchName'), 1, MaxStrLen(ItemJournalLine."Journal Batch Name"));
        PostingDate := Values.DateValue(Payload, 'postingDate');
        if PostingDate = 0D then
            PostingDate := WorkDate();
        if Values.TextValue(Payload, 'itemNo') <> '' then
            Item.SetRange("No.", CopyStr(Values.TextValue(Payload, 'itemNo'), 1, MaxStrLen(Item."No.")));
        if Values.TextValue(Payload, 'locationCode') <> '' then
            Item.SetRange("Location Filter", CopyStr(Values.TextValue(Payload, 'locationCode'), 1, 10));
        CalculateAdjustment.SetItemJnlLine(ItemJournalLine);
        CalculateAdjustment.InitializeRequest(PostingDate, CopyStr(Values.TextValue(Payload, 'documentNo'), 1, 20));
        CalculateAdjustment.SetHideValidationDialog(true);
        CalculateAdjustment.SetTableView(Item);
        CalculateAdjustment.UseRequestPage(false);
        CalculateAdjustment.Run();
    end;

    /// <summary>Returns whether the caller can write item journal lines.</summary>
    /// <returns>True when the caller can calculate the warehouse adjustment.</returns>
    procedure IsEnabled(): Boolean
    var
        ItemJournalLine: Record "Item Journal Line";
        Location: Record Location;
    begin
        exit(ItemJournalLine.WritePermission() and Location.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The item journal line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Item Journal Line");
    end;

    /// <summary>Returns a short description of Warehouse.Adjustment.Calculate.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Calculates the warehouse adjustment of directed locations into an empty item journal batch.', Comment = 'is-IS=Reiknar leiðréttingu vöruhúss á beinum staðsetningum inn í tóma keyrslu birgðabókar.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'calculate warehouse adjustment, adjustment bin, item journal, synchronize item ledger, warehouse to inventory', Comment = 'is-IS=reikna leiðréttingu vöruhúss, leiðréttingarhólf, birgðabók, samstilla birgðahöfuðbók, vöruhús í birgðir';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Writes item journal lines for the quantity in the adjustment bins of directed locations, so the item ledger can follow registered warehouse adjustments. It posts nothing; post the batch with Inventory.ItemJournal.Post, sending journalTemplateName as templateName and journalBatchName as batchName. The batch must be empty.', Comment = 'is-IS=Skrifar línur í birgðabók fyrir magnið í leiðréttingarhólfum beinna staðsetninga, svo birgðahöfuðbókin geti fylgt skráðum leiðréttingum vöruhúss. Hún bókar ekkert; bókaðu keyrsluna með Inventory.ItemJournal.Post og sendu journalTemplateName sem templateName og journalBatchName sem batchName. Keyrslan verður að vera tóm.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. Limits the calculation to one directed location, like locationCode. Do not send a different location in both.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'Optional location filter.'));
        Target.Add(ContractMgt.TargetEntry('data.journalTemplateName + data.journalBatchName', 'item journal batch', 'The empty item journal batch the lines are written to.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('journalTemplateName', 'string', true, 'Item journal template of type Item. Inventory.ItemJournal.Post calls it templateName.'));
        Parameters.Add(ContractMgt.Parameter('journalBatchName', 'string', true, 'Item journal batch name. The batch must be empty. Inventory.ItemJournal.Post calls it batchName.'));
        Parameters.Add(ContractMgt.Parameter('postingDate', 'string', false, 'Posting date written as YYYY-MM-DD. Defaults to the work date.'));
        Parameters.Add(ContractMgt.Parameter('documentNo', 'string', false, 'Document number of the lines. Required when the batch has no number series.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', false, 'Limits the calculation to one item.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Limits the calculation to one directed location.'));
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
        Fields.Add(ContractMgt.ResponseField('journalTemplateName', 'string', 'Item journal template.'));
        Fields.Add(ContractMgt.ResponseField('journalBatchName', 'string', 'Item journal batch.'));
        Fields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of item journal lines written. Nothing to adjust answers zero.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Item journal line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        LineFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        LineFields.Add(ContractMgt.ResponseField('entryType', 'string', 'Positive Adjmt. or Negative Adjmt.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity of the line.'));
        LineFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure.'));
        LineFields.Add(ContractMgt.ResponseField('documentNo', 'string', 'Document number.'));
        LineFields.Add(ContractMgt.ResponseField('postingDate', 'string', 'Posting date, YYYY-MM-DD.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Item journal lines written by this call.');
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
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The item journal template or batch was not found.', 'Create the batch first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The item or location was not found.', 'Check the value and send the request again.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The batch already has lines with an item. The empty line Business Central leaves after posting does not count.', 'Post the lines with Inventory.ItemJournal.Post (templateName, batchName), or delete them first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use directed put-away and pick, so it has no warehouse adjustment.', 'Send a directed location, or omit locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'journalTemplateName or journalBatchName is missing, or documentNo is missing for a batch without a number series.', 'Send the batch keys, and documentNo when the batch has no number series.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, is too long, or a date is not YYYY-MM-DD.', 'Send text for codes and dates.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'The item journal template is not of type Item.', 'Use an item journal template of type Item.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations.', 'Send one location: subject or locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write item journal lines.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the calculation.', 'Read the returned text and correct the batch. Nothing was written.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Writes item journal lines (and their reservation entries for tracked items) into the empty batch. Nothing is posted.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Inventory.ItemJournal.Post', 'Use it to post the calculated lines: send journalTemplateName as templateName and journalBatchName as batchName.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Journal.Register', 'Use it first to register the warehouse adjustments that this type brings to the item ledger.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PhysInventory.Register', 'Use it first to register a warehouse count.'));
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
            'Calculate the adjustment of one item',
            '{"journalTemplateName":"ITEM","journalBatchName":"WHSEADJ","itemNo":"1896-S","documentNo":"ADJ-01"}',
            '{"status":"Success","journalTemplateName":"ITEM","journalBatchName":"WHSEADJ","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"1896-S","variantCode":"","locationCode":"WHITE","entryType":"Positive Adjmt.","quantity":5,"unitOfMeasureCode":"PCS","documentNo":"ADJ-01","postingDate":"2026-10-19"}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Runs Calculate Warehouse Adjustment into an empty item journal batch, filtered by item and location, and answers the lines it wrote. Nothing to adjust is a success with an empty list. Post the batch with Inventory.ItemJournal.Post (templateName = journalTemplateName, batchName = journalBatchName).', Comment = 'is-IS=Keyrir Reikna leiðréttingu vöruhúss inn í tóma keyrslu birgðabókar, síað eftir vöru og staðsetningu, og skilar línunum sem hún skrifaði. Ekkert til að leiðrétta er árangur með tómum lista. Bókaðu keyrsluna með Inventory.ItemJournal.Post (templateName = journalTemplateName, batchName = journalBatchName).';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>False. There are no extra notes.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := '';
        exit(false);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the batch and the filters and runs the calculation, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        AllowedKeys: List of [Text];
        TemplateText: Text;
        BatchText: Text;
        DocumentNoText: Text;
        ItemText: Text;
        LocationText: Text;
        PostingDate: Date;
        TemplatePresent: Boolean;
        BatchPresent: Boolean;
        Present: Boolean;
        LocationPresent: Boolean;
        TemplateRead: Boolean;
        BatchRead: Boolean;
        DocumentNoRead: Boolean;
        ItemRead: Boolean;
        LocationRead: Boolean;
        DeniedLbl: Label 'You do not have permission to calculate the warehouse adjustment.', Comment = 'is-IS=Þú hefur ekki heimild til að reikna leiðréttingu vöruhúss.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
        MissingLbl: Label '%1 is required.', Comment = '%1 = parameter, is-IS=%1 er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send journalTemplateName and journalBatchName.', Comment = 'is-IS=Sendu journalTemplateName og journalBatchName.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
    begin
        Context.Reset();
        if not IsEnabled() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        AllowedKeys.Add('journalTemplateName');
        AllowedKeys.Add('journalBatchName');
        AllowedKeys.Add('postingDate');
        AllowedKeys.Add('documentNo');
        AllowedKeys.Add('itemNo');
        AllowedKeys.Add('locationCode');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        TemplateRead := Context.ReadText(RequestJson, 'journalTemplateName', 10, Argument, TemplateText, TemplatePresent, 'journalTemplateName');
        BatchRead := Context.ReadText(RequestJson, 'journalBatchName', 10, Argument, BatchText, BatchPresent, 'journalBatchName');
        Values.ReadDate(RequestJson, 'postingDate', Argument, PostingDate, Present, 'postingDate');
        DocumentNoRead := Context.ReadText(RequestJson, 'documentNo', 20, Argument, DocumentNoText, Present, 'documentNo');
        ItemRead := Context.ReadText(RequestJson, 'itemNo', 20, Argument, ItemText, Present, 'itemNo');
        LocationRead := Context.ReadText(RequestJson, 'locationCode', 10, Argument, LocationText, LocationPresent, 'locationCode');
        // Independent problems are answered together (#68): a value that was read is checked even when another failed.
        if TemplateRead and not TemplatePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'journalTemplateName'), 'journalTemplateName', '', '', MissingNextStepLbl);
        if BatchRead and not BatchPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'journalBatchName'), 'journalBatchName', '', '', MissingNextStepLbl);
        if LocationPresent and (DelChr(Argument.Subject, '<>', ' ') <> '') and (UpperCase(DelChr(Argument.Subject, '<>', ' ')) <> UpperCase(LocationText)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationText, Argument.Subject, ConflictNextStepLbl);
            // Which location was meant is unclear, so neither is looked up.
            LocationRead := false;
        end;
        if LocationRead and not LocationPresent then
            LocationText := CopyStr(DelChr(Argument.Subject, '<>', ' '), 1, 10);
        if TemplatePresent and BatchPresent then
            CheckBatch(Argument, CopyStr(TemplateText, 1, 10), CopyStr(BatchText, 1, 10), DocumentNoText, DocumentNoRead);
        if not ItemRead then
            ItemText := '';
        if not LocationRead then
            LocationText := '';
        CheckFilters(Argument, ItemText, LocationText);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('journalTemplateName', TemplateText);
        Payload.Add('journalBatchName', BatchText);
        Payload.Add('postingDate', Values.DateText(PostingDate));
        Payload.Add('documentNo', DocumentNoText);
        Payload.Add('itemNo', ItemText);
        Payload.Add('locationCode', LocationText);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Adjustment Calc Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Adjustment Calc Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        WriteResponse(Argument, CopyStr(TemplateText, 1, 10), CopyStr(BatchText, 1, 10));
        Context.Reset();
    end;

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10])
    var
        ItemJournalLine: Record "Item Journal Line";
        Values: Codeunit "Whse Msg Values ori";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
        Lines: JsonArray;
    begin
        ItemJournalLine.SetRange("Journal Template Name", TemplateName);
        ItemJournalLine.SetRange("Journal Batch Name", BatchName);
        ItemJournalLine.SetLoadFields("Line No.", "Item No.", "Variant Code", "Location Code", "Entry Type", Quantity, "Unit of Measure Code", "Document No.", "Posting Date");
        if ItemJournalLine.FindSet() then
            repeat
                Clear(LineJson);
                LineJson.Add('lineNo', ItemJournalLine."Line No.");
                LineJson.Add('itemNo', ItemJournalLine."Item No.");
                LineJson.Add('variantCode', ItemJournalLine."Variant Code");
                LineJson.Add('locationCode', ItemJournalLine."Location Code");
                LineJson.Add('entryType', EntryTypeName(ItemJournalLine."Entry Type"));
                LineJson.Add('quantity', ItemJournalLine.Quantity);
                LineJson.Add('unitOfMeasureCode', ItemJournalLine."Unit of Measure Code");
                LineJson.Add('documentNo', ItemJournalLine."Document No.");
                LineJson.Add('postingDate', Values.DateText(ItemJournalLine."Posting Date"));
                Lines.Add(LineJson);
            until ItemJournalLine.Next() = 0;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('journalTemplateName', TemplateName);
        ResponseJson.Add('journalBatchName', BatchName);
        ResponseJson.Add('lineCount', Lines.Count());
        ResponseJson.Add('lines', Lines);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure CheckBatch(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; DocumentNoText: Text; DocumentNoRead: Boolean)
    var
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
        ItemJournalLine: Record "Item Journal Line";
        TemplateNotFoundLbl: Label 'Item journal template %1 was not found.', Comment = '%1 = template, is-IS=Birgðabókarsniðmát %1 fannst ekki.';
        BatchNotFoundLbl: Label 'Item journal batch %1 %2 was not found.', Comment = '%1 = template, %2 = batch, is-IS=Keyrsla birgðabókar %1 %2 fannst ekki.';
        CreateBatchNextStepLbl: Label 'Create the batch first.', Comment = 'is-IS=Stofnaðu keyrsluna fyrst.';
        TypeLbl: Label 'Item journal template %1 is not of type Item.', Comment = '%1 = template, is-IS=Birgðabókarsniðmát %1 er ekki af tegundinni Vara.';
        TypeNextStepLbl: Label 'Use an item journal template of type Item.', Comment = 'is-IS=Notaðu birgðabókarsniðmát af tegundinni Vara.';
        HasLinesLbl: Label 'Item journal batch %1 %2 already has lines.', Comment = '%1 = template, %2 = batch, is-IS=Keyrsla birgðabókar %1 %2 hefur þegar línur.';
        HasLinesNextStepLbl: Label 'Post the lines with Inventory.ItemJournal.Post (templateName %1, batchName %2), or delete them first.', Comment = '%1 = template, %2 = batch, is-IS=Bókaðu línurnar með Inventory.ItemJournal.Post (templateName %1, batchName %2), eða eyddu þeim fyrst.';
        DocumentNoLbl: Label 'documentNo is required because batch %1 has no number series.', Comment = '%1 = batch, is-IS=documentNo er nauðsynlegt því keyrsla %1 hefur enga númeraröð.';
        DocumentNoNextStepLbl: Label 'Send documentNo, or give the batch a number series.', Comment = 'is-IS=Sendu documentNo, eða gefðu keyrslunni númeraröð.';
    begin
        ItemJournalTemplate.SetLoadFields(Name, Type, Recurring);
        if not ItemJournalTemplate.Get(TemplateName) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(TemplateNotFoundLbl, TemplateName), 'journalTemplateName', TemplateName, '', CreateBatchNextStepLbl);
            exit;
        end;
        if (ItemJournalTemplate.Type <> ItemJournalTemplate.Type::Item) or ItemJournalTemplate.Recurring then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TypeLbl, TemplateName), 'journalTemplateName', TemplateName, 'Item', TypeNextStepLbl);
            exit;
        end;
        ItemJournalBatch.SetLoadFields("Journal Template Name", Name, "No. Series");
        if not ItemJournalBatch.Get(TemplateName, BatchName) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(BatchNotFoundLbl, TemplateName, BatchName), 'journalBatchName', BatchName, '', CreateBatchNextStepLbl);
            exit;
        end;
        // The empty line Business Central leaves after posting a batch is not a line (#68); OnRun deletes it.
        ItemJournalLine.SetRange("Journal Template Name", TemplateName);
        ItemJournalLine.SetRange("Journal Batch Name", BatchName);
        ItemJournalLine.SetFilter("Item No.", '<>%1', '');
        if not ItemJournalLine.IsEmpty() then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(HasLinesLbl, TemplateName, BatchName), 'journalBatchName', BatchName, '', StrSubstNo(HasLinesNextStepLbl, TemplateName, BatchName));
        if DocumentNoRead and (DocumentNoText = '') and (ItemJournalBatch."No. Series" = '') then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(DocumentNoLbl, BatchName), 'documentNo', '', '', DocumentNoNextStepLbl);
    end;

    local procedure DeleteEmptyLines(TemplateName: Code[10]; BatchName: Code[10])
    var
        ItemJournalLine: Record "Item Journal Line";
    begin
        ItemJournalLine.SetRange("Journal Template Name", TemplateName);
        ItemJournalLine.SetRange("Journal Batch Name", BatchName);
        ItemJournalLine.SetRange("Item No.", '');
        ItemJournalLine.SetRange(Quantity, 0);
        if not ItemJournalLine.IsEmpty() then
            ItemJournalLine.DeleteAll(true);
    end;

    local procedure CheckFilters(var Argument: Record "Message Argument ori"; ItemText: Text; LocationText: Text)
    var
        Item: Record Item;
        Location: Record Location;
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table caption, %2 = value, is-IS=%1 %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the value and send the request again.', Comment = 'is-IS=Athugaðu gildið og sendu beiðnina aftur.';
        DirectedLbl: Label 'Location %1 does not use directed put-away and pick, so it has no warehouse adjustment.', Comment = '%1 = location, is-IS=Staðsetning %1 notar ekki beina frágangs- og tínsluvinnslu, svo hún hefur enga leiðréttingu vöruhúss.';
        DirectedNextStepLbl: Label 'Send a directed location, or omit locationCode.', Comment = 'is-IS=Sendu beina staðsetningu, eða slepptu locationCode.';
    begin
        if ItemText <> '' then begin
            Item.SetLoadFields("No.");
            if not Item.Get(CopyStr(ItemText, 1, MaxStrLen(Item."No."))) then
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemText), 'itemNo', ItemText, '', NotFoundNextStepLbl);
        end;
        if LocationText <> '' then begin
            Location.SetLoadFields(Code, "Directed Put-away and Pick");
            if not Location.Get(CopyStr(LocationText, 1, MaxStrLen(Location.Code))) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Location.TableCaption(), LocationText), 'locationCode', LocationText, '', NotFoundNextStepLbl);
                exit;
            end;
            if not Location."Directed Put-away and Pick" then
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(DirectedLbl, LocationText), 'locationCode', LocationText, '', DirectedNextStepLbl);
        end;
    end;

    local procedure EntryTypeName(EntryType: Enum "Item Ledger Entry Type"): Text
    begin
        exit(Enum::"Item Ledger Entry Type".Names().Get(Enum::"Item Ledger Entry Type".Ordinals().IndexOf(EntryType.AsInteger())));
    end;
}
