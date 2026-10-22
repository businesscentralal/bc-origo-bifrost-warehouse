namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Request;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Receipt.GetSourceDocuments.
/// Adds lines from released inbound source documents to an existing warehouse receipt, or to a new receipt at a
/// location, through report 5753 Get Source Documents, the same as the Get Source Documents action on the receipt.
/// The report runs in this codeunit's own OnRun inside Codeunit.Run, so a failure leaves nothing written.
/// </summary>
codeunit 10078431 "Whse Rcpt GetSrcDocs Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        WarehouseRequest: Record "Warehouse Request";
        GetSourceDocuments: Report "Get Source Documents";
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        ReceiptNo: Code[20];
        Created: Boolean;
        MissingPayloadErr: Label 'The get source documents payload was empty.', Comment = 'is-IS=Gögnin til að sækja upprunaskjöl voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        ReceiptNo := CopyStr(TextValue(Payload, 'receiptNo'), 1, MaxStrLen(ReceiptNo));
        if ReceiptNo = '' then begin
            // The same fields report 5753 sets when it creates a receipt header itself.
            ReceiptHeader.Init();
            ReceiptHeader."No." := '';
            ReceiptHeader."Location Code" := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(ReceiptHeader."Location Code"));
            ReceiptHeader.Insert(true);
            Created := true;
        end else
            ReceiptHeader.Get(ReceiptNo);
        // The view is this codeunit's own GetView(false) of filters it built from validated parameters, not a caller tableView.
        // tableView validated by the caller
        WarehouseRequest.SetView(TextValue(Payload, 'requestView'));
        GetSourceDocuments.SetOneCreatedReceiptHeader(ReceiptHeader);
        GetSourceDocuments.SetHideDialog(true);
        GetSourceDocuments.SetSuppressCommit(true);
        GetSourceDocuments.UseRequestPage(false);
        GetSourceDocuments.SetTableView(WarehouseRequest);
        GetSourceDocuments.RunModal();
        if Created then begin
            ReceiptLine.SetRange("No.", ReceiptHeader."No.");
            if ReceiptLine.IsEmpty() then begin
                // Nothing was added: do not leave an empty receipt behind.
                ReceiptHeader.Delete(true);
                Context.SetResult('', 0);
                exit;
            end;
        end;
        Context.SetResult(ReceiptHeader."No.", 0);
    end;

    /// <summary>Returns whether the caller can write warehouse receipts and read warehouse requests.</summary>
    /// <returns>True when the caller can add source document lines to a receipt.</returns>
    procedure IsEnabled(): Boolean
    begin
        exit(HasPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse receipt header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Receipt Header");
    end;

    /// <summary>Returns a short description of Warehouse.Receipt.GetSourceDocuments.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Adds lines from released inbound source documents to a warehouse receipt, or to a new receipt at a location.', Comment = 'is-IS=Bætir línum úr útgefnum innkomandi upprunaskjölum við vöruhúsamóttöku eða nýja móttöku á staðsetningu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'get source documents, add purchase orders to receipt, pull orders into warehouse receipt, receive several orders, combine receipts, inbound source documents', Comment = 'is-IS=sækja upprunaskjöl, bæta innkaupapöntunum við móttöku, draga pantanir í vöruhúsamóttöku, taka á móti mörgum pöntunum, sameina móttökur, innkomandi upprunaskjöl';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Changes data. Adds lines from released purchase orders, sales return orders or inbound transfers to one warehouse receipt. Use Warehouse.Request.Get to see what is waiting.', Comment = 'is-IS=Breytir gögnum. Bætir línum úr útgefnum innkaupapöntunum, söluskilapöntunum eða innkomandi flutningum við eina vöruhúsamóttöku. Notaðu Warehouse.Request.Get til að sjá hvað bíður.';
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
        Forms.Add('receipt no.');
        Forms.Add('guid');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. The warehouse receipt to add lines to: its number or SystemId. Leave it out and send locationCode to create a new receipt.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'receipt no. or SystemId', 'The warehouse receipt to add lines to.'));
        Target.Add(ContractMgt.TargetEntry('data.receiptNo', 'receipt no.', 'The warehouse receipt number.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId', 'SystemId', 'The warehouse receipt SystemId.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('receiptNo', 'string', false, 'Existing warehouse receipt. Required unless systemId, the subject or locationCode is sent.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'SystemId of the existing warehouse receipt.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location of a new warehouse receipt when no receipt is named. With a receipt it must be the receipt location.'));
        Parameters.Add(ContractMgt.Parameter('sourceDocument', 'string', false, 'Purchase Order, Sales Return Order or Inbound Transfer. Spaces and case are ignored. Defaults to all three.'));
        Parameters.Add(ContractMgt.Parameter('sourceNos', 'array', false, 'Source document numbers to add. Each one must have a released warehouse request at the receipt location.'));
        Parameters.Add(ContractMgt.Parameter('vendorNo', 'string', false, 'Only source documents for this vendor.'));
        Parameters.Add(ContractMgt.Parameter('expectedReceiptDateFrom', 'date', false, 'First expected receipt date, YYYY-MM-DD.'));
        Parameters.Add(ContractMgt.Parameter('expectedReceiptDateTo', 'date', false, 'Last expected receipt date, YYYY-MM-DD.'));
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
        Fields.Add(ContractMgt.ResponseField('receiptNo', 'string', 'Warehouse receipt the lines were added to. Empty when a new receipt would have had no lines.'));
        Fields.Add(ContractMgt.ResponseField('receiptSystemId', 'string', 'Warehouse receipt SystemId.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Receipt location.'));
        Fields.Add(ContractMgt.ResponseField('created', 'boolean', 'True when a new receipt was created.'));
        Fields.Add(ContractMgt.ResponseField('linesAdded', 'integer', 'Number of receipt lines added.'));
        Fields.Add(ContractMgt.ResponseField('sourceDocuments', 'array', 'Lines added per source document: sourceDocument, sourceNo, linesAdded.'));
        Fields.Add(ContractMgt.ResponseField('skipped', 'array', 'Source lines already on another warehouse receipt: sourceDocument, sourceNo, sourceLineNo, itemNo, otherReceiptNo.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Context: Codeunit "Whse Write Context ori";
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Entry: JsonObject;
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'No receipt and no locationCode were sent.', 'Send receiptNo for an existing receipt or locationCode for a new one.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The warehouse receipt or the location does not exist.', 'Create it with Warehouse.Receipt.Create or pass locationCode.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'Two identifiers name different receipts, locationCode is not the receipt location, or a named source document is at another location.', 'Use a receipt at the same location.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'No released warehouse request matches the filters (the parameter names the filters that were sent), or the location does not require receive.', 'Release the source documents first; read Warehouse.Request.Get.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'sourceDocument is not one of the listed values, or a date range ends before it starts.', 'Use one of the values listed in the help.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, sourceNos is not an array of strings, or a date is not YYYY-MM-DD.', 'Send text for codes, an array of strings for sourceNos and dates as YYYY-MM-DD.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write warehouse receipts or read warehouse requests.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Parts.AddBusinessCentralError(Errors, 'a blocked item or vendor, or a location without a receipt number series');
        Parts.AddDateErrors(Errors, 'expectedReceiptDateFrom, expectedReceiptDateTo', Context.TextDateNextStep());
        Parts.AddDateRangeError(Errors, 'expectedReceiptDateFrom and expectedReceiptDateTo');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Adds warehouse receipt lines, and creates the receipt when only locationCode is sent. Nothing is posted.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Request.Get', 'Use it to see the released inbound source documents waiting at the location.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Create', 'Use it to create one receipt per source document instead.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Post', 'Use it to post the receipt, with optional per-line quantities.'));
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
            'Add two purchase orders to a new receipt at WHITE',
            '{"locationCode":"WHITE","sourceDocument":"Purchase Order","sourceNos":["106001","106002"]}',
            '{"status":"Success","receiptNo":"RE000003","receiptSystemId":"6f1c1d2e-0000-0000-0000-000000000004","locationCode":"WHITE","created":true,"linesAdded":3,"sourceDocuments":[{"sourceDocument":"Purchase Order","sourceNo":"106001","linesAdded":2},{"sourceDocument":"Purchase Order","sourceNo":"106002","linesAdded":1}],"skipped":[]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Adds lines from released inbound source documents (purchase orders, sales return orders, inbound transfers) to an existing warehouse receipt, or to a new receipt when only locationCode is sent, the same as the Get Source Documents action. Filter by source document, source numbers, vendor and expected receipt date. Source lines already on another receipt are skipped and listed under skipped. Nothing is posted.', Comment = 'is-IS=Bætir línum úr útgefnum innkomandi upprunaskjölum (innkaupapöntunum, söluskilapöntunum, innkomandi flutningum) við fyrirliggjandi vöruhúsamóttöku, eða við nýja móttöku þegar aðeins locationCode er sent, eins og aðgerðin Sækja upprunaskjöl. Síaðu eftir upprunaskjali, númerum upprunaskjala, lánardrottni og væntanlegum móttökudegi. Upprunalínum sem eru þegar á annarri móttöku er sleppt og þær taldar upp undir skipped. Ekkert er bókað.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes describe targets, filters, skipped lines and the all-or-nothing run.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Send receiptNo (or systemId, or the subject) to add lines to an existing receipt, or only locationCode to create a new receipt at that location; when a receipt is named, locationCode must be its location. A new location must have Require Receive set. ' +
            'Only released inbound source documents (purchase orders, sales return orders and inbound transfers) that are not completely handled and sit at the receipt location are considered. sourceDocument, sourceNos, vendorNo and the expected receipt dates narrow them. sourceNos is an array of text values, so send document numbers as strings. ' +
            'Every sourceNos entry must have a released request at the receipt location. A number released at another location is refused as ConflictingIdentifiers and an unreleased one as PreconditionFailed; the refusal names the entry. ' +
            'If a new receipt would get no lines it is removed again, and the answer has an empty receiptNo, created false and linesAdded 0. ' +
            'Source lines that already sit on another warehouse receipt are not added; they are listed under skipped with the receipt that holds them. When lines are added to an existing receipt, only the lines added by this call are counted in linesAdded and sourceDocuments. ' +
            'Bad parameters are collected and answered together as MultipleErrors. The run is all-or-nothing: a failure leaves nothing written, and nothing is posted. ' +
            'The caller needs the BIFROST Whse - Full ori permission set. Use Warehouse.Request.Get to see what is waiting, and Warehouse.Receipt.Post to receive.';
        exit(true);
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
        ReceiptHeader: Record "Warehouse Receipt Header";
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
        HasReceipt: Boolean;
        DeniedLbl: Label 'You do not have permission to add source documents to a warehouse receipt.', Comment = 'is-IS=Þú hefur ekki heimild til að bæta upprunaskjölum við vöruhúsamóttöku.';
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
        ResolveTarget(RequestJson, Argument, ReceiptHeader, LocationCode, HasReceipt);
        BuildRequestFilters(RequestJson, Argument, WarehouseRequest, LocationCode, SourceNos, FilterKeys);
        if not Argument.HasCollectedErrors() then
            CheckRequests(Argument, WarehouseRequest, LocationCode, SourceNos, FilterKeys);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if HasReceipt then begin
            SnapshotLineNo := LastLineNo(ReceiptHeader."No.");
            Payload.Add('receiptNo', ReceiptHeader."No.");
        end else
            Payload.Add('receiptNo', '');
        Payload.Add('locationCode', LocationCode);
        Payload.Add('requestView', WarehouseRequest.GetView(false));
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Rcpt GetSrcDocs Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Rcpt GetSrcDocs Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        Context.TryGetResult(ResultNo, Quantity);
        Context.Reset();
        WriteResponse(Argument, WarehouseRequest, ResultNo, LocationCode, not HasReceipt, SnapshotLineNo);
    end;

    local procedure ResolveTarget(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var ReceiptHeader: Record "Warehouse Receipt Header"; var LocationCode: Code[10]; var HasReceipt: Boolean)
    var
        ByNumber: Record "Warehouse Receipt Header";
        BySystemId: Record "Warehouse Receipt Header";
        Location: Record Location;
        Context: Codeunit "Whse Write Context ori";
        ReceiptNo: Text;
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
        MissingLbl: Label 'receiptNo or locationCode is required.', Comment = 'is-IS=receiptNo eða locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send receiptNo for an existing receipt or locationCode for a new one.', Comment = 'is-IS=Sendu receiptNo fyrir fyrirliggjandi móttöku eða locationCode fyrir nýja.';
        FormatLbl: Label 'systemId is not a GUID.', Comment = 'is-IS=systemId er ekki GUID.';
        FormatNextStepLbl: Label 'Send the SystemId of the receipt as a GUID.', Comment = 'is-IS=Sendu SystemId móttökunnar sem GUID.';
        NotFoundLbl: Label 'Warehouse receipt %1 was not found.', Comment = '%1 = identifier, is-IS=Vöruhúsamóttaka %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Create it with Warehouse.Receipt.Create or pass locationCode.', Comment = 'is-IS=Stofnaðu hana með Warehouse.Receipt.Create eða sendu locationCode.';
        ConflictLbl: Label 'The receipt identifiers name different receipts.', Comment = 'is-IS=Auðkenni móttökunnar nefna mismunandi móttökur.';
        ConflictNextStepLbl: Label 'Send one receipt.', Comment = 'is-IS=Sendu eina móttöku.';
        LocationConflictLbl: Label 'locationCode %1 is not the location %2 of warehouse receipt %3.', Comment = '%1 = sent location, %2 = receipt location, %3 = receipt no., is-IS=locationCode %1 er ekki staðsetningin %2 á vöruhúsamóttöku %3.';
        SameLocationNextStepLbl: Label 'Use a receipt at the same location.', Comment = 'is-IS=Notaðu móttöku á sömu staðsetningu.';
        LocationNotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        LocationNotFoundNextStepLbl: Label 'Check the location code and try again.', Comment = 'is-IS=Athugaðu kóða staðsetningar og reyndu aftur.';
        NoReceiveLbl: Label 'Location %1 does not require receive, so it has no warehouse receipts.', Comment = '%1 = location code, is-IS=Staðsetning %1 krefst ekki móttöku og hefur því engar vöruhúsamóttökur.';
        NoReceiveNextStepLbl: Label 'Turn on Require Receive on the location, or use a location that has it.', Comment = 'is-IS=Kveiktu á Krefjast móttöku á staðsetningunni eða notaðu staðsetningu sem hefur það.';
    begin
        HasReceipt := false;
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        // All three are read before stopping, so one value of the wrong type does not hide another.
        NumberFormatOk := Context.ReadText(RequestJson, 'receiptNo', MaxStrLen(ReceiptHeader."No."), Argument, ReceiptNo, NumberPresent, 'receiptNo');
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
                if NumberPresent and (UpperCase(SubjectText) <> UpperCase(ReceiptNo)) then begin
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'receiptNo', ReceiptNo, SubjectText, ConflictNextStepLbl);
                    exit;
                end;
                ReceiptNo := SubjectText;
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
            ReceiptHeader := BySystemId;
            HasReceipt := true;
        end;
        if NumberPresent then begin
            if StrLen(ReceiptNo) > MaxStrLen(ByNumber."No.") then
                ReceiptNo := CopyStr(ReceiptNo, 1, MaxStrLen(ByNumber."No."));
            if not ByNumber.Get(UpperCase(ReceiptNo)) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ReceiptNo), 'receiptNo', ReceiptNo, '', NotFoundNextStepLbl);
                exit;
            end;
            if HasReceipt and (ByNumber."No." <> ReceiptHeader."No.") then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'receiptNo', ReceiptNo, SystemIdText, ConflictNextStepLbl);
                exit;
            end;
            ReceiptHeader := ByNumber;
            HasReceipt := true;
        end;
        if HasReceipt then begin
            LocationCode := ReceiptHeader."Location Code";
            if LocationPresent and (UpperCase(LocationText) <> LocationCode) then
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(LocationConflictLbl, LocationText, LocationCode, ReceiptHeader."No."), 'locationCode', LocationText, LocationCode, SameLocationNextStepLbl);
            exit;
        end;
        if not LocationPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'receiptNo', '', '', MissingNextStepLbl);
            exit;
        end;
        LocationCode := CopyStr(UpperCase(LocationText), 1, MaxStrLen(LocationCode));
        Location.SetLoadFields(Code);
        if not Location.Get(LocationCode) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(LocationNotFoundLbl, LocationCode), 'locationCode', LocationText, '', LocationNotFoundNextStepLbl);
            exit;
        end;
        if not Location.RequireReceive(LocationCode) then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NoReceiveLbl, LocationCode), 'locationCode', LocationText, '', NoReceiveNextStepLbl);
    end;

    local procedure BuildRequestFilters(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var WarehouseRequest: Record "Warehouse Request"; LocationCode: Code[10]; var SourceNos: List of [Text]; var FilterKeys: Text)
    var
        Context: Codeunit "Whse Write Context ori";
        SourceDocumentText: Text;
        VendorNo: Text;
        DateFrom: Date;
        DateTo: Date;
        Present: Boolean;
        ValueLbl: Label 'Parameter %1 has the value %2, which is not one of the values listed in the help.', Comment = '%1 = parameter, %2 = value, is-IS=Færibreytan %1 hefur gildið %2 sem er ekki eitt af gildunum sem talin eru upp í hjálpinni.';
        ValueNextStepLbl: Label 'Use one of the values listed in the help.', Comment = 'is-IS=Notaðu eitt af gildunum sem talin eru upp í hjálpinni.';
        RangeLbl: Label 'The date range %1 ends before it starts.', Comment = '%1 = parameter, is-IS=Dagsetningabilið %1 endar áður en það byrjar.';
    begin
        Context.ReadText(RequestJson, 'sourceDocument', 50, Argument, SourceDocumentText, Present, 'sourceDocument');
        Context.ReadCodeList(RequestJson, 'sourceNos', MaxStrLen(WarehouseRequest."Source No."), Argument, SourceNos, Present);
        Context.ReadText(RequestJson, 'vendorNo', MaxStrLen(WarehouseRequest."Destination No."), Argument, VendorNo, Present, 'vendorNo');
        Context.ReadDate(RequestJson, 'expectedReceiptDateFrom', Argument, DateFrom, Present, 'expectedReceiptDateFrom');
        Context.ReadDate(RequestJson, 'expectedReceiptDateTo', Argument, DateTo, Present, 'expectedReceiptDateTo');
        WarehouseRequest.SetRange(Type, WarehouseRequest.Type::Inbound);
        WarehouseRequest.SetRange("Document Status", WarehouseRequest."Document Status"::Released);
        WarehouseRequest.SetRange("Completely Handled", false);
        if SourceDocumentText = '' then
            WarehouseRequest.SetFilter("Source Document", '%1|%2|%3', WarehouseRequest."Source Document"::"Purchase Order", WarehouseRequest."Source Document"::"Sales Return Order", WarehouseRequest."Source Document"::"Inbound Transfer")
        else
            case true of
                Context.SameName(SourceDocumentText, 'Purchase Order'):
                    WarehouseRequest.SetRange("Source Document", WarehouseRequest."Source Document"::"Purchase Order");
                Context.SameName(SourceDocumentText, 'Sales Return Order'):
                    WarehouseRequest.SetRange("Source Document", WarehouseRequest."Source Document"::"Sales Return Order");
                Context.SameName(SourceDocumentText, 'Inbound Transfer'):
                    WarehouseRequest.SetRange("Source Document", WarehouseRequest."Source Document"::"Inbound Transfer");
                else
                    Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(ValueLbl, 'sourceDocument', SourceDocumentText), 'sourceDocument', SourceDocumentText, 'Purchase Order, Sales Return Order, Inbound Transfer', ValueNextStepLbl);
            end;
        if SourceNos.Count() > 0 then
            WarehouseRequest.SetFilter("Source No.", Context.LiteralFilter(SourceNos));
        if VendorNo <> '' then begin
            WarehouseRequest.SetRange("Destination Type", WarehouseRequest."Destination Type"::Vendor);
            WarehouseRequest.SetRange("Destination No.", CopyStr(UpperCase(VendorNo), 1, MaxStrLen(WarehouseRequest."Destination No.")));
        end;
        if (DateFrom <> 0D) and (DateTo <> 0D) and (DateTo < DateFrom) then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, 'expectedReceiptDateFrom'), 'expectedReceiptDateTo', Context.FormatDate(DateTo), '', Context.DateRangeNextStep());
        if (DateFrom <> 0D) or (DateTo <> 0D) then
            WarehouseRequest.SetRange("Expected Receipt Date", DateFrom, Context.RangeEnd(DateTo));
        // The refusal "no released request matches" names the filters that were sent (#71).
        FilterKeys := '';
        AddFilterKey(FilterKeys, SourceDocumentText <> '', 'sourceDocument');
        AddFilterKey(FilterKeys, SourceNos.Count() > 0, 'sourceNos');
        AddFilterKey(FilterKeys, VendorNo <> '', 'vendorNo');
        AddFilterKey(FilterKeys, DateFrom <> 0D, 'expectedReceiptDateFrom');
        AddFilterKey(FilterKeys, DateTo <> 0D, 'expectedReceiptDateTo');
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
        ReleaseNextStepLbl: Label 'Release the source documents first; read Warehouse.Request.Get.', Comment = 'is-IS=Gefðu upprunaskjölin út fyrst; lestu Warehouse.Request.Get.';
        OtherLocationLbl: Label 'Source document %1 is at location %2, not at the receipt location %3.', Comment = '%1 = source no., %2 = source location, %3 = receipt location, is-IS=Upprunaskjal %1 er á staðsetningu %2, ekki á staðsetningu móttökunnar %3.';
        SameLocationNextStepLbl: Label 'Use a receipt at the same location.', Comment = 'is-IS=Notaðu móttöku á sömu staðsetningu.';
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

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; var WarehouseRequest: Record "Warehouse Request"; ReceiptNo: Code[20]; LocationCode: Code[10]; Created: Boolean; SnapshotLineNo: Integer)
    var
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
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
        if ReceiptNo <> '' then begin
            ReceiptLine.SetLoadFields("No.", "Line No.", "Source Document", "Source No.");
            ReceiptLine.SetRange("No.", ReceiptNo);
            ReceiptLine.SetFilter("Line No.", '>%1', SnapshotLineNo);
            if ReceiptLine.FindSet() then
                repeat
                    RecordReference.GetTable(ReceiptLine);
                    KeyText := Context.EnumValueName(RecordReference, ReceiptLine.FieldNo("Source Document")) + '|' + ReceiptLine."Source No.";
                    if not Counts.ContainsKey(KeyText) then begin
                        KeyOrder.Add(KeyText);
                        Counts.Add(KeyText, 0);
                        Names.Add(KeyText, Context.EnumValueName(RecordReference, ReceiptLine.FieldNo("Source Document")));
                        Numbers.Add(KeyText, ReceiptLine."Source No.");
                    end;
                    Counts.Set(KeyText, Counts.Get(KeyText) + 1);
                    LinesAdded += 1;
                until ReceiptLine.Next() = 0;
        end;
        foreach KeyText in KeyOrder do begin
            Clear(DocumentJson);
            DocumentJson.Add('sourceDocument', Names.Get(KeyText));
            DocumentJson.Add('sourceNo', Numbers.Get(KeyText));
            DocumentJson.Add('linesAdded', Counts.Get(KeyText));
            SourceDocuments.Add(DocumentJson);
        end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('receiptNo', ReceiptNo);
        if (ReceiptNo <> '') and ReceiptHeader.Get(ReceiptNo) then
            ResponseJson.Add('receiptSystemId', Format(ReceiptHeader.SystemId, 0, 4))
        else
            ResponseJson.Add('receiptSystemId', '');
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('created', Created and (ReceiptNo <> ''));
        ResponseJson.Add('linesAdded', LinesAdded);
        ResponseJson.Add('sourceDocuments', SourceDocuments);
        ResponseJson.Add('skipped', SkippedLines(WarehouseRequest, ReceiptNo, SnapshotLineNo));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure SkippedLines(var WarehouseRequest: Record "Warehouse Request"; ReceiptNo: Code[20]; SnapshotLineNo: Integer) Skipped: JsonArray
    var
        OtherLine: Record "Warehouse Receipt Line";
        AddedLine: Record "Warehouse Receipt Line";
        Context: Codeunit "Whse Write Context ori";
        RecordReference: RecordRef;
        SkippedJson: JsonObject;
    begin
        // A source line that is already on another receipt is not added again by the report. List each such
        // line unless the run still added its remaining quantity to this receipt.
        WarehouseRequest.SetLoadFields("Source Type", "Source Subtype", "Source No.");
        if not WarehouseRequest.FindSet() then
            exit;
        repeat
            OtherLine.SetLoadFields("No.", "Source Document", "Source No.", "Source Line No.", "Item No.");
            OtherLine.SetRange("Source Type", WarehouseRequest."Source Type");
            OtherLine.SetRange("Source Subtype", WarehouseRequest."Source Subtype");
            OtherLine.SetRange("Source No.", WarehouseRequest."Source No.");
            OtherLine.SetFilter("No.", '<>%1', ReceiptNo);
            if OtherLine.FindSet() then
                repeat
                    AddedLine.SetRange("No.", ReceiptNo);
                    AddedLine.SetFilter("Line No.", '>%1', SnapshotLineNo);
                    AddedLine.SetRange("Source Type", WarehouseRequest."Source Type");
                    AddedLine.SetRange("Source Subtype", WarehouseRequest."Source Subtype");
                    AddedLine.SetRange("Source No.", WarehouseRequest."Source No.");
                    AddedLine.SetRange("Source Line No.", OtherLine."Source Line No.");
                    if (ReceiptNo = '') or AddedLine.IsEmpty() then begin
                        RecordReference.GetTable(OtherLine);
                        Clear(SkippedJson);
                        SkippedJson.Add('sourceDocument', Context.EnumValueName(RecordReference, OtherLine.FieldNo("Source Document")));
                        SkippedJson.Add('sourceNo', OtherLine."Source No.");
                        SkippedJson.Add('sourceLineNo', OtherLine."Source Line No.");
                        SkippedJson.Add('itemNo', OtherLine."Item No.");
                        SkippedJson.Add('otherReceiptNo', OtherLine."No.");
                        Skipped.Add(SkippedJson);
                    end;
                until OtherLine.Next() = 0;
        until WarehouseRequest.Next() = 0;
    end;

    local procedure LastLineNo(ReceiptNo: Code[20]): Integer
    var
        ReceiptLine: Record "Warehouse Receipt Line";
    begin
        ReceiptLine.SetLoadFields("No.", "Line No.");
        ReceiptLine.SetRange("No.", ReceiptNo);
        if ReceiptLine.FindLast() then
            exit(ReceiptLine."Line No.");
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
            if not (KeyName in ['receiptNo', 'systemId', 'locationCode', 'sourceDocument', 'sourceNos', 'vendorNo', 'expectedReceiptDateFrom', 'expectedReceiptDateTo']) then
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
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptLine: Record "Warehouse Receipt Line";
        WarehouseRequest: Record "Warehouse Request";
    begin
        exit(ReceiptHeader.WritePermission() and ReceiptLine.WritePermission() and WarehouseRequest.ReadPermission());
    end;
}
