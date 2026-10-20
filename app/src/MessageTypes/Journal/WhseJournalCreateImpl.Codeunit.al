namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Tracking;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Tracking;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Journal.Create (#48).
/// Inserts warehouse item journal or warehouse reclassification journal lines through Validate at a directed
/// put-away and pick location, with optional lot, serial and package numbers as warehouse item tracking lines.
/// Nothing is registered; Warehouse.Journal.Register does that.
/// </summary>
codeunit 10078446 "Whse Journal Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        JournalTemplate: Record "Warehouse Journal Template";
        LastLine: Record "Warehouse Journal Line";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Journal Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        LineObject: JsonObject;
        Result: JsonObject;
        Token: JsonToken;
        LineNos: JsonArray;
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        NextLineNo: Integer;
        MissingPayloadErr: Label 'The warehouse journal payload was empty.', Comment = 'is-IS=Gögn birgðabókar vöruhússins voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        TemplateName := CopyStr(Values.TextValue(Payload, 'journalTemplateName'), 1, MaxStrLen(TemplateName));
        BatchName := CopyStr(Values.TextValue(Payload, 'journalBatchName'), 1, MaxStrLen(BatchName));
        LocationCode := CopyStr(Values.TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        JournalTemplate.Get(TemplateName);
        Helper.DeleteEmptyLines(TemplateName, BatchName, LocationCode);
        NextLineNo := Helper.LastLineNo(TemplateName, BatchName, LocationCode);
        LastLine."Journal Template Name" := TemplateName;
        LastLine."Journal Batch Name" := BatchName;
        LastLine."Location Code" := LocationCode;
        foreach Token in Values.ArrayValue(Payload, 'lines') do begin
            LineObject := Token.AsObject();
            NextLineNo += 10000;
            InsertLine(Payload, LineObject, JournalTemplate, NextLineNo, LastLine);
            LineNos.Add(NextLineNo);
        end;
        Result.Add('lineNos', LineNos);
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can write warehouse journal lines and their item tracking lines.</summary>
    /// <returns>True when the caller can write the journal and tracking tables.</returns>
    procedure IsEnabled(): Boolean
    begin
        exit(HasWritePermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse journal line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Journal Line");
    end;

    /// <summary>Returns a short description of Warehouse.Journal.Create.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates warehouse item journal or warehouse reclassification journal lines at a directed location.', Comment = 'is-IS=Stofnar línur í birgðabók vöruhúss eða endurflokkunarbók vöruhúss á beinni staðsetningu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'warehouse item journal, warehouse reclassification journal, bin adjustment, positive adjustment, negative adjustment, move between bins, reclassify lot', Comment = 'is-IS=birgðabók vöruhúss, endurflokkunarbók vöruhúss, leiðrétting hólfs, jákvæð leiðrétting, neikvæð leiðrétting, færa milli hólfa, endurflokka lotu';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Writes warehouse journal lines at a directed put-away and pick location and registers nothing. Register the batch with Warehouse.Journal.Register. Use Inventory.ItemJournal.* or Inventory.Reclassification.* at a basic location.', Comment = 'is-IS=Skrifar línur í birgðabók vöruhúss á staðsetningu með beina frágangs- og tínsluvinnslu og skráir ekkert. Skráðu keyrsluna með Warehouse.Journal.Register. Notaðu Inventory.ItemJournal.* eða Inventory.Reclassification.* á einfaldri staðsetningu.';
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
        Target.Add(ContractMgt.TargetEntry('data.journalTemplateName + data.journalBatchName + data.locationCode', 'journal batch', 'The warehouse item or reclassification journal batch. A warehouse journal batch belongs to one location.'));
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
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Directed put-away and pick location of the batch. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('registeringDate', 'string', false, 'Registering date written as YYYY-MM-DD. Defaults to the work date.'));
        Parameters.Add(ContractMgt.Parameter('documentNo', 'string', false, 'Warehouse document number. Defaults to the next number of the batch number series.'));
        Parameters.Add(ContractMgt.Parameter('lines', 'array', true, 'Journal lines to insert, in order.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', true, 'Item number on a line.'));
        Parameters.Add(ContractMgt.Parameter('variantCode', 'string', false, 'Variant code on a line.'));
        Parameters.Add(ContractMgt.Parameter('unitOfMeasureCode', 'string', false, 'Unit of measure on a line. Defaults to the base unit of measure.'));
        Parameters.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Item journal only. Zone of binCode; it must match the zone of the bin.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', false, 'Item journal only, required there. The bin that is adjusted.'));
        Parameters.Add(ContractMgt.Parameter('fromBin', 'string', false, 'Reclassification journal only, required there. The bin the quantity is taken from.'));
        Parameters.Add(ContractMgt.Parameter('toBin', 'string', false, 'Reclassification journal only, required there. The bin the quantity is placed in.'));
        Parameters.Add(ContractMgt.Parameter('quantity', 'number', true, 'Quantity in the line unit of measure. Item journal: positive adds to the bin, negative removes from it. Reclassification journal: positive only.'));
        Parameters.Add(ContractMgt.Parameter('lotNo', 'string', false, 'Lot number for an item with warehouse lot tracking.'));
        Parameters.Add(ContractMgt.Parameter('serialNo', 'string', false, 'Serial number for an item with warehouse serial tracking. The line quantity must then be one base unit.'));
        Parameters.Add(ContractMgt.Parameter('packageNo', 'string', false, 'Package number for an item with warehouse package tracking.'));
        Parameters.Add(ContractMgt.Parameter('expirationDate', 'string', false, 'Expiration date of a new lot or serial number, written as YYYY-MM-DD.'));
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
        Fields.Add(ContractMgt.ResponseField('lineNos', 'array', 'Line numbers of the inserted lines, in request order.'));
        Fields.Add(LinesField(ContractMgt, 'Inserted lines: lineNo, itemNo, variantCode, unitOfMeasureCode, entryType, zoneCode, binCode, fromBin, toBin, quantity, lotNo, serialNo, packageNo, whseDocumentNo and registeringDate.'));
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
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidLine, 'A negative adjustment or a reclassification takes more than the bin content holds, or lot, serial or package numbers are sent for an item without warehouse item tracking, or a serial number is sent for more than one base unit.', 'Read Warehouse.BinContent.Get.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The journal template or batch was not found at the location.', 'Create the batch first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The location, item, variant, unit of measure or bin was not found.', 'Check the value and send the request again.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'journalTemplateName, journalBatchName, locationCode, lines, or itemNo, quantity or a bin on a line is missing.', 'Send the batch keys and, on every line, itemNo, quantity and binCode (item journal) or fromBin and toBin (reclassification journal).');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, is too long, or a date is not YYYY-MM-DD.', 'Send text for codes and dates, numbers for quantities and an array of objects for lines.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'The template is a physical inventory template, a quantity is zero, a reclassification quantity is negative, or a line sends the bin keys of the other journal type.', 'Use Warehouse.PhysInventory.* for physical inventory, a non-zero quantity, and the bin keys of the journal type.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request or a line contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations, or zoneCode is not the zone of binCode.', 'Send one location, and a zone that holds the bin.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write warehouse journal lines.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected a line.', 'Read the returned text and correct the line. Nothing was written.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Inserts warehouse journal lines and their warehouse item tracking lines, all or nothing. Nothing is registered and no entry is written until Warehouse.Journal.Register runs.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Journal.Register', 'Use it to register the batch.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read the quantity in a bin before a negative adjustment or a reclassification.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Adjustment.Calculate', 'Use it after registering to bring the item ledger in line with the warehouse adjustment bin.'));
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
            'Add five units to a pick bin',
            '{"journalTemplateName":"ITEM","journalBatchName":"DEFAULT","locationCode":"WHITE","lines":[{"itemNo":"1896-S","binCode":"W-01-0001","quantity":5}]}',
            '{"status":"Success","journalTemplateName":"ITEM","journalBatchName":"DEFAULT","locationCode":"WHITE","lineNos":[10000],"lines":[{"lineNo":10000,"itemNo":"1896-S","entryType":"Positive Adjmt.","binCode":"W-01-0001","fromBin":"W-11-0001","toBin":"W-01-0001","quantity":5}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Inserts warehouse item journal lines (bin adjustments) or warehouse reclassification journal lines (moves between bins, with lot, serial or package numbers) at a directed put-away and pick location. Every line is validated as on the journal page; one failing line writes nothing.', Comment = 'is-IS=Setur inn línur í birgðabók vöruhúss (leiðréttingar hólfa) eða endurflokkunarbók vöruhúss (færslur milli hólfa, með lotu-, rað- eða pakkanúmerum) á staðsetningu með beina frágangs- og tínsluvinnslu. Hver lína er staðfest eins og á bókarsíðunni; ein röng lína skrifar ekkert.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    var
        NotesLbl: Label 'A warehouse item journal line adjusts the bin against the location adjustment bin; the item ledger follows when Warehouse.Adjustment.Calculate and Inventory.ItemJournal.Post run. A reclassification line moves the quantity between two bins and keeps its lot, serial and package numbers.', Comment = 'is-IS=Lína í birgðabók vöruhúss leiðréttir hólfið á móti leiðréttingarhólfi staðsetningarinnar; birgðafærslur fylgja þegar Warehouse.Adjustment.Calculate og Inventory.ItemJournal.Post keyra. Endurflokkunarlína færir magnið milli tveggja hólfa og heldur lotu-, rað- og pakkanúmerum sínum.';
    begin
        Notes := NotesLbl;
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the batch and the lines and inserts them, or writes nothing.</summary>
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
        Lines: JsonArray;
        PlannedLines: JsonArray;
        AllowedKeys: List of [Text];
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        RegisteringDate: Date;
        DocumentNoText: Text;
        DatePresent: Boolean;
        DocumentNoPresent: Boolean;
        LinesPresent: Boolean;
        DeniedLbl: Label 'You do not have permission to write warehouse journal lines.', Comment = 'is-IS=Þú hefur ekki heimild til að skrifa línur í birgðabók vöruhúss.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
        LinesMissingLbl: Label 'lines is required and must hold at least one line.', Comment = 'is-IS=lines er nauðsynlegt og verður að innihalda að minnsta kosti eina línu.';
        LinesMissingNextStepLbl: Label 'Send at least one line.', Comment = 'is-IS=Sendu að minnsta kosti eina línu.';
        DirectedNextStepLbl: Label 'Use Inventory.ItemJournal.* or Inventory.Reclassification.* for basic locations.', Comment = 'is-IS=Notaðu Inventory.ItemJournal.* eða Inventory.Reclassification.* fyrir einfaldar staðsetningar.';
    begin
        Context.Reset();
        if not HasWritePermission() then begin
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
        AllowedKeys.Add('lines');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Helper.ReadBatchKeys(RequestJson, Argument, TemplateName, BatchName, LocationCode);
        Values.ReadDate(RequestJson, 'registeringDate', Argument, RegisteringDate, DatePresent, 'registeringDate');
        Context.ReadText(RequestJson, 'documentNo', 20, Argument, DocumentNoText, DocumentNoPresent, 'documentNo');
        if Values.ReadArray(RequestJson, 'lines', Argument, Lines, LinesPresent) then
            if (not LinesPresent) or (Lines.Count() = 0) then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, LinesMissingLbl, 'lines', '', '', LinesMissingNextStepLbl);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not Helper.ResolveBatch(Argument, TemplateName, BatchName, LocationCode, false, DirectedNextStepLbl, JournalTemplate) then
            exit;
        ReadLines(Lines, Argument, JournalTemplate, LocationCode, PlannedLines);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('journalTemplateName', TemplateName);
        Payload.Add('journalBatchName', BatchName);
        Payload.Add('locationCode', LocationCode);
        Payload.Add('registeringDate', Values.DateText(RegisteringDate));
        Payload.Add('documentNo', DocumentNoText);
        Payload.Add('lines', PlannedLines);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Journal Create Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Journal Create Impl ori") then begin
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
        Values: Codeunit "Whse Msg Values ori";
        Result: JsonObject;
        ResponseJson: JsonObject;
        Token: JsonToken;
        LineNos: JsonArray;
        Lines: JsonArray;
    begin
        if Context.TryGetResult(Result) then
            LineNos := Values.ArrayValue(Result, 'lineNos');
        foreach Token in LineNos do
            if JournalLine.Get(TemplateName, BatchName, LocationCode, Token.AsValue().AsInteger()) then
                Lines.Add(Helper.LineJson(JournalLine));
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('journalTemplateName', TemplateName);
        ResponseJson.Add('journalBatchName', BatchName);
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('lineNos', LineNos);
        ResponseJson.Add('lines', Lines);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ReadLines(Lines: JsonArray; var Argument: Record "Message Argument ori"; JournalTemplate: Record "Warehouse Journal Template"; LocationCode: Code[10]; var PlannedLines: JsonArray)
    var
        Values: Codeunit "Whse Msg Values ori";
        LineObject: JsonObject;
        Taken: Dictionary of [Text, Decimal];
        Index: Integer;
    begin
        Clear(PlannedLines);
        for Index := 0 to Lines.Count() - 1 do
            if Values.TryGetLineObject(Lines, Index, 'lines', Argument, LineObject) then
                ReadOneLine(LineObject, Index, Argument, JournalTemplate.Type = JournalTemplate.Type::Reclassification, LocationCode, Taken, PlannedLines);
    end;

    local procedure ReadOneLine(LineObject: JsonObject; Index: Integer; var Argument: Record "Message Argument ori"; Reclass: Boolean; LocationCode: Code[10]; var Taken: Dictionary of [Text, Decimal]; var PlannedLines: JsonArray)
    var
        Item: Record Item;
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        Bin: Record Bin;
        FromBin: Record Bin;
        ToBin: Record Bin;
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Planned: JsonObject;
        AllowedKeys: List of [Text];
        ItemText: Text;
        VariantText: Text;
        UomText: Text;
        ZoneText: Text;
        BinText: Text;
        FromBinText: Text;
        ToBinText: Text;
        LotText: Text;
        SerialText: Text;
        PackageText: Text;
        Quantity: Decimal;
        ExpirationDate: Date;
        ItemPresent: Boolean;
        VariantPresent: Boolean;
        UomPresent: Boolean;
        ZonePresent: Boolean;
        BinPresent: Boolean;
        FromBinPresent: Boolean;
        ToBinPresent: Boolean;
        LotPresent: Boolean;
        SerialPresent: Boolean;
        PackagePresent: Boolean;
        QuantityPresent: Boolean;
        ExpirationPresent: Boolean;
        ErrorCount: Integer;
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line index, %2 = parameter, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send itemNo, quantity and binCode (item journal) or fromBin and toBin (reclassification journal) on every line.', Comment = 'is-IS=Sendu itemNo, quantity og binCode (birgðabók) eða fromBin og toBin (endurflokkunarbók) á hverri línu.';
        ZeroLbl: Label 'quantity on line %1 must not be zero.', Comment = '%1 = line index, is-IS=quantity á línu %1 má ekki vera núll.';
        NegativeLbl: Label 'quantity on reclassification line %1 must be positive.', Comment = '%1 = line index, is-IS=quantity á endurflokkunarlínu %1 verður að vera jákvætt.';
        QuantityNextStepLbl: Label 'Send a non-zero quantity; a reclassification quantity is positive.', Comment = 'is-IS=Sendu magn sem er ekki núll; magn endurflokkunar er jákvætt.';
        WrongBinKeyLbl: Label 'Line %1 sends %2, which this journal type does not use.', Comment = '%1 = line index, %2 = parameter, is-IS=Lína %1 sendir %2, sem þessi bókartegund notar ekki.';
        WrongBinKeyNextStepLbl: Label 'Send binCode on an item journal line and fromBin and toBin on a reclassification line.', Comment = 'is-IS=Sendu binCode á línu í birgðabók og fromBin og toBin á endurflokkunarlínu.';
        ZoneConflictLbl: Label 'Bin %1 is not in zone %2.', Comment = '%1 = bin, %2 = zone, is-IS=Hólf %1 er ekki á svæði %2.';
        ZoneConflictNextStepLbl: Label 'Send a zone that holds the bin, or omit zoneCode.', Comment = 'is-IS=Sendu svæði sem inniheldur hólfið, eða slepptu zoneCode.';
    begin
        AllowedKeys.Add('itemNo');
        AllowedKeys.Add('variantCode');
        AllowedKeys.Add('unitOfMeasureCode');
        AllowedKeys.Add('zoneCode');
        AllowedKeys.Add('binCode');
        AllowedKeys.Add('fromBin');
        AllowedKeys.Add('toBin');
        AllowedKeys.Add('quantity');
        AllowedKeys.Add('lotNo');
        AllowedKeys.Add('serialNo');
        AllowedKeys.Add('packageNo');
        AllowedKeys.Add('expirationDate');
        ErrorCount := Argument.GetCollectedErrorsJson().Count();
        Values.RefuseUnknownKeys(LineObject, AllowedKeys, Argument, 'lines', Index);
        Context.ReadText(LineObject, 'itemNo', MaxStrLen(Item."No."), Argument, ItemText, ItemPresent, Values.LineParameter('lines', Index, 'itemNo'));
        Context.ReadText(LineObject, 'variantCode', 10, Argument, VariantText, VariantPresent, Values.LineParameter('lines', Index, 'variantCode'));
        Context.ReadText(LineObject, 'unitOfMeasureCode', 10, Argument, UomText, UomPresent, Values.LineParameter('lines', Index, 'unitOfMeasureCode'));
        Context.ReadText(LineObject, 'zoneCode', 10, Argument, ZoneText, ZonePresent, Values.LineParameter('lines', Index, 'zoneCode'));
        Context.ReadText(LineObject, 'binCode', 20, Argument, BinText, BinPresent, Values.LineParameter('lines', Index, 'binCode'));
        Context.ReadText(LineObject, 'fromBin', 20, Argument, FromBinText, FromBinPresent, Values.LineParameter('lines', Index, 'fromBin'));
        Context.ReadText(LineObject, 'toBin', 20, Argument, ToBinText, ToBinPresent, Values.LineParameter('lines', Index, 'toBin'));
        Context.ReadText(LineObject, 'lotNo', 50, Argument, LotText, LotPresent, Values.LineParameter('lines', Index, 'lotNo'));
        Context.ReadText(LineObject, 'serialNo', 50, Argument, SerialText, SerialPresent, Values.LineParameter('lines', Index, 'serialNo'));
        Context.ReadText(LineObject, 'packageNo', 50, Argument, PackageText, PackagePresent, Values.LineParameter('lines', Index, 'packageNo'));
        Context.ReadDecimal(LineObject, 'quantity', Argument, Quantity, QuantityPresent, Values.LineParameter('lines', Index, 'quantity'));
        Values.ReadDate(LineObject, 'expirationDate', Argument, ExpirationDate, ExpirationPresent, Values.LineParameter('lines', Index, 'expirationDate'));
        if Argument.GetCollectedErrorsJson().Count() <> ErrorCount then
            exit;
        if not ItemPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'itemNo'), Values.LineParameter('lines', Index, 'itemNo'), '', '', MissingNextStepLbl);
        if not QuantityPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'quantity'), Values.LineParameter('lines', Index, 'quantity'), '', '', MissingNextStepLbl);
        if Reclass then begin
            if BinPresent then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(WrongBinKeyLbl, Index, 'binCode'), Values.LineParameter('lines', Index, 'binCode'), BinText, '', WrongBinKeyNextStepLbl);
            if ZonePresent then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(WrongBinKeyLbl, Index, 'zoneCode'), Values.LineParameter('lines', Index, 'zoneCode'), ZoneText, '', WrongBinKeyNextStepLbl);
            if not FromBinPresent then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'fromBin'), Values.LineParameter('lines', Index, 'fromBin'), '', '', MissingNextStepLbl);
            if not ToBinPresent then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'toBin'), Values.LineParameter('lines', Index, 'toBin'), '', '', MissingNextStepLbl);
        end else begin
            if FromBinPresent then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(WrongBinKeyLbl, Index, 'fromBin'), Values.LineParameter('lines', Index, 'fromBin'), FromBinText, '', WrongBinKeyNextStepLbl);
            if ToBinPresent then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(WrongBinKeyLbl, Index, 'toBin'), Values.LineParameter('lines', Index, 'toBin'), ToBinText, '', WrongBinKeyNextStepLbl);
            if not BinPresent then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'binCode'), Values.LineParameter('lines', Index, 'binCode'), '', '', MissingNextStepLbl);
        end;
        if QuantityPresent then begin
            if Quantity = 0 then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ZeroLbl, Index), Values.LineParameter('lines', Index, 'quantity'), '0', '', QuantityNextStepLbl);
            if Reclass and (Quantity < 0) then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(NegativeLbl, Index), Values.LineParameter('lines', Index, 'quantity'), Format(Quantity, 0, 9), '', QuantityNextStepLbl);
        end;
        if Argument.GetCollectedErrorsJson().Count() <> ErrorCount then
            exit;
        if not ResolveItem(Argument, Index, ItemText, VariantText, UomText, Item, ItemUnitOfMeasure) then
            exit;
        if Reclass then begin
            if not ResolveBin(Argument, Index, 'fromBin', LocationCode, FromBinText, FromBin) then
                exit;
            if not ResolveBin(Argument, Index, 'toBin', LocationCode, ToBinText, ToBin) then
                exit;
        end else begin
            if not ResolveBin(Argument, Index, 'binCode', LocationCode, BinText, Bin) then
                exit;
            if ZonePresent and (UpperCase(ZoneText) <> UpperCase(Bin."Zone Code")) then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(ZoneConflictLbl, Bin.Code, ZoneText), Values.LineParameter('lines', Index, 'zoneCode'), ZoneText, Bin."Zone Code", ZoneConflictNextStepLbl);
                exit;
            end;
        end;
        if not CheckTracking(Argument, Index, Item."No.", Quantity * ItemUnitOfMeasure."Qty. per Unit of Measure", LotText, SerialText, PackageText) then
            exit;
        if Reclass then begin
            if not CheckBinContent(Argument, Index, LocationCode, FromBin.Code, Item."No.", CopyStr(VariantText, 1, 10), ItemUnitOfMeasure, Quantity, LotText, SerialText, PackageText, Taken) then
                exit;
        end else
            if Quantity < 0 then
                if not CheckBinContent(Argument, Index, LocationCode, Bin.Code, Item."No.", CopyStr(VariantText, 1, 10), ItemUnitOfMeasure, -Quantity, LotText, SerialText, PackageText, Taken) then
                    exit;
        Planned.Add('itemNo', Item."No.");
        Planned.Add('variantCode', VariantText);
        Planned.Add('unitOfMeasureCode', ItemUnitOfMeasure.Code);
        Planned.Add('binCode', Bin.Code);
        Planned.Add('zoneCode', Bin."Zone Code");
        Planned.Add('fromBin', FromBin.Code);
        Planned.Add('fromZone', FromBin."Zone Code");
        Planned.Add('toBin', ToBin.Code);
        Planned.Add('toZone', ToBin."Zone Code");
        Planned.Add('quantity', Quantity);
        Planned.Add('lotNo', LotText);
        Planned.Add('serialNo', SerialText);
        Planned.Add('packageNo', PackageText);
        Planned.Add('expirationDate', Values.DateText(ExpirationDate));
        PlannedLines.Add(Planned);
    end;

    local procedure ResolveItem(var Argument: Record "Message Argument ori"; Index: Integer; ItemText: Text; VariantText: Text; UomText: Text; var Item: Record Item; var ItemUnitOfMeasure: Record "Item Unit of Measure"): Boolean
    var
        ItemVariant: Record "Item Variant";
        Values: Codeunit "Whse Msg Values ori";
        UomCode: Code[10];
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table caption, %2 = value, is-IS=%1 %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the value and send the request again.', Comment = 'is-IS=Athugaðu gildið og sendu beiðnina aftur.';
    begin
        Item.SetLoadFields("No.", "Base Unit of Measure");
        if not Item.Get(CopyStr(ItemText, 1, MaxStrLen(Item."No."))) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemText), Values.LineParameter('lines', Index, 'itemNo'), ItemText, '', NotFoundNextStepLbl);
            exit(false);
        end;
        if VariantText <> '' then begin
            ItemVariant.SetLoadFields("Item No.", Code);
            if not ItemVariant.Get(Item."No.", CopyStr(VariantText, 1, MaxStrLen(ItemVariant.Code))) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ItemVariant.TableCaption(), VariantText), Values.LineParameter('lines', Index, 'variantCode'), VariantText, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        UomCode := CopyStr(UomText, 1, MaxStrLen(UomCode));
        if UomCode = '' then
            UomCode := Item."Base Unit of Measure";
        ItemUnitOfMeasure.SetLoadFields("Item No.", Code, "Qty. per Unit of Measure");
        if not ItemUnitOfMeasure.Get(Item."No.", UomCode) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ItemUnitOfMeasure.TableCaption(), UomCode), Values.LineParameter('lines', Index, 'unitOfMeasureCode'), UomCode, '', NotFoundNextStepLbl);
            exit(false);
        end;
        exit(true);
    end;

    local procedure ResolveBin(var Argument: Record "Message Argument ori"; Index: Integer; KeyName: Text; LocationCode: Code[10]; BinText: Text; var Bin: Record Bin): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
        NotFoundLbl: Label 'Bin %1 was not found at location %2.', Comment = '%1 = bin, %2 = location, is-IS=Hólf %1 fannst ekki á staðsetningu %2.';
        NotFoundNextStepLbl: Label 'Check the bin with Warehouse.Bin.Get.', Comment = 'is-IS=Athugaðu hólfið með Warehouse.Bin.Get.';
    begin
        Bin.SetLoadFields("Location Code", Code, "Zone Code");
        if Bin.Get(LocationCode, CopyStr(BinText, 1, MaxStrLen(Bin.Code))) then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, BinText, LocationCode), Values.LineParameter('lines', Index, KeyName), BinText, '', NotFoundNextStepLbl);
        exit(false);
    end;

    local procedure CheckTracking(var Argument: Record "Message Argument ori"; Index: Integer; ItemNo: Code[20]; QuantityBase: Decimal; LotText: Text; SerialText: Text; PackageText: Text): Boolean
    var
        TempWhseItemTrackingSetup: Record "Item Tracking Setup" temporary;
        ItemTrackingMgt: Codeunit "Item Tracking Management";
        Values: Codeunit "Whse Msg Values ori";
        NoTrackingLbl: Label 'Item %1 does not use warehouse item tracking, so line %2 cannot carry lot, serial or package numbers.', Comment = '%1 = item, %2 = line index, is-IS=Vara %1 notar ekki vörurakningu í vöruhúsi, svo lína %2 getur ekki borið lotu-, rað- eða pakkanúmer.';
        NoTrackingNextStepLbl: Label 'Remove lotNo, serialNo and packageNo from the line.', Comment = 'is-IS=Fjarlægðu lotNo, serialNo og packageNo af línunni.';
        SerialLbl: Label 'Line %1 carries serial number %2 for more than one base unit.', Comment = '%1 = line index, %2 = serial no., is-IS=Lína %1 ber raðnúmer %2 fyrir meira en eina grunneiningu.';
        SerialNextStepLbl: Label 'Send one line per serial number with quantity 1.', Comment = 'is-IS=Sendu eina línu fyrir hvert raðnúmer með magnið 1.';
    begin
        if (LotText = '') and (SerialText = '') and (PackageText = '') then
            exit(true);
        if not ItemTrackingMgt.GetWhseItemTrkgSetup(ItemNo, TempWhseItemTrackingSetup) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(NoTrackingLbl, ItemNo, Index), Values.LineParameter('lines', Index, 'lotNo'), LotText + SerialText + PackageText, '', NoTrackingNextStepLbl);
            exit(false);
        end;
        if (SerialText <> '') and (Abs(QuantityBase) <> 1) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(SerialLbl, Index, SerialText), Values.LineParameter('lines', Index, 'serialNo'), SerialText, '1', SerialNextStepLbl);
            exit(false);
        end;
        exit(true);
    end;

    local procedure CheckBinContent(var Argument: Record "Message Argument ori"; Index: Integer; LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; ItemUnitOfMeasure: Record "Item Unit of Measure"; Quantity: Decimal; LotText: Text; SerialText: Text; PackageText: Text; var Taken: Dictionary of [Text, Decimal]): Boolean
    var
        BinContent: Record "Bin Content";
        Values: Codeunit "Whse Msg Values ori";
        Available: Decimal;
        AlreadyTaken: Decimal;
        Requested: Decimal;
        TakenKey: Text;
        ShortLbl: Label 'Bin %1 holds %2 base units of item %3 that can be taken; line %4 asks for %5.', Comment = '%1 = bin, %2 = available, %3 = item, %4 = line index, %5 = requested, is-IS=Hólf %1 geymir %2 grunneiningar af vöru %3 sem má taka; lína %4 biður um %5.';
        ShortNextStepLbl: Label 'Read Warehouse.BinContent.Get.', Comment = 'is-IS=Lestu Warehouse.BinContent.Get.';
    begin
        Requested := Quantity * ItemUnitOfMeasure."Qty. per Unit of Measure";
        TakenKey := BinCode + '|' + ItemNo + '|' + VariantCode + '|' + ItemUnitOfMeasure.Code + '|' + LotText + '|' + SerialText + '|' + PackageText;
        if Taken.ContainsKey(TakenKey) then
            AlreadyTaken := Taken.Get(TakenKey);
        Available := 0;
        if BinContent.Get(LocationCode, BinCode, ItemNo, VariantCode, ItemUnitOfMeasure.Code) then begin
            if LotText <> '' then
                BinContent.SetRange("Lot No. Filter", LotText);
            if SerialText <> '' then
                BinContent.SetRange("Serial No. Filter", SerialText);
            if PackageText <> '' then
                BinContent.SetRange("Package No. Filter", PackageText);
            Available := BinContent.CalcQtyAvailToTake(0);
        end;
        if Requested + AlreadyTaken > Available then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(ShortLbl, BinCode, Available - AlreadyTaken, ItemNo, Index, Requested), Values.LineParameter('lines', Index, 'quantity'), Format(Quantity, 0, 9), Format(Available - AlreadyTaken, 0, 9), ShortNextStepLbl);
            exit(false);
        end;
        if Taken.ContainsKey(TakenKey) then
            Taken.Set(TakenKey, AlreadyTaken + Requested)
        else
            Taken.Add(TakenKey, Requested);
        exit(true);
    end;

    local procedure InsertLine(Payload: JsonObject; LineObject: JsonObject; JournalTemplate: Record "Warehouse Journal Template"; LineNo: Integer; var LastLine: Record "Warehouse Journal Line")
    var
        JournalLine: Record "Warehouse Journal Line";
        Values: Codeunit "Whse Msg Values ori";
    begin
        JournalLine.Init();
        JournalLine.Validate("Journal Template Name", LastLine."Journal Template Name");
        JournalLine.Validate("Journal Batch Name", LastLine."Journal Batch Name");
        JournalLine.Validate("Location Code", LastLine."Location Code");
        JournalLine."Line No." := LineNo;
        JournalLine.SetUpNewLine(LastLine);
        JournalLine.Insert(true);
        if Values.DateValue(Payload, 'registeringDate') <> 0D then
            JournalLine.Validate("Registering Date", Values.DateValue(Payload, 'registeringDate'));
        if Values.TextValue(Payload, 'documentNo') <> '' then
            JournalLine.Validate("Whse. Document No.", CopyStr(Values.TextValue(Payload, 'documentNo'), 1, MaxStrLen(JournalLine."Whse. Document No.")));
        JournalLine.Validate("Item No.", CopyStr(Values.TextValue(LineObject, 'itemNo'), 1, MaxStrLen(JournalLine."Item No.")));
        if Values.TextValue(LineObject, 'variantCode') <> '' then
            JournalLine.Validate("Variant Code", CopyStr(Values.TextValue(LineObject, 'variantCode'), 1, MaxStrLen(JournalLine."Variant Code")));
        JournalLine.Validate("Unit of Measure Code", CopyStr(Values.TextValue(LineObject, 'unitOfMeasureCode'), 1, MaxStrLen(JournalLine."Unit of Measure Code")));
        if JournalTemplate.Type = JournalTemplate.Type::Reclassification then begin
            JournalLine.Validate("From Zone Code", CopyStr(Values.TextValue(LineObject, 'fromZone'), 1, MaxStrLen(JournalLine."From Zone Code")));
            JournalLine.Validate("From Bin Code", CopyStr(Values.TextValue(LineObject, 'fromBin'), 1, MaxStrLen(JournalLine."From Bin Code")));
            JournalLine.Validate("To Zone Code", CopyStr(Values.TextValue(LineObject, 'toZone'), 1, MaxStrLen(JournalLine."To Zone Code")));
            JournalLine.Validate("To Bin Code", CopyStr(Values.TextValue(LineObject, 'toBin'), 1, MaxStrLen(JournalLine."To Bin Code")));
        end else begin
            JournalLine.Validate("Zone Code", CopyStr(Values.TextValue(LineObject, 'zoneCode'), 1, MaxStrLen(JournalLine."Zone Code")));
            JournalLine.Validate("Bin Code", CopyStr(Values.TextValue(LineObject, 'binCode'), 1, MaxStrLen(JournalLine."Bin Code")));
        end;
        JournalLine.Validate(Quantity, Values.DecimalValue(LineObject, 'quantity'));
        JournalLine.Modify(true);
        InsertTracking(JournalLine, LineObject, JournalTemplate.Type = JournalTemplate.Type::Reclassification);
        LastLine := JournalLine;
    end;

    local procedure InsertTracking(JournalLine: Record "Warehouse Journal Line"; LineObject: JsonObject; Reclass: Boolean)
    var
        TrackingLine: Record "Whse. Item Tracking Line";
        Values: Codeunit "Whse Msg Values ori";
        LotNo: Code[50];
        SerialNo: Code[50];
        PackageNo: Code[50];
    begin
        LotNo := CopyStr(Values.TextValue(LineObject, 'lotNo'), 1, MaxStrLen(LotNo));
        SerialNo := CopyStr(Values.TextValue(LineObject, 'serialNo'), 1, MaxStrLen(SerialNo));
        PackageNo := CopyStr(Values.TextValue(LineObject, 'packageNo'), 1, MaxStrLen(PackageNo));
        if (LotNo = '') and (SerialNo = '') and (PackageNo = '') then
            exit;
        TrackingLine.Init();
        TrackingLine."Entry No." := TrackingLine.GetLastEntryNo() + 1;
        TrackingLine.SetSource(Database::"Warehouse Journal Line", 0, JournalLine."Journal Batch Name", JournalLine."Line No.", JournalLine."Journal Template Name", 0);
        TrackingLine.Validate("Item No.", JournalLine."Item No.");
        TrackingLine.Validate("Location Code", JournalLine."Location Code");
        TrackingLine.Validate("Variant Code", JournalLine."Variant Code");
        TrackingLine.Validate("Qty. per Unit of Measure", JournalLine."Qty. per Unit of Measure");
        TrackingLine.Validate("Quantity (Base)", Abs(JournalLine."Qty. (Base)"));
        TrackingLine.Validate("Serial No.", SerialNo);
        TrackingLine.Validate("Lot No.", LotNo);
        TrackingLine.Validate("Package No.", PackageNo);
        if Reclass then begin
            TrackingLine."New Serial No." := SerialNo;
            TrackingLine."New Lot No." := LotNo;
            TrackingLine."New Package No." := PackageNo;
        end;
        if Values.DateValue(LineObject, 'expirationDate') <> 0D then begin
            TrackingLine.Validate("Expiration Date", Values.DateValue(LineObject, 'expirationDate'));
            if Reclass then
                TrackingLine."New Expiration Date" := TrackingLine."Expiration Date";
        end;
        TrackingLine.Insert(true);
    end;

    local procedure LinesField(ContractMgt: Codeunit "Msg Contract Mgt ori"; Description: Text): JsonObject
    var
        LineFields: JsonArray;
        Lines: JsonObject;
    begin
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Journal line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('entryType', 'string', 'Positive Adjmt., Negative Adjmt. or Movement.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin of an item journal line.'));
        LineFields.Add(ContractMgt.ResponseField('fromBin', 'string', 'Bin the quantity is taken from.'));
        LineFields.Add(ContractMgt.ResponseField('toBin', 'string', 'Bin the quantity is placed in.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity of the line.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', Description);
        Lines.Add('children', LineFields);
        exit(Lines);
    end;

    local procedure HasWritePermission(): Boolean
    var
        JournalLine: Record "Warehouse Journal Line";
        TrackingLine: Record "Whse. Item Tracking Line";
    begin
        exit(JournalLine.WritePermission() and TrackingLine.WritePermission());
    end;
}
