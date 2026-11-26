namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Location;
using Microsoft.Inventory.Transfer;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.CrossDock;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;

/// <summary>Calculates cross-dock suggestions on selected receipt lines using Business Central, with a rolled-back preview.</summary>
codeunit 10078444 "Whse Rcpt CrossDock Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    begin
        Calculate();
    end;

    local procedure Calculate()
    var
        Header: Record "Warehouse Receipt Header";
        Line: Record "Warehouse Receipt Line";
        Opportunity: Record "Whse. Cross-Dock Opportunity";
        Calculation: Codeunit "Whse. Cross-Dock Management";
        Scope: Codeunit "Whse CrossDock Scope ori";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        Result: JsonObject;
        Lines: JsonArray;
        Total: Decimal;
    begin
        Context.TryGetPayload(Payload);
        Header.Get(Values.TextValue(Payload, 'whseReceiptNo'));
        Scope.SetScope(Header."No.", Values.TextValue(Payload, 'lineFilter'));
        BindSubscription(Scope);
        Calculation.CalculateCrossDockLines(Opportunity, '', Header."No.", Header."Location Code");
        UnbindSubscription(Scope);
        Line.SetRange("No.", Header."No.");
        if Values.TextValue(Payload, 'lineFilter') <> '' then
            Line.SetFilter("Line No.", Values.TextValue(Payload, 'lineFilter'));
        if Line.FindSet() then
            repeat
                Lines.Add(LineResult(Line));
                Total += Line."Qty. to Cross-Dock";
            until Line.Next() = 0;
        Result.Add('status', 'Success');
        Result.Add('whseReceiptNo', Header."No.");
        Result.Add('lines', Lines);
        Result.Add('totalQtyToCrossDock', Total);
        Context.SetResult(Result);
        if not Values.BooleanValue(Payload, 'apply') then
            Error(PreviewRollback());
    end;

    /// <summary>Returns whether receipt lines and suggestion working data can be changed.</summary>
    /// <returns>True for a caller with the required write permissions.</returns>
    procedure IsEnabled(): Boolean
    var
        Line: Record "Warehouse Receipt Line";
        Opportunity: Record "Whse. Cross-Dock Opportunity";
        SalesLine: Record "Sales Line";
        PurchaseLine: Record "Purchase Line";
        TransferLine: Record "Transfer Line";
    begin
        exit(Line.ReadPermission() and Line.WritePermission() and Opportunity.ReadPermission() and Opportunity.WritePermission() and
            SalesLine.ReadPermission() and PurchaseLine.ReadPermission() and TransferLine.ReadPermission());
    end;

    /// <summary>Returns the receipt header filter table.</summary>
    /// <returns>Warehouse receipt header table number.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Receipt Header");
    end;

    /// <summary>Returns discovery text.</summary>
    /// <returns>A short description.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Calculates cross-dock opportunities on a warehouse receipt; optionally previews without saving.', Comment = 'is-IS=Reiknar tækifæri til gegnumstreymis á vöruhúsamóttöku; getur forskoðað án þess að vista.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search terms.</summary>
    /// <returns>Search keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'cross-dock receipt, calculate cross docking, receipt demand, preview cross dock', Comment = 'is-IS=gegnumstreymi móttöku, reikna gegnumstreymi, eftirspurn móttöku, forskoða gegnumstreymi';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description.</summary>
    /// <returns>Effect and preview guidance.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Changes data. Recalculates receipt cross-dock suggestions. Send apply false to preview and roll back.', Comment = 'is-IS=Breytir gögnum. Endurreiknar tillögur um gegnumstreymi móttöku. Sendu apply false til að forskoða og afturkalla.';
    begin
        exit(SelectionLbl);
    end;

    /// <summary>Returns the subject envelope.</summary>
    /// <param name="Envelope">Receives the envelope.</param>
    /// <returns>True.</returns>
    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('receipt no.');
        Forms.Add('guid');
        Envelope := Parts.RecordEnvelope(Forms, 'The open warehouse receipt number or SystemId.', false);
        exit(true);
    end;

    /// <summary>Returns accepted targets.</summary>
    /// <param name="Target">Receives targets.</param>
    /// <returns>True.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        Mgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(Mgt.TargetEntry('subject', 'receipt no. or SystemId', 'The warehouse receipt.'));
        Target.Add(Mgt.TargetEntry('data.whseReceiptNo, data.systemId, data.id', 'receipt no. or SystemId', 'Every supplied identifier must identify the same receipt.'));
        exit(true);
    end;

    /// <summary>Returns parameters.</summary>
    /// <param name="Parameters">Receives parameters.</param>
    /// <returns>True.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        Mgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
        Children: JsonArray;
    begin
        Parameters.Add(Mgt.Parameter('whseReceiptNo', 'string', false, 'Warehouse receipt number. Required unless subject, systemId or id is sent.'));
        Parameters.Add(Mgt.Parameter('systemId', 'string', false, 'Warehouse receipt SystemId as a GUID.'));
        Parameters.Add(Mgt.Parameter('id', 'string', false, 'Alias for systemId.'));
        Children.Add(Mgt.Parameter('lineNo', 'integer', true, 'A positive receipt line number; each may appear once.'));
        Entry := Mgt.Parameter('lineNos', 'array', false, 'Optional nonempty array of positive integer line numbers. Omit for all receipt lines.');
        Entry.Add('children', Children);
        Parameters.Add(Entry);
        Parameters.Add(Mgt.Parameter('apply', 'boolean', false, 'Defaults to true. False reports the same opportunities and rolls all calculation changes back.'));
        exit(true);
    end;

    /// <summary>Returns response fields.</summary>
    /// <param name="Response">Receives response.</param>
    /// <returns>True.</returns>
    procedure GetResponse(var Response: JsonObject): Boolean
    var
        Mgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(Mgt.ResponseField('whseReceiptNo', 'string', 'Warehouse receipt number.'));
        Fields.Add(Mgt.ResponseField('lines', 'array', 'Selected lines: lineNo, itemNo, qtyToReceive, qtyToCrossDock, crossDockBinCode, opportunities.'));
        Fields.Add(Mgt.ResponseField('opportunities', 'array', 'Per line: sourceType (source table number), sourceNo, sourceLineNo, dueDate, qtyNeeded, qtyToCrossDock. Quantities use the opportunity unit of measure.'));
        Fields.Add(Mgt.ResponseField('totalQtyToCrossDock', 'number', 'Sum of selected receipt-line quantities in their respective units of measure.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns declared refusal codes and recovery guidance.</summary>
    /// <param name="Errors">Receives errors.</param>
    /// <returns>True.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'No receipt identifier was supplied.', 'Send whseReceiptNo, systemId or id, or the receipt as subject.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'An identifier, apply or lineNos has the wrong format.', FormatNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'An undeclared parameter was sent.', 'Remove the unknown parameter and consult Help.Implementation.Get.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The receipt or one of its selected lines does not exist.', 'Read Warehouse.Document.Get and send identifiers from that receipt.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'Identifiers name different receipts.', 'Send identifiers for one receipt.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot change receipt lines or cross-dock working suggestions.', PermissionNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use cross-docking, preview cannot isolate, or Business Central refuses the calculation.', SetupNextStep());
        exit(true);
    end;

    /// <summary>Returns write effect and permission requirements.</summary>
    /// <param name="Effect">Receives effect.</param>
    /// <returns>True.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Replaces only selected receipt cross-dock working suggestions and quantities. apply false rolls the calculation back. Nothing is posted; expectedCount is not required.', 'BIFROST Whse - Full ori', false);
        exit(true);
    end;

    /// <summary>Declares no metering.</summary>
    /// <param name="Metering">Unused.</param>
    /// <returns>False.</returns>
    procedure GetMetering(var Metering: JsonObject): Boolean
    begin
        exit(false);
    end;

    /// <summary>Returns related operations.</summary>
    /// <param name="Related">Receives related operations.</param>
    /// <returns>True.</returns>
    procedure GetRelated(var Related: JsonArray): Boolean
    var
        Mgt: Codeunit "Msg Contract Mgt ori";
    begin
        Related.Add(Mgt.RelatedEntry('Warehouse.Document.Get', 'Read the receipt and its cross-dock quantities.'));
        Related.Add(Mgt.RelatedEntry('Warehouse.Receipt.Post', 'Receive the goods after applying the suggestions.'));
        Related.Add(Mgt.RelatedEntry('Warehouse.Putaway.Create', 'Create the put-away after receiving.'));
        exit(true);
    end;

    /// <summary>Returns the inbound workflow.</summary>
    /// <param name="Workflow">Receives workflow.</param>
    /// <returns>True.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.InboundWorkflow(Workflow);
        exit(true);
    end;

    /// <summary>Returns a preview example.</summary>
    /// <param name="Examples">Receives examples.</param>
    /// <returns>True.</returns>
    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        Mgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(Mgt.Example('Preview cross-docking on selected receipt lines', '{"whseReceiptNo":"R-100","lineNos":[10000],"apply":false}', '{"status":"Success","whseReceiptNo":"R-100","lines":[{"lineNo":10000,"itemNo":"X","qtyToReceive":5,"qtyToCrossDock":3,"crossDockBinCode":"CROSS","opportunities":[]}],"totalQtyToCrossDock":3}'));
        exit(true);
    end;

    /// <summary>Returns the English overview chapter.</summary>
    /// <param name="Overview">Receives overview.</param>
    /// <returns>True.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Calculates cross-dock opportunities for an open warehouse receipt using Business Central demand and location rules. Apply the suggestions or preview without saving.';
        exit(true);
    end;

    /// <summary>Returns English notes.</summary>
    /// <param name="Notes">Receives notes.</param>
    /// <returns>True.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'The location must already have Use Cross-Docking enabled; setup is never changed. Items must also allow cross-docking. Only lines with quantity to receive are calculated. Omit lineNos for all lines; an explicit array must be nonempty and contain unique positive integers belonging to this receipt. ' +
            'Business Central replaces its working opportunities for the selected receipt lines. No document, line or ledger entry is deleted. apply defaults to true and persists the suggestion; apply false runs the identical calculation and rolls it back, including opportunities and receipt quantities. ' +
            'A refusal leaves all calculation changes rolled back. Preview requires an isolated transaction and is refused when Omit Commit is enabled. Standard Business Central warehouse permissions must allow receipt and cross-dock working-data writes and demand reads; this operation never elevates base-application access. Posting and put-away creation are separate operations with their own permission gates. Quantity totals combine the selected line units of measure.';
        exit(true);
    end;

    /// <summary>Returns inbound direction.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit("Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the entire request before calculating in isolation.</summary>
    /// <param name="Argument">Request and response.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        Header: Record "Warehouse Receipt Header";
        Location: Record Location;
        Context: Codeunit "Whse Write Context ori";
        Lookup: Codeunit "Whse Record Lookup ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        Request: JsonObject;
        Result: JsonObject;
        Token: JsonToken;
        SystemId: Guid;
        KeyName: Text;
        LineFilter: Text;
        Apply: Boolean;
        Ran: Boolean;
        Failure: Text;
        UnknownLbl: Label 'Unknown parameter %1.', Comment = '%1 = parameter, is-IS=Óþekkt færibreyta %1.';
        DeniedLbl: Label 'You do not have permission to calculate cross-docking.', Comment = 'is-IS=Þú hefur ekki heimild til að reikna gegnumstreymi.';
        SetupLbl: Label 'The receipt location does not use cross-docking.', Comment = 'is-IS=Staðsetning móttökunnar notar ekki gegnumstreymi.';
        InvalidLbl: Label 'The cross-dock request has an invalid format.', Comment = 'is-IS=Beiðnin um gegnumstreymi er á ógildu sniði.';
        IsolateLbl: Label 'Preview requires an isolated transaction.', Comment = 'is-IS=Forskoðun krefst einangraðrar færslu.';
    begin
        Context.Reset();
        if not IsEnabled() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', PermissionNextStep());
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not Lookup.TryReadIdentifiers(Argument, 'whseReceiptNo=no,systemId=guid,id=guid', Request) then
            exit;
        foreach KeyName in Request.Keys() do
            if not (KeyName in ['whseReceiptNo', 'systemId', 'id', 'lineNos', 'apply']) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, '', '', FormatNextStep());
                exit;
            end;
        foreach KeyName in Request.Keys() do
            if KeyName in ['systemId', 'id'] then begin
                Request.Get(KeyName, Token);
                if Token.AsValue().AsText() <> '' then
                    if not Values.IsGuid(Token.AsValue().AsText()) then begin
                        Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameterFormat, InvalidLbl, KeyName, Token.AsValue().AsText(), 'GUID', FormatNextStep());
                        exit;
                    end;
            end;
        Apply := true;
        if Request.Get('apply', Token) then begin
            if not IsBoolean(Token) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameterFormat, InvalidLbl, 'apply', '', '', FormatNextStep());
                exit;
            end;
            Apply := Token.AsValue().AsBoolean();
        end;
        if not Lookup.FindRecord(Argument, Database::"Warehouse Receipt Header", 'guid|no', 'whseReceiptNo=no,systemId=guid,id=guid', SystemId) then
            exit;
        Header.GetBySystemId(SystemId);
        if not ReadLines(Argument, Request, Header."No.", LineFilter) then
            exit;
        Location.Get(Header."Location Code");
        if not Location."Use Cross-Docking" then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, SetupLbl, 'whseReceiptNo', Header."No.", '', SetupNextStep());
            exit;
        end;
        if not Apply and Argument."Omit Commit" then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, IsolateLbl, 'apply', '', '', SetupNextStep());
            exit;
        end;
        Payload.Add('whseReceiptNo', Header."No.");
        Payload.Add('lineFilter', LineFilter);
        Payload.Add('apply', Apply);
        Context.SetPayload(Payload);
        if Argument."Omit Commit" then begin
            Codeunit.Run(Codeunit::"Whse Rcpt CrossDock Impl ori");
            Ran := true;
        end else
            Ran := Codeunit.Run(Codeunit::"Whse Rcpt CrossDock Impl ori");
        Failure := GetLastErrorText();
        if Context.TryGetResult(Result) and (Ran or ((not Apply) and (Failure = PreviewRollback()))) then begin
            Context.Reset();
            Argument.SetResponseJson(Result);
            Argument."Content Type" := Argument.GetContentTypeJson();
            exit;
        end;
        Context.Reset();
        Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, Failure, '', '', '', SetupNextStep());
    end;

    local procedure ReadLines(var Argument: Record "Message Argument ori"; Request: JsonObject; ReceiptNo: Code[20]; var LineFilter: Text): Boolean
    var
        Line: Record "Warehouse Receipt Line";
        Token: JsonToken;
        Entry: JsonToken;
        Numbers: List of [Integer];
        Number: Integer;
        Written: Text;
        InvalidLbl: Label 'lineNos must contain unique positive integer receipt line numbers.', Comment = 'is-IS=lineNos verður að innihalda einkvæm jákvæð heiltölunúmer móttökulína.';
        MissingLbl: Label 'Receipt line %1 was not found on receipt %2.', Comment = '%1 = line number, %2 = receipt number, is-IS=Móttökulína %1 fannst ekki á móttöku %2.';
    begin
        if not Request.Get('lineNos', Token) then
            exit(true);
        if Token.IsArray() then
            if Token.AsArray().Count() > 0 then begin
                foreach Entry in Token.AsArray() do begin
                    Entry.WriteTo(Written);
                    if not Entry.IsValue() or (DelChr(Written, '=', '0123456789') <> '') or not Evaluate(Number, Written, 9) then
                        break;
                    if (Number <= 0) or Numbers.Contains(Number) then
                        break;
                    if not Line.Get(ReceiptNo, Number) then begin
                        Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(MissingLbl, Number, ReceiptNo), 'lineNos', Written, '', FormatNextStep());
                        exit(false);
                    end;
                    Numbers.Add(Number);
                    if LineFilter <> '' then
                        LineFilter += '|';
                    LineFilter += Written;
                end;
                if Numbers.Count() = Token.AsArray().Count() then
                    exit(true);
            end;
        Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameterFormat, InvalidLbl, 'lineNos', '', '', FormatNextStep());
        exit(false);
    end;

    local procedure LineResult(Line: Record "Warehouse Receipt Line") Result: JsonObject
    var
        Opportunity: Record "Whse. Cross-Dock Opportunity";
        Values: Codeunit "Whse Msg Values ori";
        Opportunities: JsonArray;
        Entry: JsonObject;
    begin
        Opportunity.SetRange("Source Template Name", '');
        Opportunity.SetRange("Source Name/No.", Line."No.");
        Opportunity.SetRange("Source Line No.", Line."Line No.");
        Opportunity.SetRange("Location Code", Line."Location Code");
        if Opportunity.FindSet() then
            repeat
                Clear(Entry);
                Entry.Add('sourceType', Opportunity."To Source Type");
                Entry.Add('sourceNo', Opportunity."To Source No.");
                Entry.Add('sourceLineNo', Opportunity."To Source Line No.");
                Entry.Add('dueDate', Values.DateText(Opportunity."Due Date"));
                Entry.Add('qtyNeeded', Opportunity."Qty. Needed");
                Entry.Add('qtyToCrossDock', Opportunity."Qty. to Cross-Dock");
                Opportunities.Add(Entry);
            until Opportunity.Next() = 0;
        Result.Add('lineNo', Line."Line No.");
        Result.Add('itemNo', Line."Item No.");
        Result.Add('qtyToReceive', Line."Qty. to Receive");
        Result.Add('qtyToCrossDock', Line."Qty. to Cross-Dock");
        Result.Add('crossDockBinCode', Line."Cross-Dock Bin Code");
        Result.Add('opportunities', Opportunities);
    end;

    local procedure IsBoolean(Token: JsonToken): Boolean
    var
        Written: Text;
    begin
        Token.WriteTo(Written);
        exit((Written = 'true') or (Written = 'false'));
    end;

    local procedure PreviewRollback(): Text
    begin
        exit('BIFROST_WAREHOUSE_CROSSDOCK_PREVIEW_ROLLBACK');
    end;

    local procedure FormatNextStep(): Text
    var
        NextStepLbl: Label 'Send text receipt identifiers, true or false for apply, and unique positive integers in lineNos; consult Warehouse.Document.Get.', Comment = 'is-IS=Sendu móttökuauðkenni sem texta, true eða false fyrir apply og einkvæmar jákvæðar heiltölur í lineNos; skoðaðu Warehouse.Document.Get.';
    begin
        exit(NextStepLbl);
    end;

    local procedure SetupNextStep(): Text
    var
        NextStepLbl: Label 'Check Use Cross-Docking on the receipt location and item, then retry without Omit Commit for preview; setup is never changed by this operation.', Comment = 'is-IS=Athugaðu Nota gegnumstreymi á staðsetningu móttökunnar og vörunni og reyndu aftur án Omit Commit við forskoðun; þessi aðgerð breytir aldrei uppsetningu.';
    begin
        exit(NextStepLbl);
    end;

    local procedure PermissionNextStep(): Text
    var
        NextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
    begin
        exit(NextStepLbl);
    end;
}
