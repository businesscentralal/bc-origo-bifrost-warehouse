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
    begin
        exit('Simulates posting a Warehouse Shipment (Ship + Invoice) and returns the ledger entries that would be produced without committing changes.');
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
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Target := Parts.RecordTarget('Warehouse Shipment Header', 'systemId, recordSystemId, id, shipmentNo, no');
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
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddLookupErrors(Errors, 'Warehouse Shipment Header');
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::NothingToPreview, 'The Warehouse Shipment has no lines or no quantities to post.', 'Add lines and quantities to ship.'));
        Parts.AddBusinessCentralError(Errors, 'invalid quantities, posting setup or source-document state');
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

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Read-only posting preview for a Warehouse Shipment. It captures predicted ledger entries and rolls back the transaction.';
        exit(true);
    end;

    procedure GetMessageDirection() MessageDirection: Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    procedure GetMessageHelpAsMarkdownDocument(var Argument: Record "Message Argument ori")
    begin
        Argument.SetResponseMarkdown('');
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        GLSetup: Record "General Ledger Setup";
        TempDocumentEntry: Record "Document Entry" temporary;
        PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler";
        Dispatcher: Codeunit "Dispatcher ori";
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
        NoLinesToPostErr: Label 'Warehouse Shipment %1 has no lines to post.', Comment = '%1 = Whse. Shipment No.', Locked = true;
        PreviewFailedErr: Label 'Posting preview failed and no entries were captured. The shipment cannot be posted in its current state.', Comment = 'is-IS=Bókunarforsýning mistókst og engar færslur voru teknar. Sendingin getur ekki verið bókuð í núverandi stöðu.';
        NothingToPostNextStepTok: Label 'No shipment line has Qty. to Ship. Set quantities on the shipment lines.', Comment = 'is-IS=Engin sendingarlína hefur Magn til afhendingar. Setjið magn á sendingarlínurnar.';
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();

        RequestJson := Argument.GetRequestJson();
        if not FindWhseShipmentHeader(Argument, WhseShipmentHeader) then
            exit;

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        if WhseShipmentLine.IsEmpty() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::NothingToPreview, StrSubstNo(NoLinesToPostErr, WhseShipmentHeader."No."), '', '', '', NothingToPostNextStepTok);
            exit;
        end;
        LinesToPost := WhseShipmentLine.Count();
        PostingDate := WhseShipmentHeader."Posting Date";
        if PostingDate = 0D then
            PostingDate := WorkDate();

        WhseShipmentLine.FindFirst();

        GLSetup.Get();
        LCYCode := GLSetup."LCY Code";

        if not PreviewWhseShipment(WhseShipmentLine, PostingPreviewEventHandler, PreviewErrorText) then begin
            if PreviewErrorText = '' then
                PreviewErrorText := PreviewFailedErr;
            Dispatcher.RespondWithPreviewError(Argument, PreviewErrorText, NothingToPostNextStepTok);
            exit;
        end;

        Dispatcher.GetPreviewFieldNames(PreviewFieldNames);

        PostingPreviewEventHandler.FillDocumentEntry(TempDocumentEntry);
        if TempDocumentEntry.FindSet() then
            repeat
                Dispatcher.AddTableToPreview(PreviewArray, PostingPreviewEventHandler, TempDocumentEntry."Table ID", TempDocumentEntry."Table Name", PreviewFieldNames);
            until TempDocumentEntry.Next() = 0;

        if not Dispatcher.EvaluatePreviewOutcome(Argument, PreviewArray, PostingPreviewEventHandler, NothingToPostNextStepTok, TotalsJson, Balanced, EntryCount, GLEntryCount) then

            exit;

        CollectDistinctGLDocumentNos(PostingPreviewEventHandler, PredictedNumbersArray);

        Summary := BuildShipmentPreviewSummary(WhseShipmentHeader."No.", LinesToPost, PreviewArray, Dispatcher.GLStatusSentence(GLEntryCount, Balanced));

        ResponseJson.Add('status', 'Success');
        Dispatcher.AddEntryCounts(ResponseJson, EntryCount, GLEntryCount);
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
        Dispatcher: Codeunit "Dispatcher ori";
        TotalEntries: Integer;
        SummaryTxt: Label 'Preview-posting warehouse shipment %1 (%2 lines, Ship + Invoice) would create %3 ledger entries across %4 tables. %5', Comment = '%1 = shipment no, %2 = lines to post, %3 = total entry count, %4 = number of tables, %5 = balanced status sentence, is-IS=Forsýning bókunar vöruhúsasendingar %1 (%2 línur, Sending + Reikningur) myndi búa til %3 fjárhagsfærslur í %4 töflum. %5';
    begin
        TotalEntries := Dispatcher.CountPreviewEntries(PreviewArray);
        exit(StrSubstNo(SummaryTxt, ShipmentNo, LinesToPost, TotalEntries, PreviewArray.Count(), GLStatusText));
    end;

    /// <summary>
    /// Runs the BC built-in posting preview for a Warehouse Shipment and returns the
    /// Posting Preview Event Handler containing the captured (rolled-back) ledger entries.
    /// `Whse.-Post Shipment (Yes/No)` subscribes to `Gen. Jnl.-Post Preview.OnRunPreview`
    /// and forces `Invoice = true` for the simulated post.
    /// </summary>
    local procedure PreviewWhseShipment(var WhseShipmentLine: Record "Warehouse Shipment Line"; var PostingPreviewEventHandler: Codeunit "Posting Preview Event Handler"; var ErrorText: Text): Boolean
    var
        GenJnlPostPreview: Codeunit "Gen. Jnl.-Post Preview";
        WhsePostShipmentYesNo: Codeunit "Whse.-Post Shipment (Yes/No)";
    begin
        BindSubscription(WhsePostShipmentYesNo);
        GenJnlPostPreview.SetContext(WhsePostShipmentYesNo, WhseShipmentLine);
        if GenJnlPostPreview.Run() then; // expected to fail with Error('') after capturing entries
        UnbindSubscription(WhsePostShipmentYesNo);

        if not GenJnlPostPreview.IsSuccess() then begin
            ErrorText := GetLastErrorText();
            exit(false);
        end;

        GenJnlPostPreview.GetPreviewHandler(PostingPreviewEventHandler);
        exit(true);
    end;
}
