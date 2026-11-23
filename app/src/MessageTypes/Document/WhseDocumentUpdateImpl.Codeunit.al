namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Document;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Document.Update (#105).
/// Changes header data and line bins on an open warehouse receipt or shipment. Every value goes through Validate, so
/// Business Central's own checks apply, and the whole request runs in one Codeunit.Run transaction: one refused value
/// leaves the document unchanged. A released shipment is refused before anything is written.
/// </summary>
codeunit 10078441 "Whse Document Update Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The document update payload was empty.', Comment = 'is-IS=Gögnin til að uppfæra skjal voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        Result := ApplyUpdate(Payload, true);
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can change warehouse receipts and shipments.</summary>
    /// <returns>True when the caller can write receipt and shipment headers and lines.</returns>
    procedure IsEnabled(): Boolean
    begin
        exit(HasWritePermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse receipt header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Receipt Header");
    end;

    /// <summary>Returns a short description of Warehouse.Document.Update.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Changes header data and line bins on an open warehouse receipt or shipment.', Comment = 'is-IS=Breytir hausgögnum og hólfum lína á opinni vöruhúsamóttöku eða -afhendingu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'update receipt, update shipment, change posting date, vendor shipment no, shipping agent, external document no, receipt bin, shipment bin, assign receipt, sort shipment', Comment = 'is-IS=uppfæra móttöku, uppfæra afhendingu, breyta bókunardagsetningu, afhendingarnúmer lánardrottins, flutningsaðili, ytra skjalanúmer, hólf móttöku, hólf afhendingar, úthluta móttöku, raða afhendingu';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Changes data. Updates header fields and line bins on an open warehouse receipt or shipment. A released shipment must be reopened first.', Comment = 'is-IS=Breytir gögnum. Uppfærir hausreiti og hólf lína á opinni vöruhúsamóttöku eða -afhendingu. Opna þarf útgefna afhendingu aftur fyrst.';
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
        Forms.Add('guid');
        Forms.Add('document no.');
        Envelope := Parts.RecordEnvelope(Forms, 'The warehouse receipt or shipment to change: its SystemId or No. documentType names which.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the warehouse receipt or shipment.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the warehouse receipt or shipment.'));
        Target.Add(ContractMgt.TargetEntry('data.documentNo, data.systemId, data.id', 'guid or document no.', 'The identifier keys accepted for the document. Every supplied identifier is tried; conflicting identifiers are refused.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        HeaderParameter: JsonObject;
        LinesParameter: JsonObject;
        HeaderChildren: JsonArray;
        LineChildren: JsonArray;
    begin
        Parameters.Add(ContractMgt.Parameter('documentType', 'string', true, 'receipt or shipment.'));
        Parameters.Add(ContractMgt.Parameter('documentNo', 'string', false, 'The No. of the document. Or send systemId, id or the subject.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'The SystemId of the document.'));
        Parameters.Add(ContractMgt.Parameter('id', 'string', false, 'Alias of systemId.'));
        HeaderChildren.Add(ContractMgt.Parameter('postingDate', 'date', false, 'Posting date (receipt and shipment).'));
        HeaderChildren.Add(ContractMgt.Parameter('vendorShipmentNo', 'string', false, 'Vendor shipment no. (receipt only).'));
        HeaderChildren.Add(ContractMgt.Parameter('shipmentDate', 'date', false, 'Shipment date (shipment only).'));
        HeaderChildren.Add(ContractMgt.Parameter('shippingAgentCode', 'string', false, 'Shipping agent (shipment only).'));
        HeaderChildren.Add(ContractMgt.Parameter('shippingAgentServiceCode', 'string', false, 'Shipping agent service (shipment only).'));
        HeaderChildren.Add(ContractMgt.Parameter('shipmentMethodCode', 'string', false, 'Shipment method (shipment only).'));
        HeaderChildren.Add(ContractMgt.Parameter('externalDocumentNo', 'string', false, 'External document no. (shipment only).'));
        HeaderChildren.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'Warehouse employee assigned to the document; an empty string unassigns.'));
        HeaderChildren.Add(ContractMgt.Parameter('sortingMethod', 'string', false, 'Sorting method of the document lines, by name.'));
        HeaderChildren.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Default zone of the document.'));
        HeaderChildren.Add(ContractMgt.Parameter('binCode', 'string', false, 'Default bin of the document; Business Central copies it to the lines.'));
        HeaderParameter := ContractMgt.Parameter('header', 'object', false, 'The header fields to change. Send header, lines or both.');
        HeaderParameter.Add('children', HeaderChildren);
        Parameters.Add(HeaderParameter);
        LineChildren.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'The Line No. of the document line.'));
        LineChildren.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Zone of the line.'));
        LineChildren.Add(ContractMgt.Parameter('binCode', 'string', false, 'Bin of the line.'));
        LinesParameter := ContractMgt.Parameter('lines', 'array', false, 'The lines whose zone or bin to change.');
        LinesParameter.Add('children', LineChildren);
        Parameters.Add(LinesParameter);
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
        Fields.Add(ContractMgt.ResponseField('documentType', 'string', 'receipt or shipment.'));
        Fields.Add(ContractMgt.ResponseField('documentNo', 'string', 'Document number.'));
        Fields.Add(ContractMgt.ResponseField('documentSystemId', 'string', 'Document SystemId.'));
        Fields.Add(ContractMgt.ResponseField('header', 'object', 'The stored header values after validation, with assignmentDate.'));
        Fields.Add(ContractMgt.ResponseField('lines', 'array', 'The changed lines with lineNo, zoneCode and binCode as stored.'));
        Fields.Add(ContractMgt.ResponseField('updatedCount', 'integer', 'Number of documents changed: 1.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'documentType, the document identifier, header or lines, or a lineNo is missing.', MissingNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'documentType is not receipt or shipment, or sortingMethod is not a sorting method of the document.', DocumentTypeNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, a date is not a date, a text is too long or systemId is not a GUID.', FormatNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request, header or a line contains a key this type does not accept for the document type.', UnknownNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The document or a named line was not found.', NotFoundNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'The identifiers name different documents.', ConflictNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The shipment is released, or Business Central refused a value (for example a bin that does not exist or is blocked, or a user who is not a warehouse employee at the location). Nothing is changed.', ReopenNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot change warehouse receipts and shipments, or a sent field is closed to writes in this company.', DeniedNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one problem was found before anything was written.', 'Correct every listed problem and send the request again.');
        Parts.AddBusinessCentralError(Errors, 'a subscriber that refuses the change');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Changes the named header fields and line bins of one open warehouse receipt or shipment. Another update changes them back.', 'BIFROST Whse - Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Document.Get', 'Use it to read the document and its lines before you change them.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Reopen', 'Use it to reopen a released shipment before you change it.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Assign', 'Use it to assign or sort picks and put-aways.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Bin.Get', 'Use it to find a bin for a line.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True when a workflow is declared.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.InboundWorkflow(Workflow);
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
            'Set the posting date, vendor shipment no. and a line bin on receipt RE000001',
            '{"documentType":"receipt","documentNo":"RE000001","header":{"postingDate":"2026-11-24","vendorShipmentNo":"VS-1001"},"lines":[{"lineNo":10000,"binCode":"RECEIVE"}]}',
            '{"status":"Success","documentType":"receipt","documentNo":"RE000001","documentSystemId":"6f1c1d2e-0000-0000-0000-000000000001","header":{"postingDate":"2026-11-24","vendorShipmentNo":"VS-1001"},"lines":[{"lineNo":10000,"zoneCode":"RECEIVE","binCode":"RECEIVE"}],"updatedCount":1}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Changes header data such as posting date, vendor shipment no., shipment date, shipping agent, external document no., assigned user, sorting method and default bin, and the zone and bin of named lines, on one open warehouse receipt or shipment. All or nothing: one refused value leaves the document unchanged.', Comment = 'is-IS=Breytir hausgögnum eins og bókunardagsetningu, afhendingarnúmeri lánardrottins, afhendingardagsetningu, flutningsaðila, ytra skjalanúmeri, úthlutuðum notanda, röðunaraðferð og sjálfgefnu hólfi, og svæði og hólfi tiltekinna lína, á einni opinni vöruhúsamóttöku eða -afhendingu. Allt eða ekkert: eitt hafnað gildi skilur skjalið eftir óbreytt.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes describe the fields per document type and the refusals.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'A receipt accepts postingDate, vendorShipmentNo, assignedUserId, sortingMethod, zoneCode and binCode in header. A shipment accepts postingDate, shipmentDate, shippingAgentCode, shippingAgentServiceCode, shipmentMethodCode, externalDocumentNo, assignedUserId, sortingMethod, zoneCode and binCode. Any other key is refused as UnknownParameter. ' +
            'Each line in lines names its lineNo and may change zoneCode and binCode. Problems found before anything is written are answered together as MultipleErrors. ' +
            'Every value is validated the same way as when it is typed on the document, so Business Central''s own checks apply: the assigned user must be a warehouse employee at the location, a bin must exist at the location and fit the zone. A header bin is copied to the lines by Business Central. ' +
            'All or nothing: when Business Central refuses one value, the call answers PreconditionFailed with its reason and the document is left unchanged. ' +
            'A released shipment is refused as PreconditionFailed; reopen it with Warehouse.Shipment.Reopen first. The document is never reopened silently. ' +
            'The caller needs BIFROST Whse - Full ori. A field closed to writes in this company is refused as PermissionDenied. Nothing is posted; the change is committed.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the request and changes the document, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        DocumentRef: RecordRef;
        RequestJson: JsonObject;
        HeaderJson: JsonObject;
        Payload: JsonObject;
        PayloadHeader: JsonObject;
        PayloadLines: JsonArray;
        Lines: JsonArray;
        Result: JsonObject;
        Token: JsonToken;
        AllowedKeys: List of [Text];
        TypeText: Text;
        TypePresent: Boolean;
        IsShipment: Boolean;
        HeaderPresent: Boolean;
        LinesPresent: Boolean;
        DocumentFound: Boolean;
        DeniedLbl: Label 'You do not have permission to change warehouse receipts and shipments.', Comment = 'is-IS=Þú hefur ekki heimild til að breyta vöruhúsamóttökum og -afhendingum.';
        ProblemsLbl: Label 'Nothing was changed.', Comment = 'is-IS=Engu var breytt.';
        TypeMissingLbl: Label 'documentType is required.', Comment = 'is-IS=documentType er nauðsynlegt.';
        TypeInvalidLbl: Label 'documentType %1 is not receipt or shipment.', Comment = '%1 = value, is-IS=documentType %1 er hvorki receipt né shipment.';
        NothingLbl: Label 'Send header, lines or both.', Comment = 'is-IS=Sendu header, lines eða hvort tveggja.';
        HeaderFormatLbl: Label 'header must be a JSON object.', Comment = 'is-IS=header verður að vera JSON-hlutur.';
        ReleasedLbl: Label 'Warehouse shipment %1 is released and cannot be changed.', Comment = '%1 = shipment no., is-IS=Vöruhúsaafhending %1 er útgefin og ekki er hægt að breyta henni.';
    begin
        Context.Reset();
        if not HasWritePermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStep());
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        AllowedKeys.Add('documentType');
        AllowedKeys.Add('documentNo');
        AllowedKeys.Add('systemId');
        AllowedKeys.Add('id');
        AllowedKeys.Add('header');
        AllowedKeys.Add('lines');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Context.ReadText(RequestJson, 'documentType', 30, Argument, TypeText, TypePresent, 'documentType');
        if not Argument.HasCollectedErrors() then
            if not TypePresent then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, TypeMissingLbl, 'documentType', '', '', MissingNextStep())
            else
                case LowerCase(TypeText) of
                    'receipt':
                        DocumentRef.Open(Database::"Warehouse Receipt Header");
                    'shipment':
                        begin
                            DocumentRef.Open(Database::"Warehouse Shipment Header");
                            IsShipment := true;
                        end;
                    else
                        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TypeInvalidLbl, TypeText), 'documentType', TypeText, 'receipt, shipment', DocumentTypeNextStep());
                end;
        if RequestJson.Get('header', Token) then begin
            HeaderPresent := true;
            if Token.IsObject() then
                HeaderJson := Token.AsObject()
            else
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, HeaderFormatLbl, 'header', '', 'object', FormatNextStep());
        end;
        Values.ReadArray(RequestJson, 'lines', Argument, Lines, LinesPresent);
        if not HeaderPresent and not LinesPresent and not Argument.HasCollectedErrors() then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, NothingLbl, 'header', '', '', MissingNextStep());
        if DocumentRef.Number() <> 0 then
            DocumentFound := ResolveDocument(Argument, RequestJson, DocumentRef);
        if DocumentFound then begin
            if HeaderPresent and (HeaderJson.Keys().Count() > 0) then
                ReadHeader(Argument, HeaderJson, DocumentRef, PayloadHeader);
            if LinesPresent then
                ReadLines(Argument, Lines, DocumentRef, PayloadLines);
        end;
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        // AL evaluates both operands of and, so the shipment check is nested.
        if IsShipment then
            if IsReleased(DocumentRef) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(ReleasedLbl, Format(DocumentRef.Field(1).Value())), 'documentNo', Format(DocumentRef.Field(1).Value()), 'Open', ReopenNextStep());
                exit;
            end;
        Payload.Add('tableNo', DocumentRef.Number());
        Payload.Add('documentNo', Format(DocumentRef.Field(1).Value()));
        Payload.Add('header', PayloadHeader);
        Payload.Add('lines', PayloadLines);
        // Business Central's own checks run first without writing, so a refusal never depends on a rollback.
        if not TryPrevalidate(Payload) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, GetLastErrorText(), '', '', '', RefusedNextStep());
            exit;
        end;
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Document Update Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Document Update Impl ori") then begin
                Context.Reset();
                Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, GetLastErrorText(), '', '', '', RefusedNextStep());
                exit;
            end;
        Context.TryGetResult(Result);
        Context.Reset();
        Result.Add('status', 'Success');
        if IsShipment then
            Result.Add('documentType', 'shipment')
        else
            Result.Add('documentType', 'receipt');
        Result.Add('updatedCount', 1);
        Argument.SetResponseJson(Result);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ResolveDocument(var Argument: Record "Message Argument ori"; RequestJson: JsonObject; var DocumentRef: RecordRef): Boolean
    var
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        NoFieldRef: FieldRef;
        NumberText: Text;
        SystemIdText: Text;
        IdText: Text;
        SubjectText: Text;
        NumberPresent: Boolean;
        SystemPresent: Boolean;
        IdPresent: Boolean;
        ParsedId: Guid;
        FoundSystemId: Guid;
        NumberSystemId: Guid;
        MissingLbl: Label 'documentNo or systemId is required.', Comment = 'is-IS=documentNo eða systemId er nauðsynlegt.';
        FormatLbl: Label 'systemId is not a GUID.', Comment = 'is-IS=systemId er ekki GUID.';
        NotFoundLbl: Label 'Warehouse document %1 was not found.', Comment = '%1 = identifier, is-IS=Vöruhúsaskjal %1 fannst ekki.';
        ConflictLbl: Label 'The document identifiers name different documents.', Comment = 'is-IS=Auðkenni skjalsins nefna mismunandi skjöl.';
    begin
        Context.ReadText(RequestJson, 'documentNo', 20, Argument, NumberText, NumberPresent, 'documentNo');
        Context.ReadText(RequestJson, 'systemId', 50, Argument, SystemIdText, SystemPresent, 'systemId');
        Context.ReadText(RequestJson, 'id', 50, Argument, IdText, IdPresent, 'id');
        if Argument.HasCollectedErrors() then
            exit(false);
        if IdPresent then begin
            if SystemPresent and (UpperCase(DelChr(IdText, '=', '{}')) <> UpperCase(DelChr(SystemIdText, '=', '{}'))) then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'id', IdText, SystemIdText, ConflictNextStep());
                exit(false);
            end;
            SystemIdText := IdText;
            SystemPresent := true;
        end;
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if SubjectText <> '' then
            if Values.IsGuid(SubjectText) then begin
                if SystemPresent and (UpperCase(DelChr(SubjectText, '=', '{}')) <> UpperCase(DelChr(SystemIdText, '=', '{}'))) then begin
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'systemId', SystemIdText, SubjectText, ConflictNextStep());
                    exit(false);
                end;
                SystemIdText := SubjectText;
                SystemPresent := true;
            end else begin
                if NumberPresent and (UpperCase(SubjectText) <> UpperCase(NumberText)) then begin
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'documentNo', NumberText, SubjectText, ConflictNextStep());
                    exit(false);
                end;
                NumberText := CopyStr(SubjectText, 1, 20);
                NumberPresent := true;
            end;
        if not NumberPresent and not SystemPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'documentNo', '', '', MissingNextStep());
            exit(false);
        end;
        if SystemPresent then begin
            if not Evaluate(ParsedId, SystemIdText) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'systemId', SystemIdText, 'guid', FormatNextStep());
                exit(false);
            end;
            if not DocumentRef.GetBySystemId(ParsedId) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, SystemIdText), 'systemId', SystemIdText, '', NotFoundNextStep());
                exit(false);
            end;
            FoundSystemId := ParsedId;
        end;
        if NumberPresent then begin
            NoFieldRef := DocumentRef.Field(1);
            NoFieldRef.SetRange(CopyStr(UpperCase(NumberText), 1, 20));
            if not DocumentRef.FindFirst() then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, NumberText), 'documentNo', NumberText, '', NotFoundNextStep());
                exit(false);
            end;
            NumberSystemId := DocumentRef.Field(DocumentRef.SystemIdNo()).Value();
            if SystemPresent and (NumberSystemId <> FoundSystemId) then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'documentNo', NumberText, SystemIdText, ConflictNextStep());
                exit(false);
            end;
            NoFieldRef.SetRange();
        end;
        exit(true);
    end;

    local procedure ReadHeader(var Argument: Record "Message Argument ori"; HeaderJson: JsonObject; var DocumentRef: RecordRef; var PayloadHeader: JsonObject)
    var
        Context: Codeunit "Whse Write Context ori";
        RequestValueReader: Codeunit "Request Value Reader ori";
        FieldReference: FieldRef;
        KeyName: Text;
        TextValue: Text;
        DateValue: Date;
        Present: Boolean;
        FieldNo: Integer;
        Ordinal: Integer;
        UnknownLbl: Label 'The key %1 is not a header field of this document type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki hausreitur þessarar skjalagerðar.';
        SortingLbl: Label 'sortingMethod %1 is not a sorting method of this document.', Comment = '%1 = value, is-IS=sortingMethod %1 er ekki röðunaraðferð þessa skjals.';
        RestrictedLbl: Label 'Field %1 is restricted for write on table %2.', Comment = '%1 = field caption, %2 = table caption, is-IS=Ekki er heimilt að skrifa í reitinn %1 í töflunni %2.';
    begin
        foreach KeyName in HeaderJson.Keys() do begin
            FieldNo := HeaderFieldNo(DocumentRef.Number(), KeyName);
            if FieldNo = 0 then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), 'header.' + KeyName, KeyName, '', UnknownNextStep())
            else begin
                FieldReference := DocumentRef.Field(FieldNo);
                if RequestValueReader.IsFieldWriteRestricted(DocumentRef.Number(), FieldNo) then
                    Argument.AddError("Bifrost Error Code ori"::PermissionDenied, StrSubstNo(RestrictedLbl, FieldReference.Caption(), DocumentRef.Caption()), 'header.' + KeyName, '', '', DeniedNextStep())
                else
                    case FieldReference.Type() of
                        FieldType::Date:
                            if Context.ReadDate(HeaderJson, KeyName, Argument, DateValue, Present, 'header.' + KeyName) then
                                PayloadHeader.Add(KeyName, Format(DateValue, 0, 9));
                        FieldType::Option:
                            if Context.ReadText(HeaderJson, KeyName, 100, Argument, TextValue, Present, 'header.' + KeyName) then
                                if TryFindEnumOrdinal(FieldReference, TextValue, Ordinal) then
                                    PayloadHeader.Add(KeyName, Ordinal)
                                else
                                    Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(SortingLbl, TextValue), 'header.' + KeyName, TextValue, EnumNames(FieldReference), DocumentTypeNextStep());
                        else
                            if Context.ReadText(HeaderJson, KeyName, FieldReference.Length(), Argument, TextValue, Present, 'header.' + KeyName) then
                                // An empty string is a value here: it clears the field.
                                PayloadHeader.Add(KeyName, TextValue);
                    end;
            end;
        end;
    end;

    local procedure ReadLines(var Argument: Record "Message Argument ori"; Lines: JsonArray; var DocumentRef: RecordRef; var PayloadLines: JsonArray)
    var
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        LineRef: RecordRef;
        LineJson: JsonObject;
        PayloadLine: JsonObject;
        AllowedKeys: List of [Text];
        Index: Integer;
        LineNo: Integer;
        LinePresent: Boolean;
        ZoneText: Text;
        BinText: Text;
        ZonePresent: Boolean;
        BinPresent: Boolean;
        LineMissingLbl: Label 'lineNo is required on every line.', Comment = 'is-IS=lineNo er nauðsynlegt í hverri línu.';
        LineNotFoundLbl: Label 'Line %1 was not found on document %2.', Comment = '%1 = line no., %2 = document no., is-IS=Lína %1 fannst ekki í skjali %2.';
    begin
        AllowedKeys.Add('lineNo');
        AllowedKeys.Add('zoneCode');
        AllowedKeys.Add('binCode');
        if DocumentRef.Number() = Database::"Warehouse Receipt Header" then
            LineRef.Open(Database::"Warehouse Receipt Line")
        else
            LineRef.Open(Database::"Warehouse Shipment Line");
        for Index := 0 to Lines.Count() - 1 do
            if Values.TryGetLineObject(Lines, Index, 'lines', Argument, LineJson) then begin
                Values.RefuseUnknownKeys(LineJson, AllowedKeys, Argument, 'lines', Index);
                Context.ReadInteger(LineJson, 'lineNo', Argument, LineNo, LinePresent, Values.LineParameter('lines', Index, 'lineNo'));
                Context.ReadText(LineJson, 'zoneCode', 10, Argument, ZoneText, ZonePresent, Values.LineParameter('lines', Index, 'zoneCode'));
                Context.ReadText(LineJson, 'binCode', 20, Argument, BinText, BinPresent, Values.LineParameter('lines', Index, 'binCode'));
                if not LinePresent then
                    Argument.AddError("Bifrost Error Code ori"::MissingParameter, LineMissingLbl, Values.LineParameter('lines', Index, 'lineNo'), '', '', MissingNextStep())
                else
                    if not LineExists(LineRef, Format(DocumentRef.Field(1).Value()), LineNo) then
                        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(LineNotFoundLbl, LineNo, Format(DocumentRef.Field(1).Value())), Values.LineParameter('lines', Index, 'lineNo'), Format(LineNo), '', NotFoundNextStep())
                    else begin
                        Clear(PayloadLine);
                        PayloadLine.Add('lineNo', LineNo);
                        if ZonePresent or LineJson.Contains('zoneCode') then
                            PayloadLine.Add('zoneCode', ZoneText);
                        if BinPresent or LineJson.Contains('binCode') then
                            PayloadLine.Add('binCode', BinText);
                        PayloadLines.Add(PayloadLine);
                    end;
            end;
    end;

    local procedure LineExists(var LineRef: RecordRef; DocumentNo: Text; LineNo: Integer): Boolean
    begin
        LineRef.Reset();
        LineRef.Field(1).SetRange(DocumentNo);
        LineRef.Field(2).SetRange(LineNo);
        exit(not LineRef.IsEmpty());
    end;

    [TryFunction]
    local procedure TryPrevalidate(Payload: JsonObject)
    begin
        ApplyUpdate(Payload, false);
    end;

    local procedure ApplyUpdate(Payload: JsonObject; Persist: Boolean) Result: JsonObject
    var
        Values: Codeunit "Whse Msg Values ori";
        DocumentRef: RecordRef;
        LineRef: RecordRef;
        FieldReference: FieldRef;
        HeaderJson: JsonObject;
        LineJson: JsonObject;
        ResultHeader: JsonObject;
        ResultLine: JsonObject;
        ResultLines: JsonArray;
        Lines: JsonArray;
        Token: JsonToken;
        KeyName: Text;
        DocumentNo: Text;
        FieldNo: Integer;
        DateValue: Date;
        Index: Integer;
    begin
        DocumentRef.Open(Values.IntegerValue(Payload, 'tableNo'));
        DocumentNo := Values.TextValue(Payload, 'documentNo');
        DocumentRef.Field(1).SetRange(DocumentNo);
        DocumentRef.FindFirst();
        Payload.Get('header', Token);
        HeaderJson := Token.AsObject();
        // Fixed order: the zone before the bin, because validating a bin sets its zone.
        foreach KeyName in HeaderKeys() do
            if HeaderJson.Get(KeyName, Token) then begin
                FieldNo := HeaderFieldNo(DocumentRef.Number(), KeyName);
                FieldReference := DocumentRef.Field(FieldNo);
                case FieldReference.Type() of
                    FieldType::Date:
                        begin
                            Evaluate(DateValue, Token.AsValue().AsText(), 9);
                            FieldReference.Validate(DateValue);
                        end;
                    FieldType::Option:
                        // Re-sorting writes the lines, so the sorting method is only applied in the write transaction.
                        if Persist then
                            FieldReference.Validate(Token.AsValue().AsInteger());
                    else
                        FieldReference.Validate(Token.AsValue().AsText());
                end;
            end;
        if Persist and (HeaderJson.Keys().Count() > 0) then
            DocumentRef.Modify(true);
        if DocumentRef.Number() = Database::"Warehouse Receipt Header" then
            LineRef.Open(Database::"Warehouse Receipt Line")
        else
            LineRef.Open(Database::"Warehouse Shipment Line");
        Payload.Get('lines', Token);
        Lines := Token.AsArray();
        for Index := 0 to Lines.Count() - 1 do begin
            Lines.Get(Index, Token);
            LineJson := Token.AsObject();
            LineRef.Reset();
            LineRef.Field(1).SetRange(DocumentNo);
            LineRef.Field(2).SetRange(Values.IntegerValue(LineJson, 'lineNo'));
            LineRef.FindFirst();
            if LineJson.Get('zoneCode', Token) then
                LineRef.Field(13).Validate(Token.AsValue().AsText());
            if LineJson.Get('binCode', Token) then
                LineRef.Field(12).Validate(Token.AsValue().AsText());
            if Persist then
                LineRef.Modify(true);
            Clear(ResultLine);
            ResultLine.Add('lineNo', Values.IntegerValue(LineJson, 'lineNo'));
            ResultLine.Add('zoneCode', Format(LineRef.Field(13).Value()));
            ResultLine.Add('binCode', Format(LineRef.Field(12).Value()));
            ResultLines.Add(ResultLine);
        end;
        if not Persist then
            exit;
        DocumentRef.Find();
        foreach KeyName in HeaderKeys() do begin
            FieldNo := HeaderFieldNo(DocumentRef.Number(), KeyName);
            if FieldNo <> 0 then
                AddFieldValue(ResultHeader, KeyName, DocumentRef.Field(FieldNo));
        end;
        AddFieldValue(ResultHeader, 'assignmentDate', DocumentRef.Field(4));
        Result.Add('documentNo', DocumentNo);
        Result.Add('documentSystemId', Format(DocumentRef.Field(DocumentRef.SystemIdNo()).Value(), 0, 4).ToLower());
        Result.Add('header', ResultHeader);
        Result.Add('lines', ResultLines);
    end;

    local procedure AddFieldValue(var Target: JsonObject; KeyName: Text; FieldReference: FieldRef)
    var
        DateValue: Date;
    begin
        case FieldReference.Type() of
            FieldType::Date:
                begin
                    DateValue := FieldReference.Value();
                    if DateValue = 0D then
                        Target.Add(KeyName, '')
                    else
                        Target.Add(KeyName, Format(DateValue, 0, 9));
                end;
            FieldType::Option:
                Target.Add(KeyName, EnumValueName(FieldReference));
            else
                Target.Add(KeyName, Format(FieldReference.Value()));
        end;
    end;

    local procedure EnumValueName(FieldReference: FieldRef): Text
    var
        Ordinal: Integer;
        Index: Integer;
    begin
        Ordinal := FieldReference.Value();
        for Index := 1 to FieldReference.EnumValueCount() do
            if FieldReference.GetEnumValueOrdinal(Index) = Ordinal then
                exit(FieldReference.GetEnumValueName(Index));
        exit(Format(Ordinal));
    end;

    local procedure HeaderKeys() KeyNames: List of [Text]
    begin
        KeyNames.Add('postingDate');
        KeyNames.Add('vendorShipmentNo');
        KeyNames.Add('shipmentDate');
        KeyNames.Add('shippingAgentCode');
        KeyNames.Add('shippingAgentServiceCode');
        KeyNames.Add('shipmentMethodCode');
        KeyNames.Add('externalDocumentNo');
        KeyNames.Add('assignedUserId');
        KeyNames.Add('sortingMethod');
        KeyNames.Add('zoneCode');
        KeyNames.Add('binCode');
    end;

    local procedure HeaderFieldNo(TableNo: Integer; KeyName: Text): Integer
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ShipmentHeader: Record "Warehouse Shipment Header";
    begin
        if TableNo = Database::"Warehouse Receipt Header" then
            case KeyName of
                'postingDate':
                    exit(ReceiptHeader.FieldNo("Posting Date"));
                'vendorShipmentNo':
                    exit(ReceiptHeader.FieldNo("Vendor Shipment No."));
                'assignedUserId':
                    exit(ReceiptHeader.FieldNo("Assigned User ID"));
                'sortingMethod':
                    exit(ReceiptHeader.FieldNo("Sorting Method"));
                'zoneCode':
                    exit(ReceiptHeader.FieldNo("Zone Code"));
                'binCode':
                    exit(ReceiptHeader.FieldNo("Bin Code"));
            end;
        if TableNo = Database::"Warehouse Shipment Header" then
            case KeyName of
                'postingDate':
                    exit(ShipmentHeader.FieldNo("Posting Date"));
                'shipmentDate':
                    exit(ShipmentHeader.FieldNo("Shipment Date"));
                'shippingAgentCode':
                    exit(ShipmentHeader.FieldNo("Shipping Agent Code"));
                'shippingAgentServiceCode':
                    exit(ShipmentHeader.FieldNo("Shipping Agent Service Code"));
                'shipmentMethodCode':
                    exit(ShipmentHeader.FieldNo("Shipment Method Code"));
                'externalDocumentNo':
                    exit(ShipmentHeader.FieldNo("External Document No."));
                'assignedUserId':
                    exit(ShipmentHeader.FieldNo("Assigned User ID"));
                'sortingMethod':
                    exit(ShipmentHeader.FieldNo("Sorting Method"));
                'zoneCode':
                    exit(ShipmentHeader.FieldNo("Zone Code"));
                'binCode':
                    exit(ShipmentHeader.FieldNo("Bin Code"));
            end;
        exit(0);
    end;

    local procedure TryFindEnumOrdinal(FieldReference: FieldRef; Received: Text; var Ordinal: Integer): Boolean
    var
        Context: Codeunit "Whse Write Context ori";
        Index: Integer;
    begin
        for Index := 1 to FieldReference.EnumValueCount() do
            if Context.SameName(Received, FieldReference.GetEnumValueName(Index)) then begin
                Ordinal := FieldReference.GetEnumValueOrdinal(Index);
                exit(true);
            end;
        exit(false);
    end;

    local procedure EnumNames(FieldReference: FieldRef) Names: Text
    var
        Index: Integer;
    begin
        for Index := 1 to FieldReference.EnumValueCount() do begin
            if Names <> '' then
                Names += ', ';
            Names += FieldReference.GetEnumValueName(Index);
        end;
    end;

    local procedure IsReleased(var DocumentRef: RecordRef): Boolean
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
    begin
        DocumentRef.SetTable(ShipmentHeader);
        exit(ShipmentHeader.Status = ShipmentHeader.Status::Released);
    end;

    local procedure MissingNextStep(): Text
    var
        NextStepLbl: Label 'Send the missing value; Help.Implementation.Get lists the parameters.', Comment = 'is-IS=Sendu gildið sem vantar; Help.Implementation.Get sýnir viðföngin.';
    begin
        exit(NextStepLbl);
    end;

    local procedure DocumentTypeNextStep(): Text
    var
        NextStepLbl: Label 'Send one of the values listed in expected.', Comment = 'is-IS=Sendu eitt af gildunum sem talin eru upp í expected.';
    begin
        exit(NextStepLbl);
    end;

    local procedure FormatNextStep(): Text
    var
        NextStepLbl: Label 'Send the value in the format listed in expected.', Comment = 'is-IS=Sendu gildið á sniðinu sem tilgreint er í expected.';
    begin
        exit(NextStepLbl);
    end;

    local procedure UnknownNextStep(): Text
    var
        NextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        exit(NextStepLbl);
    end;

    local procedure NotFoundNextStep(): Text
    var
        NextStepLbl: Label 'Check the document and its lines with Warehouse.Document.Get.', Comment = 'is-IS=Athugaðu skjalið og línur þess með Warehouse.Document.Get.';
    begin
        exit(NextStepLbl);
    end;

    local procedure ConflictNextStep(): Text
    var
        NextStepLbl: Label 'Send one identifier, or identifiers that name the same document.', Comment = 'is-IS=Sendu eitt auðkenni, eða auðkenni sem nefna sama skjal.';
    begin
        exit(NextStepLbl);
    end;

    local procedure ReopenNextStep(): Text
    var
        NextStepLbl: Label 'Reopen the shipment first with Warehouse.Shipment.Reopen.', Comment = 'is-IS=Opnaðu afhendinguna aftur fyrst með Warehouse.Shipment.Reopen.';
    begin
        exit(NextStepLbl);
    end;

    local procedure RefusedNextStep(): Text
    var
        NextStepLbl: Label 'Correct the value Business Central refused and send the request again; nothing was changed.', Comment = 'is-IS=Leiðréttu gildið sem Business Central hafnaði og sendu beiðnina aftur; engu var breytt.';
    begin
        exit(NextStepLbl);
    end;

    local procedure DeniedNextStep(): Text
    var
        NextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori, or leave out a field that is closed to writes.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori, eða slepptu reit sem lokað er fyrir skrif í.';
    begin
        exit(NextStepLbl);
    end;

    local procedure HasWritePermission(): Boolean
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        exit(ReceiptHeader.WritePermission() and ReceiptLine.WritePermission() and ShipmentHeader.WritePermission() and ShipmentLine.WritePermission());
    end;
}
