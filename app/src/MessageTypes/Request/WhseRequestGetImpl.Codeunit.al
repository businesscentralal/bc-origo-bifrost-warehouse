namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Request;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Request.Get: a paged read of the warehouse requests at one location that are not
/// completely handled, the list the Get Source Documents action works from.
/// </summary>
codeunit 10078435 "Whse Request Get Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can read warehouse requests.</summary>
    /// <returns>True when the caller has read permission on Warehouse Request.</returns>
    procedure IsEnabled(): Boolean
    var
        WarehouseRequest: Record "Warehouse Request";
    begin
        exit(WarehouseRequest.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The Warehouse Request table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Request");
    end;

    /// <summary>Returns a short description of Warehouse.Request.Get.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Reads the warehouse requests at a location: source documents waiting for a warehouse receipt or shipment.', Comment = 'is-IS=Les vöruhúsabeiðnir á staðsetningu: upprunaskjöl sem bíða eftir vöruhúsamóttöku eða vöruhúsaafhendingu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'warehouse request, what is waiting, released orders, source documents to receive, source documents to ship, open warehouse work', Comment = 'is-IS=vöruhúsabeiðni, hvað bíður, útgefnar pantanir, upprunaskjöl til móttöku, upprunaskjöl til afhendingar, opin vöruhúsavinna';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Lists the warehouse requests at one location, paged. Use Warehouse.Receipt.GetSourceDocuments or Warehouse.Shipment.GetSourceDocuments to act on them.', Comment = 'is-IS=Lesaðgangur. Listar vöruhúsabeiðnir á einni staðsetningu, blaðsíðuskipt. Notaðu Warehouse.Receipt.GetSourceDocuments eða Warehouse.Shipment.GetSourceDocuments til að vinna úr þeim.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A location code selects the same location as locationCode. Do not send a different location in both places.', false);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The location whose warehouse requests are read.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode', 'location code', 'The location whose warehouse requests are read.'));
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
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', true, 'Location code. Required unless the subject carries it.'));
        Parameters.Add(ContractMgt.Parameter('type', 'string', false, 'Inbound or Outbound.'));
        Parameters.Add(ContractMgt.Parameter('sourceDocument', 'string', false, 'One of: Sales Order, Sales Return Order, Purchase Order, Purchase Return Order, Inbound Transfer, Outbound Transfer, Job Usage. Spaces and case are ignored.'));
        Parameters.Add(ContractMgt.Parameter('sourceNo', 'string', false, 'Source document number.'));
        Parameters.Add(ContractMgt.Parameter('status', 'string', false, 'Open or Released. Defaults to both.'));
        Parameters.Add(ContractMgt.Parameter('expectedReceiptDateFrom', 'date', false, 'First expected receipt date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('expectedReceiptDateTo', 'date', false, 'Last expected receipt date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('shipmentDateFrom', 'date', false, 'First shipment date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('shipmentDateTo', 'date', false, 'Last shipment date, YYYY-MM-DD.'));
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
        Result: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('noOfRecords', 'integer', 'Number of matching warehouse requests before paging.'));
        Fields.Add(ContractMgt.ResponseField('skip', 'integer', 'Records skipped.'));
        Fields.Add(ContractMgt.ResponseField('take', 'integer', 'Page size.'));
        ResultFields.Add(ContractMgt.ResponseField('type', 'string', 'Inbound or Outbound.'));
        ResultFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        ResultFields.Add(ContractMgt.ResponseField('sourceDocument', 'string', 'Kind of source document, for example Purchase Order.'));
        ResultFields.Add(ContractMgt.ResponseField('sourceNo', 'string', 'Source document number.'));
        ResultFields.Add(ContractMgt.ResponseField('documentStatus', 'string', 'Open or Released.'));
        ResultFields.Add(ContractMgt.ResponseField('destinationType', 'string', 'Destination type, for example Customer or Vendor; blank when none.'));
        ResultFields.Add(ContractMgt.ResponseField('destinationNo', 'string', 'Destination number.'));
        ResultFields.Add(ContractMgt.ResponseField('expectedReceiptDate', 'string', 'Expected receipt date as YYYY-MM-DD, or blank.'));
        ResultFields.Add(ContractMgt.ResponseField('shipmentDate', 'string', 'Shipment date as YYYY-MM-DD, or blank.'));
        ResultFields.Add(ContractMgt.ResponseField('shippingAgentCode', 'string', 'Shipping agent code.'));
        ResultFields.Add(ContractMgt.ResponseField('shipmentMethodCode', 'string', 'Shipment method code.'));
        ResultFields.Add(ContractMgt.ResponseField('externalDocumentNo', 'string', 'External document number.'));
        Result.Add('name', 'result');
        Result.Add('type', 'array');
        Result.Add('description', 'The paged warehouse requests.');
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
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'locationCode and the subject are both empty.', 'Send locationCode or the location code as the subject.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The location does not exist.', 'Check the location code and try again.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations.', 'Send one location: subject or locationCode.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'type, sourceDocument or status is not one of the listed values, or a date range ends before it starts.', 'Use one of the values listed in the help.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or a date is not YYYY-MM-DD.', 'Send text for codes and values, and dates as YYYY-MM-DD.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot read warehouse requests.', 'Ask an administrator to assign BIFROST Whse - Read ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again.');
        Parts.AddDateErrors(Errors, 'expectedReceiptDateFrom, expectedReceiptDateTo, shipmentDateFrom, shipmentDateTo', Context.TextDateNextStep());
        Parts.AddDateRangeError(Errors, 'expectedReceiptDateFrom and expectedReceiptDateTo, or shipmentDateFrom and shipmentDateTo');
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
        Parts.ReadEffect(Effect, 'Reads warehouse requests. Nothing is written.', 'BIFROST Whse - Read ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.GetSourceDocuments', 'Use it to add released inbound requests to a warehouse receipt.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.GetSourceDocuments', 'Use it to add released outbound requests to a warehouse shipment.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.PostedDocument.Get', 'Use it to read what has already been received or shipped.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True. The read is the first step towards a warehouse receipt or shipment.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Request.Get', 'Find the released source documents that wait for a warehouse receipt or shipment.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Receipt.Create', 'For an inbound request, create the Warehouse Receipt from the source document.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Shipment.Create', 'For an outbound sales order or transfer request, create the Warehouse Shipment from the source document.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Receipt.GetSourceDocuments', 'Alternatively add an inbound request to a receipt that already exists.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Shipment.GetSourceDocuments', 'Alternatively add an outbound request to a shipment that already exists.'));
        Workflow.Add('steps', Steps);
        Workflow.Add('text', 'Follow the inbound or the outbound steps according to the type of the request. The sourceDocument of a request names the kind of source document that the next step needs in its own spelling.');
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
            'Released inbound requests at WHITE',
            '{"locationCode":"WHITE","type":"Inbound","status":"Released","take":10}',
            '{"status":"Success","noOfRecords":1,"skip":0,"take":10,"result":[{"type":"Inbound","locationCode":"WHITE","sourceDocument":"Purchase Order","sourceNo":"106001","documentStatus":"Released","destinationType":"Vendor","destinationNo":"10000","expectedReceiptDate":"2026-10-20","shipmentDate":"","shippingAgentCode":"","shipmentMethodCode":"","externalDocumentNo":""}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Reads the warehouse requests at one location that are not completely handled: the source documents waiting for a warehouse receipt or shipment. Filter by type, source document, source number, status and date ranges, and page with take and skip. Filters that match nothing answer success with an empty list. Nothing is written.', Comment = 'is-IS=Les vöruhúsabeiðnir á einni staðsetningu sem eru ekki fullafgreiddar: upprunaskjöl sem bíða eftir vöruhúsamóttöku eða vöruhúsaafhendingu. Síaðu eftir tegund, upprunaskjali, númeri upprunaskjals, stöðu og dagsetningabilum og flettu með take og skip. Síur sem passa ekki við neitt skila árangri með tómum lista. Ekkert er skrifað.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes list edge cases of the filters.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'One location is read per call, and it must exist. Only requests that are not completely handled are returned, so a source document disappears from the list once everything on it has been received or shipped; use Warehouse.PostedDocument.Get for what is done. ' +
            'Without status both Open and Released requests are returned; add status Released to see only what can be taken into a receipt or shipment. ' +
            'type, sourceDocument and status are matched by name, ignoring case, spaces, hyphens and dots, so Purchase Order, purchaseorder and Purchase-Order are the same. sourceNo is an exact match and is read in upper case. ' +
            'sourceDocument is one of Sales Order, Sales Return Order, Purchase Order, Purchase Return Order, Inbound Transfer, Outbound Transfer or Job Usage. A value outside the list is refused, not ignored. ' +
            'Dates are inclusive. A from date without a to date has no upper end. A request with no date in the field filtered is left out when a from date is sent, and kept when only a to date is sent. expectedReceiptDate is usually blank on outbound requests and shipmentDate on inbound ones. ' +
            'The rows are read in the order type, status, expected receipt date, shipment date, source document and source number. skip and take page them, and noOfRecords is the total before paging. ' +
            'Filters that match nothing are Success with an empty result. All invalid values, including a bad skip or take, are answered together. ' +
            'The spelling of the source document differs in the next step: Warehouse.Receipt.Create takes sourceType PurchaseOrder, SalesReturnOrder or TransferOrder, and Warehouse.Shipment.Create takes SalesOrder or TransferOrder. A Purchase Return Order request is added to a shipment with Warehouse.Shipment.GetSourceDocuments.';
        exit(true);
    end;

    /// <summary>Returns the outbound direction of this message type.</summary>
    /// <returns>Outbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Outbound);
    end;

    /// <summary>Validates the filters and writes one page of warehouse requests.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WarehouseRequest: Record "Warehouse Request";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        LocationCode: Code[10];
        TypeText: Text;
        SourceDocumentText: Text;
        SourceNo: Text;
        StatusText: Text;
        ReceiptFrom: Date;
        ReceiptTo: Date;
        ShipmentFrom: Date;
        ShipmentTo: Date;
        Present: Boolean;
        Skip: Integer;
        Take: Integer;
        DeniedLbl: Label 'You do not have permission to read warehouse requests.', Comment = 'is-IS=Þú hefur ekki heimild til að lesa vöruhúsabeiðnir.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Read ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Read ori.';
        ProblemsLbl: Label 'The request has invalid values.', Comment = 'is-IS=Beiðnin hefur ógild gildi.';
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
        ResolveLocationCode(RequestJson, Argument, LocationCode);
        Context.ReadText(RequestJson, 'type', 20, Argument, TypeText, Present, 'type');
        Context.ReadText(RequestJson, 'sourceDocument', 50, Argument, SourceDocumentText, Present, 'sourceDocument');
        Context.ReadText(RequestJson, 'sourceNo', MaxStrLen(WarehouseRequest."Source No."), Argument, SourceNo, Present, 'sourceNo');
        Context.ReadText(RequestJson, 'status', 20, Argument, StatusText, Present, 'status');
        Context.ReadDate(RequestJson, 'expectedReceiptDateFrom', Argument, ReceiptFrom, Present, 'expectedReceiptDateFrom');
        Context.ReadDate(RequestJson, 'expectedReceiptDateTo', Argument, ReceiptTo, Present, 'expectedReceiptDateTo');
        Context.ReadDate(RequestJson, 'shipmentDateFrom', Argument, ShipmentFrom, Present, 'shipmentDateFrom');
        Context.ReadDate(RequestJson, 'shipmentDateTo', Argument, ShipmentTo, Present, 'shipmentDateTo');
        // Independent problems are collected and answered together: a bad date does not hide a bad value, an unknown
        // location or a bad skip or take.
        ApplyFilters(Argument, WarehouseRequest, LocationCode, TypeText, SourceDocumentText, SourceNo, StatusText, ReceiptFrom, ReceiptTo, ShipmentFrom, ShipmentTo);
        if LocationCode <> '' then
            CheckLocationExists(LocationCode, Argument);
        if not Context.RespondOrReadPaging(RequestJson, Argument, ProblemsLbl, Skip, Take) then
            exit;
        WritePage(Argument, WarehouseRequest, Skip, Take);
    end;

    local procedure ApplyFilters(var Argument: Record "Message Argument ori"; var WarehouseRequest: Record "Warehouse Request"; LocationCode: Code[10]; TypeText: Text; SourceDocumentText: Text; SourceNo: Text; StatusText: Text; ReceiptFrom: Date; ReceiptTo: Date; ShipmentFrom: Date; ShipmentTo: Date)
    var
        Context: Codeunit "Whse Write Context ori";
        Ordinal: Integer;
        ValueLbl: Label 'Parameter %1 has the value %2, which is not one of the values listed in the help.', Comment = '%1 = parameter, %2 = value, is-IS=Færibreytan %1 hefur gildið %2 sem er ekki eitt af gildunum sem talin eru upp í hjálpinni.';
        ValueNextStepLbl: Label 'Use one of the values listed in the help.', Comment = 'is-IS=Notaðu eitt af gildunum sem talin eru upp í hjálpinni.';
        RangeLbl: Label 'The date range %1 ends before it starts.', Comment = '%1 = parameter, is-IS=Dagsetningabilið %1 endar áður en það byrjar.';
    begin
        WarehouseRequest.SetCurrentKey(Type, "Location Code", "Completely Handled", "Document Status", "Expected Receipt Date", "Shipment Date", "Source Document", "Source No.");
        WarehouseRequest.SetRange("Location Code", LocationCode);
        WarehouseRequest.SetRange("Completely Handled", false);
        if TypeText <> '' then
            if FindOrdinal(Enum::"Warehouse Request Type".Names(), Enum::"Warehouse Request Type".Ordinals(), TypeText, Ordinal) then
                WarehouseRequest.SetRange(Type, Enum::"Warehouse Request Type".FromInteger(Ordinal))
            else
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'type', TypeText), 'type', TypeText, 'Inbound, Outbound', ValueNextStepLbl);
        if SourceDocumentText <> '' then
            if FindOrdinal(Enum::"Warehouse Request Source Document".Names(), Enum::"Warehouse Request Source Document".Ordinals(), SourceDocumentText, Ordinal) then
                WarehouseRequest.SetRange("Source Document", Enum::"Warehouse Request Source Document".FromInteger(Ordinal))
            else
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'sourceDocument', SourceDocumentText), 'sourceDocument', SourceDocumentText, 'Sales Order, Sales Return Order, Purchase Order, Purchase Return Order, Inbound Transfer, Outbound Transfer, Job Usage', ValueNextStepLbl);
        if SourceNo <> '' then
            WarehouseRequest.SetRange("Source No.", CopyStr(UpperCase(SourceNo), 1, MaxStrLen(WarehouseRequest."Source No.")));
        if StatusText <> '' then
            case true of
                Context.SameName(StatusText, 'Open'):
                    WarehouseRequest.SetRange("Document Status", WarehouseRequest."Document Status"::Open);
                Context.SameName(StatusText, 'Released'):
                    WarehouseRequest.SetRange("Document Status", WarehouseRequest."Document Status"::Released);
                else
                    Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'status', StatusText), 'status', StatusText, 'Open, Released', ValueNextStepLbl);
            end;
        if (ReceiptFrom <> 0D) and (ReceiptTo <> 0D) and (ReceiptTo < ReceiptFrom) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, 'expectedReceiptDateFrom'), 'expectedReceiptDateTo', Context.FormatDate(ReceiptTo), '', Context.DateRangeNextStep());
        if (ShipmentFrom <> 0D) and (ShipmentTo <> 0D) and (ShipmentTo < ShipmentFrom) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, 'shipmentDateFrom'), 'shipmentDateTo', Context.FormatDate(ShipmentTo), '', Context.DateRangeNextStep());
        if (ReceiptFrom <> 0D) or (ReceiptTo <> 0D) then
            WarehouseRequest.SetRange("Expected Receipt Date", ReceiptFrom, Context.RangeEnd(ReceiptTo));
        if (ShipmentFrom <> 0D) or (ShipmentTo <> 0D) then
            WarehouseRequest.SetRange("Shipment Date", ShipmentFrom, Context.RangeEnd(ShipmentTo));
    end;

    local procedure FindOrdinal(Names: List of [Text]; Ordinals: List of [Integer]; Received: Text; var Ordinal: Integer): Boolean
    var
        Context: Codeunit "Whse Write Context ori";
        Index: Integer;
    begin
        for Index := 1 to Names.Count() do
            if Context.SameName(Received, Names.Get(Index)) then begin
                Ordinal := Ordinals.Get(Index);
                exit(true);
            end;
        exit(false);
    end;

    local procedure WritePage(var Argument: Record "Message Argument ori"; var WarehouseRequest: Record "Warehouse Request"; Skip: Integer; Take: Integer)
    var
        ResponseJson: JsonObject;
        ResultArray: JsonArray;
        NoOfRecords: Integer;
    begin
        WarehouseRequest.ReadIsolation := IsolationLevel::ReadCommitted;
        WarehouseRequest.SetLoadFields(Type, "Location Code", "Source Document", "Source No.", "Document Status", "Destination Type", "Destination No.", "Expected Receipt Date", "Shipment Date", "Shipping Agent Code", "Shipment Method Code", "External Document No.");
        NoOfRecords := WarehouseRequest.Count();
        if Skip < NoOfRecords then
            if WarehouseRequest.FindSet() then begin
                if Skip > 0 then
                    WarehouseRequest.Next(Skip);
                repeat
                    ResultArray.Add(RequestJsonOf(WarehouseRequest));
                    if ResultArray.Count() >= Take then
                        break;
                until WarehouseRequest.Next() = 0;
            end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('noOfRecords', NoOfRecords);
        ResponseJson.Add('skip', Skip);
        ResponseJson.Add('take', Take);
        ResponseJson.Add('result', ResultArray);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure RequestJsonOf(WarehouseRequest: Record "Warehouse Request") Result: JsonObject
    var
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
    begin
        RecordReference.GetTable(WarehouseRequest);
        Result.Add('type', Context.EnumValueName(RecordReference, WarehouseRequest.FieldNo(Type)));
        Result.Add('locationCode', WarehouseRequest."Location Code");
        Result.Add('sourceDocument', Context.EnumValueName(RecordReference, WarehouseRequest.FieldNo("Source Document")));
        Result.Add('sourceNo', WarehouseRequest."Source No.");
        Result.Add('documentStatus', Context.EnumValueName(RecordReference, WarehouseRequest.FieldNo("Document Status")));
        Result.Add('destinationType', Context.EnumValueName(RecordReference, WarehouseRequest.FieldNo("Destination Type")));
        Result.Add('destinationNo', WarehouseRequest."Destination No.");
        Result.Add('expectedReceiptDate', Context.FormatDate(WarehouseRequest."Expected Receipt Date"));
        Result.Add('shipmentDate', Context.FormatDate(WarehouseRequest."Shipment Date"));
        Result.Add('shippingAgentCode', WarehouseRequest."Shipping Agent Code");
        Result.Add('shipmentMethodCode', WarehouseRequest."Shipment Method Code");
        Result.Add('externalDocumentNo', WarehouseRequest."External Document No.");
    end;

    local procedure CheckLocationExists(LocationCode: Code[10]; var Argument: Record "Message Argument ori")
    var
        Location: Record Location;
        NotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the location code and try again.', Comment = 'is-IS=Athugaðu kóða staðsetningar og reyndu aftur.';
    begin
        Location.SetLoadFields(Code);
        if not Location.Get(LocationCode) then
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LocationCode), 'locationCode', LocationCode, '', NotFoundNextStepLbl);
    end;

    local procedure ResolveLocationCode(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10])
    var
        Context: Codeunit "Whse Write Context ori";
        LocationText: Text;
        SubjectText: Text;
        Present: Boolean;
        MissingLbl: Label 'locationCode is required.', Comment = 'is-IS=locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode or the location code as the subject.', Comment = 'is-IS=Sendu locationCode eða kóða staðsetningar sem subject.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
    begin
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Context.ReadText(RequestJson, 'locationCode', MaxStrLen(LocationCode), Argument, LocationText, Present, 'locationCode') then
            exit;
        if Present and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(LocationText)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationText, SubjectText, ConflictNextStepLbl);
            exit;
        end;
        if not Present then
            LocationText := SubjectText;
        if LocationText = '' then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'locationCode', '', '', MissingNextStepLbl);
            exit;
        end;
        LocationCode := CopyStr(UpperCase(LocationText), 1, MaxStrLen(LocationCode));
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['locationCode', 'type', 'sourceDocument', 'sourceNo', 'status', 'expectedReceiptDateFrom', 'expectedReceiptDateTo', 'shipmentDateFrom', 'shipmentDateTo', 'skip', 'take']) then
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
