namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Shipment.Reopen.
/// Reopens a released warehouse shipment through Whse.-Shipment Release (codeunit 7310), the same as the Reopen
/// action. Open picks or pick worksheet lines for the shipment are refused before anything is written.
/// </summary>
codeunit 10078434 "Whse Shipment Reopen Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        Context: Codeunit "Whse Write Context ori";
        WhseShipmentRelease: Codeunit "Whse.-Shipment Release";
        Payload: JsonObject;
        Token: JsonToken;
        MissingPayloadErr: Label 'The shipment reopen payload was empty.', Comment = 'is-IS=Gögnin til að opna afhendingu aftur voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        Payload.Get('shipmentNo', Token);
        ShipmentHeader.Get(CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(ShipmentHeader."No.")));
        WhseShipmentRelease.Reopen(ShipmentHeader);
        Context.SetResult(ShipmentHeader."No.", 0);
    end;

    /// <summary>Returns whether the caller can write warehouse shipments and pick requests.</summary>
    /// <returns>True when the caller can reopen a shipment.</returns>
    procedure IsEnabled(): Boolean
    begin
        exit(HasWritePermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse shipment header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Shipment Header");
    end;

    /// <summary>Returns a short description of Warehouse.Shipment.Reopen.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Reopens a released warehouse shipment so it can be changed.', Comment = 'is-IS=Opnar útgefna vöruhúsaafhendingu aftur svo hægt sé að breyta henni.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'reopen shipment, reopen warehouse shipment, change released shipment, shipment status open, unrelease shipment', Comment = 'is-IS=opna afhendingu aftur, opna vöruhúsaafhendingu aftur, breyta útgefinni afhendingu, staða afhendingar opin, afturkalla útgáfu afhendingar';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Changes data. Reopens a released warehouse shipment. Open picks must be registered or deleted first.', Comment = 'is-IS=Breytir gögnum. Opnar útgefna vöruhúsaafhendingu aftur. Opnar tínslur þarf fyrst að skrá eða eyða.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'The Warehouse Shipment to reopen: its SystemId or No.', false);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the Warehouse Shipment Header.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the Warehouse Shipment Header.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId, data.recordSystemId, data.id, data.shipmentNo, data.no', 'guid or document no.', 'The identifier keys accepted for the Warehouse Shipment Header. Every supplied identifier is tried; conflicting identifiers are refused.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>False. The shipment identifiers are the only input.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    begin
        exit(false);
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
        Fields.Add(ContractMgt.ResponseField('shipmentNo', 'string', 'Warehouse shipment number.'));
        Fields.Add(ContractMgt.ResponseField('shipmentSystemId', 'string', 'Warehouse shipment SystemId.'));
        Fields.Add(ContractMgt.ResponseField('shipmentStatus', 'string', 'Open.'));
        Fields.Add(ContractMgt.ResponseField('changed', 'boolean', 'False when the shipment was already open.'));
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
        UnknownParameterNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        Parts.AddLookupErrors(Errors, 'Warehouse Shipment Header', 'systemId, recordSystemId, id, shipmentNo, no');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', UnknownParameterNextStepLbl);
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'Open pick lines or pick worksheet lines exist for the shipment.', 'Register or delete the picks first.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write warehouse shipments.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        Parts.AddBusinessCentralError(Errors, 'a subscriber that refuses the reopen');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Sets the warehouse shipment status to Open and reopens its pick request. Release it again with Warehouse.Shipment.Release.', 'BIFROST Whse - Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.Release', 'Use it to release the shipment again.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Get', 'Use it to find open picks for the shipment, with activityType Pick.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Shipment.GetSourceDocuments', 'Use it to add lines to the reopened shipment.'));
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
            'Reopen warehouse shipment SH000001',
            '{"shipmentNo":"SH000001"}',
            '{"status":"Success","shipmentNo":"SH000001","shipmentSystemId":"6f1c1d2e-0000-0000-0000-000000000001","shipmentStatus":"Open","changed":true}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Reopens a released warehouse shipment, the same as the Reopen action, so it can be changed. Open picks or pick worksheet lines for the shipment are refused. An already open shipment answers success with changed false.', Comment = 'is-IS=Opnar útgefna vöruhúsaafhendingu aftur, eins og aðgerðin Opna aftur, svo hægt sé að breyta henni. Opnum tínslum eða línum í tínsluvinnublaði fyrir afhendinguna er hafnað. Afhending sem er þegar opin skilar árangri með changed false.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes describe the refusals, the no-op case and the order with sibling types.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'The only input is the shipment identifier, as the subject or as systemId, recordSystemId, id, shipmentNo or no under data; any other key is refused as UnknownParameter, together with any lookup problem as MultipleErrors. ' +
            'Reopening a shipment that is already open is not an error: the call answers success with changed false and writes nothing. ' +
            'The call is refused as PreconditionFailed, with nothing written, while the shipment still has pick lines (activity type Pick) or lines in a pick worksheet. Register the picks with Warehouse.Pick.Register or delete them first; Warehouse.Activity.Get with activityType Pick finds them. ' +
            'Reopening is what Business Central does with the Reopen action: the status becomes Open and the pick request is reopened, so lines can be added with Warehouse.Shipment.GetSourceDocuments. Release the shipment again with Warehouse.Shipment.Release before picks are created. ' +
            'The caller needs write permission on warehouse shipments and pick requests (BIFROST Whse - Full ori). Nothing is posted; the change is committed.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the request and reopens the shipment.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        FoundSystemId: Guid;
        IdentifierKey: Text;
        Received: Text;
        DeniedLbl: Label 'You do not have permission to reopen a warehouse shipment.', Comment = 'is-IS=Þú hefur ekki heimild til að opna vöruhúsaafhendingu aftur.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was reopened.', Comment = 'is-IS=Ekkert var opnað aftur.';
        PicksLbl: Label 'Warehouse shipment %1 has open pick lines or pick worksheet lines.', Comment = '%1 = shipment no., is-IS=Vöruhúsaafhending %1 hefur opnar tínslulínur eða línur í tínsluvinnublaði.';
        PicksNextStepLbl: Label 'Register or delete the picks first.', Comment = 'is-IS=Skráðu eða eyddu tínslunum fyrst.';
    begin
        Context.Reset();
        if not HasWritePermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, 'systemId=guid,recordSystemId=guid,id=guid,shipmentNo=no,no=no', RequestJson) then
            exit;
        // An unknown key is answered together with the lookup problems, so it does not hide them.
        RefuseUnknownKeys(RequestJson, Argument);
        if not WhseRecordLookup.FindRecord(Argument, Database::"Warehouse Shipment Header", 'guid|no', 'systemId=guid,recordSystemId=guid,id=guid,shipmentNo=no,no=no', FoundSystemId) then
            exit;
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        ShipmentHeader.GetBySystemId(FoundSystemId);
        if ShipmentHeader.Status = ShipmentHeader.Status::Open then begin
            WriteResponse(Argument, ShipmentHeader, false);
            exit;
        end;
        if HasOpenPicks(ShipmentHeader."No.") then begin
            // The refusal names the key that identified the shipment: subject, shipmentNo or a SystemId key (#71).
            IdentifierKey := WhseRecordLookup.IdentifierParameter(Argument, RequestJson, 'systemId=guid,recordSystemId=guid,id=guid,shipmentNo=no,no=no', Received);
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(PicksLbl, ShipmentHeader."No."), IdentifierKey, Received, '', PicksNextStepLbl);
            exit;
        end;
        Payload.Add('shipmentNo', ShipmentHeader."No.");
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Shipment Reopen Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Shipment Reopen Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        Context.Reset();
        ShipmentHeader.Get(ShipmentHeader."No.");
        WriteResponse(Argument, ShipmentHeader, true);
    end;

    local procedure HasOpenPicks(ShipmentNo: Code[20]): Boolean
    var
        ActivityLine: Record "Warehouse Activity Line";
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        // The same two checks Whse.-Shipment Release runs before it reopens.
        WorksheetLine.SetCurrentKey("Whse. Document Type", "Whse. Document No.");
        WorksheetLine.SetRange("Whse. Document Type", WorksheetLine."Whse. Document Type"::Shipment);
        WorksheetLine.SetRange("Whse. Document No.", ShipmentNo);
        if not WorksheetLine.IsEmpty() then
            exit(true);
        ActivityLine.SetCurrentKey("Whse. Document No.", "Whse. Document Type", "Activity Type");
        ActivityLine.SetRange("Whse. Document No.", ShipmentNo);
        ActivityLine.SetRange("Whse. Document Type", ActivityLine."Whse. Document Type"::Shipment);
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
        exit(not ActivityLine.IsEmpty());
    end;

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; ShipmentHeader: Record "Warehouse Shipment Header"; Changed: Boolean)
    var
        ResponseJson: JsonObject;
    begin
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('shipmentNo', ShipmentHeader."No.");
        ResponseJson.Add('shipmentSystemId', Format(ShipmentHeader.SystemId, 0, 4));
        if ShipmentHeader.Status = ShipmentHeader.Status::Released then
            ResponseJson.Add('shipmentStatus', 'Released')
        else
            ResponseJson.Add('shipmentStatus', 'Open');
        ResponseJson.Add('changed', Changed);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['systemId', 'recordSystemId', 'id', 'shipmentNo', 'no']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;

    local procedure HasWritePermission(): Boolean
    var
        ShipmentHeader: Record "Warehouse Shipment Header";
        PickRequest: Record "Whse. Pick Request";
    begin
        exit(ShipmentHeader.WritePermission() and PickRequest.WritePermission());
    end;
}
