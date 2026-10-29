namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Inventory.Transfer;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.InventoryPutAway.Create.
/// Report 7323 creates the inventory put-away and commits it.
/// A location that uses receipts is refused so this type does not create a warehouse put-away.
/// </summary>
codeunit 10078425 "Whse InvtPut Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The inventory put-away create payload was empty.', Comment = 'is-IS=Gögnin til að stofna birgðafrágang voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        CreatePutaways(Payload, Result);
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can create an inventory put-away.</summary>
    /// <returns>True when the caller can write the activity the report creates.</returns>
    procedure IsEnabled(): Boolean
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        WarehouseRequest: Record "Warehouse Request";
        Location: Record Location;
    begin
        exit(ActivityHeader.WritePermission() and ActivityLine.WritePermission() and WarehouseRequest.ReadPermission() and Location.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse activity header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Activity Header");
    end;

    /// <summary>Returns a short description of Warehouse.InventoryPutAway.Create.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates an inventory put-away from a released inbound source document at a basic location that requires put-away.', Comment = 'is-IS=Stofnar birgðafrágang úr staðfestu innleiðsluupprunaskjali á einfaldri staðsetningu sem krefst frágangs.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'create inventory put-away, inventory put-away, put away purchase order, basic warehouse put-away, require put-away, source document', Comment = 'is-IS=stofna birgðafrágang, birgðafrágangur, frágangur úr innkaupapöntun, einfaldur vöruhúsafrágangur, krefst frágangs, upprunaskjal';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Business Central commits the inventory put-away it creates. Use Warehouse.Receipt.Create and Warehouse.Putaway.Create when the location uses warehouse receipts.', Comment = 'is-IS=Óafturkræft. Business Central staðfestir birgðafráganginn sem það stofnar. Notaðu Warehouse.Receipt.Create og Warehouse.Putaway.Create þegar staðsetningin notar vöruhúsamóttökur.';
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
        Forms.Add('document no.');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A SystemId or document number of the source document. Do not send a different document in subject and in sourceNo or systemId.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'system id or document no.', 'The inbound source document to put away.'));
        Target.Add(ContractMgt.TargetEntry('data.sourceNo', 'document no.', 'The source document number.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId', 'guid', 'The source document SystemId.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('sourceDocument', 'string', true, 'Purchase Order, Sales Return Order or Inbound Transfer.'));
        Parameters.Add(ContractMgt.Parameter('sourceNo', 'string', false, 'Source document number. Required when systemId and subject are empty.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'Source document SystemId. Required when sourceNo and subject are empty.'));
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
        PutawayFields: JsonArray;
        LineFields: JsonArray;
        WarningFields: JsonArray;
        Putaways: JsonObject;
        Lines: JsonObject;
        Warnings: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('sourceDocument', 'string', 'Source document type.'));
        Fields.Add(ContractMgt.ResponseField('sourceNo', 'string', 'Source document number.'));
        Fields.Add(ContractMgt.ResponseField('putawayCount', 'integer', 'Number of inventory put-aways returned.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Inventory put-away line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Suggested bin for the quantity. Empty when the location has no bins.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity on the line.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle.'));
        LineFields.Add(ContractMgt.ResponseField('qtyOutstanding', 'number', 'Quantity still outstanding.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Lines on the inventory put-away, including the suggested bin.');
        Lines.Add('children', LineFields);
        PutawayFields.Add(ContractMgt.ResponseField('putawayNo', 'string', 'Inventory put-away number.'));
        PutawayFields.Add(ContractMgt.ResponseField('putawaySystemId', 'string', 'Inventory put-away SystemId.'));
        PutawayFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        PutawayFields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of lines.'));
        PutawayFields.Add(Lines);
        Putaways.Add('name', 'putaways');
        Putaways.Add('type', 'array');
        Putaways.Add('description', 'Inventory put-aways for the source document. An existing open put-away is returned with a warning instead of creating another.');
        Putaways.Add('children', PutawayFields);
        Fields.Add(Putaways);
        WarningFields.Add(ContractMgt.ResponseField('code', 'string', 'PreconditionFailed.'));
        WarningFields.Add(ContractMgt.ResponseField('message', 'string', 'An open inventory put-away already exists for this source document.'));
        WarningFields.Add(ContractMgt.ResponseField('parameter', 'string', 'sourceNo.'));
        WarningFields.Add(ContractMgt.ResponseField('nextStep', 'string', 'Use Warehouse.InventoryPutAway.Post for the existing inventory put-away.'));
        Warnings.Add('name', 'warnings');
        Warnings.Add('type', 'array');
        Warnings.Add('description', 'Present only when an open inventory put-away already existed and was returned instead of creating another.');
        Warnings.Add('children', WarningFields);
        Fields.Add(Warnings);
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
        UnknownParameterNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The source document is not released, or the location does not require put-away.', 'Release the document first, or post it directly.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The location uses warehouse receipts.', 'Use Warehouse.Receipt.Create and Warehouse.Putaway.Create instead.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'sourceDocument, or a document number or SystemId, is missing.', 'Send sourceDocument and sourceNo or systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes and a GUID for systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'sourceDocument is not a supported inventory put-away source.', 'Send Purchase Order, Sales Return Order or Inbound Transfer.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', UnknownParameterNextStepLbl);
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The source document was not found.', 'Check sourceDocument and the document number or SystemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject, sourceNo and systemId name different documents.', 'Send one document: subject, sourceNo or systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot create an inventory put-away.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the inventory put-away.', 'Read the returned text and correct the source document or the inventory.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Creates an inventory put-away. Business Central commits the put-away when it is created, so a later failure does not roll it back. An existing open put-away is returned and nothing new is written.', 'BIFROST Whse - Full ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.InventoryPutAway.Post', 'Use it to post the inventory put-away and receive the source document.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Bin.Get', 'Use it to read the bins the put-away may use.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Receipt.Create', 'Use it, with Warehouse.Putaway.Create, when the location requires a warehouse receipt.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True. The workflow runs from creating the put-away to posting it.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.InventoryPutAway.Create', 'Create the inventory put-away from a released inbound source document at a location that requires put-away.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Activity.Get', 'Read the open put-away and its lines. Optional.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.ActivityLine.ChangeBin', 'Change the bin on a line when the suggested bin is not the one to use. Optional.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.InventoryPutAway.Post', 'Post the inventory put-away; the source document is received and the goods are placed in the bins.'));
        Workflow.Add('steps', Steps);
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
            'Create an inventory put-away for purchase order 106001',
            '{"sourceDocument":"Purchase Order","sourceNo":"106001"}',
            '{"status":"Success","sourceDocument":"Purchase Order","sourceNo":"106001","putawayCount":1,"putaways":[{"putawayNo":"IPU00001","locationCode":"BASIC","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"WRB-1000","binCode":"RECV","quantity":1,"qtyToHandle":1,"qtyOutstanding":1}]}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Creates an inventory put-away from a released purchase order, sales return order or inbound transfer at a location that requires put-away but not a warehouse receipt. Business Central commits the put-away. An open inventory put-away for the same document is returned with a warning.', Comment = 'is-IS=Stofnar birgðafrágang úr staðfestri innkaupapöntun, söluskilapöntun eða innleiðsflutningi á staðsetningu sem krefst frágangs en ekki vöruhúsamóttöku. Business Central staðfestir fráganginn. Opinn birgðafrágangur fyrir sama skjal er skilaður með viðvörun.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes hold edge cases for consultants.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'The source document must be released, and every item line must sit at a location that requires put-away. A location that uses warehouse receipts or directed put-away and pick is refused: use Warehouse.Receipt.Create and Warehouse.Putaway.Create there. A document with no item line at such a location is refused as not released or not requiring put-away. ' +
            'sourceDocument takes Purchase Order, Sales Return Order or Inbound Transfer. ' +
            'If an open inventory put-away already exists for the document, nothing is created: that put-away is returned with a warning, also when the document has lines that put-away does not cover. ' +
            'When Business Central creates no put-away, the call is refused with the error No inventory put-away was created. A created put-away is committed, so a later failure does not roll it back. ' +
            'Quantity to handle is set to the outstanding quantity on every line, so the put-away can be posted straight away with Warehouse.InventoryPutAway.Post. The bin on each line is the one Business Central suggests; it is empty at a location without bins. ' +
            'Nothing is received or posted by this call.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the request and creates the inventory put-away, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        SourceDocument: Enum "Warehouse Request Source Document";
        DocumentNo: Code[20];
        DeniedLbl: Label 'You do not have permission to create an inventory put-away.', Comment = 'is-IS=Þú hefur ekki heimild til að stofna birgðafrágang.';
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
        RefuseUnknownKeys(RequestJson, Argument);
        if not Argument.HasCollectedErrors() then
            ResolveDocument(RequestJson, Argument, SourceDocument, DocumentNo);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if ReturnExistingPutaways(Argument, SourceDocument, DocumentNo) then begin
            Context.Reset();
            exit;
        end;
        Payload.Add('sourceDocument', SourceDocumentName(SourceDocument));
        Payload.Add('sourceNo', DocumentNo);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse InvtPut Create Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse InvtPut Create Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        WriteCreated(Argument);
        Context.Reset();
    end;

    local procedure ReturnExistingPutaways(var Argument: Record "Message Argument ori"; SourceDocument: Enum "Warehouse Request Source Document"; DocumentNo: Code[20]): Boolean
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        Putaways: JsonArray;
        PutawayJson: JsonObject;
        Warning: JsonObject;
        Warnings: JsonArray;
        ExistsLbl: Label 'An open inventory put-away already exists for this source document.', Comment = 'is-IS=Opinn birgðafrágangur er þegar til fyrir þetta upprunaskjal.';
        ExistsNextStepLbl: Label 'Use Warehouse.InventoryPutAway.Post for the existing inventory put-away.', Comment = 'is-IS=Notaðu Warehouse.InventoryPutAway.Post fyrir birgðafráganginn sem er til.';
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Put-away");
        ActivityHeader.SetRange("Source Document", ToActivitySource(SourceDocument));
        ActivityHeader.SetRange("Source No.", DocumentNo);
        if not ActivityHeader.FindSet() then
            exit(false);
        repeat
            Clear(PutawayJson);
            WriteOnePutaway(ActivityHeader, PutawayJson);
            Putaways.Add(PutawayJson);
        until ActivityHeader.Next() = 0;
        Warning.Add('code', 'PreconditionFailed');
        Warning.Add('message', ExistsLbl);
        Warning.Add('parameter', 'sourceNo');
        Warning.Add('nextStep', ExistsNextStepLbl);
        Warnings.Add(Warning);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('sourceDocument', SourceDocumentName(SourceDocument));
        ResponseJson.Add('sourceNo', DocumentNo);
        ResponseJson.Add('putawayCount', Putaways.Count());
        ResponseJson.Add('putaways', Putaways);
        ResponseJson.Add('warnings', Warnings);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
        exit(true);
    end;

    local procedure WriteCreated(var Argument: Record "Message Argument ori")
    var
        Context: Codeunit "Whse Write Context ori";
        Result: JsonObject;
        ResponseJson: JsonObject;
        Token: JsonToken;
        MissingResultErr: Label 'The inventory put-away was created but its number was not returned.', Comment = 'is-IS=Birgðafrágangurinn var stofnaður en númer hans skilaði sér ekki.';
        MissingResultNextStepLbl: Label 'Read the returned text and correct the source document or the inventory.', Comment = 'is-IS=Lestu textann sem skilaði sér og leiðréttu upprunaskjalið eða birgðirnar.';
    begin
        if not Context.TryGetResult(Result) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'putawayNo', '', '', MissingResultNextStepLbl);
            exit;
        end;
        ResponseJson.Add('status', 'Success');
        CopyValue(Result, ResponseJson, 'sourceDocument');
        CopyValue(Result, ResponseJson, 'sourceNo');
        if not Result.Get('putaways', Token) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'putaways', '', '', MissingResultNextStepLbl);
            exit;
        end;
        ResponseJson.Add('putawayCount', Token.AsArray().Count());
        ResponseJson.Add('putaways', Token.AsArray());
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure WriteOnePutaway(ActivityHeader: Record "Warehouse Activity Header"; var PutawayJson: JsonObject)
    var
        ActivityLine: Record "Warehouse Activity Line";
        Lines: JsonArray;
        LineJson: JsonObject;
    begin
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if ActivityLine.FindSet() then
            repeat
                Clear(LineJson);
                LineJson.Add('lineNo', ActivityLine."Line No.");
                LineJson.Add('itemNo', ActivityLine."Item No.");
                LineJson.Add('binCode', ActivityLine."Bin Code");
                LineJson.Add('quantity', ActivityLine.Quantity);
                LineJson.Add('qtyToHandle', ActivityLine."Qty. to Handle");
                LineJson.Add('qtyOutstanding', ActivityLine."Qty. Outstanding");
                Lines.Add(LineJson);
            until ActivityLine.Next() = 0;
        PutawayJson.Add('putawayNo', ActivityHeader."No.");
        PutawayJson.Add('putawaySystemId', Format(ActivityHeader.SystemId, 0, 4));
        PutawayJson.Add('locationCode', ActivityHeader."Location Code");
        PutawayJson.Add('lineCount', Lines.Count());
        PutawayJson.Add('lines', Lines);
    end;

    local procedure ResolveDocument(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var SourceDocument: Enum "Warehouse Request Source Document"; var DocumentNo: Code[20])
    var
        Context: Codeunit "Whse Write Context ori";
        Locations: List of [Code[10]];
        SourceText: Text;
        SourceNoText: Text;
        SystemIdText: Text;
        SubjectText: Text;
        SourcePresent: Boolean;
        SourceNoPresent: Boolean;
        SystemPresent: Boolean;
        Released: Boolean;
        Found: Boolean;
        IdentifierKey: Text;
        IdentifierValue: Text;
    begin
        Clear(DocumentNo);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Context.ReadText(RequestJson, 'sourceDocument', 50, Argument, SourceText, SourcePresent, 'sourceDocument') then
            exit;
        if not Context.ReadText(RequestJson, 'sourceNo', 20, Argument, SourceNoText, SourceNoPresent, 'sourceNo') then
            exit;
        if not Context.ReadText(RequestJson, 'systemId', 50, Argument, SystemIdText, SystemPresent, 'systemId') then
            exit;
        if not SourcePresent then begin
            RequireSourceDocument(Argument);
            exit;
        end;
        if not TryParseSourceDocument(SourceText, SourceDocument) then begin
            RefuseSourceDocument(Argument, SourceText);
            exit;
        end;
        ApplySubject(Argument, SubjectText, SourceNoText, SourceNoPresent, SystemIdText, SystemPresent);
        if Argument.HasCollectedErrors() then
            exit;
        if (SourceNoText = '') and (SystemIdText = '') then begin
            RequireIdentifier(Argument);
            exit;
        end;
        Found := LoadDocument(Argument, SourceDocument, SourceNoText, SystemIdText, DocumentNo, Released, Locations);
        if not Found then
            exit;
        // A refusal about the document or its location names the key that identified the document (#71).
        IdentifierSource(SubjectText, SourceNoText, SourceNoPresent, SystemIdText, SystemPresent, IdentifierKey, IdentifierValue);
        if not Released then begin
            RefuseNotReleased(Argument, IdentifierKey, IdentifierValue);
            exit;
        end;
        CheckLocations(Argument, Locations, IdentifierKey, IdentifierValue);
    end;

    local procedure IdentifierSource(SubjectText: Text; SourceNoText: Text; SourceNoPresent: Boolean; SystemIdText: Text; SystemPresent: Boolean; var IdentifierKey: Text; var IdentifierValue: Text)
    begin
        case true of
            SourceNoPresent:
                begin
                    IdentifierKey := 'sourceNo';
                    IdentifierValue := SourceNoText;
                end;
            SystemPresent:
                begin
                    IdentifierKey := 'systemId';
                    IdentifierValue := SystemIdText;
                end;
            else begin
                IdentifierKey := 'subject';
                IdentifierValue := SubjectText;
            end;
        end;
    end;

    local procedure ApplySubject(var Argument: Record "Message Argument ori"; SubjectText: Text; var SourceNoText: Text; SourceNoPresent: Boolean; var SystemIdText: Text; SystemPresent: Boolean)
    var
        SubjectId: Guid;
        SubjectIsGuid: Boolean;
        ConflictLbl: Label 'subject and sourceNo or systemId name different documents.', Comment = 'is-IS=subject og sourceNo eða systemId nefna mismunandi skjöl.';
        ConflictNextStepLbl: Label 'Send one document: subject, sourceNo or systemId.', Comment = 'is-IS=Sendu eitt skjal: subject, sourceNo eða systemId.';
    begin
        if SubjectText = '' then
            exit;
        SubjectIsGuid := Evaluate(SubjectId, SubjectText);
        if SubjectIsGuid then begin
            if SystemPresent and (UpperCase(DelChr(SystemIdText, '=', '{}')) <> UpperCase(DelChr(SubjectText, '=', '{}'))) then
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'systemId', SystemIdText, SubjectText, ConflictNextStepLbl);
            if not SystemPresent then
                SystemIdText := SubjectText;
            exit;
        end;
        if SourceNoPresent and (UpperCase(SourceNoText) <> UpperCase(SubjectText)) then
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'sourceNo', SourceNoText, SubjectText, ConflictNextStepLbl);
        if not SourceNoPresent then
            SourceNoText := SubjectText;
    end;

    local procedure LoadDocument(var Argument: Record "Message Argument ori"; SourceDocument: Enum "Warehouse Request Source Document"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    begin
        Clear(Locations);
        Released := false;
        case SourceDocument of
            SourceDocument::"Purchase Order":
                exit(LoadPurchaseOrder(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
            SourceDocument::"Sales Return Order":
                exit(LoadSalesReturn(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
            SourceDocument::"Inbound Transfer":
                exit(LoadInboundTransfer(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
        end;
        exit(false);
    end;

    local procedure LoadPurchaseOrder(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
    begin
        if not FindPurchaseHeader(Argument, PurchaseHeader, PurchaseHeader."Document Type"::Order, SourceNoText, SystemIdText) then
            exit(false);
        DocumentNo := PurchaseHeader."No.";
        Released := PurchaseHeader.Status = PurchaseHeader.Status::Released;
        if PurchaseHeader."Location Code" <> '' then
            AddLocation(Locations, PurchaseHeader."Location Code");
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
        if PurchaseLine.FindSet() then
            repeat
                AddLocation(Locations, PurchaseLine."Location Code");
            until PurchaseLine.Next() = 0;
        exit(true);
    end;

    local procedure LoadSalesReturn(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        if not FindSalesHeader(Argument, SalesHeader, SalesHeader."Document Type"::"Return Order", SourceNoText, SystemIdText) then
            exit(false);
        DocumentNo := SalesHeader."No.";
        Released := SalesHeader.Status = SalesHeader.Status::Released;
        if SalesHeader."Location Code" <> '' then
            AddLocation(Locations, SalesHeader."Location Code");
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.SetRange(Type, SalesLine.Type::Item);
        if SalesLine.FindSet() then
            repeat
                AddLocation(Locations, SalesLine."Location Code");
            until SalesLine.Next() = 0;
        exit(true);
    end;

    local procedure FindSalesHeader(var Argument: Record "Message Argument ori"; var SalesHeader: Record "Sales Header"; DocumentType: Enum "Sales Document Type"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        SystemId: Guid;
        ById: Boolean;
    begin
        if not TryReadGuid(Argument, SystemIdText, SystemId, ById) then
            exit(false);
        if ById then begin
            if SalesHeader.GetBySystemId(SystemId) and (SalesHeader."Document Type" = DocumentType) then begin
                if (SourceNoText <> '') and (SalesHeader."No." <> CopyStr(SourceNoText, 1, MaxStrLen(SalesHeader."No."))) then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
                exit(true);
            end;
            if (SourceNoText <> '') and SalesHeader.Get(DocumentType, CopyStr(SourceNoText, 1, MaxStrLen(SalesHeader."No."))) then
                exit(Conflict(Argument, SourceNoText, SystemIdText));
            exit(NotFound(Argument, SourceNoText, SystemIdText));
        end;
        if SalesHeader.Get(DocumentType, CopyStr(SourceNoText, 1, MaxStrLen(SalesHeader."No."))) then
            exit(true);
        exit(NotFound(Argument, SourceNoText, SystemIdText));
    end;

    local procedure FindPurchaseHeader(var Argument: Record "Message Argument ori"; var PurchaseHeader: Record "Purchase Header"; DocumentType: Enum "Purchase Document Type"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        SystemId: Guid;
        ById: Boolean;
    begin
        if not TryReadGuid(Argument, SystemIdText, SystemId, ById) then
            exit(false);
        if ById then begin
            if PurchaseHeader.GetBySystemId(SystemId) and (PurchaseHeader."Document Type" = DocumentType) then begin
                if (SourceNoText <> '') and (PurchaseHeader."No." <> CopyStr(SourceNoText, 1, MaxStrLen(PurchaseHeader."No."))) then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
                exit(true);
            end;
            if (SourceNoText <> '') and PurchaseHeader.Get(DocumentType, CopyStr(SourceNoText, 1, MaxStrLen(PurchaseHeader."No."))) then
                exit(Conflict(Argument, SourceNoText, SystemIdText));
            exit(NotFound(Argument, SourceNoText, SystemIdText));
        end;
        if PurchaseHeader.Get(DocumentType, CopyStr(SourceNoText, 1, MaxStrLen(PurchaseHeader."No."))) then
            exit(true);
        exit(NotFound(Argument, SourceNoText, SystemIdText));
    end;

    local procedure LoadInboundTransfer(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        TransferHeader: Record "Transfer Header";
        TransferLine: Record "Transfer Line";
    begin
        if not FindTransferHeader(Argument, TransferHeader, SourceNoText, SystemIdText) then
            exit(false);
        DocumentNo := TransferHeader."No.";
        Released := TransferHeader.Status = TransferHeader.Status::Released;
        AddLocation(Locations, TransferHeader."Transfer-to Code");
        TransferLine.SetRange("Document No.", TransferHeader."No.");
        if TransferLine.FindSet() then
            repeat
                AddLocation(Locations, TransferLine."Transfer-to Code");
            until TransferLine.Next() = 0;
        exit(true);
    end;

    local procedure FindTransferHeader(var Argument: Record "Message Argument ori"; var TransferHeader: Record "Transfer Header"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        SystemId: Guid;
        ById: Boolean;
    begin
        if not TryReadGuid(Argument, SystemIdText, SystemId, ById) then
            exit(false);
        if ById then begin
            if TransferHeader.GetBySystemId(SystemId) then begin
                if (SourceNoText <> '') and (TransferHeader."No." <> CopyStr(SourceNoText, 1, MaxStrLen(TransferHeader."No."))) then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
                exit(true);
            end;
            if (SourceNoText <> '') and TransferHeader.Get(CopyStr(SourceNoText, 1, MaxStrLen(TransferHeader."No."))) then
                exit(Conflict(Argument, SourceNoText, SystemIdText));
            exit(NotFound(Argument, SourceNoText, SystemIdText));
        end;
        if TransferHeader.Get(CopyStr(SourceNoText, 1, MaxStrLen(TransferHeader."No."))) then
            exit(true);
        exit(NotFound(Argument, SourceNoText, SystemIdText));
    end;

    local procedure CheckLocations(var Argument: Record "Message Argument ori"; Locations: List of [Code[10]]; IdentifierKey: Text; IdentifierValue: Text)
    var
        Location: Record Location;
        LocationCode: Code[10];
        SawPutAway: Boolean;
    begin
        if Locations.Count() = 0 then begin
            RefuseNotReleased(Argument, IdentifierKey, IdentifierValue);
            exit;
        end;
        foreach LocationCode in Locations do begin
            Location.SetLoadFields(Code, "Require Put-away", "Require Receive", "Directed Put-away and Pick");
            if not Location.Get(LocationCode) then begin
                NotFound(Argument, LocationCode, '');
                exit;
            end;
            if Location."Directed Put-away and Pick" or Location."Require Receive" then begin
                RefuseReceiptLocation(Argument, LocationCode, IdentifierKey, IdentifierValue);
                exit;
            end;
            if Location."Require Put-away" then
                SawPutAway := true
            else begin
                RefuseNotReleased(Argument, IdentifierKey, IdentifierValue);
                exit;
            end;
        end;
        if not SawPutAway then
            RefuseNotReleased(Argument, IdentifierKey, IdentifierValue);
    end;

    local procedure AddLocation(var Locations: List of [Code[10]]; LocationCode: Code[10])
    begin
        if LocationCode = '' then
            exit;
        if Locations.Contains(LocationCode) then
            exit;
        Locations.Add(LocationCode);
    end;

    local procedure TryReadGuid(var Argument: Record "Message Argument ori"; SystemIdText: Text; var SystemId: Guid; var ById: Boolean): Boolean
    var
        FormatLbl: Label 'systemId must be a GUID.', Comment = 'is-IS=systemId verður að vera GUID.';
        FormatNextStepLbl: Label 'Send text for codes and a GUID for systemId.', Comment = 'is-IS=Sendu texta fyrir kóða og GUID fyrir systemId.';
    begin
        Clear(SystemId);
        ById := SystemIdText <> '';
        if not ById then
            exit(true);
        if Evaluate(SystemId, SystemIdText) then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'systemId', CopyStr(SystemIdText, 1, 80), 'guid', FormatNextStepLbl);
        exit(false);
    end;

    local procedure TryParseSourceDocument(SourceText: Text; var SourceDocument: Enum "Warehouse Request Source Document"): Boolean
    begin
        case UpperCase(DelChr(SourceText, '=', ' ')) of
            'PURCHASEORDER':
                SourceDocument := SourceDocument::"Purchase Order";
            'SALESRETURNORDER':
                SourceDocument := SourceDocument::"Sales Return Order";
            'INBOUNDTRANSFER':
                SourceDocument := SourceDocument::"Inbound Transfer";
            else
                exit(false);
        end;
        exit(true);
    end;

    local procedure SourceDocumentName(SourceDocument: Enum "Warehouse Request Source Document"): Text
    begin
        case SourceDocument of
            SourceDocument::"Purchase Order":
                exit('Purchase Order');
            SourceDocument::"Sales Return Order":
                exit('Sales Return Order');
            SourceDocument::"Inbound Transfer":
                exit('Inbound Transfer');
        end;
    end;

    local procedure ToActivitySource(SourceDocument: Enum "Warehouse Request Source Document") ActivitySource: Enum "Warehouse Activity Source Document"
    begin
        case SourceDocument of
            SourceDocument::"Purchase Order":
                exit(ActivitySource::"Purchase Order");
            SourceDocument::"Sales Return Order":
                exit(ActivitySource::"Sales Return Order");
            SourceDocument::"Inbound Transfer":
                exit(ActivitySource::"Inbound Transfer");
        end;
    end;

    local procedure RequireSourceDocument(var Argument: Record "Message Argument ori")
    var
        MissingLbl: Label 'sourceDocument is required.', Comment = 'is-IS=sourceDocument er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send sourceDocument and sourceNo or systemId.', Comment = 'is-IS=Sendu sourceDocument og sourceNo eða systemId.';
    begin
        Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'sourceDocument', '', '', MissingNextStepLbl);
    end;

    local procedure RequireIdentifier(var Argument: Record "Message Argument ori")
    var
        MissingLbl: Label 'sourceNo or systemId is required.', Comment = 'is-IS=sourceNo eða systemId er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send sourceDocument and sourceNo or systemId.', Comment = 'is-IS=Sendu sourceDocument og sourceNo eða systemId.';
    begin
        Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'sourceNo', '', '', MissingNextStepLbl);
    end;

    local procedure RefuseSourceDocument(var Argument: Record "Message Argument ori"; SourceText: Text)
    var
        InvalidLbl: Label 'sourceDocument %1 is not a supported inventory put-away source.', Comment = '%1 = source document, is-IS=sourceDocument %1 er ekki studd birgðafrágangsuppspretta.';
        InvalidNextStepLbl: Label 'Send Purchase Order, Sales Return Order or Inbound Transfer.', Comment = 'is-IS=Sendu Purchase Order, Sales Return Order eða Inbound Transfer.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(InvalidLbl, SourceText), 'sourceDocument', SourceText, '', InvalidNextStepLbl);
    end;

    local procedure RefuseNotReleased(var Argument: Record "Message Argument ori"; IdentifierKey: Text; Received: Text)
    var
        NotReleasedLbl: Label 'The source document is not released, or the location does not require put-away.', Comment = 'is-IS=Upprunaskjalið er ekki staðfest, eða staðsetningin krefst ekki frágangs.';
        NotReleasedNextStepLbl: Label 'Release the document first, or post it directly.', Comment = 'is-IS=Staðfestu skjalið fyrst, eða bókaðu það beint.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NotReleasedLbl, IdentifierKey, Received, '', NotReleasedNextStepLbl);
    end;

    local procedure RefuseReceiptLocation(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; IdentifierKey: Text; IdentifierValue: Text)
    var
        ReceiptLbl: Label 'Location %1 uses warehouse receipts.', Comment = '%1 = location, is-IS=Staðsetning %1 notar vöruhúsamóttökur.';
        ReceiptNextStepLbl: Label 'Use Warehouse.Receipt.Create and Warehouse.Putaway.Create instead.', Comment = 'is-IS=Notaðu Warehouse.Receipt.Create og Warehouse.Putaway.Create í staðinn.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(ReceiptLbl, LocationCode), IdentifierKey, IdentifierValue, '', ReceiptNextStepLbl);
    end;

    local procedure NotFound(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        NotFoundLbl: Label 'The source document was not found.', Comment = 'is-IS=Upprunaskjalið fannst ekki.';
        NotFoundNextStepLbl: Label 'Check sourceDocument and the document number or SystemId.', Comment = 'is-IS=Athugaðu sourceDocument og skjalnúmer eða SystemId.';
        Received: Text;
    begin
        Received := SourceNoText;
        if Received = '' then
            Received := SystemIdText;
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, NotFoundLbl, 'sourceNo', CopyStr(Received, 1, 80), '', NotFoundNextStepLbl);
        exit(false);
    end;

    local procedure Conflict(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        ConflictLbl: Label 'sourceNo and systemId name different documents.', Comment = 'is-IS=sourceNo og systemId nefna mismunandi skjöl.';
        ConflictNextStepLbl: Label 'Send one document: subject, sourceNo or systemId.', Comment = 'is-IS=Sendu eitt skjal: subject, sourceNo eða systemId.';
    begin
        Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'sourceNo', SourceNoText, SystemIdText, ConflictNextStepLbl);
        exit(false);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['sourceDocument', 'sourceNo', 'systemId']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure CopyValue(SourceJson: JsonObject; var TargetJson: JsonObject; KeyName: Text)
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

    local procedure CreatePutaways(Payload: JsonObject; var Result: JsonObject)
    var
        WarehouseRequest: Record "Warehouse Request";
        CreateReport: Report "Create Invt Put-away/Pick/Mvmt";
        SourceDocument: Enum "Warehouse Request Source Document";
        SourceNo: Code[20];
        Putaways: JsonArray;
        NothingErr: Label 'No inventory put-away was created.', Comment = 'is-IS=Enginn birgðafrágangur var stofnaður.';
    begin
        SourceDocument := ParseSourceDocument(TextValue(Payload, 'sourceDocument'));
        SourceNo := CopyStr(TextValue(Payload, 'sourceNo'), 1, MaxStrLen(SourceNo));
        WarehouseRequest.SetRange("Source Document", SourceDocument);
        WarehouseRequest.SetRange("Source No.", SourceNo);
        WarehouseRequest.SetRange(Type, WarehouseRequest.Type::Inbound);
        CreateReport.UseRequestPage(false);
        CreateReport.InitializeRequest(true, false, false, false, true);
        CreateReport.SuppressMessages(true);
        CreateReport.SetTableView(WarehouseRequest);
        CreateReport.RunModal();
        // Report 7323 leaves Qty. to Handle at zero when the request page is suppressed.
        FillQtyToHandle(SourceDocument, SourceNo);
        BuildPutaways(SourceDocument, SourceNo, Putaways);
        if Putaways.Count() = 0 then
            Error(NothingErr);
        Result.Add('sourceDocument', TextValue(Payload, 'sourceDocument'));
        Result.Add('sourceNo', SourceNo);
        Result.Add('putaways', Putaways);
    end;

    local procedure BuildPutaways(SourceDocument: Enum "Warehouse Request Source Document"; SourceNo: Code[20]; var Putaways: JsonArray)
    var
        ActivityHeader: Record "Warehouse Activity Header";
        PutawayJson: JsonObject;
    begin
        Clear(Putaways);
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Put-away");
        ActivityHeader.SetRange("Source Document", ToActivitySource(SourceDocument));
        ActivityHeader.SetRange("Source No.", SourceNo);
        if not ActivityHeader.FindSet() then
            exit;
        repeat
            Clear(PutawayJson);
            WritePutaway(ActivityHeader, PutawayJson);
            Putaways.Add(PutawayJson);
        until ActivityHeader.Next() = 0;
    end;

    local procedure WritePutaway(ActivityHeader: Record "Warehouse Activity Header"; var PutawayJson: JsonObject)
    var
        Lines: JsonArray;
    begin
        BuildLines(ActivityHeader, Lines);
        PutawayJson.Add('putawayNo', ActivityHeader."No.");
        PutawayJson.Add('putawaySystemId', Format(ActivityHeader.SystemId, 0, 4));
        PutawayJson.Add('locationCode', ActivityHeader."Location Code");
        PutawayJson.Add('lineCount', Lines.Count());
        PutawayJson.Add('lines', Lines);
    end;

    local procedure BuildLines(ActivityHeader: Record "Warehouse Activity Header"; var Lines: JsonArray)
    var
        ActivityLine: Record "Warehouse Activity Line";
        LineJson: JsonObject;
    begin
        Clear(Lines);
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if not ActivityLine.FindSet() then
            exit;
        repeat
            Clear(LineJson);
            LineJson.Add('lineNo', ActivityLine."Line No.");
            LineJson.Add('itemNo', ActivityLine."Item No.");
            LineJson.Add('binCode', ActivityLine."Bin Code");
            LineJson.Add('quantity', ActivityLine.Quantity);
            LineJson.Add('qtyToHandle', ActivityLine."Qty. to Handle");
            LineJson.Add('qtyOutstanding', ActivityLine."Qty. Outstanding");
            Lines.Add(LineJson);
        until ActivityLine.Next() = 0;
    end;

    local procedure FillQtyToHandle(SourceDocument: Enum "Warehouse Request Source Document"; SourceNo: Code[20])
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Put-away");
        ActivityHeader.SetRange("Source Document", ToActivitySource(SourceDocument));
        ActivityHeader.SetRange("Source No.", SourceNo);
        if not ActivityHeader.FindSet() then
            exit;
        repeat
            ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
            ActivityLine.SetRange("No.", ActivityHeader."No.");
            if ActivityLine.FindSet() then
                repeat
                    if (ActivityLine."Qty. to Handle" = 0) and (ActivityLine."Qty. Outstanding" > 0) then begin
                        // Assign without Validate. A tracked line without a lot rejects Validate,
                        // and a try function cannot write the quantity afterwards.
                        ActivityLine."Qty. to Handle" := ActivityLine."Qty. Outstanding";
                        ActivityLine."Qty. to Handle (Base)" := ActivityLine."Qty. Outstanding (Base)";
                        ActivityLine.Modify(true);
                    end;
                until ActivityLine.Next() = 0;
        until ActivityHeader.Next() = 0;
    end;

    local procedure ParseSourceDocument(SourceText: Text) SourceDocument: Enum "Warehouse Request Source Document"
    var
        UnsupportedErr: Label 'Source document %1 is not supported.', Comment = '%1 = source document, is-IS=Upprunaskjal %1 er ekki stutt.';
    begin
        case UpperCase(DelChr(SourceText, '=', ' ')) of
            'PURCHASEORDER':
                exit(SourceDocument::"Purchase Order");
            'SALESRETURNORDER':
                exit(SourceDocument::"Sales Return Order");
            'INBOUNDTRANSFER':
                exit(SourceDocument::"Inbound Transfer");
        end;
        Error(UnsupportedErr, SourceText);
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
}
