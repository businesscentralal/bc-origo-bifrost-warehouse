namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Implementation of the Warehouse.Shipment.Create message type.
/// Creates one Warehouse Shipment per source document supplied (Sales Order or Outbound Transfer Order)
/// by delegating to BC's Get Source Doc. Outbound (codeunit 5752). Each source produces its own
/// Warehouse Shipment Header (BC standard behaviour). Optional `assignedUserId` is applied to each
/// created header after creation.
/// </summary>

using Microsoft.Inventory.Location;
using Microsoft.Inventory.Transfer;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Request;

using Origo.Bifrost;

codeunit 10078406 "Whse Shipment Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;
    procedure IsEnabled(): Boolean
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(GetFilterTableNo());
        exit(RecRef.WritePermission());
    end;
    procedure GetFilterTableNo() FilterTableId: Integer
    begin
        exit(Database::"Warehouse Shipment Header");
    end;

    procedure GetDescription() Description: Text[250]
    begin
        exit('Creates Warehouse Shipment(s) from one or more released source documents (Sales Order, Outbound Transfer Order).');
    end;

    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'warehouse shipment, create shipment, prepare shipment, ship the order from the warehouse, outbound shipment, dispatch', Comment = 'is-IS=vöruhúsaafhending, stofna afhendingu, undirbúa afhendingu, senda pöntun frá vöruhúsi, útsending';
    begin
        exit(KeywordsLbl);
    end;

    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Creates outbound warehouse shipments from released sales or transfer orders; use Warehouse.Shipment.Post to post one.', Comment = 'is-IS=Stofnar útleiðarafhendingar úr útgefnum sölu- eða millifærslupöntunum; notaðu Warehouse.Shipment.Post til að bóka afhendingu.';
    begin
        exit(SelectionLbl);
    end;

    procedure GetEnvelope(var Envelope: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
        Forms: List of [Text];
    begin
        Forms.Add('data only');
        Envelope := Parts.RecordEnvelope(Forms, 'The request must contain one or more source documents under data.', true);
        exit(true);
    end;

    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('data.sourceDocuments[].documentNo', 'document no.', 'The released Sales Order or outbound Transfer Order from which a Warehouse Shipment is created.'));
        exit(true);
    end;

    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('sourceDocuments', 'array', true, 'One or more source documents. Each child has sourceType (SalesOrder or TransferOrder) and documentNo.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Optional source-location check. It does not override the source document.'));
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'User assigned to each created Warehouse Shipment Header.'));
        Parameters.Add(ContractMgt.Parameter('postingDate', 'string', false, 'Posting date applied to each created Warehouse Shipment Header.'));
        exit(true);
    end;

    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('noOfShipments', 'integer', 'Number of Warehouse Shipments created.'));
        Fields.Add(ContractMgt.ResponseField('shipments', 'array', 'Created Warehouse Shipment summaries with recordSystemId, no, locationCode, assignedUserId, sourceType, sourceDocumentNo and linesCreated.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.AddSourceDocumentErrors(Errors, 'SalesOrder, TransferOrder');
        exit(true);
    end;

    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Creates Warehouse Shipment Header and Line records and applies requested header fields.', 'BIFROST Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Post', 'Use it after creation to ship the Warehouse Shipment.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Create', 'Use it to create a pick for the shipment when warehouse picking is required.'));
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
    begin
        exit(false);
    end;

    procedure GetOverview(var Overview: Text): Boolean
    begin
        Overview := 'Creates one Warehouse Shipment for each released Sales Order or outbound Transfer Order supplied in sourceDocuments.';
        exit(true);
    end;

    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := '';
        exit(false);
    end;

    procedure GetMessageDirection() MessageDirection: Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        Dispatcher: Codeunit "Dispatcher ori";
        RequestJson: JsonObject;
        ResponseJson: JsonObject;
        SourceToken: JsonToken;
        SourcesArray: JsonArray;
        ResultArray: JsonArray;
        LocationFilter: Code[10];
        AssignedUserIdValue: Code[50];
        PostingDateValue: Date;
        HasAssignedUserId: Boolean;
        HasPostingDate: Boolean;
        I: Integer;
        MissingSourcesErr: Label 'sourceDocuments is required and must contain at least one entry.', Locked = true;
        FieldWriteRestrictedErr: Label 'Field %1 is restricted for write on table %2.', Comment = '%1 = field caption, %2 = table caption', Locked = true;
    begin
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        RequestJson := Argument.GetRequestJson();

        if not RequestJson.Get('sourceDocuments', SourceToken) then begin
            Argument.RespondWithError(MissingSourcesErr);
            exit;
        end;
        SourcesArray := SourceToken.AsArray();
        if SourcesArray.Count() = 0 then begin
            Argument.RespondWithError(MissingSourcesErr);
            exit;
        end;

        // Optional locationCode — used only to validate sources match (no override on the header).
        LocationFilter := ReadCode10(RequestJson, 'locationCode');
        if LocationFilter <> '' then
            if Dispatcher.IsFieldWriteRestricted(Database::"Warehouse Shipment Header", WhseShipmentHeader.FieldNo("Location Code")) then begin
                Argument.RespondWithError(StrSubstNo(FieldWriteRestrictedErr, WhseShipmentHeader.FieldCaption("Location Code"), WhseShipmentHeader.TableCaption()));
                exit;
            end;

        // Optional header overrides
        AssignedUserIdValue := ReadCode50(RequestJson, 'assignedUserId');
        HasAssignedUserId := AssignedUserIdValue <> '';
        if not Dispatcher.TryReadDate(Argument, RequestJson, 'postingDate', false, PostingDateValue) then
            exit;
        HasPostingDate := PostingDateValue <> 0D;

        // Process each source
        for I := 0 to SourcesArray.Count() - 1 do
            if not ProcessSource(Argument, SourcesArray, I, LocationFilter, AssignedUserIdValue, HasAssignedUserId, PostingDateValue, HasPostingDate, ResultArray) then
                exit;

        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('noOfShipments', ResultArray.Count());
        ResponseJson.Add('shipments', ResultArray);

        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ProcessSource(var Argument: Record "Message Argument ori"; SourcesArray: JsonArray; Index: Integer; LocationFilter: Code[10]; AssignedUserIdValue: Code[50]; HasAssignedUserId: Boolean; PostingDateValue: Date; HasPostingDate: Boolean; var ResultArray: JsonArray): Boolean
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        SourceToken: JsonToken;
        SourceObject: JsonObject;
        SourceType: Text;
        DocumentNo: Code[20];
        CreatedHeaderNo: Code[20];
        ShipmentJson: JsonObject;
        InvalidSourceErr: Label 'Source #%1 is missing sourceType or documentNo (both required).', Comment = '%1 = source index', Locked = true;
        UnsupportedSourceErr: Label 'Unsupported sourceType ''%1''. Expected: SalesOrder, TransferOrder.', Comment = '%1 = sourceType value', Locked = true;
        NoShipmentCreatedErr: Label 'No Warehouse Shipment was created for %1 ''%2'' — already on an open shipment, no lines remain to ship, or pick already started.', Comment = '%1 = sourceType, %2 = documentNo', Locked = true;
    begin
        SourcesArray.Get(Index, SourceToken);
        SourceObject := SourceToken.AsObject();
        SourceType := ReadString(SourceObject, 'sourceType');
        DocumentNo := ReadCode20Direct(SourceObject, 'documentNo');
        if (SourceType = '') or (DocumentNo = '') then begin
            Argument.RespondWithError(StrSubstNo(InvalidSourceErr, Index + 1));
            exit(false);
        end;

        case UpperCase(SourceType) of
            'SALESORDER':
                if not CreateFromSalesOrder(Argument, DocumentNo, LocationFilter, CreatedHeaderNo) then
                    exit(false);
            'TRANSFERORDER':
                if not CreateFromTransferOrder(Argument, DocumentNo, LocationFilter, CreatedHeaderNo) then
                    exit(false);
            else begin
                Argument.RespondWithError(StrSubstNo(UnsupportedSourceErr, SourceType));
                exit(false);
            end;
        end;

        if CreatedHeaderNo = '' then begin
            Argument.RespondWithError(StrSubstNo(NoShipmentCreatedErr, SourceType, DocumentNo));
            exit(false);
        end;

        WhseShipmentHeader.Get(CreatedHeaderNo);
        if HasAssignedUserId then begin
            WhseShipmentHeader.Validate("Assigned User ID", AssignedUserIdValue);
            WhseShipmentHeader.Modify(true);
        end;
        if HasPostingDate then begin
            WhseShipmentHeader.Validate("Posting Date", PostingDateValue);
            WhseShipmentHeader.Modify(true);
        end;

        ShipmentJson.Add('recordSystemId', Format(WhseShipmentHeader.SystemId, 0, 4));
        ShipmentJson.Add('no', WhseShipmentHeader."No.");
        ShipmentJson.Add('locationCode', WhseShipmentHeader."Location Code");
        ShipmentJson.Add('assignedUserId', WhseShipmentHeader."Assigned User ID");
        ShipmentJson.Add('sourceType', SourceType);
        ShipmentJson.Add('sourceDocumentNo', DocumentNo);
        ShipmentJson.Add('linesCreated', CountLines(WhseShipmentHeader."No."));
        ResultArray.Add(ShipmentJson);
        exit(true);
    end;

    local procedure CreateFromSalesOrder(var Argument: Record "Message Argument ori"; DocumentNo: Code[20]; LocationFilter: Code[10]; var CreatedHeaderNo: Code[20]): Boolean
    var
        SalesHeader: Record "Sales Header";
        Location: Record Location;
        GetSourceDocOutbound: Codeunit "Get Source Doc. Outbound";
        SalesNotReleasedErr: Label 'Sales Order ''%1'' is not Released. Release it before creating a Warehouse Shipment.', Comment = '%1 = sales order no.', Locked = true;
        LocationMismatchErr: Label 'Sales Order ''%1'' uses location ''%2'' which does not match the requested locationCode ''%3''.', Comment = '%1 = sales order no., %2 = source location, %3 = requested location', Locked = true;
        LocationNotRequireShipmentErr: Label 'Location ''%1'' (from Sales Order ''%2'') does not require shipment routing — set ''Require Shipment'' on the Location card to enable warehouse shipments.', Comment = '%1 = location code, %2 = sales order no.', Locked = true;
    begin
        if not SalesHeader.Get(SalesHeader."Document Type"::Order, DocumentNo) then begin
            Argument.RespondWithRecordNotFound(Database::"Sales Header", DocumentNo, 'sourceDocuments.documentNo');
            exit(false);
        end;
        if SalesHeader.Status <> SalesHeader.Status::Released then begin
            Argument.RespondWithError(StrSubstNo(SalesNotReleasedErr, DocumentNo));
            exit(false);
        end;
        if (LocationFilter <> '') and (LocationFilter <> SalesHeader."Location Code") then begin
            Argument.RespondWithError(StrSubstNo(LocationMismatchErr, DocumentNo, SalesHeader."Location Code", LocationFilter));
            exit(false);
        end;
        if SalesHeader."Location Code" <> '' then begin
            Location.Get(SalesHeader."Location Code");
            if not Location."Require Shipment" then begin
                Argument.RespondWithError(StrSubstNo(LocationNotRequireShipmentErr, Location.Code, DocumentNo));
                exit(false);
            end;
        end;

        GetSourceDocOutbound.CreateFromSalesOrderHideDialog(SalesHeader);
        CreatedHeaderNo := FindHeaderForSource(Database::"Sales Line", SalesHeader."Document Type".AsInteger(), DocumentNo);
        exit(true);
    end;

    local procedure CreateFromTransferOrder(var Argument: Record "Message Argument ori"; DocumentNo: Code[20]; LocationFilter: Code[10]; var CreatedHeaderNo: Code[20]): Boolean
    var
        TransferHeader: Record "Transfer Header";
        Location: Record Location;
        GetSourceDocOutbound: Codeunit "Get Source Doc. Outbound";
        TransferNotReleasedErr: Label 'Transfer Order ''%1'' is not Released. Release it before creating a Warehouse Shipment.', Comment = '%1 = transfer order no.', Locked = true;
        LocationMismatchErr: Label 'Transfer Order ''%1'' ships from ''%2'' which does not match the requested locationCode ''%3''.', Comment = '%1 = transfer order no., %2 = source location, %3 = requested location', Locked = true;
        LocationNotRequireShipmentErr: Label 'Location ''%1'' (Transfer-from on Transfer Order ''%2'') does not require shipment routing — set ''Require Shipment'' on the Location card to enable warehouse shipments.', Comment = '%1 = location code, %2 = transfer order no.', Locked = true;
    begin
        if not TransferHeader.Get(DocumentNo) then begin
            Argument.RespondWithRecordNotFound(Database::"Transfer Header", DocumentNo, 'sourceDocuments.documentNo');
            exit(false);
        end;
        if TransferHeader.Status <> TransferHeader.Status::Released then begin
            Argument.RespondWithError(StrSubstNo(TransferNotReleasedErr, DocumentNo));
            exit(false);
        end;
        if (LocationFilter <> '') and (LocationFilter <> TransferHeader."Transfer-from Code") then begin
            Argument.RespondWithError(StrSubstNo(LocationMismatchErr, DocumentNo, TransferHeader."Transfer-from Code", LocationFilter));
            exit(false);
        end;
        if TransferHeader."Transfer-from Code" <> '' then begin
            Location.Get(TransferHeader."Transfer-from Code");
            if not Location."Require Shipment" then begin
                Argument.RespondWithError(StrSubstNo(LocationNotRequireShipmentErr, Location.Code, DocumentNo));
                exit(false);
            end;
        end;

        GetSourceDocOutbound.CreateFromOutbndTransferOrderHideDialog(TransferHeader);
        CreatedHeaderNo := FindHeaderForSource(Database::"Transfer Line", 0, DocumentNo);
        exit(true);
    end;

    local procedure FindHeaderForSource(SourceTableNo: Integer; SourceSubtype: Integer; SourceDocumentNo: Code[20]): Code[20]
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
    begin
        WhseShipmentLine.SetRange("Source Type", SourceTableNo);
        if SourceTableNo = Database::"Sales Line" then
            WhseShipmentLine.SetRange("Source Subtype", SourceSubtype);
        WhseShipmentLine.SetRange("Source No.", SourceDocumentNo);
        if not WhseShipmentLine.FindLast() then
            exit('');
        exit(WhseShipmentLine."No.");
    end;

    local procedure CountLines(HeaderNo: Code[20]): Integer
    var
        WhseShipmentLine: Record "Warehouse Shipment Line";
    begin
        WhseShipmentLine.SetRange("No.", HeaderNo);
        exit(WhseShipmentLine.Count());
    end;

    local procedure ReadString(JObject: JsonObject; PropertyName: Text): Text
    var
        Token: JsonToken;
    begin
        if JObject.Get(PropertyName, Token) then
            if not Token.AsValue().IsNull() then
                exit(Token.AsValue().AsText());
        exit('');
    end;

    local procedure ReadCode10(JObject: JsonObject; PropertyName: Text): Code[10]
    begin
        exit(CopyStr(UpperCase(ReadString(JObject, PropertyName)), 1, 10));
    end;

    local procedure ReadCode50(JObject: JsonObject; PropertyName: Text): Code[50]
    begin
        exit(CopyStr(UpperCase(ReadString(JObject, PropertyName)), 1, 50));
    end;

    local procedure ReadCode20Direct(JObject: JsonObject; PropertyName: Text): Code[20]
    begin
        exit(CopyStr(ReadString(JObject, PropertyName), 1, 20));
    end;
}
