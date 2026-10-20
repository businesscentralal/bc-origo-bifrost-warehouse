namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.PhysInventory.Calculate (#49).
/// Runs report 7390 "Whse. Calculate Inventory" into a warehouse physical inventory journal batch at a directed
/// put-away and pick location and answers the calculated lines.
/// </summary>
codeunit 10078448 "Whse PhysInvt Calc Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        JournalLine: Record "Warehouse Journal Line";
        BinContent: Record "Bin Content";
        CalculateInventory: Report "Whse. Calculate Inventory";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Journal Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        RegisteringDate: Date;
        MissingPayloadErr: Label 'The physical inventory payload was empty.', Comment = 'is-IS=Gögnin fyrir birgðatalningu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        JournalLine.Init();
        JournalLine."Journal Template Name" := CopyStr(Values.TextValue(Payload, 'journalTemplateName'), 1, MaxStrLen(JournalLine."Journal Template Name"));
        JournalLine."Journal Batch Name" := CopyStr(Values.TextValue(Payload, 'journalBatchName'), 1, MaxStrLen(JournalLine."Journal Batch Name"));
        JournalLine."Location Code" := CopyStr(Values.TextValue(Payload, 'locationCode'), 1, MaxStrLen(JournalLine."Location Code"));
        Helper.DeleteEmptyLines(JournalLine."Journal Template Name", JournalLine."Journal Batch Name", JournalLine."Location Code");
        Context.SetSnapshot(Helper.LastLineNo(JournalLine."Journal Template Name", JournalLine."Journal Batch Name", JournalLine."Location Code"));
        RegisteringDate := Values.DateValue(Payload, 'registeringDate');
        if RegisteringDate = 0D then
            RegisteringDate := WorkDate();
        BinContent.SetRange("Location Code", JournalLine."Location Code");
        if Values.TextValue(Payload, 'zoneCode') <> '' then
            BinContent.SetRange("Zone Code", CopyStr(Values.TextValue(Payload, 'zoneCode'), 1, MaxStrLen(BinContent."Zone Code")));
        if Values.TextValue(Payload, 'binCode') <> '' then
            BinContent.SetRange("Bin Code", CopyStr(Values.TextValue(Payload, 'binCode'), 1, MaxStrLen(BinContent."Bin Code")));
        if Values.TextValue(Payload, 'itemNo') <> '' then
            BinContent.SetRange("Item No.", CopyStr(Values.TextValue(Payload, 'itemNo'), 1, MaxStrLen(BinContent."Item No.")));
        CalculateInventory.SetWhseJnlLine(JournalLine);
        CalculateInventory.InitializeRequest(RegisteringDate, CopyStr(Values.TextValue(Payload, 'documentNo'), 1, 20), Values.BooleanValue(Payload, 'itemsNotOnInventory'));
        CalculateInventory.SetHideValidationDialog(true);
        CalculateInventory.SetTableView(BinContent);
        CalculateInventory.UseRequestPage(false);
        CalculateInventory.Run();
    end;

    /// <summary>Returns whether the caller can write warehouse journal lines and read bins and their content.</summary>
    /// <returns>True when the caller can calculate a warehouse physical inventory.</returns>
    procedure IsEnabled(): Boolean
    var
        JournalLine: Record "Warehouse Journal Line";
        BinContent: Record "Bin Content";
        Bin: Record Bin;
    begin
        exit(JournalLine.WritePermission() and BinContent.ReadPermission() and Bin.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse journal line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Journal Line");
    end;

    /// <summary>Returns a short description of Warehouse.PhysInventory.Calculate.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Calculates the warehouse physical inventory of a directed location into a physical inventory journal batch.', Comment = 'is-IS=Reiknar talningu vöruhúss á beinni staðsetningu inn í keyrslu talningarbókar.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'warehouse physical inventory, calculate inventory, stock count, cycle count, bin count, physical inventory journal', Comment = 'is-IS=talning vöruhúss, reikna birgðir, birgðatalning, reglubundin talning, talning hólfa, talningarbók';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Writes warehouse physical inventory journal lines with the calculated quantity per bin at a directed put-away and pick location. Nothing is registered; send the counted quantities to Warehouse.PhysInventory.Register. Use Inventory.PhysInventory.* at a basic location.', Comment = 'is-IS=Skrifar línur í talningarbók vöruhúss með reiknuðu magni fyrir hvert hólf á staðsetningu með beina frágangs- og tínsluvinnslu. Ekkert er skráð; sendu talið magn í Warehouse.PhysInventory.Register. Notaðu Inventory.PhysInventory.* á einfaldri staðsetningu.';
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
        Target.Add(ContractMgt.TargetEntry('data.journalTemplateName + data.journalBatchName + data.locationCode', 'journal batch', 'The warehouse physical inventory journal batch.'));
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
        Parameters.Add(ContractMgt.Parameter('registeringDate', 'string', false, 'Registering date written as YYYY-MM-DD. Defaults to the work date.'));
        Parameters.Add(ContractMgt.Parameter('documentNo', 'string', false, 'Warehouse document number of the lines. Required when the batch has no number series.'));
        Parameters.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Limits the calculation to one zone.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', false, 'Limits the calculation to one bin.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', false, 'Limits the calculation to one item.'));
        Parameters.Add(ContractMgt.Parameter('itemsNotOnInventory', 'boolean', false, 'Also write lines for bin content with zero quantity. Defaults to false.'));
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
        Fields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of lines this call wrote. Nothing to count answers zero.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Journal line number; send it to Warehouse.PhysInventory.Register with the counted quantity.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin.'));
        LineFields.Add(ContractMgt.ResponseField('qtyCalculated', 'number', 'Quantity the warehouse entries hold in the bin.'));
        LineFields.Add(ContractMgt.ResponseField('qtyPhysInventory', 'number', 'Counted quantity; Business Central fills it with the calculated quantity.'));
        LineFields.Add(ContractMgt.ResponseField('lotNo', 'string', 'Lot number of a tracked line.'));
        LineFields.Add(ContractMgt.ResponseField('serialNo', 'string', 'Serial number of a tracked line.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Lines this call wrote.');
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
        Parts: Codeunit "Whse Contract Parts ori";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use directed put-away and pick.', 'Use Inventory.PhysInventory.* for basic locations.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The journal template or batch was not found at the location.', 'Create the batch first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The location, zone, bin or item was not found.', 'Check the value and send the request again.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'journalTemplateName, journalBatchName or locationCode is missing, or documentNo is missing for a batch without a number series.', 'Send the batch keys, and documentNo when the batch has no number series.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, is too long, or a date is not YYYY-MM-DD.', 'Send text for codes and dates and true or false for itemsNotOnInventory.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'The template is not a physical inventory template.', 'Use a physical inventory template, or Warehouse.Journal.Create for item and reclassification journals.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations, or the bin is not in the named zone.', 'Send one location, and a bin that belongs to the named zone.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write warehouse journal lines.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the calculation.', 'Read the returned text and correct the batch or the filters. Nothing was written.');
        Parts.AddDateErrors(Errors, 'registeringDate', Context.IsoDateNextStep());
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Writes warehouse physical inventory journal lines for the filtered bin content. Nothing is registered. Calling it twice adds the lines twice.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PhysInventory.Register', 'Use it to send the counted quantities and register the batch.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read bin content without writing journal lines.'));
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
            'Count one zone',
            '{"journalTemplateName":"PHYS. INV.","journalBatchName":"DEFAULT","locationCode":"WHITE","zoneCode":"PICK","documentNo":"COUNT-01"}',
            '{"status":"Success","journalTemplateName":"PHYS. INV.","journalBatchName":"DEFAULT","locationCode":"WHITE","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"1896-S","zoneCode":"PICK","binCode":"W-01-0001","qtyCalculated":5,"qtyPhysInventory":5}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Runs Calculate Inventory into a warehouse physical inventory journal batch at a directed location, filtered by zone, bin and item, and answers the lines it wrote with the calculated quantity. Nothing to count is a success with an empty list.', Comment = 'is-IS=Keyrir Reikna birgðir inn í keyrslu talningarbókar vöruhúss á beinni staðsetningu, síað eftir svæði, hólfi og vöru, og skilar línunum sem hún skrifaði með reiknuðu magni. Ekkert til að telja er árangur með tómum lista.';
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

    /// <summary>Validates the request and runs the calculation, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        JournalTemplate: Record "Warehouse Journal Template";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Journal Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        AllowedKeys: List of [Text];
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        RegisteringDate: Date;
        DocumentNoText: Text;
        ZoneText: Text;
        BinText: Text;
        ItemText: Text;
        ItemsNotOnInventory: Boolean;
        Present: Boolean;
        DeniedLbl: Label 'You do not have permission to calculate a warehouse physical inventory.', Comment = 'is-IS=Þú hefur ekki heimild til að reikna talningu vöruhúss.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
        DirectedNextStepLbl: Label 'Use Inventory.PhysInventory.* for basic locations.', Comment = 'is-IS=Notaðu Inventory.PhysInventory.* fyrir einfaldar staðsetningar.';
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
        AllowedKeys.Add('locationCode');
        AllowedKeys.Add('registeringDate');
        AllowedKeys.Add('documentNo');
        AllowedKeys.Add('zoneCode');
        AllowedKeys.Add('binCode');
        AllowedKeys.Add('itemNo');
        AllowedKeys.Add('itemsNotOnInventory');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Helper.ReadBatchKeys(RequestJson, Argument, TemplateName, BatchName, LocationCode);
        Values.ReadDate(RequestJson, 'registeringDate', Argument, RegisteringDate, Present, 'registeringDate');
        Context.ReadText(RequestJson, 'documentNo', 20, Argument, DocumentNoText, Present, 'documentNo');
        Context.ReadText(RequestJson, 'zoneCode', 10, Argument, ZoneText, Present, 'zoneCode');
        Context.ReadText(RequestJson, 'binCode', 20, Argument, BinText, Present, 'binCode');
        Context.ReadText(RequestJson, 'itemNo', 20, Argument, ItemText, Present, 'itemNo');
        Context.ReadBoolean(RequestJson, 'itemsNotOnInventory', Argument, ItemsNotOnInventory, Present, 'itemsNotOnInventory');
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not Helper.ResolveBatch(Argument, TemplateName, BatchName, LocationCode, true, DirectedNextStepLbl, JournalTemplate) then
            exit;
        if not CheckDocumentNo(Argument, TemplateName, BatchName, LocationCode, DocumentNoText) then
            exit;
        if not CheckFilters(Argument, LocationCode, ZoneText, BinText, ItemText) then
            exit;
        Payload.Add('journalTemplateName', TemplateName);
        Payload.Add('journalBatchName', BatchName);
        Payload.Add('locationCode', LocationCode);
        Payload.Add('registeringDate', Values.DateText(RegisteringDate));
        Payload.Add('documentNo', DocumentNoText);
        Payload.Add('zoneCode', ZoneText);
        Payload.Add('binCode', BinText);
        Payload.Add('itemNo', ItemText);
        Payload.Add('itemsNotOnInventory', ItemsNotOnInventory);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse PhysInvt Calc Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse PhysInvt Calc Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        WriteResponse(Argument, TemplateName, BatchName, LocationCode);
        Context.Reset();
    end;

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        JournalLine: Record "Warehouse Journal Line";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Journal Helper ori";
        ResponseJson: JsonObject;
        Lines: JsonArray;
        SnapshotLineNo: Integer;
    begin
        Context.TryGetSnapshot(SnapshotLineNo);
        Helper.FilterBatch(JournalLine, TemplateName, BatchName, LocationCode);
        JournalLine.SetFilter("Line No.", '>%1', SnapshotLineNo);
        if JournalLine.FindSet() then
            repeat
                Lines.Add(Helper.LineJson(JournalLine));
            until JournalLine.Next() = 0;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('journalTemplateName', TemplateName);
        ResponseJson.Add('journalBatchName', BatchName);
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('lineCount', Lines.Count());
        ResponseJson.Add('lines', Lines);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure CheckDocumentNo(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]; DocumentNoText: Text): Boolean
    var
        JournalBatch: Record "Warehouse Journal Batch";
        MissingLbl: Label 'documentNo is required because batch %1 has no number series.', Comment = '%1 = batch, is-IS=documentNo er nauðsynlegt því keyrsla %1 hefur enga númeraröð.';
        MissingNextStepLbl: Label 'Send documentNo, or give the batch a number series.', Comment = 'is-IS=Sendu documentNo, eða gefðu keyrslunni númeraröð.';
    begin
        if DocumentNoText <> '' then
            exit(true);
        JournalBatch.SetLoadFields("No. Series");
        JournalBatch.Get(TemplateName, BatchName, LocationCode);
        if JournalBatch."No. Series" <> '' then
            exit(true);
        Argument.RespondWithError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, BatchName), 'documentNo', '', '', MissingNextStepLbl);
        exit(false);
    end;

    local procedure CheckFilters(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; ZoneText: Text; BinText: Text; ItemText: Text): Boolean
    var
        Zone: Record Zone;
        Bin: Record Bin;
        Item: Record Item;
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table caption, %2 = value, is-IS=%1 %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the value and send the request again.', Comment = 'is-IS=Athugaðu gildið og sendu beiðnina aftur.';
        ZoneConflictLbl: Label 'Bin %1 is not in zone %2.', Comment = '%1 = bin, %2 = zone, is-IS=Hólf %1 er ekki á svæði %2.';
        ZoneConflictNextStepLbl: Label 'Send a bin in the named zone, or omit one of them.', Comment = 'is-IS=Sendu hólf á nefndu svæði, eða slepptu öðru hvoru.';
    begin
        if ZoneText <> '' then begin
            Zone.SetLoadFields("Location Code", Code);
            if not Zone.Get(LocationCode, CopyStr(ZoneText, 1, MaxStrLen(Zone.Code))) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Zone.TableCaption(), ZoneText), 'zoneCode', ZoneText, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        if BinText <> '' then begin
            Bin.SetLoadFields("Location Code", Code, "Zone Code");
            if not Bin.Get(LocationCode, CopyStr(BinText, 1, MaxStrLen(Bin.Code))) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), BinText), 'binCode', BinText, '', NotFoundNextStepLbl);
                exit(false);
            end;
            if (ZoneText <> '') and (UpperCase(Bin."Zone Code") <> UpperCase(ZoneText)) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(ZoneConflictLbl, BinText, ZoneText), 'binCode', BinText, ZoneText, ZoneConflictNextStepLbl);
                exit(false);
            end;
        end;
        if ItemText <> '' then begin
            Item.SetLoadFields("No.");
            if not Item.Get(CopyStr(ItemText, 1, MaxStrLen(Item."No."))) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemText), 'itemNo', ItemText, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        exit(true);
    end;
}
