namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Document;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Document.Get: a paged read of open warehouse receipts or open warehouse
/// shipments, by number or by filters, optionally with their lines.
/// </summary>
codeunit 10078439 "Whse Document Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can read open warehouse receipts and shipments.</summary>
    /// <returns>True when the caller can read the four open warehouse document tables.</returns>
    procedure IsEnabled(): Boolean
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        exit(ReceiptHeader.ReadPermission() and ReceiptLine.ReadPermission() and ShipmentHeader.ReadPermission() and ShipmentLine.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The open warehouse receipt header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Receipt Header");
    end;

    /// <summary>Returns a short description of Warehouse.Document.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Reads open warehouse receipts or open warehouse shipments, optionally with lines.', Comment = 'is-IS=Les opnar vöruhúsamóttökur eða opnar vöruhúsaafhendingar, valfrjálst með línum. Leitarorð: opin vöruhúsamóttaka, opin vöruhúsaafhending, óafgreidd móttaka, óafgreidd afhending, tínt magn, línur opinna skjala.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'open warehouse receipt, open warehouse shipment, outstanding receipt, outstanding shipment, picked quantity, open document lines', Comment = 'is-IS=opin vöruhúsamóttaka, opin vöruhúsaafhending, óafgreidd móttaka, óafgreidd afhending, tínt magn, línur opinna skjala';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Reads open warehouse receipts or shipments by number or by location, source number and posting date, paged.', Comment = 'is-IS=Lesaðgangur. Les opnar vöruhúsamóttökur eða vöruhúsaafhendingar eftir númeri eða eftir staðsetningu, númeri upprunaskjals og bókunardegi, blaðsíðuskipt.';
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
        Forms.Add('systemId');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional document number or SystemId. All supplied identifiers must refer to the same document.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The number of the open warehouse receipt or shipment.'));
        Target.Add(ContractMgt.TargetEntry('data.documentNo', 'document no.', 'The number of the open warehouse receipt or shipment.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId', 'systemId', 'SystemId of the document. id is an alias.'));
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
        Parameters.Add(ContractMgt.Parameter('documentNo', 'string', false, 'Open document number. Leave identifiers out to search with filters.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'SystemId of the open document.'));
        Parameters.Add(ContractMgt.Parameter('id', 'string', false, 'Alias for systemId.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location code.'));
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'Exact assigned user ID.'));
        Parameters.Add(ContractMgt.Parameter('status', 'string', false, 'Open or Released. Shipments only.'));
        Parameters.Add(ContractMgt.Parameter('sourceType', 'integer', false, 'Source type number on the same line as sourceNo, for example 39 for purchase lines or 37 for sales lines.'));
        Parameters.Add(ContractMgt.Parameter('sourceNo', 'string', false, 'Source document number on any line of the open document.'));
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
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Open document line number.'));
        LineFields.Add(ContractMgt.ResponseField('sourceType', 'integer', 'Source type number.'));
        LineFields.Add(ContractMgt.ResponseField('sourceDocument', 'string', 'Kind of source document, for example Purchase Order.'));
        LineFields.Add(ContractMgt.ResponseField('sourceNo', 'string', 'Source document number.'));
        LineFields.Add(ContractMgt.ResponseField('sourceLineNo', 'integer', 'Source document line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        LineFields.Add(ContractMgt.ResponseField('description', 'string', 'Line description.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Original document quantity in the line unit of measure.'));
        LineFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure code.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin code.'));
        LineFields.Add(ContractMgt.ResponseField('qtyOutstanding', 'number', 'Quantity still to receive or ship.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToReceive', 'number', 'Quantity selected to receive. Receipt only.'));
        LineFields.Add(ContractMgt.ResponseField('qtyReceived', 'number', 'Quantity already received. Receipt only.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToShip', 'number', 'Quantity selected to ship. Shipment only.'));
        LineFields.Add(ContractMgt.ResponseField('qtyShipped', 'number', 'Quantity already shipped. Shipment only.'));
        LineFields.Add(ContractMgt.ResponseField('qtyPicked', 'number', 'Registered picked quantity. Shipment only.'));
        LineFields.Add(ContractMgt.ResponseField('pickQty', 'number', 'Outstanding quantity on unregistered picks. Shipment only.'));
        LineFields.Add(ContractMgt.ResponseField('putAwayQty', 'number', 'Zero on open documents; put-away progress belongs to posted receipts.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToCrossDock', 'number', 'Suggested cross-dock quantity. Receipt only.'));
        LineFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone code.'));
        LineFields.Add(ContractMgt.ResponseField('dueDate', 'string', 'Due date as YYYY-MM-DD, or blank.'));
        ResultFields.Add(ContractMgt.ResponseField('no', 'string', 'Open document number.'));
        ResultFields.Add(ContractMgt.ResponseField('systemId', 'string', 'SystemId of the open document.'));
        ResultFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        ResultFields.Add(ContractMgt.ResponseField('postingDate', 'string', 'Posting date as YYYY-MM-DD.'));
        ResultFields.Add(ContractMgt.ResponseField('vendorShipmentNo', 'string', 'Vendor shipment number. Receipt only.'));
        ResultFields.Add(ContractMgt.ResponseField('externalDocumentNo', 'string', 'External document number. Shipment only.'));
        ResultFields.Add(ContractMgt.ResponseField('shipmentDate', 'string', 'Shipment date as YYYY-MM-DD, or blank. Shipment only.'));
        ResultFields.Add(ContractMgt.ResponseField('shippingAgentCode', 'string', 'Shipping agent code. Shipment only.'));
        ResultFields.Add(ContractMgt.ResponseField('assignedUserId', 'string', 'Assigned user ID.'));
        ResultFields.Add(ContractMgt.ResponseField('status', 'string', 'Open or Released for shipments; Open for receipts.'));
        ResultFields.Add(ContractMgt.ResponseField('documentStatus', 'string', 'Current document handling progress.'));
        ResultFields.Add(ContractMgt.ResponseField('sortingMethod', 'string', 'Sorting method name.'));
        ResultFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Default zone code.'));
        ResultFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Default bin code.'));
        ResultFields.Add(ContractMgt.ResponseField('completelyPicked', 'boolean', 'Whether all shipment lines are completely picked. Shipment only.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Included when includeLines is true.');
        Lines.Add('children', LineFields);
        ResultFields.Add(Lines);
        Result.Add('name', 'documents');
        Result.Add('type', 'array');
        Result.Add('description', 'The paged open documents.');
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
        OriginalLanguage: Integer;
        UnknownNextStep: Text;
        UnknownParameterNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        // Read before the language switch: the declared unknown-key next step is rendered in the caller's language (#88 AC02).
        UnknownNextStep := UnknownParameterNextStepLbl;
        OriginalLanguage := GlobalLanguage();
        GlobalLanguage(1033);
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'documentType is missing.', 'Send documentType Receipt or Shipment.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'documentType or status is unknown, status is used for a receipt, sourceType is negative, or the posting date range is reversed.', 'Use one of the values listed in the help.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The named open document does not exist.', 'Search with filters instead of a document identifier.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'The supplied identifiers name different documents.', 'Send only identifiers for the same document.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or a date is not YYYY-MM-DD.', 'Send text for codes, true or false for includeLines, and dates as YYYY-MM-DD.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', UnknownNextStep);
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot read open warehouse receipts and shipments.', 'Ask an administrator to assign BIFROST Whse - Read ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again.');
        Parts.AddDateErrors(Errors, 'postingDateFrom, postingDateTo', Context.TextDateNextStep());
        Parts.AddDateRangeError(Errors, 'postingDateFrom and postingDateTo');
        Parts.AddPagingErrors(Errors, true);
        Parts.AddLookupErrors(Errors, 'open warehouse document', 'documentNo, systemId, id');
        GlobalLanguage(OriginalLanguage);
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Reads open warehouse receipts or shipments. Nothing is written.', 'BIFROST Whse - Read ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Post', 'Receive the quantities selected on the receipt.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Post', 'Ship the quantities selected on the shipment.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Create', 'After posting the receipt, create the put-away from the posted receipt number (see Warehouse.PostedDocument.Get).'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Create', 'Create picks for a released shipment.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PostedDocument.Get', 'Read receipts and shipments after posting.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True. The read returns an open warehouse document; the put-away is created later from the posted receipt.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Document.Get', 'Read the open receipt and its outstanding line quantities.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Receipt.Post', 'Receive the selected quantities, with explicit confirmation.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Document.Get', 'Read any remaining quantities before receiving again.'));
        Workflow.Add('steps', Steps);
        Workflow.Add('text', 'For shipments, read status and picked quantities before posting. Use Warehouse.PostedDocument.Get for documents that have been fully posted.');
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
            'Open receipts for a purchase order',
            '{"documentType":"receipt","sourceType":39,"sourceNo":"XPO001","includeLines":true}',
            '{"status":"Success","documentType":"Receipt","noOfRecords":0,"skip":0,"take":100,"documents":[]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read open warehouse receipts or shipments by document number or SystemId, or search by location, source, assigned user and posting date. Shipment status and picked quantities show readiness to ship. includeLines adds outstanding and handled quantities. Nothing is written.';
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes list edge cases of the filters.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'documentType is required and ignores case. documentNo, systemId, id and subject must all identify the same document. A missing named document is refused; other filters can still exclude an existing document. ' +
            'sourceType and sourceNo match the same line. includeLines returns every line on each matching document. Codes are exact matches, not filter expressions. Dates are inclusive. status accepts Open or Released for shipments only. ' +
            'Documents are ordered by number. noOfRecords is the total before skip and take. Paging follows the common defaults and limits. Filters matching nothing succeed with an empty documents array. ' +
            'Quantities use the unit of measure on the line. qtyPicked is registered picking; pickQty is outstanding work on unregistered picks. putAwayQty is zero on open documents because put-away progress belongs to posted receipts. ' +
            'Receipts have no release status and answer status Open. documentStatus reports handling progress. Fully posted documents are read with Warehouse.PostedDocument.Get. Help chapters remain English in every language.';
        exit(true);
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Validates the filters and writes one page of open documents.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        DocumentTypeText: Text;
        DocumentId: Guid;
        DocumentNo: Text;
        AssignedUserId: Text;
        StatusText: Text;
        SourceType: Integer;
        HasSourceType: Boolean;
        LocationText: Text;
        SourceNo: Text;
        PostingFrom: Date;
        PostingTo: Date;
        IncludeLines: Boolean;
        Present: Boolean;
        IsShipment: Boolean;
        Skip: Integer;
        Take: Integer;
        DeniedLbl: Label 'You do not have permission to read open warehouse receipts and shipments.', Comment = 'is-IS=Þú hefur ekki heimild til að lesa opnar vöruhúsamóttökur og vöruhúsaafhendingar.';
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
        if not WhseRecordLookup.TryReadIdentifiers(Argument, 'documentNo=no,systemId=guid,id=guid', RequestJson) then
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
        Context.ReadText(RequestJson, 'documentNo', 20, Argument, DocumentNo, Present, 'documentNo');
        Context.ReadText(RequestJson, 'assignedUserId', 50, Argument, AssignedUserId, Present, 'assignedUserId');
        Context.ReadText(RequestJson, 'status', 20, Argument, StatusText, Present, 'status');
        if Present then
            if (not IsShipment) or not (LowerCase(StatusText) in ['open', 'released']) then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'status', StatusText), 'status', StatusText, 'Open, Released (shipments)', ValueNextStepLbl);
        Context.ReadInteger(RequestJson, 'sourceType', Argument, SourceType, HasSourceType, 'sourceType');
        if HasSourceType and (SourceType < 0) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'sourceType', SourceType), 'sourceType', Format(SourceType, 0, 9), '0 or greater', ValueNextStepLbl);
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
        if not ResolveDocument(RequestJson, Argument, IsShipment, DocumentId) then
            exit;
        if IsShipment then
            WriteShipments(Argument, DocumentId, LocationText, SourceNo, SourceType, HasSourceType, AssignedUserId, StatusText, PostingFrom, PostingTo, IncludeLines, Skip, Take)
        else
            WriteReceipts(Argument, DocumentId, LocationText, SourceNo, SourceType, HasSourceType, AssignedUserId, PostingFrom, PostingTo, IncludeLines, Skip, Take);
    end;

    local procedure WriteReceipts(var Argument: Record "Message Argument ori"; DocumentId: Guid; LocationText: Text; SourceNo: Text; SourceType: Integer; HasSourceType: Boolean; AssignedUserId: Text; PostingFrom: Date; PostingTo: Date; IncludeLines: Boolean; Skip: Integer; Take: Integer)
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        ResultArray: JsonArray;
        DocumentJson: JsonObject;
        HeaderNos: List of [Text];
        NoOfRecords: Integer;
    begin
        ReceiptHeader.ReadIsolation := IsolationLevel::ReadCommitted;
        if not IsNullGuid(DocumentId) then
            ReceiptHeader.SetRange(SystemId, DocumentId);
        if AssignedUserId <> '' then
            ReceiptHeader.SetRange("Assigned User ID", CopyStr(AssignedUserId, 1, MaxStrLen(ReceiptHeader."Assigned User ID")));
        if LocationText <> '' then
            ReceiptHeader.SetRange("Location Code", CopyStr(UpperCase(LocationText), 1, MaxStrLen(ReceiptHeader."Location Code")));
        if (SourceNo <> '') or HasSourceType then begin
            ReceiptLine.ReadIsolation := IsolationLevel::ReadCommitted;
            if HasSourceType then
                ReceiptLine.SetRange("Source Type", SourceType);
            if SourceNo <> '' then
                ReceiptLine.SetRange("Source No.", CopyStr(UpperCase(SourceNo), 1, MaxStrLen(ReceiptLine."Source No.")));
            ReceiptLine.SetLoadFields("No.", "Source No.", "Source Type");
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
        NoOfRecords := ReceiptHeader.Count();
        if Skip < NoOfRecords then
            if ReceiptHeader.FindSet() then begin
                if Skip > 0 then
                    ReceiptHeader.Next(Skip);
                repeat
                    RecordReference.GetTable(ReceiptHeader);
                    Clear(DocumentJson);
                    DocumentJson.Add('no', ReceiptHeader."No.");
                    DocumentJson.Add('systemId', Format(ReceiptHeader.SystemId, 0, 4));
                    DocumentJson.Add('locationCode', ReceiptHeader."Location Code");
                    DocumentJson.Add('postingDate', Context.FormatDate(ReceiptHeader."Posting Date"));
                    DocumentJson.Add('vendorShipmentNo', ReceiptHeader."Vendor Shipment No.");
                    DocumentJson.Add('assignedUserId', ReceiptHeader."Assigned User ID");
                    DocumentJson.Add('documentStatus', Context.EnumValueName(RecordReference, ReceiptHeader.FieldNo("Document Status")));
                    DocumentJson.Add('sortingMethod', Context.EnumValueName(RecordReference, ReceiptHeader.FieldNo("Sorting Method")));
                    DocumentJson.Add('zoneCode', ReceiptHeader."Zone Code");
                    DocumentJson.Add('binCode', ReceiptHeader."Bin Code");
                    DocumentJson.Add('status', 'Open');

                    if IncludeLines then
                        DocumentJson.Add('lines', ReceiptLinesJson(ReceiptHeader."No."));
                    ResultArray.Add(DocumentJson);
                    if ResultArray.Count() >= Take then
                        break;
                until ReceiptHeader.Next() = 0;
            end;
        WritePage(Argument, 'Receipt', NoOfRecords, Skip, Take, ResultArray);
    end;

    local procedure WriteShipments(var Argument: Record "Message Argument ori"; DocumentId: Guid; LocationText: Text; SourceNo: Text; SourceType: Integer; HasSourceType: Boolean; AssignedUserId: Text; StatusText: Text; PostingFrom: Date; PostingTo: Date; IncludeLines: Boolean; Skip: Integer; Take: Integer)
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        ResultArray: JsonArray;
        DocumentJson: JsonObject;
        HeaderNos: List of [Text];
        NoOfRecords: Integer;
    begin
        ShipmentHeader.ReadIsolation := IsolationLevel::ReadCommitted;
        if not IsNullGuid(DocumentId) then
            ShipmentHeader.SetRange(SystemId, DocumentId);
        if AssignedUserId <> '' then
            ShipmentHeader.SetRange("Assigned User ID", CopyStr(AssignedUserId, 1, MaxStrLen(ShipmentHeader."Assigned User ID")));
        if StatusText <> '' then
            if LowerCase(StatusText) = 'released' then
                ShipmentHeader.SetRange(Status, ShipmentHeader.Status::Released)
            else
                ShipmentHeader.SetRange(Status, ShipmentHeader.Status::Open);
        if LocationText <> '' then
            ShipmentHeader.SetRange("Location Code", CopyStr(UpperCase(LocationText), 1, MaxStrLen(ShipmentHeader."Location Code")));
        if (SourceNo <> '') or HasSourceType then begin
            ShipmentLine.ReadIsolation := IsolationLevel::ReadCommitted;
            if HasSourceType then
                ShipmentLine.SetRange("Source Type", SourceType);
            if SourceNo <> '' then
                ShipmentLine.SetRange("Source No.", CopyStr(UpperCase(SourceNo), 1, MaxStrLen(ShipmentLine."Source No.")));
            ShipmentLine.SetLoadFields("No.", "Source No.", "Source Type");
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
        NoOfRecords := ShipmentHeader.Count();
        if Skip < NoOfRecords then
            if ShipmentHeader.FindSet() then begin
                if Skip > 0 then
                    ShipmentHeader.Next(Skip);
                repeat
                    RecordReference.GetTable(ShipmentHeader);
                    Clear(DocumentJson);
                    DocumentJson.Add('no', ShipmentHeader."No.");
                    DocumentJson.Add('systemId', Format(ShipmentHeader.SystemId, 0, 4));
                    DocumentJson.Add('locationCode', ShipmentHeader."Location Code");
                    DocumentJson.Add('postingDate', Context.FormatDate(ShipmentHeader."Posting Date"));
                    DocumentJson.Add('externalDocumentNo', ShipmentHeader."External Document No.");
                    DocumentJson.Add('shipmentDate', Context.FormatDate(ShipmentHeader."Shipment Date"));
                    DocumentJson.Add('shippingAgentCode', ShipmentHeader."Shipping Agent Code");
                    DocumentJson.Add('assignedUserId', ShipmentHeader."Assigned User ID");
                    DocumentJson.Add('documentStatus', Context.EnumValueName(RecordReference, ShipmentHeader.FieldNo("Document Status")));
                    DocumentJson.Add('sortingMethod', Context.EnumValueName(RecordReference, ShipmentHeader.FieldNo("Sorting Method")));
                    DocumentJson.Add('zoneCode', ShipmentHeader."Zone Code");
                    DocumentJson.Add('binCode', ShipmentHeader."Bin Code");
                    DocumentJson.Add('status', Context.EnumValueName(RecordReference, ShipmentHeader.FieldNo(Status)));
                    ShipmentHeader.CalcFields("Completely Picked");
                    DocumentJson.Add('completelyPicked', ShipmentHeader."Completely Picked");

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
        ReceiptLine: Record "Warehouse Receipt Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        LineJson: JsonObject;
    begin
        ReceiptLine.ReadIsolation := IsolationLevel::ReadCommitted;
        ReceiptLine.SetRange("No.", DocumentNo);
        if ReceiptLine.FindSet() then
            repeat
                RecordReference.GetTable(ReceiptLine);
                Clear(LineJson);
                LineJson.Add('sourceType', ReceiptLine."Source Type");
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
                LineJson.Add('qtyOutstanding', ReceiptLine."Qty. Outstanding");
                LineJson.Add('zoneCode', ReceiptLine."Zone Code");
                LineJson.Add('qtyToReceive', ReceiptLine."Qty. to Receive");
                LineJson.Add('qtyReceived', ReceiptLine."Qty. Received");
                LineJson.Add('qtyToCrossDock', ReceiptLine."Qty. to Cross-Dock");
                LineJson.Add('dueDate', Context.FormatDate(ReceiptLine."Due Date"));
                LineJson.Add('putAwayQty', 0);
                Lines.Add(LineJson);
            until ReceiptLine.Next() = 0;
    end;

    local procedure ShipmentLinesJson(DocumentNo: Code[20]) Lines: JsonArray
    var
        ShipmentLine: Record "Warehouse Shipment Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        LineJson: JsonObject;
    begin
        ShipmentLine.ReadIsolation := IsolationLevel::ReadCommitted;
        ShipmentLine.SetRange("No.", DocumentNo);
        if ShipmentLine.FindSet() then
            repeat
                RecordReference.GetTable(ShipmentLine);
                Clear(LineJson);
                LineJson.Add('sourceType', ShipmentLine."Source Type");
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
                ShipmentLine.CalcFields("Pick Qty.");
                LineJson.Add('qtyOutstanding', ShipmentLine."Qty. Outstanding");
                LineJson.Add('zoneCode', ShipmentLine."Zone Code");
                LineJson.Add('qtyToShip', ShipmentLine."Qty. to Ship");
                LineJson.Add('qtyShipped', ShipmentLine."Qty. Shipped");
                LineJson.Add('qtyPicked', ShipmentLine."Qty. Picked");
                LineJson.Add('pickQty', ShipmentLine."Pick Qty.");
                LineJson.Add('dueDate', Context.FormatDate(ShipmentLine."Due Date"));
                LineJson.Add('putAwayQty', 0);
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
        ResponseJson.Add('documents', ResultArray);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ResolveDocument(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; IsShipment: Boolean; var DocumentId: Guid): Boolean
    var
        TempLookupArgument: Record "Message Argument ori" temporary;
        Lookup: Codeunit "Whse Record Lookup ori";
        Values: Codeunit "Whse Msg Values ori";
        Response: JsonObject;
        TableNo: Integer;
        NotFoundNextStepLbl: Label 'Search with filters instead of a document identifier.', Comment = 'is-IS=Leitaðu með síum í stað auðkennis skjals.';
        GuidNextStepLbl: Label 'Send the SystemId as a GUID, or send the number in documentNo.', Comment = 'is-IS=Sendu SystemId sem GUID eða sendu númerið í documentNo.';
        NextStep: Text;
    begin
        if (Argument.Subject = '') and (Values.TextValue(RequestJson, 'documentNo') = '') and
           (Values.TextValue(RequestJson, 'systemId') = '') and (Values.TextValue(RequestJson, 'id') = '') then
            exit(true);
        TableNo := Database::"Warehouse Receipt Header";
        if IsShipment then
            TableNo := Database::"Warehouse Shipment Header";
        TempLookupArgument := Argument;
        TempLookupArgument.Insert();
        TempLookupArgument.SetRequestJson(RequestJson);
        if Lookup.FindRecord(TempLookupArgument, TableNo, 'no|guid', 'documentNo=no,systemId=guid,id=guid', DocumentId) then
            exit(true);
        Response := TempLookupArgument.GetResponseJson();
        case Values.TextValue(Response, 'code') of
            'RecordNotFound':
                NextStep := NotFoundNextStepLbl;
            'InvalidParameterFormat':
                NextStep := GuidNextStepLbl;
        end;
        if NextStep <> '' then
            if Response.Contains('nextStep') then
                Response.Replace('nextStep', NextStep)
            else
                Response.Add('nextStep', NextStep);
        Argument.SetResponseJson(Response);
        Argument."Content Type" := Argument.GetContentTypeJson();
        exit(false);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['documentType', 'documentNo', 'systemId', 'id', 'assignedUserId', 'status', 'sourceType', 'locationCode', 'sourceNo', 'postingDateFrom', 'postingDateTo', 'includeLines', 'skip', 'take']) then
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
