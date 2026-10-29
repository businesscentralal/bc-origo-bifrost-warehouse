namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Worksheet.GetDocuments (#55).
/// Runs report 7304 "Get Outbound Source Documents" into a pick worksheet or report 7303 "Get Inbound Source Documents"
/// into a put-away worksheet, the Get Warehouse Documents action of the worksheet pages, without the selection page.
/// </summary>
codeunit 10078460 "Whse Wksh GetDocs Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        PickRequest: Record "Whse. Pick Request";
        PutAwayRequest: Record "Whse. Put-away Request";
        GetOutbound: Report "Get Outbound Source Documents";
        GetInbound: Report "Get Inbound Source Documents";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Worksheet Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        TemplateName: Code[10];
        WorksheetName: Code[10];
        LocationCode: Code[10];
        MissingPayloadErr: Label 'The worksheet payload was empty.', Comment = 'is-IS=Gögn vinnublaðsins voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        TemplateName := CopyStr(Values.TextValue(Payload, 'worksheetTemplateName'), 1, MaxStrLen(TemplateName));
        WorksheetName := CopyStr(Values.TextValue(Payload, 'worksheetName'), 1, MaxStrLen(WorksheetName));
        LocationCode := CopyStr(Values.TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        Context.SetSnapshot(Helper.LastLineNo(TemplateName, WorksheetName, LocationCode));
        if Values.BooleanValue(Payload, 'isPick') then begin
            PickRequest.SetRange("Location Code", LocationCode);
            if Values.TextValue(Payload, 'documentType') <> '' then
                PickRequest.SetRange("Document Type", Enum::"Warehouse Pick Request Document Type".FromInteger(Values.IntegerValue(Payload, 'documentTypeOrdinal')));
            if Values.TextValue(Payload, 'documentNo') <> '' then
                PickRequest.SetFilter("Document No.", '%1', Values.TextValue(Payload, 'documentNo'));
            GetOutbound.SetPickWkshName(TemplateName, WorksheetName, LocationCode);
            GetOutbound.SetHideDialog(true);
            GetOutbound.UseRequestPage(false);
            GetOutbound.SetTableView(PickRequest);
            GetOutbound.Run();
        end else begin
            PutAwayRequest.SetRange("Location Code", LocationCode);
            if Values.TextValue(Payload, 'documentType') <> '' then
                PutAwayRequest.SetRange("Document Type", Enum::"Warehouse Put-away Request Document Type".FromInteger(Values.IntegerValue(Payload, 'documentTypeOrdinal')));
            if Values.TextValue(Payload, 'documentNo') <> '' then
                PutAwayRequest.SetFilter("Document No.", '%1', Values.TextValue(Payload, 'documentNo'));
            GetInbound.SetWhseWkshName(TemplateName, WorksheetName, LocationCode);
            GetInbound.SetHideDialog(true);
            GetInbound.UseRequestPage(false);
            GetInbound.SetTableView(PutAwayRequest);
            GetInbound.Run();
        end;
    end;

    /// <summary>Returns whether the caller can write worksheet lines and read the warehouse requests.</summary>
    /// <returns>True when the caller can fill a pick or put-away worksheet.</returns>
    procedure IsEnabled(): Boolean
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        PickRequest: Record "Whse. Pick Request";
        PutAwayRequest: Record "Whse. Put-away Request";
    begin
        exit(WorksheetLine.WritePermission() and PickRequest.ReadPermission() and PutAwayRequest.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse worksheet line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Whse. Worksheet Line");
    end;

    /// <summary>Returns a short description of Warehouse.Worksheet.GetDocuments.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Fills a pick or put-away worksheet from released warehouse documents.', Comment = 'is-IS=Fyllir tínslu- eða frágangsvinnublað úr útgefnum vöruhúsaskjölum.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'pick worksheet, put-away worksheet, get warehouse documents, plan picks, plan put-aways, worksheet lines', Comment = 'is-IS=tínsluvinnublað, frágangsvinnublað, sækja vöruhúsaskjöl, skipuleggja tínslu, skipuleggja frágang, vinnublaðslínur';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Writes pick worksheet lines from released shipments, internal picks, assembly or project demand, or put-away worksheet lines from posted receipts and internal put-aways, at a location that requires pick or put-away. It creates no pick or put-away; Warehouse.Worksheet.CreateActivities does.', Comment = 'is-IS=Skrifar línur á tínsluvinnublað úr útgefnum afhendingum, innri tínslum, samsetningar- eða verkþörf, eða línur á frágangsvinnublað úr bókuðum móttökum og innri frágangi, á staðsetningu sem krefst tínslu eða frágangs. Hún stofnar hvorki tínslu né frágang; Warehouse.Worksheet.CreateActivities gerir það.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. The location of the worksheet. Do not send a different location in subject and locationCode.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The location. Optional when locationCode is sent.'));
        Target.Add(ContractMgt.TargetEntry('data.worksheetTemplateName + data.worksheetName + data.locationCode', 'worksheet', 'The pick or put-away worksheet name at the location.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('worksheetType', 'string', true, 'pick or putAway.'));
        Parameters.Add(ContractMgt.Parameter('worksheetTemplateName', 'string', true, 'Worksheet template of the matching type.'));
        Parameters.Add(ContractMgt.Parameter('worksheetName', 'string', true, 'Worksheet name at the location.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location of the worksheet. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('documentType', 'string', false, 'Limits the documents. pick: Shipment, Internal Pick, Production, Assembly or Job. putAway: Receipt or Internal Put-away.'));
        Parameters.Add(ContractMgt.Parameter('documentNo', 'string', false, 'Limits the documents to one warehouse document number (a posted receipt number for put-away).'));
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
        Fields.Add(ContractMgt.ResponseField('worksheetType', 'string', 'pick or putAway.'));
        Fields.Add(ContractMgt.ResponseField('worksheetTemplateName', 'string', 'Worksheet template.'));
        Fields.Add(ContractMgt.ResponseField('worksheetName', 'string', 'Worksheet name.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location.'));
        Fields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of worksheet lines added. No open document answers zero.'));
        Fields.Add(WorksheetLinesField(ContractMgt, 'lines', 'Worksheet lines added by this call.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
        UnknownParameterNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not require pick and shipment (pick) or put-away and receipt (putAway).', 'Use the inventory activities instead.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The worksheet template or worksheet name was not found at the location.', 'Create the worksheet name first.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The location was not found.', 'Check the location code and send the request again.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'worksheetType, worksheetTemplateName, worksheetName or locationCode is missing.', 'Send worksheetType, worksheetTemplateName, worksheetName and locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for every parameter.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'worksheetType is not pick or putAway, the template is not of that type, or documentType is not a document type of that worksheet.', 'Send a matching worksheetType, template and documentType.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', UnknownParameterNextStepLbl);
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations.', 'Send one location: subject or locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write worksheet lines.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected a document, for example a blocked customer.', 'Read the returned text and correct the document. Nothing was written.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Writes pick or put-away worksheet lines for the open quantity of the released documents. A document already in a worksheet is not added again.', 'BIFROST Whse - Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Worksheet.CreateActivities', 'Use it to create the picks or put-aways from the worksheet.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Create', 'Use it to create the pick of one shipment without a worksheet.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Create', 'Use it to create the put-away of one posted receipt without a worksheet.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True when a workflow is declared.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Helper: Codeunit "Whse Worksheet Helper ori";
    begin
        Helper.WorksheetWorkflow(Workflow);
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
            'Get one released shipment into the pick worksheet',
            '{"worksheetType":"pick","worksheetTemplateName":"PICK","worksheetName":"DEFAULT","locationCode":"WHITE","documentType":"Shipment","documentNo":"SH000001"}',
            '{"status":"Success","worksheetType":"pick","worksheetTemplateName":"PICK","worksheetName":"DEFAULT","locationCode":"WHITE","lineCount":1,"lines":[{"lineNo":10000,"whseDocumentType":"Shipment","whseDocumentNo":"SH000001","whseDocumentLineNo":10000,"itemNo":"1896-S","quantity":5,"qtyOutstanding":5,"qtyToHandle":5}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Runs Get Warehouse Documents for a pick or put-away worksheet without the selection page, optionally for one document type or number, and answers the worksheet lines it added.', Comment = 'is-IS=Keyrir Sækja vöruhúsaskjöl fyrir tínslu- eða frágangsvinnublað án valsíðunnar, valfrjálst fyrir eina skjalategund eða eitt númer, og skilar vinnublaðslínunum sem hún bætti við.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'The call only fills the worksheet; it creates no pick or put-away. Send the lines to Warehouse.Worksheet.CreateActivities afterwards, after setting the quantity to handle you want. ';
        Notes := Notes + 'worksheetType decides the source: pick reads released warehouse shipments, internal picks, and assembly, production or project demand; putAway reads posted receipts and internal put-aways. documentType must be one of the types of that worksheet type, and documentNo then limits the run to one document (for put-away, a posted receipt number). ';
        Notes := Notes + 'The location must require both pick and shipment (pick) or both put-away and receive (putAway); otherwise the call is refused, and the inventory pick and put-away types are the way to work there. The worksheet template must be of the matching type and the worksheet name must already exist at the location. ';
        Notes := Notes + 'The answer lists only the worksheet lines this call added, so lines that were already in the worksheet are not repeated. When no released document is open the call succeeds with lineCount 0. ';
        Notes := Notes + 'If Business Central rejects one document, for example a blocked customer, the whole call is refused and no line is written.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the worksheet and the filters and gets the documents, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Worksheet Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        AllowedKeys: List of [Text];
        TemplateName: Code[10];
        WorksheetName: Code[10];
        LocationCode: Code[10];
        DocumentTypeText: Text;
        DocumentNoText: Text;
        DocumentTypeOrdinal: Integer;
        IsPick: Boolean;
        Present: Boolean;
        DeniedLbl: Label 'You do not have permission to fill a warehouse worksheet.', Comment = 'is-IS=Þú hefur ekki heimild til að fylla vinnublað vöruhúss.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
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
        AllowedKeys.Add('worksheetType');
        AllowedKeys.Add('worksheetTemplateName');
        AllowedKeys.Add('worksheetName');
        AllowedKeys.Add('locationCode');
        AllowedKeys.Add('documentType');
        AllowedKeys.Add('documentNo');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Helper.ReadWorksheetKeys(RequestJson, Argument, IsPick, TemplateName, WorksheetName, LocationCode);
        Context.ReadText(RequestJson, 'documentType', 30, Argument, DocumentTypeText, Present, 'documentType');
        Context.ReadText(RequestJson, 'documentNo', 20, Argument, DocumentNoText, Present, 'documentNo');
        if not Argument.HasCollectedErrors() then
            if DocumentTypeText <> '' then
                ParseDocumentType(Argument, IsPick, DocumentTypeText, DocumentTypeOrdinal);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not Helper.ResolveWorksheet(Argument, IsPick, TemplateName, WorksheetName, LocationCode) then
            exit;
        Payload.Add('isPick', IsPick);
        Payload.Add('worksheetTemplateName', TemplateName);
        Payload.Add('worksheetName', WorksheetName);
        Payload.Add('locationCode', LocationCode);
        Payload.Add('documentType', DocumentTypeText);
        Payload.Add('documentTypeOrdinal', DocumentTypeOrdinal);
        Payload.Add('documentNo', DocumentNoText);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Wksh GetDocs Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Wksh GetDocs Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        WriteResponse(Argument, IsPick, TemplateName, WorksheetName, LocationCode);
        Context.Reset();
    end;

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; IsPick: Boolean; TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10])
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Worksheet Helper ori";
        ResponseJson: JsonObject;
        Lines: JsonArray;
        SnapshotLineNo: Integer;
    begin
        Context.TryGetSnapshot(SnapshotLineNo);
        Helper.FilterWorksheet(WorksheetLine, TemplateName, WorksheetName, LocationCode);
        WorksheetLine.SetFilter("Line No.", '>%1', SnapshotLineNo);
        if WorksheetLine.FindSet() then
            repeat
                Lines.Add(Helper.LineJson(WorksheetLine));
            until WorksheetLine.Next() = 0;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('worksheetType', Helper.WorksheetTypeName(IsPick));
        ResponseJson.Add('worksheetTemplateName', TemplateName);
        ResponseJson.Add('worksheetName', WorksheetName);
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('lineCount', Lines.Count());
        ResponseJson.Add('lines', Lines);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ParseDocumentType(var Argument: Record "Message Argument ori"; IsPick: Boolean; DocumentTypeText: Text; var DocumentTypeOrdinal: Integer)
    var
        Names: List of [Text];
        Ordinals: List of [Integer];
        Index: Integer;
        InvalidLbl: Label 'documentType %1 is not a document type of this worksheet. Use one of: %2.', Comment = '%1 = value, %2 = allowed values, is-IS=documentType %1 er ekki skjalategund þessa vinnublaðs. Notaðu eitt af: %2.';
        InvalidNextStepLbl: Label 'Send a documentType of the worksheet type, or omit it.', Comment = 'is-IS=Sendu documentType sem passar við tegund vinnublaðsins, eða slepptu því.';
    begin
        if IsPick then begin
            Names := Enum::"Warehouse Pick Request Document Type".Names();
            Ordinals := Enum::"Warehouse Pick Request Document Type".Ordinals();
        end else begin
            Names := Enum::"Warehouse Put-away Request Document Type".Names();
            Ordinals := Enum::"Warehouse Put-away Request Document Type".Ordinals();
        end;
        for Index := 1 to Names.Count() do
            if LowerCase(Names.Get(Index)) = LowerCase(DocumentTypeText) then begin
                DocumentTypeOrdinal := Ordinals.Get(Index);
                exit;
            end;
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(InvalidLbl, DocumentTypeText, JoinNames(Names)), 'documentType', DocumentTypeText, JoinNames(Names), InvalidNextStepLbl);
    end;

    local procedure JoinNames(Names: List of [Text]): Text
    var
        Builder: TextBuilder;
        Name: Text;
    begin
        foreach Name in Names do begin
            if Builder.Length() > 0 then
                Builder.Append(', ');
            Builder.Append(Name);
        end;
        exit(Builder.ToText());
    end;

    local procedure WorksheetLinesField(ContractMgt: Codeunit "Msg Contract Mgt ori"; Name: Text; Description: Text): JsonObject
    var
        LineFields: JsonArray;
        Lines: JsonObject;
    begin
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Worksheet line number.'));
        LineFields.Add(ContractMgt.ResponseField('whseDocumentType', 'string', 'Warehouse document type of the line.'));
        LineFields.Add(ContractMgt.ResponseField('whseDocumentNo', 'string', 'Warehouse document number.'));
        LineFields.Add(ContractMgt.ResponseField('whseDocumentLineNo', 'integer', 'Line number on the warehouse document.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('variantCode', 'string', 'Variant code.'));
        LineFields.Add(ContractMgt.ResponseField('unitOfMeasureCode', 'string', 'Unit of measure.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity of the line.'));
        LineFields.Add(ContractMgt.ResponseField('qtyOutstanding', 'number', 'Quantity still to handle.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle when the activity is created.'));
        LineFields.Add(ContractMgt.ResponseField('fromBin', 'string', 'From bin code.'));
        LineFields.Add(ContractMgt.ResponseField('toBin', 'string', 'To bin code.'));
        Lines.Add('name', Name);
        Lines.Add('type', 'array');
        Lines.Add('description', Description);
        Lines.Add('children', LineFields);
        exit(Lines);
    end;
}
