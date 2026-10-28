namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.History;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.PostedDocument.Get: a paged read of posted warehouse receipts or posted warehouse
/// shipments, by number or by filters, optionally with their lines.
/// </summary>
codeunit 10078436 "Whse PostedDoc Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can read posted warehouse receipts and shipments.</summary>
    /// <returns>True when the caller can read the four posted warehouse document tables.</returns>
    procedure IsEnabled(): Boolean
    var
        ReceiptHeader: Record "Posted Whse. Receipt Header";
        ReceiptLine: Record "Posted Whse. Receipt Line";
        ShipmentHeader: Record "Posted Whse. Shipment Header";
        ShipmentLine: Record "Posted Whse. Shipment Line";
    begin
        exit(ReceiptHeader.ReadPermission() and ReceiptLine.ReadPermission() and ShipmentHeader.ReadPermission() and ShipmentLine.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The posted warehouse receipt header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Posted Whse. Receipt Header");
    end;

    /// <summary>Returns a short description of Warehouse.PostedDocument.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Reads posted warehouse receipts or posted warehouse shipments, optionally with lines.', Comment = 'is-IS=Les bókaðar vöruhúsamóttökur eða bókaðar vöruhúsaafhendingar, valfrjálst með línum.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'posted warehouse receipt, posted warehouse shipment, what was received, what was shipped, warehouse history, posted receipt lines', Comment = 'is-IS=bókuð vöruhúsamóttaka, bókuð vöruhúsaafhending, hvað var móttekið, hvað var afhent, vöruhúsasaga, línur bókaðrar móttöku';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Reads posted warehouse receipts or shipments by number or by location, source number and posting date, paged.', Comment = 'is-IS=Lesaðgangur. Les bókaðar vöruhúsamóttökur eða vöruhúsaafhendingar eftir númeri eða eftir staðsetningu, númeri upprunaskjals og bókunardegi, blaðsíðuskipt.';
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
        Forms.Add('document no.');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A posted document number selects the same document as no. Do not send a different number in both places.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The number of the posted warehouse receipt or shipment.'));
        Target.Add(ContractMgt.TargetEntry('data.no', 'document no.', 'The number of the posted warehouse receipt or shipment.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parameters.Add(ContractMgt.Parameter('documentType', 'string', true, 'Receipt or Shipment.'));
        Parameters.Add(ContractMgt.Parameter('no', 'string', false, 'Posted document number. Leave it out to search with filters.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location code.'));
        Parameters.Add(ContractMgt.Parameter('sourceNo', 'string', false, 'Source document number on any line of the posted document.'));
        Parameters.Add(ContractMgt.Parameter('postingDateFrom', 'date', false, 'First posting date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('postingDateTo', 'date', false, 'Last posting date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('includeLines', 'boolean', false, 'Return the lines of each document. Defaults to false.'));
        Parts.AddPagingParameters(Parameters);
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
        ResultFields: JsonArray;
        LineFields: JsonArray;
        Result: JsonObject;
        Lines: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('documentType', 'string', 'Receipt or Shipment.'));
        Fields.Add(ContractMgt.ResponseField('noOfRecords', 'integer', 'Number of matching documents before paging.'));
        Fields.Add(ContractMgt.ResponseField('skip', 'integer', 'Records skipped.'));
        Fields.Add(ContractMgt.ResponseField('take', 'integer', 'Page size.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Posted line number.'));
        LineFields.Add(ContractMgt.ResponseField('sourceDocument', 'string', 'Kind of source document, for example Purchase Order.'));
        LineFields.Add(ContractMgt.ResponseField('sourceNo', 'string', 'Source document number.'));
        LineFields.Add(ContractMgt.ResponseField('sourceLineNo', 'integer', 'Source document line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        LineFields.Add(ContractMgt.ResponseField('description', 'string', 'Line description.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Posted quantity.'));
        LineFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure code.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin code.'));
        LineFields.Add(ContractMgt.ResponseField('postedSourceDocument', 'string', 'Kind of posted source document, for example Posted Receipt.'));
        LineFields.Add(ContractMgt.ResponseField('postedSourceNo', 'string', 'Posted source document number.'));
        ResultFields.Add(ContractMgt.ResponseField('no', 'string', 'Posted document number.'));
        ResultFields.Add(ContractMgt.ResponseField('systemId', 'string', 'SystemId of the posted document.'));
        ResultFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        ResultFields.Add(ContractMgt.ResponseField('postingDate', 'string', 'Posting date as YYYY-MM-DD.'));
        ResultFields.Add(ContractMgt.ResponseField('whseReceiptNo', 'string', 'Warehouse receipt it was posted from. Receipt only.'));
        ResultFields.Add(ContractMgt.ResponseField('vendorShipmentNo', 'string', 'Vendor shipment number. Receipt only.'));
        ResultFields.Add(ContractMgt.ResponseField('whseShipmentNo', 'string', 'Warehouse shipment it was posted from. Shipment only.'));
        ResultFields.Add(ContractMgt.ResponseField('externalDocumentNo', 'string', 'External document number. Shipment only.'));
        ResultFields.Add(ContractMgt.ResponseField('shipmentDate', 'string', 'Shipment date as YYYY-MM-DD, or blank. Shipment only.'));
        ResultFields.Add(ContractMgt.ResponseField('shippingAgentCode', 'string', 'Shipping agent code. Shipment only.'));
        ResultFields.Add(ContractMgt.ResponseField('assignedUserId', 'string', 'Assigned user ID.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Included when includeLines is true.');
        Lines.Add('children', LineFields);
        ResultFields.Add(Lines);
        Result.Add('name', 'result');
        Result.Add('type', 'array');
        Result.Add('description', 'The paged posted documents.');
        Result.Add('children', ResultFields);
        Fields.Add(Result);
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
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
        UnknownParameterNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'documentType is missing.', 'Send documentType Receipt or Shipment.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'documentType is not Receipt or Shipment, or the posting date range ends before it starts.', 'Use one of the values listed in the help.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The named posted document does not exist.', 'Search with filters instead of a no.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and no name different documents.', 'Send one number: subject or no.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or a date is not YYYY-MM-DD.', 'Send text for codes, true or false for includeLines, and dates as YYYY-MM-DD.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', UnknownParameterNextStepLbl);
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot read posted warehouse receipts and shipments.', 'Ask an administrator to assign BIFROST Whse - Read ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again.');
        Parts.AddDateErrors(Errors, 'postingDateFrom, postingDateTo', Context.TextDateNextStep());
        Parts.AddDateRangeError(Errors, 'postingDateFrom and postingDateTo');
        Parts.AddPagingErrors(Errors, true);
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Reads posted warehouse receipts or shipments. Nothing is written.', 'BIFROST Whse - Read ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Post', 'It creates the posted warehouse receipts this type reads.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Post', 'It creates the posted warehouse shipments this type reads.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Create', 'Use it with a posted warehouse receipt number to create the put-away.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.RegisteredActivity.Get', 'Use it to read the registered picks, put-aways and movements.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True. The read finds the posted receipt that the put-away is created from.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Receipt.Post', 'Post the warehouse receipt; this creates the posted warehouse receipt.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.PostedDocument.Get', 'Find the posted warehouse receipt, with documentType Receipt and the source document number, and read its lines.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Putaway.Create', 'Create the put-away from the posted warehouse receipt number.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Putaway.Register', 'Register the put-away to place the goods in their bins.'));
        Workflow.Add('steps', Steps);
        Workflow.Add('text', 'For a shipment the read only confirms what was shipped: Warehouse.Shipment.Post creates the posted warehouse shipment, and there is no further step in this app.');
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
            'Posted warehouse receipts for purchase order 106001',
            '{"documentType":"Receipt","sourceNo":"106001","includeLines":true}',
            '{"status":"Success","documentType":"Receipt","noOfRecords":1,"skip":0,"take":20,"result":[{"no":"R_000001","systemId":"6f1c1d2e-0000-0000-0000-000000000002","locationCode":"WHITE","postingDate":"2026-10-19","whseReceiptNo":"RE000001","vendorShipmentNo":"","assignedUserId":"","lines":[{"lineNo":10000,"sourceDocument":"Purchase Order","sourceNo":"106001","sourceLineNo":10000,"itemNo":"1896-S","variantCode":"","description":"ATHENS Desk","quantity":5,"unitOfMeasureCode":"PCS","binCode":"W-08-0001","postedSourceDocument":"Posted Receipt","postedSourceNo":"107001"}]}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Reads posted warehouse receipts (documentType Receipt) or posted warehouse shipments (documentType Shipment) by number, or by location, source document number and posting date range, paged with take and skip. includeLines adds the lines. A number that does not exist is refused; filters that match nothing answer success with an empty list. Nothing is written.', Comment = 'is-IS=Les bókaðar vöruhúsamóttökur (documentType Receipt) eða bókaðar vöruhúsaafhendingar (documentType Shipment) eftir númeri, eða eftir staðsetningu, númeri upprunaskjals og bili bókunardaga, blaðsíðuskipt með take og skip. includeLines bætir línunum við. Númeri sem er ekki til er hafnað; síur sem passa ekki við neitt skila árangri með tómum lista. Ekkert er skrifað.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes list edge cases of the filters.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'documentType is always required, also when a number is sent: Receipt reads Posted Warehouse Receipts and Shipment reads Posted Warehouse Shipments, and the names are matched ignoring case. The other fields of a document differ by type, see the response. ' +
            'Posted documents are created by Warehouse.Receipt.Post and Warehouse.Shipment.Post and cannot be changed, so this read is the way to see what was received or shipped. ' +
            'A number (as subject or no, read in upper case) must exist, or the answer is RecordNotFound. If other filters then exclude that document, the answer is Success with noOfRecords 0. Sending subject and no with different numbers is refused. ' +
            'sourceNo keeps the documents that have at least one line for that source document number, read in upper case. With includeLines, every line of such a document is returned, not only the lines of that source document. ' +
            'postingDateFrom and postingDateTo are inclusive and either can be left out. locationCode is an exact match. Filters that match nothing are Success with an empty result. ' +
            'Documents are returned in the order of their numbers, paged with skip and take; noOfRecords is the total before paging. All invalid values, including a bad skip or take, are answered together. ' +
            'includeLines must be the JSON value true or false; text such as "true" is refused. Quantities are the posted quantities, in the unit of measure on the line.';
        exit(true);
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Validates the filters and writes one page of posted documents.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        DocumentTypeText: Text;
        DocumentNo: Text;
        LocationText: Text;
        SourceNo: Text;
        PostingFrom: Date;
        PostingTo: Date;
        IncludeLines: Boolean;
        Present: Boolean;
        IsShipment: Boolean;
        Skip: Integer;
        Take: Integer;
        DeniedLbl: Label 'You do not have permission to read posted warehouse receipts and shipments.', Comment = 'is-IS=Þú hefur ekki heimild til að lesa bókaðar vöruhúsamóttökur og vöruhúsaafhendingar.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Read ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Read ori.';
        ProblemsLbl: Label 'The request has invalid values.', Comment = 'is-IS=Beiðnin hefur ógild gildi.';
        MissingLbl: Label 'documentType is required.', Comment = 'is-IS=documentType er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send documentType Receipt or Shipment.', Comment = 'is-IS=Sendu documentType Receipt eða Shipment.';
        ValueLbl: Label 'Parameter %1 has the value %2, which is not one of the values listed in the help.', Comment = '%1 = parameter, %2 = value, is-IS=Færibreytan %1 hefur gildið %2 sem er ekki eitt af gildunum sem talin eru upp í hjálpinni.';
        ValueNextStepLbl: Label 'Use one of the values listed in the help.', Comment = 'is-IS=Notaðu eitt af gildunum sem talin eru upp í hjálpinni.';
        RangeLbl: Label 'The date range %1 ends before it starts.', Comment = '%1 = parameter, is-IS=Dagsetningabilið %1 endar áður en það byrjar.';
    begin
        if not IsEnabled() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        RefuseUnknownKeys(RequestJson, Argument);
        if Context.ReadText(RequestJson, 'documentType', 20, Argument, DocumentTypeText, Present, 'documentType') then
            if not Present then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'documentType', '', 'Receipt, Shipment', MissingNextStepLbl)
            else
                case true of
                    Context.SameName(DocumentTypeText, 'Receipt'):
                        IsShipment := false;
                    Context.SameName(DocumentTypeText, 'Shipment'):
                        IsShipment := true;
                    else
                        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'documentType', DocumentTypeText), 'documentType', DocumentTypeText, 'Receipt, Shipment', ValueNextStepLbl);
                end;
        ResolveNumber(RequestJson, Argument, DocumentNo);
        Context.ReadText(RequestJson, 'locationCode', 10, Argument, LocationText, Present, 'locationCode');
        Context.ReadText(RequestJson, 'sourceNo', 20, Argument, SourceNo, Present, 'sourceNo');
        Context.ReadDate(RequestJson, 'postingDateFrom', Argument, PostingFrom, Present, 'postingDateFrom');
        Context.ReadDate(RequestJson, 'postingDateTo', Argument, PostingTo, Present, 'postingDateTo');
        Context.ReadBoolean(RequestJson, 'includeLines', Argument, IncludeLines, Present, 'includeLines');
        if (PostingFrom <> 0D) and (PostingTo <> 0D) and (PostingTo < PostingFrom) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, 'postingDateFrom'), 'postingDateTo', Context.FormatDate(PostingTo), '', Context.DateRangeNextStep());
        // Every problem of the request is answered together, a bad skip or take included.
        if not Context.RespondOrReadPaging(RequestJson, Argument, ProblemsLbl, Skip, Take) then
            exit;
        if IsShipment then
            WriteShipments(Argument, DocumentNo, LocationText, SourceNo, PostingFrom, PostingTo, IncludeLines, Skip, Take)
        else
            WriteReceipts(Argument, DocumentNo, LocationText, SourceNo, PostingFrom, PostingTo, IncludeLines, Skip, Take);
    end;

    local procedure WriteReceipts(var Argument: Record "Message Argument ori"; DocumentNo: Text; LocationText: Text; SourceNo: Text; PostingFrom: Date; PostingTo: Date; IncludeLines: Boolean; Skip: Integer; Take: Integer)
    var
        ReceiptHeader: Record "Posted Whse. Receipt Header";
        ReceiptLine: Record "Posted Whse. Receipt Line";
        Context: Codeunit "Whse Write Context ori";
        ResultArray: JsonArray;
        DocumentJson: JsonObject;
        HeaderNos: List of [Text];
        NoOfRecords: Integer;
    begin
        ReceiptHeader.ReadIsolation := IsolationLevel::ReadCommitted;
        if DocumentNo <> '' then begin
            ReceiptHeader.SetLoadFields("No.");
            if not ReceiptHeader.Get(CopyStr(UpperCase(DocumentNo), 1, MaxStrLen(ReceiptHeader."No."))) then begin
                RespondNotFound(Argument, DocumentNo);
                exit;
            end;
            ReceiptHeader.SetRange("No.", ReceiptHeader."No.");
        end;
        if LocationText <> '' then
            ReceiptHeader.SetRange("Location Code", CopyStr(UpperCase(LocationText), 1, MaxStrLen(ReceiptHeader."Location Code")));
        if SourceNo <> '' then begin
            ReceiptLine.SetRange("Source No.", CopyStr(UpperCase(SourceNo), 1, MaxStrLen(ReceiptLine."Source No.")));
            ReceiptLine.SetLoadFields("No.");
            if ReceiptLine.FindSet() then
                repeat
                    if not HeaderNos.Contains(ReceiptLine."No.") then
                        HeaderNos.Add(ReceiptLine."No.");
                until ReceiptLine.Next() = 0;
            if HeaderNos.Count() = 0 then begin
                WritePage(Argument, 'Receipt', 0, Skip, Take, ResultArray);
                exit;
            end;
            ReceiptHeader.FilterGroup(2);
            ReceiptHeader.SetFilter("No.", Context.LiteralFilter(HeaderNos));
            ReceiptHeader.FilterGroup(0);
        end;
        if (PostingFrom <> 0D) or (PostingTo <> 0D) then
            ReceiptHeader.SetRange("Posting Date", PostingFrom, Context.RangeEnd(PostingTo));
        ReceiptHeader.SetLoadFields("No.", "Location Code", "Posting Date", "Whse. Receipt No.", "Vendor Shipment No.", "Assigned User ID");
        NoOfRecords := ReceiptHeader.Count();
        if Skip < NoOfRecords then
            if ReceiptHeader.FindSet() then begin
                if Skip > 0 then
                    ReceiptHeader.Next(Skip);
                repeat
                    Clear(DocumentJson);
                    DocumentJson.Add('no', ReceiptHeader."No.");
                    DocumentJson.Add('systemId', Format(ReceiptHeader.SystemId, 0, 4));
                    DocumentJson.Add('locationCode', ReceiptHeader."Location Code");
                    DocumentJson.Add('postingDate', Context.FormatDate(ReceiptHeader."Posting Date"));
                    DocumentJson.Add('whseReceiptNo', ReceiptHeader."Whse. Receipt No.");
                    DocumentJson.Add('vendorShipmentNo', ReceiptHeader."Vendor Shipment No.");
                    DocumentJson.Add('assignedUserId', ReceiptHeader."Assigned User ID");
                    if IncludeLines then
                        DocumentJson.Add('lines', ReceiptLinesJson(ReceiptHeader."No."));
                    ResultArray.Add(DocumentJson);
                    if ResultArray.Count() >= Take then
                        break;
                until ReceiptHeader.Next() = 0;
            end;
        WritePage(Argument, 'Receipt', NoOfRecords, Skip, Take, ResultArray);
    end;

    local procedure WriteShipments(var Argument: Record "Message Argument ori"; DocumentNo: Text; LocationText: Text; SourceNo: Text; PostingFrom: Date; PostingTo: Date; IncludeLines: Boolean; Skip: Integer; Take: Integer)
    var
        ShipmentHeader: Record "Posted Whse. Shipment Header";
        ShipmentLine: Record "Posted Whse. Shipment Line";
        Context: Codeunit "Whse Write Context ori";
        ResultArray: JsonArray;
        DocumentJson: JsonObject;
        HeaderNos: List of [Text];
        NoOfRecords: Integer;
    begin
        ShipmentHeader.ReadIsolation := IsolationLevel::ReadCommitted;
        if DocumentNo <> '' then begin
            ShipmentHeader.SetLoadFields("No.");
            if not ShipmentHeader.Get(CopyStr(UpperCase(DocumentNo), 1, MaxStrLen(ShipmentHeader."No."))) then begin
                RespondNotFound(Argument, DocumentNo);
                exit;
            end;
            ShipmentHeader.SetRange("No.", ShipmentHeader."No.");
        end;
        if LocationText <> '' then
            ShipmentHeader.SetRange("Location Code", CopyStr(UpperCase(LocationText), 1, MaxStrLen(ShipmentHeader."Location Code")));
        if SourceNo <> '' then begin
            ShipmentLine.SetRange("Source No.", CopyStr(UpperCase(SourceNo), 1, MaxStrLen(ShipmentLine."Source No.")));
            ShipmentLine.SetLoadFields("No.");
            if ShipmentLine.FindSet() then
                repeat
                    if not HeaderNos.Contains(ShipmentLine."No.") then
                        HeaderNos.Add(ShipmentLine."No.");
                until ShipmentLine.Next() = 0;
            if HeaderNos.Count() = 0 then begin
                WritePage(Argument, 'Shipment', 0, Skip, Take, ResultArray);
                exit;
            end;
            ShipmentHeader.FilterGroup(2);
            ShipmentHeader.SetFilter("No.", Context.LiteralFilter(HeaderNos));
            ShipmentHeader.FilterGroup(0);
        end;
        if (PostingFrom <> 0D) or (PostingTo <> 0D) then
            ShipmentHeader.SetRange("Posting Date", PostingFrom, Context.RangeEnd(PostingTo));
        ShipmentHeader.SetLoadFields("No.", "Location Code", "Posting Date", "Whse. Shipment No.", "External Document No.", "Shipment Date", "Shipping Agent Code", "Assigned User ID");
        NoOfRecords := ShipmentHeader.Count();
        if Skip < NoOfRecords then
            if ShipmentHeader.FindSet() then begin
                if Skip > 0 then
                    ShipmentHeader.Next(Skip);
                repeat
                    Clear(DocumentJson);
                    DocumentJson.Add('no', ShipmentHeader."No.");
                    DocumentJson.Add('systemId', Format(ShipmentHeader.SystemId, 0, 4));
                    DocumentJson.Add('locationCode', ShipmentHeader."Location Code");
                    DocumentJson.Add('postingDate', Context.FormatDate(ShipmentHeader."Posting Date"));
                    DocumentJson.Add('whseShipmentNo', ShipmentHeader."Whse. Shipment No.");
                    DocumentJson.Add('externalDocumentNo', ShipmentHeader."External Document No.");
                    DocumentJson.Add('shipmentDate', Context.FormatDate(ShipmentHeader."Shipment Date"));
                    DocumentJson.Add('shippingAgentCode', ShipmentHeader."Shipping Agent Code");
                    DocumentJson.Add('assignedUserId', ShipmentHeader."Assigned User ID");
                    if IncludeLines then
                        DocumentJson.Add('lines', ShipmentLinesJson(ShipmentHeader."No."));
                    ResultArray.Add(DocumentJson);
                    if ResultArray.Count() >= Take then
                        break;
                until ShipmentHeader.Next() = 0;
            end;
        WritePage(Argument, 'Shipment', NoOfRecords, Skip, Take, ResultArray);
    end;

    local procedure ReceiptLinesJson(DocumentNo: Code[20]) Lines: JsonArray
    var
        ReceiptLine: Record "Posted Whse. Receipt Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        LineJson: JsonObject;
    begin
        ReceiptLine.ReadIsolation := IsolationLevel::ReadCommitted;
        ReceiptLine.SetLoadFields("No.", "Line No.", "Source Document", "Source No.", "Source Line No.", "Item No.", "Variant Code", Description, Quantity, "Unit of Measure Code", "Bin Code", "Posted Source Document", "Posted Source No.");
        ReceiptLine.SetRange("No.", DocumentNo);
        if ReceiptLine.FindSet() then
            repeat
                RecordReference.GetTable(ReceiptLine);
                Clear(LineJson);
                LineJson.Add('lineNo', ReceiptLine."Line No.");
                LineJson.Add('sourceDocument', Context.EnumValueName(RecordReference, ReceiptLine.FieldNo("Source Document")));
                LineJson.Add('sourceNo', ReceiptLine."Source No.");
                LineJson.Add('sourceLineNo', ReceiptLine."Source Line No.");
                LineJson.Add('itemNo', ReceiptLine."Item No.");
                LineJson.Add('variantCode', ReceiptLine."Variant Code");
                LineJson.Add('description', ReceiptLine.Description);
                LineJson.Add('quantity', ReceiptLine.Quantity);
                LineJson.Add('unitOfMeasureCode', ReceiptLine."Unit of Measure Code");
                LineJson.Add('binCode', ReceiptLine."Bin Code");
                LineJson.Add('postedSourceDocument', Context.EnumValueName(RecordReference, ReceiptLine.FieldNo("Posted Source Document")));
                LineJson.Add('postedSourceNo', ReceiptLine."Posted Source No.");
                Lines.Add(LineJson);
            until ReceiptLine.Next() = 0;
    end;

    local procedure ShipmentLinesJson(DocumentNo: Code[20]) Lines: JsonArray
    var
        ShipmentLine: Record "Posted Whse. Shipment Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        LineJson: JsonObject;
    begin
        ShipmentLine.ReadIsolation := IsolationLevel::ReadCommitted;
        ShipmentLine.SetLoadFields("No.", "Line No.", "Source Document", "Source No.", "Source Line No.", "Item No.", "Variant Code", Description, Quantity, "Unit of Measure Code", "Bin Code", "Posted Source Document", "Posted Source No.");
        ShipmentLine.SetRange("No.", DocumentNo);
        if ShipmentLine.FindSet() then
            repeat
                RecordReference.GetTable(ShipmentLine);
                Clear(LineJson);
                LineJson.Add('lineNo', ShipmentLine."Line No.");
                LineJson.Add('sourceDocument', Context.EnumValueName(RecordReference, ShipmentLine.FieldNo("Source Document")));
                LineJson.Add('sourceNo', ShipmentLine."Source No.");
                LineJson.Add('sourceLineNo', ShipmentLine."Source Line No.");
                LineJson.Add('itemNo', ShipmentLine."Item No.");
                LineJson.Add('variantCode', ShipmentLine."Variant Code");
                LineJson.Add('description', ShipmentLine.Description);
                LineJson.Add('quantity', ShipmentLine.Quantity);
                LineJson.Add('unitOfMeasureCode', ShipmentLine."Unit of Measure Code");
                LineJson.Add('binCode', ShipmentLine."Bin Code");
                LineJson.Add('postedSourceDocument', Context.EnumValueName(RecordReference, ShipmentLine.FieldNo("Posted Source Document")));
                LineJson.Add('postedSourceNo', ShipmentLine."Posted Source No.");
                Lines.Add(LineJson);
            until ShipmentLine.Next() = 0;
    end;

    local procedure WritePage(var Argument: Record "Message Argument ori"; DocumentType: Text; NoOfRecords: Integer; Skip: Integer; Take: Integer; ResultArray: JsonArray)
    var
        ResponseJson: JsonObject;
    begin
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('documentType', DocumentType);
        ResponseJson.Add('noOfRecords', NoOfRecords);
        ResponseJson.Add('skip', Skip);
        ResponseJson.Add('take', Take);
        ResponseJson.Add('result', ResultArray);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure RespondNotFound(var Argument: Record "Message Argument ori"; DocumentNo: Text)
    var
        NotFoundLbl: Label 'Posted warehouse document %1 was not found.', Comment = '%1 = document no., is-IS=Bókað vöruhúsaskjal %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Search with filters instead of a no.', Comment = 'is-IS=Leitaðu með síum í stað númers.';
    begin
        Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, DocumentNo), 'no', DocumentNo, '', NotFoundNextStepLbl);
    end;

    local procedure ResolveNumber(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var DocumentNo: Text)
    var
        Context: Codeunit "Whse Write Context ori";
        SubjectText: Text;
        Present: Boolean;
        ConflictLbl: Label 'subject and no name different documents.', Comment = 'is-IS=subject og no nefna mismunandi skjöl.';
        ConflictNextStepLbl: Label 'Send one number: subject or no.', Comment = 'is-IS=Sendu eitt númer: subject eða no.';
    begin
        DocumentNo := '';
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Context.ReadText(RequestJson, 'no', 20, Argument, DocumentNo, Present, 'no') then
            exit;
        if Present and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(DocumentNo)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'no', DocumentNo, SubjectText, ConflictNextStepLbl);
            exit;
        end;
        if not Present then
            DocumentNo := SubjectText;
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['documentType', 'no', 'locationCode', 'sourceNo', 'postingDateFrom', 'postingDateTo', 'includeLines', 'skip', 'take']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;
}
