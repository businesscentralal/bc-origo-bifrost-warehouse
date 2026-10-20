namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Request;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Shipment.GetSourceDocuments.
/// Adds lines from released outbound source documents to an open warehouse shipment, or to a new shipment at a
/// location, through report 5753 Get Source Documents, the same as the Get Source Documents action on the shipment.
/// The report runs in this codeunit's own OnRun inside Codeunit.Run, so a failure leaves nothing written.
/// </summary>
codeunit 10078432 "Whse Ship GetSrcDocs Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        WarehouseRequest: Record "Warehouse Request";
        GetSourceDocuments: Report "Get Source Documents";
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        ShipmentNo: Code[20];
        Created: Boolean;
        MissingPayloadErr: Label 'The get source documents payload was empty.', Comment = 'is-IS=Gögnin til að sækja upprunaskjöl voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        ShipmentNo := CopyStr(TextValue(Payload, 'shipmentNo'), 1, MaxStrLen(ShipmentNo));
        if ShipmentNo = '' then begin
            // The fields report 5753 sets when it creates a shipment header itself; OnInsert takes the shipment bin.
            ShipmentHeader.Init();
            ShipmentHeader."No." := '';
            ShipmentHeader."Location Code" := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(ShipmentHeader."Location Code"));
            ShipmentHeader.Insert(true);
            Created := true;
        end else
            ShipmentHeader.Get(ShipmentNo);
        // The view is this codeunit's own GetView(false) of filters it built from validated parameters, not a caller tableView.
        // tableView validated by the caller
        WarehouseRequest.SetView(TextValue(Payload, 'requestView'));
        GetSourceDocuments.SetOneCreatedShptHeader(ShipmentHeader);
        GetSourceDocuments.SetHideDialog(true);
        GetSourceDocuments.SetSuppressCommit(true);
        GetSourceDocuments.UseRequestPage(false);
        GetSourceDocuments.SetTableView(WarehouseRequest);
        GetSourceDocuments.RunModal();
        if Created then begin
            ShipmentLine.SetRange("No.", ShipmentHeader."No.");
            if ShipmentLine.IsEmpty() then begin
                // Nothing was added: do not leave an empty shipment behind.
                ShipmentHeader.Delete(true);
                Context.SetResult('', 0);
                exit;
            end;
        end;
        Context.SetResult(ShipmentHeader."No.", 0);
    end;

    /// <summary>Returns whether the caller can write warehouse shipments and read warehouse requests.</summary>
    /// <returns>True when the caller can add source document lines to a shipment.</returns>
    procedure IsEnabled(): Boolean
    begin
        exit(HasPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse shipment header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Shipment Header");
    end;

    /// <summary>Returns a short description of Warehouse.Shipment.GetSourceDocuments.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Adds lines from released outbound source documents to a warehouse shipment, or to a new shipment at a location.', Comment = 'is-IS=Bætir línum úr útgefnum útleiðandi upprunaskjölum við vöruhúsaafhendingu eða nýja afhendingu á staðsetningu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'get source documents, add sales orders to shipment, pull orders into warehouse shipment, ship several orders, combine shipments, outbound source documents', Comment = 'is-IS=sækja upprunaskjöl, bæta sölupöntunum við afhendingu, draga pantanir í vöruhúsaafhendingu, afhenda margar pantanir, sameina afhendingar, útleiðandi upprunaskjöl';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Changes data. Adds lines from released sales orders, purchase return orders or outbound transfers to one open warehouse shipment. Use Warehouse.Request.Get to see what is waiting.', Comment = 'is-IS=Breytir gögnum. Bætir línum úr útgefnum sölupöntunum, innkaupaskilapöntunum eða útleiðandi flutningum við eina opna vöruhúsaafhendingu. Notaðu Warehouse.Request.Get til að sjá hvað bíður.';
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
        Forms.Add('shipment no.');
        Forms.Add('guid');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. The warehouse shipment to add lines to: its number or SystemId. Leave it out and send locationCode to create a new shipment.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'shipment no. or SystemId', 'The warehouse shipment to add lines to.'));
        Target.Add(ContractMgt.TargetEntry('data.shipmentNo', 'shipment no.', 'The warehouse shipment number.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId', 'SystemId', 'The warehouse shipment SystemId.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('shipmentNo', 'string', false, 'Existing open warehouse shipment. Required unless systemId, the subject or locationCode is sent.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'SystemId of the existing warehouse shipment.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location of a new warehouse shipment when no shipment is named. With a shipment it must be the shipment location.'));
        Parameters.Add(ContractMgt.Parameter('sourceDocument', 'string', false, 'Sales Order, Purchase Return Order or Outbound Transfer. Spaces and case are ignored. Defaults to all three.'));
        Parameters.Add(ContractMgt.Parameter('sourceNos', 'array', false, 'Source document numbers to add. Each one must have a released warehouse request at the shipment location.'));
        Parameters.Add(ContractMgt.Parameter('customerNo', 'string', false, 'Only source documents for this customer.'));
        Parameters.Add(ContractMgt.Parameter('shipmentDateFrom', 'date', false, 'First shipment date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('shipmentDateTo', 'date', false, 'Last shipment date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('shippingAgentCode', 'string', false, 'Only source documents with this shipping agent.'));
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
        Fields.Add(ContractMgt.ResponseField('shipmentNo', 'string', 'Warehouse shipment the lines were added to. Empty when a new shipment would have had no lines.'));
        Fields.Add(ContractMgt.ResponseField('shipmentSystemId', 'string', 'Warehouse shipment SystemId.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Shipment location.'));
        Fields.Add(ContractMgt.ResponseField('created', 'boolean', 'True when a new shipment was created.'));
        Fields.Add(ContractMgt.ResponseField('linesAdded', 'integer', 'Number of shipment lines added.'));
        Fields.Add(ContractMgt.ResponseField('sourceDocuments', 'array', 'Lines added per source document: sourceDocument, sourceNo, linesAdded.'));
        Fields.Add(ContractMgt.ResponseField('skipped', 'array', 'Source lines already on another warehouse shipment: sourceDocument, sourceNo, sourceLineNo, itemNo, otherShipmentNo.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Entry: JsonObject;
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'No shipment and no locationCode were sent.', 'Send shipmentNo for an existing shipment or locationCode for a new one.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The warehouse shipment or the location does not exist.', 'Create it with Warehouse.Shipment.Create or pass locationCode.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'Two identifiers name different shipments, locationCode is not the shipment location, or a named source document is at another location.', 'Use a shipment at the same location.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'No released warehouse request matches the filters (the parameter names the filters that were sent), or the location does not require shipment.', 'Release the source documents first.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The warehouse shipment is released.', 'Reopen it with Warehouse.Shipment.Reopen.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'sourceDocument is not one of the listed values, or a date range ends before it starts.', 'Use one of the values listed in the help.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, sourceNos is not an array of strings, or a date is not YYYY-MM-DD.', 'Send text for codes, an array of strings for sourceNos and dates as YYYY-MM-DD.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write warehouse shipments or read warehouse requests.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Parts.AddBusinessCentralError(Errors, 'a blocked item or customer, or a location without a shipment number series');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Adds warehouse shipment lines, and creates the shipment when only locationCode is sent. Nothing is posted.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Request.Get', 'Use it to see the released outbound source documents waiting at the location.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Create', 'Use it to create one shipment per source document instead.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Release', 'Use it to release the shipment when the lines are in place.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Reopen', 'Use it to reopen a released shipment before adding lines.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True when a workflow is declared.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.OutboundWorkflow(Workflow);
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
            'Add two sales orders to a new shipment at WHITE',
            '{"locationCode":"WHITE","sourceDocument":"Sales Order","sourceNos":["101005","101006"]}',
            '{"status":"Success","shipmentNo":"SH000003","shipmentSystemId":"6f1c1d2e-0000-0000-0000-000000000005","locationCode":"WHITE","created":true,"linesAdded":3,"sourceDocuments":[{"sourceDocument":"Sales Order","sourceNo":"101005","linesAdded":2},{"sourceDocument":"Sales Order","sourceNo":"101006","linesAdded":1}],"skipped":[]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Adds lines from released outbound source documents (sales orders, purchase return orders, outbound transfers) to an open warehouse shipment, or to a new shipment when only locationCode is sent, the same as the Get Source Documents action. Filter by source document, source numbers, customer, shipment date and shipping agent. A released shipment is refused. Source lines already on another shipment are skipped and listed under skipped. Nothing is posted.', Comment = 'is-IS=Bætir línum úr útgefnum útleiðandi upprunaskjölum (sölupöntunum, innkaupaskilapöntunum, útleiðandi flutningum) við opna vöruhúsaafhendingu, eða við nýja afhendingu þegar aðeins locationCode er sent, eins og aðgerðin Sækja upprunaskjöl. Síaðu eftir upprunaskjali, númerum upprunaskjala, viðskiptamanni, afhendingardegi og flutningsaðila. Útgefinni afhendingu er hafnað. Upprunalínum sem eru þegar á annarri afhendingu er sleppt og þær taldar upp undir skipped. Ekkert er bókað.';
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

    /// <summary>Validates the request, adds the source document lines and answers what was added and skipped.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        WarehouseRequest: Record "Warehouse Request";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        SourceNos: List of [Text];
        LocationCode: Code[10];
        FilterKeys: Text;
        SnapshotLineNo: Integer;
        ResultNo: Code[20];
        Quantity: Decimal;
        HasShipment: Boolean;
        DeniedLbl: Label 'You do not have permission to add source documents to a warehouse shipment.', Comment = 'is-IS=Þú hefur ekki heimild til að bæta upprunaskjölum við vöruhúsaafhendingu.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was added.', Comment = 'is-IS=Engu var bætt við.';
    begin
        Context.Reset();
        if not HasPermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        // Independent problems are collected and answered together: an unknown key, a missing or unknown target and a
        // bad filter value do not hide one another. Only the check of the warehouse requests needs a valid target.
        RefuseUnknownKeys(RequestJson, Argument);
        ResolveTarget(RequestJson, Argument, ShipmentHeader, LocationCode, HasShipment);
        BuildRequestFilters(RequestJson, Argument, WarehouseRequest, LocationCode, SourceNos, FilterKeys);
        if not Argument.HasCollectedErrors() then
            CheckRequests(Argument, WarehouseRequest, LocationCode, SourceNos, FilterKeys);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if HasShipment then begin
            SnapshotLineNo := LastLineNo(ShipmentHeader."No.");
            Payload.Add('shipmentNo', ShipmentHeader."No.");
        end else
            Payload.Add('shipmentNo', '');
        Payload.Add('locationCode', LocationCode);
        Payload.Add('requestView', WarehouseRequest.GetView(false));
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Ship GetSrcDocs Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Ship GetSrcDocs Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        Context.TryGetResult(ResultNo, Quantity);
        Context.Reset();
        WriteResponse(Argument, WarehouseRequest, ResultNo, LocationCode, not HasShipment, SnapshotLineNo);
    end;

    local procedure ResolveTarget(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var ShipmentHeader: Record "Warehouse Shipment Header"; var LocationCode: Code[10]; var HasShipment: Boolean)
    var
        ByNumber: Record "Warehouse Shipment Header";
        BySystemId: Record "Warehouse Shipment Header";
        Location: Record Location;
        Context: Codeunit "Whse Write Context ori";
        ShipmentNo: Text;
        SystemIdText: Text;
        LocationText: Text;
        SubjectText: Text;
        Parsed: Guid;
        NumberPresent: Boolean;
        SystemPresent: Boolean;
        LocationPresent: Boolean;
        NumberFormatOk: Boolean;
        SystemFormatOk: Boolean;
        LocationFormatOk: Boolean;
        MissingLbl: Label 'shipmentNo or locationCode is required.', Comment = 'is-IS=shipmentNo eða locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send shipmentNo for an existing shipment or locationCode for a new one.', Comment = 'is-IS=Sendu shipmentNo fyrir fyrirliggjandi afhendingu eða locationCode fyrir nýja.';
        FormatLbl: Label 'systemId is not a GUID.', Comment = 'is-IS=systemId er ekki GUID.';
        FormatNextStepLbl: Label 'Send the SystemId of the shipment as a GUID.', Comment = 'is-IS=Sendu SystemId afhendingarinnar sem GUID.';
        NotFoundLbl: Label 'Warehouse shipment %1 was not found.', Comment = '%1 = identifier, is-IS=Vöruhúsaafhending %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Create it with Warehouse.Shipment.Create or pass locationCode.', Comment = 'is-IS=Stofnaðu hana með Warehouse.Shipment.Create eða sendu locationCode.';
        ConflictLbl: Label 'The shipment identifiers name different shipments.', Comment = 'is-IS=Auðkenni afhendingarinnar nefna mismunandi afhendingar.';
        ConflictNextStepLbl: Label 'Send one shipment.', Comment = 'is-IS=Sendu eina afhendingu.';
        LocationConflictLbl: Label 'locationCode %1 is not the location %2 of warehouse shipment %3.', Comment = '%1 = sent location, %2 = shipment location, %3 = shipment no., is-IS=locationCode %1 er ekki staðsetningin %2 á vöruhúsaafhendingu %3.';
        SameLocationNextStepLbl: Label 'Use a shipment at the same location.', Comment = 'is-IS=Notaðu afhendingu á sömu staðsetningu.';
        LocationNotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        LocationNotFoundNextStepLbl: Label 'Check the location code and try again.', Comment = 'is-IS=Athugaðu kóða staðsetningar og reyndu aftur.';
        NoShipLbl: Label 'Location %1 does not require shipment, so it has no warehouse shipments.', Comment = '%1 = location code, is-IS=Staðsetning %1 krefst ekki afhendingar og hefur því engar vöruhúsaafhendingar.';
        NoShipNextStepLbl: Label 'Turn on Require Shipment on the location, or use a location that has it.', Comment = 'is-IS=Kveiktu á Krefjast afhendingar á staðsetningunni eða notaðu staðsetningu sem hefur það.';
        ReleasedLbl: Label 'Warehouse shipment %1 is released, so lines cannot be added.', Comment = '%1 = shipment no., is-IS=Vöruhúsaafhending %1 er útgefin og því er ekki hægt að bæta við línum.';
        ReleasedNextStepLbl: Label 'Reopen it with Warehouse.Shipment.Reopen.', Comment = 'is-IS=Opnaðu hana aftur með Warehouse.Shipment.Reopen.';
    begin
        HasShipment := false;
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        // All three are read before stopping, so one value of the wrong type does not hide another.
        NumberFormatOk := Context.ReadText(RequestJson, 'shipmentNo', MaxStrLen(ShipmentHeader."No."), Argument, ShipmentNo, NumberPresent, 'shipmentNo');
        SystemFormatOk := Context.ReadText(RequestJson, 'systemId', 50, Argument, SystemIdText, SystemPresent, 'systemId');
        LocationFormatOk := Context.ReadText(RequestJson, 'locationCode', MaxStrLen(LocationCode), Argument, LocationText, LocationPresent, 'locationCode');
        if not (NumberFormatOk and SystemFormatOk and LocationFormatOk) then
            exit;
        if SubjectText <> '' then
            if Evaluate(Parsed, SubjectText) then begin
                if SystemPresent and (UpperCase(DelChr(SubjectText, '=', '{}')) <> UpperCase(DelChr(SystemIdText, '=', '{}'))) then begin
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'systemId', SystemIdText, SubjectText, ConflictNextStepLbl);
                    exit;
                end;
                SystemIdText := SubjectText;
                SystemPresent := true;
            end else begin
                if NumberPresent and (UpperCase(SubjectText) <> UpperCase(ShipmentNo)) then begin
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'shipmentNo', ShipmentNo, SubjectText, ConflictNextStepLbl);
                    exit;
                end;
                ShipmentNo := SubjectText;
                NumberPresent := true;
            end;
        if SystemPresent then begin
            if not Evaluate(Parsed, SystemIdText) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'systemId', SystemIdText, 'guid', FormatNextStepLbl);
                exit;
            end;
            if not BySystemId.GetBySystemId(Parsed) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, SystemIdText), 'systemId', SystemIdText, '', NotFoundNextStepLbl);
                exit;
            end;
            ShipmentHeader := BySystemId;
            HasShipment := true;
        end;
        if NumberPresent then begin
            if StrLen(ShipmentNo) > MaxStrLen(ByNumber."No.") then
                ShipmentNo := CopyStr(ShipmentNo, 1, MaxStrLen(ByNumber."No."));
            if not ByNumber.Get(UpperCase(ShipmentNo)) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ShipmentNo), 'shipmentNo', ShipmentNo, '', NotFoundNextStepLbl);
                exit;
            end;
            if HasShipment and (ByNumber."No." <> ShipmentHeader."No.") then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'shipmentNo', ShipmentNo, SystemIdText, ConflictNextStepLbl);
                exit;
            end;
            ShipmentHeader := ByNumber;
            HasShipment := true;
        end;
        if HasShipment then begin
            LocationCode := ShipmentHeader."Location Code";
            if LocationPresent and (UpperCase(LocationText) <> LocationCode) then
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(LocationConflictLbl, LocationText, LocationCode, ShipmentHeader."No."), 'locationCode', LocationText, LocationCode, SameLocationNextStepLbl);
            if ShipmentHeader.Status = ShipmentHeader.Status::Released then
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(ReleasedLbl, ShipmentHeader."No."), 'shipmentNo', ShipmentHeader."No.", 'Open', ReleasedNextStepLbl);
            exit;
        end;
        if not LocationPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'shipmentNo', '', '', MissingNextStepLbl);
            exit;
        end;
        LocationCode := CopyStr(UpperCase(LocationText), 1, MaxStrLen(LocationCode));
        Location.SetLoadFields(Code);
        if not Location.Get(LocationCode) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(LocationNotFoundLbl, LocationCode), 'locationCode', LocationText, '', LocationNotFoundNextStepLbl);
            exit;
        end;
        if not Location.RequireShipment(LocationCode) then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NoShipLbl, LocationCode), 'locationCode', LocationText, '', NoShipNextStepLbl);
    end;

    local procedure BuildRequestFilters(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var WarehouseRequest: Record "Warehouse Request"; LocationCode: Code[10]; var SourceNos: List of [Text]; var FilterKeys: Text)
    var
        Context: Codeunit "Whse Write Context ori";
        SourceDocumentText: Text;
        CustomerNo: Text;
        ShippingAgentCode: Text;
        DateFrom: Date;
        DateTo: Date;
        Present: Boolean;
        ValueLbl: Label 'Parameter %1 has the value %2, which is not one of the values listed in the help.', Comment = '%1 = parameter, %2 = value, is-IS=Færibreytan %1 hefur gildið %2 sem er ekki eitt af gildunum sem talin eru upp í hjálpinni.';
        ValueNextStepLbl: Label 'Use one of the values listed in the help.', Comment = 'is-IS=Notaðu eitt af gildunum sem talin eru upp í hjálpinni.';
        RangeLbl: Label 'The date range %1 ends before it starts.', Comment = '%1 = parameter, is-IS=Dagsetningabilið %1 endar áður en það byrjar.';
        RangeNextStepLbl: Label 'Send a from date that is on or before the to date.', Comment = 'is-IS=Sendu upphafsdagsetningu sem er sama dag eða á undan lokadagsetningu.';
    begin
        Context.ReadText(RequestJson, 'sourceDocument', 50, Argument, SourceDocumentText, Present, 'sourceDocument');
        Context.ReadCodeList(RequestJson, 'sourceNos', MaxStrLen(WarehouseRequest."Source No."), Argument, SourceNos, Present);
        Context.ReadText(RequestJson, 'customerNo', MaxStrLen(WarehouseRequest."Destination No."), Argument, CustomerNo, Present, 'customerNo');
        Context.ReadDate(RequestJson, 'shipmentDateFrom', Argument, DateFrom, Present, 'shipmentDateFrom');
        Context.ReadDate(RequestJson, 'shipmentDateTo', Argument, DateTo, Present, 'shipmentDateTo');
        Context.ReadText(RequestJson, 'shippingAgentCode', MaxStrLen(WarehouseRequest."Shipping Agent Code"), Argument, ShippingAgentCode, Present, 'shippingAgentCode');
        WarehouseRequest.SetRange(Type, WarehouseRequest.Type::Outbound);
        WarehouseRequest.SetRange("Document Status", WarehouseRequest."Document Status"::Released);
        WarehouseRequest.SetRange("Completely Handled", false);
        if SourceDocumentText = '' then
            WarehouseRequest.SetFilter("Source Document", '%1|%2|%3', WarehouseRequest."Source Document"::"Sales Order", WarehouseRequest."Source Document"::"Purchase Return Order", WarehouseRequest."Source Document"::"Outbound Transfer")
        else
            case true of
                Context.SameName(SourceDocumentText, 'Sales Order'):
                    WarehouseRequest.SetRange("Source Document", WarehouseRequest."Source Document"::"Sales Order");
                Context.SameName(SourceDocumentText, 'Purchase Return Order'):
                    WarehouseRequest.SetRange("Source Document", WarehouseRequest."Source Document"::"Purchase Return Order");
                Context.SameName(SourceDocumentText, 'Outbound Transfer'):
                    WarehouseRequest.SetRange("Source Document", WarehouseRequest."Source Document"::"Outbound Transfer");
                else
                    Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'sourceDocument', SourceDocumentText), 'sourceDocument', SourceDocumentText, 'Sales Order, Purchase Return Order, Outbound Transfer', ValueNextStepLbl);
            end;
        if SourceNos.Count() > 0 then
            WarehouseRequest.SetFilter("Source No.", Context.LiteralFilter(SourceNos));
        if CustomerNo <> '' then begin
            WarehouseRequest.SetRange("Destination Type", WarehouseRequest."Destination Type"::Customer);
            WarehouseRequest.SetRange("Destination No.", CopyStr(UpperCase(CustomerNo), 1, MaxStrLen(WarehouseRequest."Destination No.")));
        end;
        if ShippingAgentCode <> '' then
            WarehouseRequest.SetRange("Shipping Agent Code", CopyStr(UpperCase(ShippingAgentCode), 1, MaxStrLen(WarehouseRequest."Shipping Agent Code")));
        if (DateFrom <> 0D) and (DateTo <> 0D) and (DateTo < DateFrom) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, 'shipmentDateFrom'), 'shipmentDateTo', Context.FormatDate(DateTo), '', RangeNextStepLbl);
        if (DateFrom <> 0D) or (DateTo <> 0D) then
            WarehouseRequest.SetRange("Shipment Date", DateFrom, Context.RangeEnd(DateTo));
        // The refusal "no released request matches" names the filters that were sent (#71).
        FilterKeys := '';
        AddFilterKey(FilterKeys, SourceDocumentText <> '', 'sourceDocument');
        AddFilterKey(FilterKeys, SourceNos.Count() > 0, 'sourceNos');
        AddFilterKey(FilterKeys, CustomerNo <> '', 'customerNo');
        AddFilterKey(FilterKeys, DateFrom <> 0D, 'shipmentDateFrom');
        AddFilterKey(FilterKeys, DateTo <> 0D, 'shipmentDateTo');
        AddFilterKey(FilterKeys, ShippingAgentCode <> '', 'shippingAgentCode');
        WarehouseRequest.SetRange("Location Code", LocationCode);
    end;

    local procedure AddFilterKey(var FilterKeys: Text; Sent: Boolean; KeyName: Text)
    begin
        if not Sent then
            exit;
        if FilterKeys <> '' then
            FilterKeys += ', ';
        FilterKeys += KeyName;
    end;
    local procedure CheckRequests(var Argument: Record "Message Argument ori"; var WarehouseRequest: Record "Warehouse Request"; LocationCode: Code[10]; SourceNos: List of [Text]; FilterKeys: Text)
    var
        NamedRequest: Record "Warehouse Request";
        SourceNo: Text;
        Index: Integer;
        NoneLbl: Label 'No released warehouse request at location %1 matches the filters.', Comment = '%1 = location code, is-IS=Engin útgefin vöruhúsabeiðni á staðsetningu %1 passar við síurnar.';
        NotReleasedLbl: Label 'Source document %1 has no released warehouse request at location %2.', Comment = '%1 = source no., %2 = location code, is-IS=Upprunaskjal %1 hefur enga útgefna vöruhúsabeiðni á staðsetningu %2.';
        ReleaseNextStepLbl: Label 'Release the source documents first.', Comment = 'is-IS=Gefðu upprunaskjölin út fyrst.';
        OtherLocationLbl: Label 'Source document %1 is at location %2, not at the shipment location %3.', Comment = '%1 = source no., %2 = source location, %3 = shipment location, is-IS=Upprunaskjal %1 er á staðsetningu %2, ekki á staðsetningu afhendingarinnar %3.';
        SameLocationNextStepLbl: Label 'Use a shipment at the same location.', Comment = 'is-IS=Notaðu afhendingu á sömu staðsetningu.';
        ParameterLbl: Label 'sourceNos[%1]', Locked = true;
    begin
        Index := 0;
        foreach SourceNo in SourceNos do begin
            NamedRequest.CopyFilters(WarehouseRequest);
            NamedRequest.SetRange("Source No.", CopyStr(SourceNo, 1, MaxStrLen(NamedRequest."Source No.")));
            if NamedRequest.IsEmpty() then begin
                NamedRequest.SetRange("Location Code");
                NamedRequest.SetLoadFields("Location Code");
                if NamedRequest.FindFirst() then
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(OtherLocationLbl, SourceNo, NamedRequest."Location Code", LocationCode), StrSubstNo(ParameterLbl, Index), SourceNo, LocationCode, SameLocationNextStepLbl)
                else
                    Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NotReleasedLbl, SourceNo, LocationCode), StrSubstNo(ParameterLbl, Index), SourceNo, '', ReleaseNextStepLbl);
            end;
            Index += 1;
        end;
        if Argument.HasCollectedErrors() then
            exit;
        if WarehouseRequest.IsEmpty() then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NoneLbl, LocationCode), FilterKeys, '', '', ReleaseNextStepLbl);
    end;

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; var WarehouseRequest: Record "Warehouse Request"; ShipmentNo: Code[20]; LocationCode: Code[10]; Created: Boolean; SnapshotLineNo: Integer)
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        ResponseJson: JsonObject;
        SourceDocuments: JsonArray;
        DocumentJson: JsonObject;
        KeyOrder: List of [Text];
        Counts: Dictionary of [Text, Integer];
        Names: Dictionary of [Text, Text];
        Numbers: Dictionary of [Text, Text];
        KeyText: Text;
        LinesAdded: Integer;
    begin
        if ShipmentNo <> '' then begin
            ShipmentLine.SetLoadFields("No.", "Line No.", "Source Document", "Source No.");
            ShipmentLine.SetRange("No.", ShipmentNo);
            ShipmentLine.SetFilter("Line No.", '>%1', SnapshotLineNo);
            if ShipmentLine.FindSet() then
                repeat
                    RecordReference.GetTable(ShipmentLine);
                    KeyText := Context.EnumValueName(RecordReference, ShipmentLine.FieldNo("Source Document")) + '|' + ShipmentLine."Source No.";
                    if not Counts.ContainsKey(KeyText) then begin
                        KeyOrder.Add(KeyText);
                        Counts.Add(KeyText, 0);
                        Names.Add(KeyText, Context.EnumValueName(RecordReference, ShipmentLine.FieldNo("Source Document")));
                        Numbers.Add(KeyText, ShipmentLine."Source No.");
                    end;
                    Counts.Set(KeyText, Counts.Get(KeyText) + 1);
                    LinesAdded += 1;
                until ShipmentLine.Next() = 0;
        end;
        foreach KeyText in KeyOrder do begin
            Clear(DocumentJson);
            DocumentJson.Add('sourceDocument', Names.Get(KeyText));
            DocumentJson.Add('sourceNo', Numbers.Get(KeyText));
            DocumentJson.Add('linesAdded', Counts.Get(KeyText));
            SourceDocuments.Add(DocumentJson);
        end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('shipmentNo', ShipmentNo);
        if (ShipmentNo <> '') and ShipmentHeader.Get(ShipmentNo) then
            ResponseJson.Add('shipmentSystemId', Format(ShipmentHeader.SystemId, 0, 4))
        else
            ResponseJson.Add('shipmentSystemId', '');
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('created', Created and (ShipmentNo <> ''));
        ResponseJson.Add('linesAdded', LinesAdded);
        ResponseJson.Add('sourceDocuments', SourceDocuments);
        ResponseJson.Add('skipped', SkippedLines(WarehouseRequest, ShipmentNo, SnapshotLineNo));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure SkippedLines(var WarehouseRequest: Record "Warehouse Request"; ShipmentNo: Code[20]; SnapshotLineNo: Integer) Skipped: JsonArray
    var
        OtherLine: Record "Warehouse Shipment Line";
        AddedLine: Record "Warehouse Shipment Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        SkippedJson: JsonObject;
    begin
        // A source line that is already on another shipment is not added again by the report. List each such
        // line unless the run still added its remaining quantity to this shipment.
        WarehouseRequest.SetLoadFields("Source Type", "Source Subtype", "Source No.");
        if not WarehouseRequest.FindSet() then
            exit;
        repeat
            OtherLine.SetLoadFields("No.", "Source Document", "Source No.", "Source Line No.", "Item No.");
            OtherLine.SetRange("Source Type", WarehouseRequest."Source Type");
            OtherLine.SetRange("Source Subtype", WarehouseRequest."Source Subtype");
            OtherLine.SetRange("Source No.", WarehouseRequest."Source No.");
            OtherLine.SetFilter("No.", '<>%1', ShipmentNo);
            if OtherLine.FindSet() then
                repeat
                    AddedLine.SetRange("No.", ShipmentNo);
                    AddedLine.SetFilter("Line No.", '>%1', SnapshotLineNo);
                    AddedLine.SetRange("Source Type", WarehouseRequest."Source Type");
                    AddedLine.SetRange("Source Subtype", WarehouseRequest."Source Subtype");
                    AddedLine.SetRange("Source No.", WarehouseRequest."Source No.");
                    AddedLine.SetRange("Source Line No.", OtherLine."Source Line No.");
                    if (ShipmentNo = '') or AddedLine.IsEmpty() then begin
                        RecordReference.GetTable(OtherLine);
                        Clear(SkippedJson);
                        SkippedJson.Add('sourceDocument', Context.EnumValueName(RecordReference, OtherLine.FieldNo("Source Document")));
                        SkippedJson.Add('sourceNo', OtherLine."Source No.");
                        SkippedJson.Add('sourceLineNo', OtherLine."Source Line No.");
                        SkippedJson.Add('itemNo', OtherLine."Item No.");
                        SkippedJson.Add('otherShipmentNo', OtherLine."No.");
                        Skipped.Add(SkippedJson);
                    end;
                until OtherLine.Next() = 0;
        until WarehouseRequest.Next() = 0;
    end;

    local procedure LastLineNo(ShipmentNo: Code[20]): Integer
    var
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        ShipmentLine.SetLoadFields("No.", "Line No.");
        ShipmentLine.SetRange("No.", ShipmentNo);
        if ShipmentLine.FindLast() then
            exit(ShipmentLine."Line No.");
        exit(0);
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['shipmentNo', 'systemId', 'locationCode', 'sourceDocument', 'sourceNos', 'customerNo', 'shipmentDateFrom', 'shipmentDateTo', 'shippingAgentCode']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;

    local procedure HasPermission(): Boolean
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        ShipmentLine: Record "Warehouse Shipment Line";
        WarehouseRequest: Record "Warehouse Request";
    begin
        exit(ShipmentHeader.WritePermission() and ShipmentLine.WritePermission() and WarehouseRequest.ReadPermission());
    end;
}
