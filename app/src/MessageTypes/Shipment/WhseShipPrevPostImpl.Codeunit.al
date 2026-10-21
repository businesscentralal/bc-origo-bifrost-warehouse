namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Shipment.PreviewPost message type.
/// Simulates posting a Warehouse Shipment and returns the resulting ledger entries
/// (Item Ledger Entry, Value Entry, Posted Whse. Shipment Header/Line, plus G/L Entry
/// and VAT Entry when invoicing is included) without committing changes. The transaction
/// is rolled back after capturing the simulated entries via the Posting Preview Event Handler.
/// Mirrors BC's standard Warehouse Shipment preview action: BC's `Whse.-Post Shipment (Yes/No)`
/// preview subscriber forces `Invoice = true` for the simulated post, so this preview reports
/// the full Ship + Invoice impact regardless of the header's `Invoice` flag.
/// </summary>

using Microsoft.Finance.GeneralLedger.Ledger;
using Microsoft.Finance.GeneralLedger.Preview;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Foundation.Navigate;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Posting;

using Origo.Bifrost;

codeunit 10078408 "Whse Ship. Prev. Post Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;
    Permissions = tabledata "Warehouse Shipment Header" = R,
                  tabledata "Warehouse Shipment Line" = R;

    procedure IsEnabled(): Boolean
    begin
        // Preview does not consult the warehouse posting gate.
        exit(true);
    end;

    procedure GetFilterTableNo() FilterTableId: Integer
    begin
        exit(Database::"Warehouse Shipment Header");
    end;

    procedure GetDescription() Description: Text[250]
    var
        DescriptionLbl: Label 'Simulates posting a warehouse shipment (ship and invoice) and returns the entries it would create, without saving anything.', Comment = 'is-IS=Hermir bókun vöruhúsaafhendingar (afhending og reikningur) og skilar færslunum sem hún myndi búa til, án þess að vista neitt.';
    begin
        exit(DescriptionLbl);
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'preview warehouse shipment, simulate shipment, what would the shipment post', Comment = 'is-IS=forskoða vöruhúsaafhendingu, herma afhendingu, hvað myndi afhendingin bóka';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Read-only. Simulates Ship + Invoice and rolls back; use Warehouse.Shipment.Post to commit the posting.', Comment = 'is-IS=Lesaðgangur. Hermir Sending + Reikning og afturkallar; notaðu Warehouse.Shipment.Post til að framkvæma bókunina.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('guid');
        Forms.Add('document no.');
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Shipment to preview: its SystemId or No.', false);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the Warehouse Shipment Header.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the Warehouse Shipment Header.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId, data.recordSystemId, data.id, data.shipmentNo, data.no', 'guid or document no.', 'The identifier keys accepted for the Warehouse Shipment Header. Every supplied identifier is tried; conflicting identifiers are refused.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        LineChildren: JsonArray;
        LinesParameter: JsonObject;
    begin
        LineChildren.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Warehouse shipment line number. Each line may be listed once.'));
        LineChildren.Add(ContractMgt.Parameter('qtyToShip', 'number', true, 'Quantity to ship on that line in the preview, from zero up to the outstanding quantity, and at a location that requires pick up to the picked quantity not yet shipped.'));
        LinesParameter := ContractMgt.Parameter('lines', 'array', false, 'Optional per-line quantities to ship in the preview, the same as Warehouse.Shipment.Post. They are rolled back with the preview. Needs write permission on warehouse shipment lines.');
        LinesParameter.Add('children', LineChildren);
        Parameters.Add(LinesParameter);
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Warehouse shipment line number (inside lines).'));
        Parameters.Add(ContractMgt.Parameter('qtyToShip', 'number', true, 'Quantity to ship on that line, from zero up to the outstanding quantity (inside lines).'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('entryCount', 'integer', 'Number of predicted ledger entries.'));
        Fields.Add(ContractMgt.ResponseField('glEntryCount', 'integer', 'Number of predicted G/L entries.'));
        Fields.Add(ContractMgt.ResponseField('rollback', 'boolean', 'Always true; the preview is rolled back.'));
        Fields.Add(ContractMgt.ResponseField('summary', 'string', 'Human-readable preview summary.'));
        Fields.Add(ContractMgt.ResponseField('shipmentNo', 'string', 'Warehouse Shipment number.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Warehouse location code.'));
        Fields.Add(ContractMgt.ResponseField('invoice', 'boolean', 'Always true because the BC preview path simulates Ship + Invoice.'));
        Fields.Add(ContractMgt.ResponseField('linesToPost', 'integer', 'Number of Warehouse Shipment lines considered.'));
        Fields.Add(ContractMgt.ResponseField('postingDate', 'string', 'Posting date used by the preview.'));
        Fields.Add(ContractMgt.ResponseField('lcyCode', 'string', 'Local currency code.'));
        Fields.Add(ContractMgt.ResponseField('predictedNumbers', 'array', 'Predicted posted document numbers.'));
        Fields.Add(ContractMgt.ResponseField('totals', 'object', 'Preview totals.'));
        Fields.Add(ContractMgt.ResponseField('preview', 'array', 'Captured preview entries grouped by table.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddDocumentPreviewErrors(Errors, 'Warehouse Shipment Header', 'systemId, recordSystemId, id, shipmentNo, no', 'qtyToShip', true, OmitCommitNextStep(), NothingToPostNextStep(), LinesDeniedNextStep());
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.ReadEffect(Effect, 'Simulates Ship + Invoice and rolls the transaction back; no persistent records are changed.', 'BIFROST Read ori');
        exit(true);
    end;

    procedure GetMetering(var Metering: JsonObject): Boolean
    begin
        exit(false);
    end;

    procedure GetRelated(var Related: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Post', 'Use it to commit the shipment posting after reviewing the preview.'));
        exit(true);
    end;

    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.OutboundWorkflow(Workflow);
        exit(true);
    end;

    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Preview shipping 2 on line 10000 of warehouse shipment SH000001',
            '{"shipmentNo":"SH000001","lines":[{"lineNo":10000,"qtyToShip":2}]}',
            '{"status":"Success","entryCount":6,"glEntryCount":4,"rollback":true,"summary":"Preview-posting warehouse shipment SH000001 (1 lines, Ship + Invoice) would create 6 ledger entries across 4 tables. Transaction is balanced.","shipmentNo":"SH000001","locationCode":"WHITE","invoice":true,"linesToPost":1,"postingDate":"2026-10-20","lcyCode":"ISK","predictedNumbers":["103001"],"totals":{},"preview":[]}'));
        Examples.Add(ContractMgt.Example(
            'Refused: more than the picked quantity on a location that requires pick',
            '{"shipmentNo":"SH000001","lines":[{"lineNo":10000,"qtyToShip":5}]}',
            '{"status":"Error","code":"PreconditionFailed","error":"The quantity 5 on line 10000 is more than the picked quantity 2 that is not yet shipped.","parameter":"lines[0].qtyToShip","received":"5","nextStep":"Register the pick first."}'));
        exit(true);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read-only posting preview for a warehouse shipment, the same as the Preview Posting action. It returns the entries that posting would create (ship and invoice) and rolls everything back. Optional lines set the quantity to ship per line inside the preview only. It cannot run inside a rollback chain (Omit Commit).';
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Nothing is saved: Business Central runs the posting and rolls it back, so the shipment, its lines and the ledgers are unchanged. Quantities sent in lines are applied inside the preview only; Qty. to Ship on the shipment keeps its real value. ' +
            'The preview always simulates ship and invoice, so invoice is always true in the answer and the entries include the invoicing of the source documents, even if you later post with Warehouse.Shipment.Post without invoice. ' +
            'The preview cannot run inside a rollback chain (Omit Commit) and is refused there. ' +
            'It does not use the posting permission sets that Warehouse.Shipment.Post needs, but sending lines needs write permission on warehouse shipment lines. ' +
            'At a location that requires pick a line quantity above the picked quantity that is not yet shipped is refused, so register the pick first. Unknown keys and bad line values are answered together as MultipleErrors. ' +
            'A shipment with no lines is answered as NothingToPreview, and so is a preview that produces no entries, for example when every line would ship zero. If Business Central refuses the posting during the preview, its error text is returned. ' +
            'linesToPost counts every line on the shipment, not only the lines in the request. predictedNumbers lists the distinct G/L document numbers seen in the rolled-back run, and is empty when no G/L entries are produced. ' +
            'Use Warehouse.Shipment.Post to post for real.';
        exit(true);
    end;

    procedure GetMessageDirection() MessageDirection: Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        GLSetup: Record "General Ledger Setup";
        TempDocumentEntry: Record "Document Entry" temporary;
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler";
        PostingPreviewHelper: Codeunit "Posting Preview Helper ori";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        PlannedLines: JsonArray;
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        TotalsJson: JsonObject;
        PredictedNumbersArray: JsonArray;
        PreviewArray: JsonArray;
        LCYCode: Code[10];
        LinesToPost: Integer;
        PostingDate: Date;
        EntryCount: Integer;
        GLEntryCount: Integer;
        Balanced: Boolean;
        Summary: Text;
        PreviewErrorText: Text;
        PreviewFieldNames: List of [Text];
        NoLinesToPostErr: Label 'Warehouse Shipment %1 has no lines to post.', Comment = '%1 = Whse. Shipment No., is-IS=Vöruhúsaafhending %1 hefur engar línur til bókunar.';
        PreviewFailedErr: Label 'Posting preview failed and no entries were captured. The shipment cannot be posted in its current state.', Comment = 'is-IS=Bókunarforsýning mistókst og engar færslur voru teknar. Sendingin getur ekki verið bókuð í núverandi stöðu.';

        OmitCommitPreviewErr: Label 'Posting preview cannot run inside a rollback chain (Omit Commit). Run this message type with Omit Commit set to false.', Comment = 'is-IS=Ekki er hægt að forskoða bókun innan afturköllunarkeðju (Omit Commit). Keyrðu þessa skilaboðategund með Omit Commit stillt á false.';

        NothingPreviewedLbl: Label 'Nothing was previewed.', Comment = 'is-IS=Ekkert var forskoðað.';
        LinesDeniedLbl: Label 'You do not have permission to set quantities on warehouse shipment lines.', Comment = 'is-IS=Þú hefur ekki heimild til að setja magn á línur vöruhúsaafhendingar.';
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if Argument."Omit Commit" then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, OmitCommitPreviewErr, '', '', '', OmitCommitNextStep());
            exit;
        end;

        if not WhseRecordLookup.TryReadIdentifiers(Argument, 'systemId=guid,recordSystemId=guid,id=guid,shipmentNo=no,no=no', RequestJson) then
            exit;
        // An unknown key is answered together with the lookup and line problems, so it does not hide them.
        RefuseUnknownKeys(RequestJson, Argument);
        if not FindWhseShipmentHeader(Argument, WhseShipmentHeader) then
            exit;

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if WhseShipmentLine.IsEmpty() then begin
            if Argument.HasCollectedErrors() then begin
                Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, NothingPreviewedLbl);
                exit;
            end;
            Argument.RespondWithError("Bifrost Error Code ori"::NothingToPreview, StrSubstNo(NoLinesToPostErr, WhseShipmentHeader."No."), '', '', '', NothingToPostNextStep());
            exit;
        end;
        DocLineQty.ReadLines(RequestJson, Argument, true, WhseShipmentHeader."No.", PlannedLines);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, NothingPreviewedLbl);
            exit;
        end;
        if PlannedLines.Count() > 0 then
            if not WhseShipmentLine.WritePermission() then begin
                Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, LinesDeniedLbl, 'lines', '', '', LinesDeniedNextStep());
                exit;
            end;
        LinesToPost := WhseShipmentLine.Count();
        PostingDate := WhseShipmentHeader."Posting Date";
        if PostingDate = 0D then
            PostingDate := WorkDate();

        WhseShipmentLine.FindFirst();

        GLSetup.Get();
        LCYCode := GLSetup."LCY Code";

        if not PreviewWhseShipment(WhseShipmentLine, PlannedLines, PostingPreviewEventHandler, PreviewErrorText) then begin
            if PreviewErrorText = '' then
                PreviewErrorText := PreviewFailedErr;
            PostingPreviewHelper.RespondWithPreviewError(Argument, PreviewErrorText, NothingToPostNextStep());
            exit;
        end;

        PostingPreviewHelper.GetPreviewFieldNames(PreviewFieldNames);

        PostingPreviewEventHandler.FillDocumentEntry(TempDocumentEntry);
        if TempDocumentEntry.FindSet() then
            repeat
                PostingPreviewHelper.AddTableToPreview(PreviewArray, PostingPreviewEventHandler, TempDocumentEntry."Table ID", TempDocumentEntry."Table Name", PreviewFieldNames);
            until TempDocumentEntry.Next() = 0;

        if not PostingPreviewHelper.EvaluatePreviewOutcome(Argument, PreviewArray, PostingPreviewEventHandler, NothingToPostNextStep(), TotalsJson, Balanced, EntryCount, GLEntryCount) then

            exit;

        CollectDistinctGLDocumentNos(PostingPreviewEventHandler, PredictedNumbersArray);

        Summary := BuildShipmentPreviewSummary(WhseShipmentHeader."No.", LinesToPost, PreviewArray, PostingPreviewHelper.GLStatusSentence(GLEntryCount, Balanced));

        ResponseJson.Add('status', 'Success');
        PostingPreviewHelper.AddEntryCounts(ResponseJson, EntryCount, GLEntryCount);
        ResponseJson.Add('rollback', true);
        ResponseJson.Add('summary', Summary);
        ResponseJson.Add('shipmentNo', WhseShipmentHeader."No.");
        ResponseJson.Add('locationCode', WhseShipmentHeader."Location Code");
        ResponseJson.Add('invoice', true); // BC's preview subscriber always previews Ship + Invoice
        ResponseJson.Add('linesToPost', LinesToPost);
        ResponseJson.Add('postingDate', Format(PostingDate, 0, 9));
        ResponseJson.Add('lcyCode', LCYCode);
        ResponseJson.Add('predictedNumbers', PredictedNumbersArray);
        ResponseJson.Add('totals', TotalsJson);
        ResponseJson.Add('preview', PreviewArray);

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure FindWhseShipmentHeader(var Argument: Record "Message Argument ori"; var WhseShipmentHeader: Record "Warehouse Shipment Header"): Boolean
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        FoundSystemId: Guid;
    begin
        // Every identifier supplied is tried; the shared lookup reads the request JSON itself.
        if not WhseRecordLookup.FindRecord(Argument, Database::"Warehouse Shipment Header", 'guid|no', 'systemId=guid,recordSystemId=guid,id=guid,shipmentNo=no,no=no', FoundSystemId) then
            exit(false);
        exit(WhseShipmentHeader.GetBySystemId(FoundSystemId));
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['systemId', 'recordSystemId', 'id', 'shipmentNo', 'no', 'lines']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure CollectDistinctGLDocumentNos(var PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler"; var DocNosArray: JsonArray)
    var
        GLEntry: Record "G/L Entry";
        TempRecRef: RecordRef;
        SeenDocNos: List of [Code[20]];
    begin
        TempRecRef.Open(Database::"G/L Entry", true);
        PostingPreviewEventHandler.GetEntries(Database::"G/L Entry", TempRecRef);
        if TempRecRef.FindSet() then
            repeat
                TempRecRef.SetTable(GLEntry);
                if (GLEntry."Document No." <> '') and not SeenDocNos.Contains(GLEntry."Document No.") then begin
                    SeenDocNos.Add(GLEntry."Document No.");
                    DocNosArray.Add(GLEntry."Document No.");
                end;
            until TempRecRef.Next() = 0;
        TempRecRef.Close();
    end;

    local procedure BuildShipmentPreviewSummary(ShipmentNo: Code[20]; LinesToPost: Integer; PreviewArray: JsonArray; GLStatusText: Text): Text
    var
        PostingPreviewHelper: Codeunit "Posting Preview Helper ori";
        TotalEntries: Integer;
        SummaryTxt: Label 'Preview-posting warehouse shipment %1 (%2 lines, Ship + Invoice) would create %3 ledger entries across %4 tables. %5', Comment = '%1 = shipment no, %2 = lines to post, %3 = total entry count, %4 = number of tables, %5 = balanced status sentence, is-IS=Forsýning bókunar vöruhúsasendingar %1 (%2 línur, Sending + Reikningur) myndi búa til %3 fjárhagsfærslur í %4 töflum. %5';
    begin
        TotalEntries := PostingPreviewHelper.CountPreviewEntries(PreviewArray);
        exit(StrSubstNo(SummaryTxt, ShipmentNo, LinesToPost, TotalEntries, PreviewArray.Count(), GLStatusText));
    end;

    /// <summary>
    /// Runs the BC built-in posting preview for a Warehouse Shipment and returns the
    /// Posting Preview Event Handler containing the captured (rolled-back) ledger entries.
    /// `Whse.-Post Shipment (Yes/No)` subscribes to `Gen. Jnl.-Post Preview.OnRunPreview`
    /// and forces `Invoice = true` for the simulated post.
    /// </summary>
    local procedure PreviewWhseShipment(var WhseShipmentLine: Record "Warehouse Shipment Line"; PlannedLines: JsonArray; var PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler"; var ErrorText: Text): Boolean
    var
        GenJnlPostPreview: Codeunit "Gen. Jnl.-Post Preview";
        WhsePostShipmentYesNo: Codeunit "Whse.-Post Shipment (Yes/No)";
        DocLineQty: Codeunit "Whse Doc Line Qty ori";
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
    begin
        // The per-line quantities are applied inside the preview run (Whse.-Post Shipment OnBeforeRun),
        // so Business Central rolls them back with the preview.
        Context.Reset();
        if PlannedLines.Count() > 0 then begin
            Payload.Add('documentNo', WhseShipmentLine."No.");
            Payload.Add('isShipment', true);
            Payload.Add('lines', PlannedLines);
            Context.SetPayload(Payload);
            BindSubscription(DocLineQty);
        end;
        BindSubscription(WhsePostShipmentYesNo);
        GenJnlPostPreview.SetContext(WhsePostShipmentYesNo, WhseShipmentLine);
        if GenJnlPostPreview.Run() then; // expected to fail with Error('') after capturing entries
        UnbindSubscription(WhsePostShipmentYesNo);
        if PlannedLines.Count() > 0 then
            UnbindSubscription(DocLineQty);
        Context.Reset();

        if not GenJnlPostPreview.IsSuccess() then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;

        GenJnlPostPreview.GetPreviewHandler(PostingPreviewEventHandler);
        exit(true);
    end;

    local procedure OmitCommitNextStep(): Text
    var
        NextStepLbl: Label 'Run the preview on its own, outside a rollback chain, for example through the HTTP or MCP API.', Comment = 'is-IS=Keyrðu forskoðunina eina og sér, utan afturköllunarkeðju, til dæmis í gegnum HTTP- eða MCP-API.';
    begin
        exit(NextStepLbl);
    end;

    local procedure NothingToPostNextStep(): Text
    var
        NextStepLbl: Label 'No shipment line has Qty. to Ship. Set quantities on the shipment lines.', Comment = 'is-IS=Engin sendingarlína hefur Magn til afhendingar. Setjið magn á sendingarlínurnar.';
    begin
        exit(NextStepLbl);
    end;

    local procedure LinesDeniedNextStep(): Text
    var
        NextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori, or preview without lines.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori eða forskoðaðu án lína.';
    begin
        exit(NextStepLbl);
    end;
}