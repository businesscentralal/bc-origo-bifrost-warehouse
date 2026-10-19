namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Tracking;
using Microsoft.Inventory.Transfer;
using Microsoft.Purchases.History;
using Microsoft.Sales.History;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.InventoryPutAway.Post.
/// Posting runs inside an isolated run, which commits. A quantity above outstanding, a bad bin or missing lot or serial is refused before anything is posted.
/// </summary>
codeunit 10078426 "Whse InvtPut Post Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The inventory put-away post payload was empty.', Comment = 'is-IS=Gögnin til að bóka birgðafrágang voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        PostPutaway(Payload, Result);
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can write the documents and holds the warehouse posting gate.</summary>
    /// <returns>True when the caller can write the activity tables and holds BIFROST WhsePost ori.</returns>
    procedure IsEnabled(): Boolean
    var
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
    begin
        if not HasWritePermission() then
            exit(false);
        exit(WhsePostingGate.HasPostingPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse activity line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Activity Line");
    end;

    /// <summary>Returns a short description of Warehouse.InventoryPutAway.Post.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Posts an inventory put-away and receives the source document.', Comment = 'is-IS=Bókar birgðafrágang og móttekur upprunaskjalið.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'post inventory put-away, receive inventory put-away, inventory put-away post, post source document, invoice inventory put-away, basic warehouse', Comment = 'is-IS=bóka birgðafrágang, móttaka birgðafrágangs, bókun birgðafrágangs, bóka upprunaskjal, reikningsfæra birgðafrágang, einfalt vöruhús';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Posts the inventory put-away and the source document receipt. invoice true also invoices a purchase order.', Comment = 'is-IS=Óafturkræft. Bókar birgðafráganginn og móttöku upprunaskjalsins. invoice true reikningsfærir einnig innkaupapöntun.';
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
        Forms.Add('system id');
        Forms.Add('put-away no.');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A SystemId or inventory put-away number. Do not send a different put-away in subject and in putawayNo or systemId.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'system id or put-away no.', 'The inventory put-away to post.'));
        Target.Add(ContractMgt.TargetEntry('data.putawayNo, data.no', 'put-away no.', 'The inventory put-away number.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId, data.id, data.recordSystemId', 'guid', 'The inventory put-away SystemId.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('putawayNo', 'string', false, 'Inventory put-away number. Required when systemId and subject are empty.'));
        Parameters.Add(ContractMgt.Parameter('no', 'string', false, 'Inventory put-away number. Same as putawayNo.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'Inventory put-away SystemId.'));
        Parameters.Add(ContractMgt.Parameter('id', 'string', false, 'Inventory put-away SystemId. Same as systemId.'));
        Parameters.Add(ContractMgt.Parameter('recordSystemId', 'string', false, 'Inventory put-away SystemId. Same as systemId.'));
        Parameters.Add(ContractMgt.Parameter('invoice', 'boolean', false, 'Receive and invoice a purchase order. Default false. Refused for every other source. Requires BIFROST WhseInv ori when true.'));
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Optional per-line quantity and bin. Omitted lines keep the quantity and bin already on the put-away.'));
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Inventory put-away line number.'));
        Parameters.Add(ContractMgt.Parameter('qtyToHandle', 'number', true, 'Quantity to handle on the line, in the line unit of measure.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', false, 'Bin to put the line into. Omitted lines keep the bin already on the put-away.'));
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
        Fields.Add(ContractMgt.ResponseField('putawayNo', 'string', 'Inventory put-away number that was posted.'));
        Fields.Add(ContractMgt.ResponseField('postedPutawayNo', 'string', 'Posted inventory put-away number.'));
        Fields.Add(ContractMgt.ResponseField('sourceDocument', 'string', 'Source document type.'));
        Fields.Add(ContractMgt.ResponseField('sourceNo', 'string', 'Source document number.'));
        Fields.Add(ContractMgt.ResponseField('postedDocumentNo', 'string', 'Posted receipt, return receipt or transfer receipt number.'));
        Fields.Add(ContractMgt.ResponseField('postedInvoiceNo', 'string', 'Posted purchase invoice number when invoice was true. Otherwise empty.'));
        Fields.Add(ContractMgt.ResponseField('invoice', 'boolean', 'True when the purchase order was invoiced.'));
        Fields.Add(ContractMgt.ResponseField('postedQuantity', 'number', 'Posted quantity across the put-away lines.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Posted line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin the quantity was put away into.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Posted quantity.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Posted inventory put-away lines.');
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
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidLine, 'qtyToHandle exceeds the outstanding quantity.', 'Lower qtyToHandle to the outstanding quantity.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidLine, 'binCode is not a bin at the location, or the bin is blocked for inbound movement.', 'Read Warehouse.Bin.Get for valid bins.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidLine, 'A tracked item line has no lot or serial number.', 'Send the lot or serial number on that line before posting.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The activity is not an inventory put-away, or there is nothing to post.', 'Send an inventory put-away with a quantity to handle. Use Warehouse.Putaway.Register for a warehouse put-away.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'putawayNo or systemId is missing.', 'Send putawayNo or systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes, numbers for quantities and true or false for invoice.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'invoice is true for a source that is not a purchase order, a bin is not valid, or a quantity is negative.', 'Send invoice false, or post a purchase order. Send qtyToHandle as zero or greater.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The inventory put-away or line was not found.', 'Check the put-away number with Warehouse.InventoryPutAway.Create.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject, putawayNo and systemId name different put-aways.', 'Send one put-away: subject, putawayNo or systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write the warehouse documents, or does not hold the warehouse posting gate (or the invoicing gate when invoice is true).', 'Ask an administrator to assign BIFROST Whse - Full ori and BIFROST WhsePost ori, plus BIFROST WhseInv ori for invoice true.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one line failed validation.', 'Correct every listed line and send the request again. Nothing was written.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the post.', 'Read the returned text and correct the put-away or the inventory.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Posts the inventory put-away and the source document receipt. Business Central commits the post. invoice true also posts the purchase invoice.', 'BIFROST Whse - Full ori and BIFROST WhsePost ori; BIFROST WhseInv ori when invoice is true');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.InventoryPutAway.Create', 'Use it first when an inventory put-away does not exist.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Bin.Get', 'Use it to read bins before sending binCode.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>False. Inventory put-away post has no separate workflow chapter.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    begin
        exit(false);
    end;

    /// <summary>Returns an example request and response.</summary>
    /// <param name="Examples">Receives the examples.</param>
    /// <returns>True when an example is declared.</returns>
    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Post inventory put-away IPU00001 and receive the purchase order',
            '{"putawayNo":"IPU00001","invoice":false}',
            '{"status":"Success","putawayNo":"IPU00001","postedPutawayNo":"PPU00001","sourceDocument":"Purchase Order","sourceNo":"106001","postedDocumentNo":"107200","postedInvoiceNo":"","invoice":false,"postedQuantity":1,"lines":[{"lineNo":10000,"itemNo":"WRB-1000","binCode":"RECV","quantity":1}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Posts an inventory put-away and the source document receipt. Business Central commits the post. A line whose qtyToHandle is above the outstanding quantity, whose bin is missing or blocked, or whose tracked item has no lot or serial, writes nothing. invoice true receives and invoices a purchase order only.', Comment = 'is-IS=Bókar birgðafrágang og móttöku upprunaskjalsins. Business Central staðfestir bókunina. Líne sem hefur qtyToHandle umfram útistandandi magn, ógilt hólf eða rekjanlega vöru án lotu eða raðnúmers skrifar ekkert. invoice true móttekur og reikningsfærir aðeins innkaupapöntun.';
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

    /// <summary>Validates the request and posts the inventory put-away, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        RequestReader: Codeunit "Whse Write Context ori";
        Context: Codeunit "Whse Write Context ori";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        Lines: JsonArray;
        Invoice: Boolean;
        DeniedLbl: Label 'You do not have permission to post an inventory put-away.', Comment = 'is-IS=Þú hefur ekki heimild til að bóka birgðafrágang.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
    begin
        Context.Reset();
        if not HasWritePermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not RequestReader.ReadRequestObject(Argument, RequestJson) then
            exit;
        if Context.IsTrue(RequestJson, 'invoice') then
            if not WhsePostingGate.AssertCanInvoice(Argument) then
                exit;
        RefuseUnknownKeys(RequestJson, Argument);
        if not Argument.HasCollectedErrors() then
            ResolvePutaway(RequestJson, Argument, ActivityHeader);
        if not Argument.HasCollectedErrors() then
            ReadInvoice(RequestJson, Argument, ActivityHeader, Invoice);
        if not Argument.HasCollectedErrors() then
            ReadLines(RequestJson, Argument, ActivityHeader, Lines);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('putawayNo', ActivityHeader."No.");
        Payload.Add('invoice', Invoice);
        Payload.Add('lines', Lines);
        Context.SetPayload(Payload);
        if not Codeunit.Run(Codeunit::"Whse InvtPut Post Impl ori") then begin
            Context.Reset();
            Argument.RespondWithLastError();
            exit;
        end;
        WritePosted(Argument);
        Context.Reset();
    end;

    local procedure WritePosted(var Argument: Record "Message Argument ori")
    var
        Context: Codeunit "Whse Write Context ori";
        Result: JsonObject;
        ResponseJson: JsonObject;
        MissingResultErr: Label 'The inventory put-away was posted but its result was not returned.', Comment = 'is-IS=Birgðafrágangurinn var bókaður en niðurstaðan skilaði sér ekki.';
        MissingResultNextStepLbl: Label 'Read the returned text and correct the put-away or the inventory.', Comment = 'is-IS=Lestu textann sem skilaði sér og leiðréttu fráganginn eða birgðirnar.';
    begin
        if not Context.TryGetResult(Result) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'postedPutawayNo', '', '', MissingResultNextStepLbl);
            exit;
        end;
        ResponseJson.Add('status', 'Success');
        CopyToken(Result, ResponseJson, 'putawayNo');
        CopyToken(Result, ResponseJson, 'postedPutawayNo');
        CopyToken(Result, ResponseJson, 'sourceDocument');
        CopyToken(Result, ResponseJson, 'sourceNo');
        CopyToken(Result, ResponseJson, 'postedDocumentNo');
        CopyToken(Result, ResponseJson, 'postedInvoiceNo');
        CopyToken(Result, ResponseJson, 'invoice');
        CopyToken(Result, ResponseJson, 'postedQuantity');
        CopyToken(Result, ResponseJson, 'lines');
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ResolvePutaway(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var ActivityHeader: Record "Warehouse Activity Header")
    var
        Context: Codeunit "Whse Write Context ori";
        PickNoText: Text;
        NoText: Text;
        SystemIdText: Text;
        IdText: Text;
        RecordIdText: Text;
        SubjectText: Text;
        PickPresent: Boolean;
        NoPresent: Boolean;
        SystemPresent: Boolean;
        IdPresent: Boolean;
        RecordPresent: Boolean;
        ChosenNo: Text;
        ChosenId: Text;
    begin
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Context.ReadText(RequestJson, 'putawayNo', 20, Argument, PickNoText, PickPresent, 'putawayNo') then
            exit;
        if not Context.ReadText(RequestJson, 'no', 20, Argument, NoText, NoPresent, 'no') then
            exit;
        if not Context.ReadText(RequestJson, 'systemId', 50, Argument, SystemIdText, SystemPresent, 'systemId') then
            exit;
        if not Context.ReadText(RequestJson, 'id', 50, Argument, IdText, IdPresent, 'id') then
            exit;
        if not Context.ReadText(RequestJson, 'recordSystemId', 50, Argument, RecordIdText, RecordPresent, 'recordSystemId') then
            exit;
        if not ChooseText(Argument, 'putawayNo', PickNoText, PickPresent, NoText, NoPresent, ChosenNo) then
            exit;
        if not ChooseText(Argument, 'systemId', SystemIdText, SystemPresent, IdText, IdPresent, ChosenId) then
            exit;
        if not ChooseText(Argument, 'systemId', ChosenId, ChosenId <> '', RecordIdText, RecordPresent, ChosenId) then
            exit;
        ApplySubject(Argument, SubjectText, ChosenNo, ChosenId);
        if Argument.HasCollectedErrors() then
            exit;
        if (ChosenNo = '') and (ChosenId = '') then begin
            RequirePutaway(Argument);
            exit;
        end;
        LoadPutaway(Argument, ChosenNo, ChosenId, ActivityHeader);
    end;

    local procedure ChooseText(var Argument: Record "Message Argument ori"; ParameterName: Text; FirstText: Text; FirstPresent: Boolean; SecondText: Text; SecondPresent: Boolean; var Chosen: Text): Boolean
    var
        ConflictLbl: Label 'The identifiers name different inventory put-aways.', Comment = 'is-IS=Auðkennin nefna mismunandi birgðafráganga.';
        ConflictNextStepLbl: Label 'Send one put-away: subject, putawayNo or systemId.', Comment = 'is-IS=Sendu einn frágang: subject, putawayNo eða systemId.';
    begin
        if FirstPresent and SecondPresent and (UpperCase(DelChr(FirstText, '=', '{}')) <> UpperCase(DelChr(SecondText, '=', '{}'))) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, ParameterName, FirstText, SecondText, ConflictNextStepLbl);
            exit(false);
        end;
        if FirstPresent then
            Chosen := FirstText
        else
            if SecondPresent then
                Chosen := SecondText;
        exit(true);
    end;

    local procedure ApplySubject(var Argument: Record "Message Argument ori"; SubjectText: Text; var ChosenNo: Text; var ChosenId: Text)
    var
        SubjectId: Guid;
        SubjectIsGuid: Boolean;
        ConflictLbl: Label 'subject and putawayNo or systemId name different inventory put-aways.', Comment = 'is-IS=subject og putawayNo eða systemId nefna mismunandi birgðafráganga.';
        ConflictNextStepLbl: Label 'Send one put-away: subject, putawayNo or systemId.', Comment = 'is-IS=Sendu einn frágang: subject, putawayNo eða systemId.';
    begin
        if SubjectText = '' then
            exit;
        SubjectIsGuid := Evaluate(SubjectId, SubjectText);
        if SubjectIsGuid then begin
            if (ChosenId <> '') and (UpperCase(DelChr(ChosenId, '=', '{}')) <> UpperCase(DelChr(SubjectText, '=', '{}'))) then
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'systemId', ChosenId, SubjectText, ConflictNextStepLbl)
            else
                ChosenId := SubjectText;
            exit;
        end;
        if (ChosenNo <> '') and (UpperCase(ChosenNo) <> UpperCase(SubjectText)) then
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'putawayNo', ChosenNo, SubjectText, ConflictNextStepLbl)
        else
            ChosenNo := SubjectText;
    end;

    local procedure LoadPutaway(var Argument: Record "Message Argument ori"; ChosenNo: Text; ChosenId: Text; var ActivityHeader: Record "Warehouse Activity Header")
    var
        ById: Record "Warehouse Activity Header";
        SystemId: Guid;
        FoundByNo: Boolean;
        FoundById: Boolean;
        FormatLbl: Label 'systemId must be a GUID.', Comment = 'is-IS=systemId verður að vera GUID.';
        FormatNextStepLbl: Label 'Send text for codes, numbers for quantities and true or false for invoice.', Comment = 'is-IS=Sendu texta fyrir kóða, tölur fyrir magn og true eða false fyrir invoice.';
    begin
        if ChosenId <> '' then begin
            if not Evaluate(SystemId, ChosenId) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'systemId', CopyStr(ChosenId, 1, 80), 'guid', FormatNextStepLbl);
                exit;
            end;
            FoundById := ById.GetBySystemId(SystemId);
            if not FoundById then begin
                NotFound(Argument, ChosenId);
                exit;
            end;
            if ById.Type <> ById.Type::"Invt. Put-away" then begin
                RefuseNotInventoryPutAway(Argument, ById."No.");
                exit;
            end;
        end;
        if ChosenNo <> '' then begin
            FoundByNo := ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", CopyStr(ChosenNo, 1, MaxStrLen(ActivityHeader."No.")));
            if not FoundByNo then begin
                NotFound(Argument, ChosenNo);
                exit;
            end;
        end;
        if FoundById and FoundByNo and (ActivityHeader.SystemId <> ById.SystemId) then begin
            Conflict(Argument, ChosenNo, ChosenId);
            exit;
        end;
        if FoundById and not FoundByNo then
            ActivityHeader := ById;
    end;

    local procedure ReadInvoice(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; var Invoice: Boolean)
    var
        Context: Codeunit "Whse Write Context ori";
        Present: Boolean;
        InvoiceLbl: Label 'invoice is supported only for a purchase order.', Comment = 'is-IS=invoice er aðeins stutt fyrir innkaupapöntun.';
        InvoiceNextStepLbl: Label 'Send invoice as false, or invoice the purchase order after the receipt.', Comment = 'is-IS=Sendu invoice sem false, eða reikningsfærðu innkaupapöntunina eftir móttöku.';
    begin
        Invoice := false;
        if not Context.ReadBoolean(RequestJson, 'invoice', Argument, Invoice, Present, 'invoice') then
            exit;
        if not Present then
            Invoice := false;
        if Invoice and (ActivityHeader."Source Document" <> ActivityHeader."Source Document"::"Purchase Order") then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, InvoiceLbl, 'invoice', 'true', 'false', InvoiceNextStepLbl);
    end;

    local procedure ReadLines(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; var Planned: JsonArray)
    var
        Token: JsonToken;
        Lines: JsonArray;
        Index: Integer;
        Total: Decimal;
        FormatLbl: Label 'lines must be an array of line objects.', Comment = 'is-IS=lines verður að vera fylki línuhluta.';
        FormatNextStepLbl: Label 'Send text for codes, numbers for quantities and true or false for invoice.', Comment = 'is-IS=Sendu texta fyrir kóða, tölur fyrir magn og true eða false fyrir invoice.';
        NothingLbl: Label 'There is no quantity to post.', Comment = 'is-IS=Ekkert magn er til að bóka.';
        NothingNextStepLbl: Label 'Send qtyToHandle greater than zero on a line that still has quantity outstanding.', Comment = 'is-IS=Sendu qtyToHandle stærra en núll á línu sem á enn útistandandi magn.';
    begin
        Clear(Planned);
        if not RequestJson.Get('lines', Token) then begin
            Total := SumCurrentQtyToHandle(ActivityHeader);
            if Total <= 0 then
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NothingLbl, 'lines', '', '', NothingNextStepLbl)
            else
                RefuseTrackingOnOpenLines(Argument, ActivityHeader, Planned);
            exit;
        end;
        if not Token.IsArray() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'lines', '', 'array', FormatNextStepLbl);
            exit;
        end;
        Lines := Token.AsArray();
        for Index := 0 to Lines.Count() - 1 do begin
            Lines.Get(Index, Token);
            ReadOneLine(Token, Index, Argument, ActivityHeader, Planned);
        end;
        if Argument.HasCollectedErrors() then
            exit;
        Total := SumPlanned(ActivityHeader, Planned);
        if Total <= 0 then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NothingLbl, 'lines', '', '', NothingNextStepLbl)
        else
            RefuseTrackingOnOpenLines(Argument, ActivityHeader, Planned);
    end;

    local procedure ReadOneLine(Token: JsonToken; Index: Integer; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; var Planned: JsonArray)
    var
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        LineObject: JsonObject;
        PlannedLine: JsonObject;
        LineNo: Integer;
        Quantity: Decimal;
        BinText: Text;
        LinePresent: Boolean;
        QuantityPresent: Boolean;
        BinPresent: Boolean;
        FormatLbl: Label 'Each line must be an object.', Comment = 'is-IS=Hver lína verður að vera hlutur.';
        FormatNextStepLbl: Label 'Send text for codes, numbers for quantities and true or false for invoice.', Comment = 'is-IS=Sendu texta fyrir kóða, tölur fyrir magn og true eða false fyrir invoice.';
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line index, %2 = field, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send lineNo and qtyToHandle on every line.', Comment = 'is-IS=Sendu lineNo og qtyToHandle á hverri línu.';
        NegativeLbl: Label 'qtyToHandle must be zero or greater.', Comment = 'is-IS=qtyToHandle verður að vera núll eða stærra.';
        NegativeNextStepLbl: Label 'Send qtyToHandle as zero or greater.', Comment = 'is-IS=Sendu qtyToHandle sem núll eða stærra.';
    begin
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, LineParameter(Index, 'lineNo'), '', 'object', FormatNextStepLbl);
            exit;
        end;
        LineObject := Token.AsObject();
        RefuseUnknownLineKeys(LineObject, Index, Argument);
        Context.ReadInteger(LineObject, 'lineNo', Argument, LineNo, LinePresent, LineParameter(Index, 'lineNo'));
        Context.ReadDecimal(LineObject, 'qtyToHandle', Argument, Quantity, QuantityPresent, LineParameter(Index, 'qtyToHandle'));
        if not Context.ReadText(LineObject, 'binCode', 20, Argument, BinText, BinPresent, LineParameter(Index, 'binCode')) then
            exit;
        if not LinePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'lineNo'), LineParameter(Index, 'lineNo'), '', '', MissingNextStepLbl);
        if not QuantityPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'qtyToHandle'), LineParameter(Index, 'qtyToHandle'), '', '', MissingNextStepLbl);
        if not LinePresent or not QuantityPresent then
            exit;
        if Quantity < 0 then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, NegativeLbl, LineParameter(Index, 'qtyToHandle'), Format(Quantity), '', NegativeNextStepLbl);
            exit;
        end;
        if not ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", LineNo) then begin
            LineNotFound(Argument, Index, LineNo);
            exit;
        end;
        if Quantity > ActivityLine."Qty. Outstanding" then begin
            RefuseQuantity(Argument, Index, Quantity);
            exit;
        end;
        if BinPresent and RefuseInvalidBin(Argument, ActivityLine, Index, BinText) then
            exit;
        if Quantity > 0 then
            if RefuseMissingTracking(Argument, ActivityHeader, ActivityLine, Index) then
                exit;
        PlannedLine.Add('lineNo', LineNo);
        PlannedLine.Add('qtyToHandle', Quantity);
        if BinPresent then
            PlannedLine.Add('binCode', BinText);
        Planned.Add(PlannedLine);
    end;

    local procedure RefuseTrackingOnOpenLines(var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; Planned: JsonArray)
    var
        ActivityLine: Record "Warehouse Activity Line";
        PlannedLineNos: List of [Integer];
        Token: JsonToken;
        LineToken: JsonToken;
    begin
        // Lines sent in the request were checked with their planned quantity; check the other open lines
        // that keep a quantity to handle, so a missing lot or serial is refused before Business Central posts.
        foreach Token in Planned do
            if Token.AsObject().Get('lineNo', LineToken) then
                PlannedLineNos.Add(LineToken.AsValue().AsInteger());
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if not ActivityLine.FindSet() then
            exit;
        repeat
            if (ActivityLine."Qty. to Handle" <> 0) and not PlannedLineNos.Contains(ActivityLine."Line No.") then
                RefuseMissingTracking(Argument, ActivityHeader, ActivityLine, -1);
        until ActivityLine.Next() = 0;
    end;

    local procedure RefuseInvalidBin(var Argument: Record "Message Argument ori"; ActivityLine: Record "Warehouse Activity Line"; Index: Integer; BinText: Text): Boolean
    var
        Bin: Record Bin;
        BinCode: Code[20];
        BinLbl: Label 'Bin %1 is not at the location, or it is blocked for inbound movement.', Comment = '%1 = bin, is-IS=Hólf %1 er ekki á staðsetningunni, eða það er lokað fyrir innleiðslu.';
        BinNextStepLbl: Label 'Read Warehouse.Bin.Get for valid bins.', Comment = 'is-IS=Lestu Warehouse.Bin.Get fyrir gild hólf.';
    begin
        BinCode := CopyStr(BinText, 1, MaxStrLen(BinCode));
        Bin.SetLoadFields(Code, "Location Code", "Block Movement");
        Bin.SetRange("Location Code", ActivityLine."Location Code");
        Bin.SetRange(Code, BinCode);
        if not Bin.FindFirst() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(BinLbl, BinCode), LineParameter(Index, 'binCode'), BinCode, '', BinNextStepLbl);
            exit(true);
        end;
        if Bin."Block Movement" in [Bin."Block Movement"::Inbound, Bin."Block Movement"::All] then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(BinLbl, BinCode), LineParameter(Index, 'binCode'), BinCode, '', BinNextStepLbl);
            exit(true);
        end;
        exit(false);
    end;

    local procedure RefuseMissingTracking(var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; ActivityLine: Record "Warehouse Activity Line"; Index: Integer): Boolean
    var
        Item: Record Item;
        TrackingCode: Record "Item Tracking Code";
        NeedsLot: Boolean;
        NeedsSerial: Boolean;
        TrackingLbl: Label 'Line %1 is a tracked item and has no lot or serial number.', Comment = '%1 = line no., is-IS=Lína %1 er rekjanleg vara og hefur ekkert lotu- eða raðnúmer.';
        TrackingNextStepLbl: Label 'Send the lot or serial number on line %1 before posting.', Comment = '%1 = line no., is-IS=Sendu lotu- eða raðnúmer á línu %1 áður en bókað er.';
    begin
        if ActivityLine."Item No." = '' then
            exit(false);
        Item.SetLoadFields("No.", "Item Tracking Code");
        if not Item.Get(ActivityLine."Item No.") then
            exit(false);
        if Item."Item Tracking Code" = '' then
            exit(false);
        TrackingCode.SetLoadFields(Code, "Lot Specific Tracking", "SN Specific Tracking", "Lot Purchase Inbound Tracking", "SN Purchase Inbound Tracking", "Lot Sales Inbound Tracking", "SN Sales Inbound Tracking", "Lot Transfer Tracking", "SN Transfer Tracking");
        if not TrackingCode.Get(Item."Item Tracking Code") then
            exit(false);
        case ActivityHeader."Source Document" of
            ActivityHeader."Source Document"::"Purchase Order":
                begin
                    NeedsLot := TrackingCode."Lot Purchase Inbound Tracking" or TrackingCode."Lot Specific Tracking";
                    NeedsSerial := TrackingCode."SN Purchase Inbound Tracking" or TrackingCode."SN Specific Tracking";
                end;
            ActivityHeader."Source Document"::"Sales Return Order":
                begin
                    NeedsLot := TrackingCode."Lot Sales Inbound Tracking" or TrackingCode."Lot Specific Tracking";
                    NeedsSerial := TrackingCode."SN Sales Inbound Tracking" or TrackingCode."SN Specific Tracking";
                end;
            ActivityHeader."Source Document"::"Inbound Transfer":
                begin
                    NeedsLot := TrackingCode."Lot Transfer Tracking" or TrackingCode."Lot Specific Tracking";
                    NeedsSerial := TrackingCode."SN Transfer Tracking" or TrackingCode."SN Specific Tracking";
                end;
        end;
        if NeedsLot and (ActivityLine."Lot No." = '') then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(TrackingLbl, ActivityLine."Line No."), TrackingParameter(Index), Format(ActivityLine."Line No."), '', StrSubstNo(TrackingNextStepLbl, ActivityLine."Line No."));
            exit(true);
        end;
        if NeedsSerial and (ActivityLine."Serial No." = '') then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(TrackingLbl, ActivityLine."Line No."), TrackingParameter(Index), Format(ActivityLine."Line No."), '', StrSubstNo(TrackingNextStepLbl, ActivityLine."Line No."));
            exit(true);
        end;
        exit(false);
    end;

    local procedure SumCurrentQtyToHandle(ActivityHeader: Record "Warehouse Activity Header"): Decimal
    var
        ActivityLine: Record "Warehouse Activity Line";
        Total: Decimal;
    begin
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if ActivityLine.FindSet() then
            repeat
                Total += ActivityLine."Qty. to Handle";
            until ActivityLine.Next() = 0;
        exit(Total);
    end;

    local procedure SumPlanned(ActivityHeader: Record "Warehouse Activity Header"; Planned: JsonArray): Decimal
    var
        ActivityLine: Record "Warehouse Activity Line";
        Token: JsonToken;
        LineObject: JsonObject;
        Total: Decimal;
        LineNo: Integer;
        PlannedQty: Decimal;
        Replaced: Boolean;
    begin
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if not ActivityLine.FindSet() then
            exit(0);
        repeat
            Replaced := false;
            foreach Token in Planned do begin
                LineObject := Token.AsObject();
                LineNo := IntegerValue(LineObject, 'lineNo');
                if LineNo = ActivityLine."Line No." then begin
                    PlannedQty := DecimalValue(LineObject, 'qtyToHandle');
                    Total += PlannedQty;
                    Replaced := true;
                end;
            end;
            if not Replaced then
                Total += ActivityLine."Qty. to Handle";
        until ActivityLine.Next() = 0;
        exit(Total);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['putawayNo', 'no', 'systemId', 'id', 'recordSystemId', 'invoice', 'lines']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure RefuseUnknownLineKeys(LineObject: JsonObject; Index: Integer; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in LineObject.Keys() do
            if not (KeyName in ['lineNo', 'qtyToHandle', 'binCode']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), LineParameter(Index, KeyName), KeyName, '', UnknownNextStepLbl);
    end;

    local procedure RequirePutaway(var Argument: Record "Message Argument ori")
    var
        MissingLbl: Label 'putawayNo or systemId is required.', Comment = 'is-IS=putawayNo eða systemId er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send putawayNo or systemId.', Comment = 'is-IS=Sendu putawayNo eða systemId.';
    begin
        Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'putawayNo', '', '', MissingNextStepLbl);
    end;

    local procedure NotFound(var Argument: Record "Message Argument ori"; Received: Text)
    var
        NotFoundLbl: Label 'The inventory put-away was not found.', Comment = 'is-IS=Birgðafrágangurinn fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the put-away number with Warehouse.InventoryPutAway.Create.', Comment = 'is-IS=Athugaðu frágangsnúmerið með Warehouse.InventoryPutAway.Create.';
    begin
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, NotFoundLbl, 'putawayNo', CopyStr(Received, 1, 80), '', NotFoundNextStepLbl);
    end;

    local procedure LineNotFound(var Argument: Record "Message Argument ori"; Index: Integer; LineNo: Integer)
    var
        NotFoundLbl: Label 'Inventory put-away line %1 was not found.', Comment = '%1 = line no., is-IS=Lína %1 í birgðafrágangi fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the put-away number with Warehouse.InventoryPutAway.Create.', Comment = 'is-IS=Athugaðu frágangsnúmerið með Warehouse.InventoryPutAway.Create.';
    begin
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LineNo), LineParameter(Index, 'lineNo'), Format(LineNo), '', NotFoundNextStepLbl);
    end;

    local procedure Conflict(var Argument: Record "Message Argument ori"; ChosenNo: Text; ChosenId: Text)
    var
        ConflictLbl: Label 'putawayNo and systemId name different inventory put-aways.', Comment = 'is-IS=putawayNo og systemId nefna mismunandi birgðafráganga.';
        ConflictNextStepLbl: Label 'Send one put-away: subject, putawayNo or systemId.', Comment = 'is-IS=Sendu einn frágang: subject, putawayNo eða systemId.';
    begin
        Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'putawayNo', ChosenNo, ChosenId, ConflictNextStepLbl);
    end;

    local procedure RefuseNotInventoryPutAway(var Argument: Record "Message Argument ori"; PickNo: Code[20])
    var
        NotPutAwayLbl: Label 'The activity is not an inventory put-away.', Comment = 'is-IS=Aðgerðin er ekki birgðafrágangur.';
        NotPutAwayNextStepLbl: Label 'Send an inventory put-away with a quantity to handle. Use Warehouse.Putaway.Register for a warehouse put-away.', Comment = 'is-IS=Sendu birgðafrágang með magni til meðferðar. Notaðu Warehouse.Putaway.Register fyrir vöruhúsafrágang.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NotPutAwayLbl, 'systemId', PickNo, '', NotPutAwayNextStepLbl);
    end;

    local procedure RefuseQuantity(var Argument: Record "Message Argument ori"; Index: Integer; Quantity: Decimal)
    var
        ShortLbl: Label 'qtyToHandle exceeds the outstanding quantity.', Comment = 'is-IS=qtyToHandle er umfram útistandandi magn.';
        ShortNextStepLbl: Label 'Lower qtyToHandle to the outstanding quantity.', Comment = 'is-IS=Lækkaðu qtyToHandle niður í útistandandi magn.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidLine, ShortLbl, LineParameter(Index, 'qtyToHandle'), Format(Quantity), '', ShortNextStepLbl);
    end;

    local procedure LineParameter(Index: Integer; KeyName: Text): Text
    var
        LineParameterLbl: Label 'lines[%1].%2', Locked = true;
    begin
        exit(StrSubstNo(LineParameterLbl, Index, KeyName));
    end;

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;

    local procedure CopyToken(SourceJson: JsonObject; var TargetJson: JsonObject; KeyName: Text)
    var
        Token: JsonToken;
    begin
        if SourceJson.Get(KeyName, Token) then
            TargetJson.Add(KeyName, Token);
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;

    local procedure PostPutaway(Payload: JsonObject; var Result: JsonObject)
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        WhseActivityPost: Codeunit "Whse.-Activity-Post";
        PickNo: Code[20];
        Invoice: Boolean;
        NothingToPostErr: Label 'There is no quantity to post.', Comment = 'is-IS=Ekkert magn er til að bóka.';
    begin
        PickNo := CopyStr(TextValue(Payload, 'putawayNo'), 1, MaxStrLen(PickNo));
        Invoice := BooleanValue(Payload, 'invoice');
        ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PickNo);
        ApplyQuantities(ActivityHeader, Payload);
        if not FindLineToPost(ActivityHeader, ActivityLine) then
            Error(NothingToPostErr);
        WhseActivityPost.ShowHideDialog(true);
        WhseActivityPost.SetInvoiceSourceDoc(Invoice);
        WhseActivityPost.Run(ActivityLine);
        WritePostedInRun(ActivityHeader, Invoice, Result);
    end;

    local procedure FindLineToPost(ActivityHeader: Record "Warehouse Activity Header"; var ActivityLine: Record "Warehouse Activity Line"): Boolean
    begin
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if not ActivityLine.FindSet() then
            exit(false);
        repeat
            if ActivityLine."Qty. to Handle" <> 0 then
                exit(true);
        until ActivityLine.Next() = 0;
        exit(false);
    end;

    local procedure ApplyQuantities(ActivityHeader: Record "Warehouse Activity Header"; Payload: JsonObject)
    var
        ActivityLine: Record "Warehouse Activity Line";
        Token: JsonToken;
        Lines: JsonArray;
        LineObject: JsonObject;
        LineNo: Integer;
        Quantity: Decimal;
    begin
        if not Payload.Get('lines', Token) then
            exit;
        if not Token.IsArray() then
            exit;
        Lines := Token.AsArray();
        foreach Token in Lines do begin
            LineObject := Token.AsObject();
            LineNo := IntegerValue(LineObject, 'lineNo');
            Quantity := DecimalValue(LineObject, 'qtyToHandle');
            ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", LineNo);
            ApplyBin(ActivityLine, LineObject);
            ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", LineNo);
            ActivityLine.Validate("Qty. to Handle", Quantity);
            ActivityLine.Modify(true);
        end;
    end;

    local procedure WritePostedInRun(ActivityHeader: Record "Warehouse Activity Header"; Invoice: Boolean; var Result: JsonObject)
    var
        PostedHeader: Record "Posted Invt. Put-away Header";
        Lines: JsonArray;
        PostedQuantity: Decimal;
        PostedDocumentNo: Code[20];
        PostedInvoiceNo: Code[20];
        MissingPostedErr: Label 'The inventory put-away was posted but the posted put-away was not found.', Comment = 'is-IS=Birgðafrágangurinn var bókaður en bókfærði frágangurinn fannst ekki.';
    begin
        PostedHeader.SetRange("Invt. Put-away No.", ActivityHeader."No.");
        if not PostedHeader.FindLast() then
            Error(MissingPostedErr);
        PostedDocumentNo := FindPostedDocumentNo(ActivityHeader);
        if Invoice then
            PostedInvoiceNo := FindPostedInvoiceNo(ActivityHeader);
        PostedQuantity := BuildPostedLines(PostedHeader, Lines);
        Result.Add('putawayNo', ActivityHeader."No.");
        Result.Add('postedPutawayNo', PostedHeader."No.");
        Result.Add('sourceDocument', ActivitySourceName(ActivityHeader."Source Document"));
        Result.Add('sourceNo', ActivityHeader."Source No.");
        Result.Add('postedDocumentNo', PostedDocumentNo);
        Result.Add('postedInvoiceNo', PostedInvoiceNo);
        Result.Add('invoice', Invoice);
        Result.Add('postedQuantity', PostedQuantity);
        Result.Add('lines', Lines);
    end;

    local procedure BuildPostedLines(PostedHeader: Record "Posted Invt. Put-away Header"; var Lines: JsonArray): Decimal
    var
        PostedLine: Record "Posted Invt. Put-away Line";
        LineJson: JsonObject;
        PostedQuantity: Decimal;
    begin
        Clear(Lines);
        PostedLine.SetRange("No.", PostedHeader."No.");
        if not PostedLine.FindSet() then
            exit(0);
        repeat
            Clear(LineJson);
            LineJson.Add('lineNo', PostedLine."Line No.");
            LineJson.Add('itemNo', PostedLine."Item No.");
            LineJson.Add('binCode', PostedLine."Bin Code");
            LineJson.Add('quantity', PostedLine.Quantity);
            Lines.Add(LineJson);
            PostedQuantity += PostedLine.Quantity;
        until PostedLine.Next() = 0;
        exit(PostedQuantity);
    end;

    local procedure ApplyBin(ActivityLine: Record "Warehouse Activity Line"; LineObject: JsonObject)
    var
        BinCode: Code[20];
    begin
        BinCode := CopyStr(TextValue(LineObject, 'binCode'), 1, MaxStrLen(BinCode));
        if BinCode = '' then
            exit;
        if ActivityLine."Bin Code" = BinCode then
            exit;
        ActivityLine.Validate("Bin Code", BinCode);
        ActivityLine.Modify(true);
    end;

    local procedure FindPostedDocumentNo(ActivityHeader: Record "Warehouse Activity Header"): Code[20]
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ReturnReceiptHeader: Record "Return Receipt Header";
        TransferReceiptHeader: Record "Transfer Receipt Header";
    begin
        case ActivityHeader."Source Document" of
            ActivityHeader."Source Document"::"Purchase Order":
                begin
                    PurchRcptHeader.SetRange("Order No.", ActivityHeader."Source No.");
                    if PurchRcptHeader.FindLast() then
                        exit(PurchRcptHeader."No.");
                end;
            ActivityHeader."Source Document"::"Sales Return Order":
                begin
                    ReturnReceiptHeader.SetRange("Return Order No.", ActivityHeader."Source No.");
                    if ReturnReceiptHeader.FindLast() then
                        exit(ReturnReceiptHeader."No.");
                end;
            ActivityHeader."Source Document"::"Inbound Transfer":
                begin
                    TransferReceiptHeader.SetRange("Transfer Order No.", ActivityHeader."Source No.");
                    if TransferReceiptHeader.FindLast() then
                        exit(TransferReceiptHeader."No.");
                end;
        end;
        exit('');
    end;

    local procedure FindPostedInvoiceNo(ActivityHeader: Record "Warehouse Activity Header"): Code[20]
    var
        PurchInvHeader: Record "Purch. Inv. Header";
    begin
        if ActivityHeader."Source Document" <> ActivityHeader."Source Document"::"Purchase Order" then
            exit('');
        PurchInvHeader.SetRange("Order No.", ActivityHeader."Source No.");
        if PurchInvHeader.FindLast() then
            exit(PurchInvHeader."No.");
        exit('');
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

    local procedure BooleanValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;

    local procedure HasWritePermission(): Boolean
    var
        ActivityLine: Record "Warehouse Activity Line";
        PostedHeader: Record "Posted Invt. Put-away Header";
    begin
        exit(ActivityLine.WritePermission() and PostedHeader.WritePermission());
    end;

    local procedure TrackingParameter(Index: Integer): Text
    begin
        // Index -1 marks an open line that the request did not list.
        if Index < 0 then
            exit('lineNo');
        exit(LineParameter(Index, 'lineNo'));
    end;

    local procedure ActivitySourceName(SourceDocument: Enum "Warehouse Activity Source Document"): Text
    begin
        // The enum name, not its translated caption, so the answer matches the Create type.
        exit(SourceDocument.Names().Get(SourceDocument.Ordinals().IndexOf(SourceDocument.AsInteger())));
    end;
}
