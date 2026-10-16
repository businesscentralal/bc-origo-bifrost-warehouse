namespace Origo.Bifrost.Warehouse;

using Microsoft.Assembly.Document;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Transfer;
using Microsoft.Manufacturing.Document;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.InventoryPick.Create.
/// Report 7323 creates the inventory pick and commits it.
/// A location that uses shipments is refused so this type does not create a warehouse pick.
/// </summary>
codeunit 10078479 "Whse InvtPick Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can create an inventory pick.</summary>
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

    /// <summary>Returns a short description of Warehouse.InventoryPick.Create.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates an inventory pick from a released source document at a basic location that requires pick.', Comment = 'is-IS=Stofnar birgðatínslu úr staðfestu upprunaskjali á einfaldri staðsetningu sem krefst tínslu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'create inventory pick, inventory pick, pick from sales order, basic warehouse pick, require pick, source document', Comment = 'is-IS=stofna birgðatínslu, birgðatínsla, tínsla úr sölupöntun, einföld vöruhúsatínsla, krefst tínslu, upprunaskjal';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Business Central commits the inventory pick it creates. Use Warehouse.Shipment.Create and Warehouse.Pick.Create when the location uses warehouse shipments.', Comment = 'is-IS=Óafturkræft. Business Central staðfestir birgðatínsluna sem það stofnar. Notaðu Warehouse.Shipment.Create og Warehouse.Pick.Create þegar staðsetningin notar vöruhúsaafhendingar.';
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
        Target.Add(ContractMgt.TargetEntry('subject', 'system id or document no.', 'The source document to pick.'));
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
        Parameters.Add(ContractMgt.Parameter('sourceDocument', 'string', true, 'Sales Order, Purchase Return Order, Outbound Transfer, Assembly Consumption or Prod. Consumption.'));
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
        PickFields: JsonArray;
        LineFields: JsonArray;
        Picks: JsonObject;
        Lines: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('sourceDocument', 'string', 'Source document type.'));
        Fields.Add(ContractMgt.ResponseField('sourceNo', 'string', 'Source document number.'));
        Fields.Add(ContractMgt.ResponseField('pickCount', 'integer', 'Number of inventory picks returned.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Inventory pick line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin the quantity is picked from. Empty when the location has no bins.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity on the line.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle.'));
        LineFields.Add(ContractMgt.ResponseField('qtyOutstanding', 'number', 'Quantity still outstanding.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Lines on the inventory pick.');
        Lines.Add('children', LineFields);
        PickFields.Add(ContractMgt.ResponseField('pickNo', 'string', 'Inventory pick number.'));
        PickFields.Add(ContractMgt.ResponseField('pickSystemId', 'string', 'Inventory pick SystemId.'));
        PickFields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        PickFields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of lines.'));
        PickFields.Add(Lines);
        Picks.Add('name', 'picks');
        Picks.Add('type', 'array');
        Picks.Add('description', 'Inventory picks for the source document. An existing open pick is returned with a warning instead of creating another.');
        Picks.Add('children', PickFields);
        Fields.Add(Picks);
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
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The source document is not released, or the location does not require pick.', 'Release the document with Sales.Document.Release, or post the document directly.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The location uses warehouse shipments.', 'Use Warehouse.Shipment.Create and Warehouse.Pick.Create instead.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'sourceDocument, or a document number or SystemId, is missing.', 'Send sourceDocument and sourceNo or systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes and a GUID for systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'sourceDocument is not a supported inventory pick source.', 'Send Sales Order, Purchase Return Order, Outbound Transfer, Assembly Consumption or Prod. Consumption.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The source document was not found.', 'Check sourceDocument and the document number or SystemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject, sourceNo and systemId name different documents.', 'Send one document: subject, sourceNo or systemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot create an inventory pick.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the inventory pick.', 'Read the returned text and correct the source document or the inventory.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Creates an inventory pick. Business Central commits the pick when it is created, so a later failure does not roll it back. An existing open pick is returned and nothing new is written.', 'BIFROST Whse - Full ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.InventoryPick.Post', 'Use it to post the inventory pick and ship the source document.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read the quantity in the pick bin before posting.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Create', 'Use it, with Warehouse.Pick.Create, when the location requires a warehouse shipment.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>False. Inventory pick create has no separate workflow chapter.</returns>
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
            'Create an inventory pick for sales order 1001',
            '{"sourceDocument":"Sales Order","sourceNo":"1001"}',
            '{"status":"Success","sourceDocument":"Sales Order","sourceNo":"1001","pickCount":1,"picks":[{"pickNo":"IP000001","locationCode":"BASIC","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"WRB-1000","binCode":"","quantity":1,"qtyToHandle":1,"qtyOutstanding":1}]}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Creates an inventory pick from a released sales order, purchase return order, outbound transfer, assembly consumption or production consumption at a location that requires pick but not a warehouse shipment. Business Central commits the pick. An open inventory pick for the same document is returned with a warning.', Comment = 'is-IS=Stofnar birgðatínslu úr staðfestri sölupöntun, innkaupaskilapöntun, útleiðarflutningi, samsetningarnotkun eða framleiðslunotkun á staðsetningu sem krefst tínslu en ekki vöruhúsaafhendingar. Business Central staðfestir tínsluna. Opin birgðatínsla fyrir sama skjal er skilað með viðvörun.';
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

    /// <summary>Validates the request and creates the inventory pick, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        Context: Codeunit "Whse InvtPick Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        SourceDocument: Enum "Warehouse Request Source Document";
        DocumentNo: Code[20];
        DeniedLbl: Label 'You do not have permission to create an inventory pick.', Comment = 'is-IS=Þú hefur ekki heimild til að stofna birgðatínslu.';
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
        RequestJson := Argument.GetRequestJson();
        RefuseUnknownKeys(RequestJson, Argument);
        if not Argument.HasCollectedErrors() then
            ResolveDocument(RequestJson, Argument, SourceDocument, DocumentNo);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if ReturnExistingPicks(Argument, SourceDocument, DocumentNo) then begin
            Context.Reset();
            exit;
        end;
        Payload.Add('sourceDocument', SourceDocumentName(SourceDocument));
        Payload.Add('sourceNo', DocumentNo);
        Context.SetPayload(Payload);
        if not Codeunit.Run(Codeunit::"Whse InvtPick Create Proc ori") then begin
            Context.Reset();
            Argument.RespondWithLastError();
            exit;
        end;
        WriteCreated(Argument);
        Context.Reset();
    end;

    local procedure ReturnExistingPicks(var Argument: Record "Message Argument ori"; SourceDocument: Enum "Warehouse Request Source Document"; DocumentNo: Code[20]): Boolean
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        Picks: JsonArray;
        PickJson: JsonObject;
        Warning: JsonObject;
        Warnings: JsonArray;
        ExistsLbl: Label 'An open inventory pick already exists for this source document.', Comment = 'is-IS=Opin birgðatínsla er þegar til fyrir þetta upprunaskjal.';
        ExistsNextStepLbl: Label 'Use Warehouse.InventoryPick.Post for the existing inventory pick.', Comment = 'is-IS=Notaðu Warehouse.InventoryPick.Post fyrir birgðatínsluna sem er til.';
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Pick");
        ActivityHeader.SetRange("Source Document", ToActivitySource(SourceDocument));
        ActivityHeader.SetRange("Source No.", DocumentNo);
        if not ActivityHeader.FindSet() then
            exit(false);
        repeat
            Clear(PickJson);
            WriteOnePick(ActivityHeader, PickJson);
            Picks.Add(PickJson);
        until ActivityHeader.Next() = 0;
        Warning.Add('code', 'PreconditionFailed');
        Warning.Add('message', ExistsLbl);
        Warning.Add('parameter', 'sourceNo');
        Warning.Add('nextStep', ExistsNextStepLbl);
        Warnings.Add(Warning);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('sourceDocument', SourceDocumentName(SourceDocument));
        ResponseJson.Add('sourceNo', DocumentNo);
        ResponseJson.Add('pickCount', Picks.Count());
        ResponseJson.Add('picks', Picks);
        ResponseJson.Add('warnings', Warnings);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
        exit(true);
    end;

    local procedure WriteCreated(var Argument: Record "Message Argument ori")
    var
        Context: Codeunit "Whse InvtPick Context ori";
        Result: JsonObject;
        ResponseJson: JsonObject;
        Token: JsonToken;
        MissingResultErr: Label 'The inventory pick was created but its number was not returned.', Comment = 'is-IS=Birgðatínslan var stofnuð en númer hennar skilaði sér ekki.';
        MissingResultNextStepLbl: Label 'Read the returned text and correct the source document or the inventory.', Comment = 'is-IS=Lestu textann sem skilaði sér og leiðréttu upprunaskjalið eða birgðirnar.';
    begin
        if not Context.TryGetResult(Result) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'pickNo', '', '', MissingResultNextStepLbl);
            exit;
        end;
        ResponseJson.Add('status', 'Success');
        CopyValue(Result, ResponseJson, 'sourceDocument');
        CopyValue(Result, ResponseJson, 'sourceNo');
        if not Result.Get('picks', Token) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'picks', '', '', MissingResultNextStepLbl);
            exit;
        end;
        ResponseJson.Add('pickCount', Token.AsArray().Count());
        ResponseJson.Add('picks', Token.AsArray());
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure WriteOnePick(ActivityHeader: Record "Warehouse Activity Header"; var PickJson: JsonObject)
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
        PickJson.Add('pickNo', ActivityHeader."No.");
        PickJson.Add('pickSystemId', Format(ActivityHeader.SystemId, 0, 4));
        PickJson.Add('locationCode', ActivityHeader."Location Code");
        PickJson.Add('lineCount', Lines.Count());
        PickJson.Add('lines', Lines);
    end;

    local procedure ResolveDocument(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var SourceDocument: Enum "Warehouse Request Source Document"; var DocumentNo: Code[20])
    var
        Context: Codeunit "Whse InvtPick Context ori";
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
        if not Released then begin
            RefuseNotReleased(Argument, DocumentNo);
            exit;
        end;
        CheckLocations(Argument, Locations);
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
            SourceDocument::"Sales Order":
                exit(LoadSalesOrder(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
            SourceDocument::"Purchase Return Order":
                exit(LoadPurchaseReturn(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
            SourceDocument::"Outbound Transfer":
                exit(LoadTransfer(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
            SourceDocument::"Assembly Consumption":
                exit(LoadAssembly(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
            SourceDocument::"Prod. Consumption":
                exit(LoadProduction(Argument, SourceNoText, SystemIdText, DocumentNo, Released, Locations));
        end;
        exit(false);
    end;

    local procedure LoadSalesOrder(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        if not FindSalesHeader(Argument, SalesHeader, SourceNoText, SystemIdText) then
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

    local procedure FindSalesHeader(var Argument: Record "Message Argument ori"; var SalesHeader: Record "Sales Header"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        SystemId: Guid;
        ById: Boolean;
    begin
        if not TryReadGuid(Argument, SystemIdText, SystemId, ById) then
            exit(false);
        if ById then begin
            if SalesHeader.GetBySystemId(SystemId) and (SalesHeader."Document Type" = SalesHeader."Document Type"::Order) then begin
                if (SourceNoText <> '') and (SalesHeader."No." <> CopyStr(SourceNoText, 1, MaxStrLen(SalesHeader."No."))) then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
                exit(true);
            end;
            if (SourceNoText <> '') and SalesHeader.Get(SalesHeader."Document Type"::Order, CopyStr(SourceNoText, 1, MaxStrLen(SalesHeader."No."))) then
                exit(Conflict(Argument, SourceNoText, SystemIdText));
            exit(NotFound(Argument, SourceNoText, SystemIdText));
        end;
        if SalesHeader.Get(SalesHeader."Document Type"::Order, CopyStr(SourceNoText, 1, MaxStrLen(SalesHeader."No."))) then
            exit(true);
        exit(NotFound(Argument, SourceNoText, SystemIdText));
    end;

    local procedure LoadPurchaseReturn(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
    begin
        if not FindPurchaseHeader(Argument, PurchaseHeader, SourceNoText, SystemIdText) then
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

    local procedure FindPurchaseHeader(var Argument: Record "Message Argument ori"; var PurchaseHeader: Record "Purchase Header"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        SystemId: Guid;
        ById: Boolean;
    begin
        if not TryReadGuid(Argument, SystemIdText, SystemId, ById) then
            exit(false);
        if ById then begin
            if PurchaseHeader.GetBySystemId(SystemId) and (PurchaseHeader."Document Type" = PurchaseHeader."Document Type"::"Return Order") then begin
                if (SourceNoText <> '') and (PurchaseHeader."No." <> CopyStr(SourceNoText, 1, MaxStrLen(PurchaseHeader."No."))) then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
                exit(true);
            end;
            if (SourceNoText <> '') and PurchaseHeader.Get(PurchaseHeader."Document Type"::"Return Order", CopyStr(SourceNoText, 1, MaxStrLen(PurchaseHeader."No."))) then
                exit(Conflict(Argument, SourceNoText, SystemIdText));
            exit(NotFound(Argument, SourceNoText, SystemIdText));
        end;
        if PurchaseHeader.Get(PurchaseHeader."Document Type"::"Return Order", CopyStr(SourceNoText, 1, MaxStrLen(PurchaseHeader."No."))) then
            exit(true);
        exit(NotFound(Argument, SourceNoText, SystemIdText));
    end;

    local procedure LoadTransfer(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        TransferHeader: Record "Transfer Header";
        TransferLine: Record "Transfer Line";
    begin
        if not FindTransferHeader(Argument, TransferHeader, SourceNoText, SystemIdText) then
            exit(false);
        DocumentNo := TransferHeader."No.";
        Released := TransferHeader.Status = TransferHeader.Status::Released;
        AddLocation(Locations, TransferHeader."Transfer-from Code");
        TransferLine.SetRange("Document No.", TransferHeader."No.");
        if TransferLine.FindSet() then
            repeat
                AddLocation(Locations, TransferLine."Transfer-from Code");
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

    local procedure LoadAssembly(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        AssemblyHeader: Record "Assembly Header";
        AssemblyLine: Record "Assembly Line";
    begin
        if not FindAssemblyHeader(Argument, AssemblyHeader, SourceNoText, SystemIdText) then
            exit(false);
        DocumentNo := AssemblyHeader."No.";
        Released := AssemblyHeader.Status = AssemblyHeader.Status::Released;
        AddLocation(Locations, AssemblyHeader."Location Code");
        AssemblyLine.SetRange("Document Type", AssemblyHeader."Document Type");
        AssemblyLine.SetRange("Document No.", AssemblyHeader."No.");
        AssemblyLine.SetRange(Type, AssemblyLine.Type::Item);
        if AssemblyLine.FindSet() then
            repeat
                AddLocation(Locations, AssemblyLine."Location Code");
            until AssemblyLine.Next() = 0;
        exit(true);
    end;

    local procedure FindAssemblyHeader(var Argument: Record "Message Argument ori"; var AssemblyHeader: Record "Assembly Header"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        SystemId: Guid;
        ById: Boolean;
    begin
        if not TryReadGuid(Argument, SystemIdText, SystemId, ById) then
            exit(false);
        if ById then begin
            if AssemblyHeader.GetBySystemId(SystemId) and (AssemblyHeader."Document Type" = AssemblyHeader."Document Type"::Order) then begin
                if (SourceNoText <> '') and (AssemblyHeader."No." <> CopyStr(SourceNoText, 1, MaxStrLen(AssemblyHeader."No."))) then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
                exit(true);
            end;
            if (SourceNoText <> '') and AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, CopyStr(SourceNoText, 1, MaxStrLen(AssemblyHeader."No."))) then
                exit(Conflict(Argument, SourceNoText, SystemIdText));
            exit(NotFound(Argument, SourceNoText, SystemIdText));
        end;
        if AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, CopyStr(SourceNoText, 1, MaxStrLen(AssemblyHeader."No."))) then
            exit(true);
        exit(NotFound(Argument, SourceNoText, SystemIdText));
    end;

    local procedure LoadProduction(var Argument: Record "Message Argument ori"; SourceNoText: Text; SystemIdText: Text; var DocumentNo: Code[20]; var Released: Boolean; var Locations: List of [Code[10]]): Boolean
    var
        ProductionOrder: Record "Production Order";
        Component: Record "Prod. Order Component";
    begin
        if not FindProductionOrder(Argument, ProductionOrder, SourceNoText, SystemIdText) then
            exit(false);
        DocumentNo := ProductionOrder."No.";
        Released := ProductionOrder.Status = ProductionOrder.Status::Released;
        AddLocation(Locations, ProductionOrder."Location Code");
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        if Component.FindSet() then
            repeat
                AddLocation(Locations, Component."Location Code");
            until Component.Next() = 0;
        exit(true);
    end;

    local procedure FindProductionOrder(var Argument: Record "Message Argument ori"; var ProductionOrder: Record "Production Order"; SourceNoText: Text; SystemIdText: Text): Boolean
    var
        SystemId: Guid;
        ById: Boolean;
    begin
        if not TryReadGuid(Argument, SystemIdText, SystemId, ById) then
            exit(false);
        if ById then begin
            if ProductionOrder.GetBySystemId(SystemId) then begin
                if (SourceNoText <> '') and (ProductionOrder."No." <> CopyStr(SourceNoText, 1, MaxStrLen(ProductionOrder."No."))) then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
                exit(true);
            end;
            if SourceNoText <> '' then begin
                ProductionOrder.Reset();
                ProductionOrder.SetRange("No.", CopyStr(SourceNoText, 1, MaxStrLen(ProductionOrder."No.")));
                if ProductionOrder.FindFirst() then
                    exit(Conflict(Argument, SourceNoText, SystemIdText));
            end;
            exit(NotFound(Argument, SourceNoText, SystemIdText));
        end;
        ProductionOrder.SetRange("No.", CopyStr(SourceNoText, 1, MaxStrLen(ProductionOrder."No.")));
        ProductionOrder.SetRange(Status, ProductionOrder.Status::Released);
        if ProductionOrder.FindFirst() then
            exit(true);
        ProductionOrder.SetRange(Status);
        if ProductionOrder.FindFirst() then
            exit(true);
        exit(NotFound(Argument, SourceNoText, SystemIdText));
    end;

    local procedure CheckLocations(var Argument: Record "Message Argument ori"; Locations: List of [Code[10]])
    var
        Location: Record Location;
        LocationCode: Code[10];
        SawPick: Boolean;
    begin
        if Locations.Count() = 0 then begin
            RefuseNotReleased(Argument, '');
            exit;
        end;
        foreach LocationCode in Locations do begin
            Location.SetLoadFields(Code, "Require Pick", "Require Shipment", "Directed Put-away and Pick");
            if not Location.Get(LocationCode) then begin
                NotFound(Argument, LocationCode, '');
                exit;
            end;
            if Location."Directed Put-away and Pick" or Location."Require Shipment" then begin
                RefuseShipmentLocation(Argument, LocationCode);
                exit;
            end;
            if Location."Require Pick" then
                SawPick := true
            else begin
                RefuseNotReleased(Argument, LocationCode);
                exit;
            end;
        end;
        if not SawPick then
            RefuseNotReleased(Argument, '');
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
            'SALESORDER':
                SourceDocument := SourceDocument::"Sales Order";
            'PURCHASERETURNORDER':
                SourceDocument := SourceDocument::"Purchase Return Order";
            'OUTBOUNDTRANSFER':
                SourceDocument := SourceDocument::"Outbound Transfer";
            'ASSEMBLYCONSUMPTION':
                SourceDocument := SourceDocument::"Assembly Consumption";
            'PROD.CONSUMPTION', 'PRODCONSUMPTION', 'PRODUCTIONCONSUMPTION':
                SourceDocument := SourceDocument::"Prod. Consumption";
            else
                exit(false);
        end;
        exit(true);
    end;

    local procedure SourceDocumentName(SourceDocument: Enum "Warehouse Request Source Document"): Text
    begin
        case SourceDocument of
            SourceDocument::"Sales Order":
                exit('Sales Order');
            SourceDocument::"Purchase Return Order":
                exit('Purchase Return Order');
            SourceDocument::"Outbound Transfer":
                exit('Outbound Transfer');
            SourceDocument::"Assembly Consumption":
                exit('Assembly Consumption');
            SourceDocument::"Prod. Consumption":
                exit('Prod. Consumption');
        end;
    end;

    local procedure ToActivitySource(SourceDocument: Enum "Warehouse Request Source Document") ActivitySource: Enum "Warehouse Activity Source Document"
    begin
        case SourceDocument of
            SourceDocument::"Sales Order":
                exit(ActivitySource::"Sales Order");
            SourceDocument::"Purchase Return Order":
                exit(ActivitySource::"Purchase Return Order");
            SourceDocument::"Outbound Transfer":
                exit(ActivitySource::"Outbound Transfer");
            SourceDocument::"Assembly Consumption":
                exit(ActivitySource::"Assembly Consumption");
            SourceDocument::"Prod. Consumption":
                exit(ActivitySource::"Prod. Consumption");
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
        InvalidLbl: Label 'sourceDocument %1 is not a supported inventory pick source.', Comment = '%1 = source document, is-IS=sourceDocument %1 er ekki studd birgðatínsluuppspretta.';
        InvalidNextStepLbl: Label 'Send Sales Order, Purchase Return Order, Outbound Transfer, Assembly Consumption or Prod. Consumption.', Comment = 'is-IS=Sendu Sales Order, Purchase Return Order, Outbound Transfer, Assembly Consumption eða Prod. Consumption.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(InvalidLbl, SourceText), 'sourceDocument', SourceText, '', InvalidNextStepLbl);
    end;

    local procedure RefuseNotReleased(var Argument: Record "Message Argument ori"; Received: Text)
    var
        NotReleasedLbl: Label 'The source document is not released, or the location does not require pick.', Comment = 'is-IS=Upprunaskjalið er ekki staðfest, eða staðsetningin krefst ekki tínslu.';
        NotReleasedNextStepLbl: Label 'Release the document with Sales.Document.Release, or post the document directly.', Comment = 'is-IS=Staðfestu skjalið með Sales.Document.Release, eða bókaðu skjalið beint.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NotReleasedLbl, 'sourceNo', Received, '', NotReleasedNextStepLbl);
    end;

    local procedure RefuseShipmentLocation(var Argument: Record "Message Argument ori"; LocationCode: Code[10])
    var
        ShipmentLbl: Label 'Location %1 uses warehouse shipments.', Comment = '%1 = location, is-IS=Staðsetning %1 notar vöruhúsaafhendingar.';
        ShipmentNextStepLbl: Label 'Use Warehouse.Shipment.Create and Warehouse.Pick.Create instead.', Comment = 'is-IS=Notaðu Warehouse.Shipment.Create og Warehouse.Pick.Create í staðinn.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(ShipmentLbl, LocationCode), 'sourceDocument', LocationCode, '', ShipmentNextStepLbl);
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
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
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
}
