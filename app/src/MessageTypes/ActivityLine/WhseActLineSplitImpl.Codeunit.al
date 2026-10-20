namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.ActivityLine.Split (#56).
/// Splits a warehouse activity line through the table's SplitLine, the Split Line action of the activity pages:
/// the line keeps its quantity to handle and a new line takes the rest.
/// </summary>
codeunit 10078462 "Whse ActLine Split Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ActivityLine: Record "Warehouse Activity Line";
        NewActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The activity line payload was empty.', Comment = 'is-IS=Gögn aðgerðarlínunnar voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        ActivityLine.Get(
            Enum::"Warehouse Activity Type".FromInteger(Values.IntegerValue(Payload, 'activityTypeOrdinal')),
            CopyStr(Values.TextValue(Payload, 'activityNo'), 1, MaxStrLen(ActivityLine."No.")),
            Values.IntegerValue(Payload, 'lineNo'));
        ActivityLine.SplitLine(ActivityLine, NewActivityLine);
        ActivityLine.Get(ActivityLine."Activity Type", ActivityLine."No.", ActivityLine."Line No.");
        NewActivityLine.Get(NewActivityLine."Activity Type", NewActivityLine."No.", NewActivityLine."Line No.");
        Result.Add('line', Helper.LineJson(ActivityLine));
        Result.Add('newLine', Helper.LineJson(NewActivityLine));
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can write warehouse activity lines.</summary>
    /// <returns>True when the caller can split an activity line.</returns>
    procedure IsEnabled(): Boolean
    var
        Helper: Codeunit "Whse ActLine Helper ori";
    begin
        exit(Helper.HasWritePermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse activity line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Activity Line");
    end;

    /// <summary>Returns a short description of Warehouse.ActivityLine.Split.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Splits a warehouse activity line so the rest of its quantity can go to another bin or lot.', Comment = 'is-IS=Skiptir línu vöruhúsaaðgerðar svo afgangur magnsins geti farið í annað hólf eða aðra lotu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'split line, split pick line, split put-away line, partial bin, two bins, divide quantity', Comment = 'is-IS=skipta línu, skipta tínslulínu, skipta frágangslínu, hluti í hólf, tvö hólf, skipta magni';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Splits one warehouse activity line in two, like the Split Line action: the line keeps its quantity to handle and a new line takes the rest, without a bin on directed locations. Lower the quantity to handle first with Warehouse.ActivityLine.SetQtyToHandle.', Comment = 'is-IS=Skiptir einni línu vöruhúsaaðgerðar í tvennt, eins og aðgerðin Skipta línu: línan heldur magni sínu til meðhöndlunar og ný lína tekur afganginn, án hólfs á beinum staðsetningum. Lækkaðu fyrst magn til meðhöndlunar með Warehouse.ActivityLine.SetQtyToHandle.';
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
        Forms.Add('activity no.');
        Forms.Add('guid');
        Envelope := Parts.RecordEnvelope(Forms, 'The activity number or its SystemId. Do not send a different activity in activityNo or systemId as well.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        Helper: Codeunit "Whse ActLine Helper ori";
    begin
        Helper.AddActivityTarget(Target);
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Helper: Codeunit "Whse ActLine Helper ori";
    begin
        Helper.AddActivityParameters(Parameters);
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', false, 'Line number of the activity line. Required when lineSystemId is empty.'));
        Parameters.Add(ContractMgt.Parameter('lineSystemId', 'string', false, 'SystemId of the activity line.'));
        exit(true);
    end;

    /// <summary>Returns the response chapter.</summary>
    /// <param name="Response">Receives the response.</param>
    /// <returns>True when a response is declared.</returns>
    procedure GetResponse(var Response: JsonObject): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Parts: Codeunit "Whse Contract Parts ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Fields: JsonArray;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('activityType', 'string', 'Activity type.'));
        Fields.Add(ContractMgt.ResponseField('activityNo', 'string', 'Activity number.'));
        Fields.Add(Helper.LineField(ContractMgt, 'line', 'object', 'The split line; it keeps its quantity to handle.'));
        Fields.Add(Helper.LineField(ContractMgt, 'newLine', 'object', 'The new line with the rest of the quantity.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
        Helper: Codeunit "Whse ActLine Helper ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The line has quantity to handle equal to its outstanding quantity or zero, or it is the Take line or a breakbulk line of a put-away.', 'Lower qtyToHandle first; BC splits the rest off.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'activityType is not a warehouse activity type.', 'Send Put-away, Pick, Movement, Invt. Put-away, Invt. Pick or Invt. Movement.');
        Helper.AddActivityErrors(Errors);
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Reduces the activity line to its quantity to handle and inserts a new line for the rest.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.ActivityLine.SetQtyToHandle', 'Use it first to lower the quantity to handle.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.ActivityLine.ChangeBin', 'Use it to give the new line a bin.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.ActivityLine.AssignTracking', 'Use it to give each part its own lot or serial number; it splits the line itself.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True when a workflow is declared.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Helper: Codeunit "Whse ActLine Helper ori";
    begin
        Helper.ActivityLineWorkflow(Workflow);
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
            'Split a put-away Place line after lowering its quantity to handle to 3 of 5',
            '{"activityType":"Put-away","activityNo":"PU000001","lineNo":20000}',
            '{"status":"Success","activityType":"Put-away","activityNo":"PU000001","line":{"lineNo":20000,"actionType":"Place","binCode":"W-01-0001","quantity":3,"qtyOutstanding":3,"qtyToHandle":3},"newLine":{"lineNo":30000,"actionType":"Place","binCode":"","quantity":2,"qtyOutstanding":2,"qtyToHandle":2}}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Splits a warehouse activity line in two through Business Central''s Split Line. The line keeps its quantity to handle; the new line gets the rest. A line whose quantity to handle equals its outstanding quantity is refused.', Comment = 'is-IS=Skiptir línu vöruhúsaaðgerðar í tvennt með Skipta línu í Business Central. Línan heldur magni sínu til meðhöndlunar; nýja línan fær afganginn. Línu þar sem magn til meðhöndlunar er jafnt útistandandi magni er hafnað.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Only the named line is split. On a directed pick or movement the paired line of the other action type is not split; split it in its own call when both sides need it.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the activity and the line and splits it, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        Result: JsonObject;
        ResponseJson: JsonObject;
        Token: JsonToken;
        AllowedKeys: List of [Text];
        DeniedLbl: Label 'You do not have permission to change warehouse activity lines.', Comment = 'is-IS=Þú hefur ekki heimild til að breyta línum vöruhúsaaðgerða.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
    begin
        Context.Reset();
        if not Helper.HasWritePermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        Helper.AddActivityKeys(AllowedKeys);
        AllowedKeys.Add('lineNo');
        AllowedKeys.Add('lineSystemId');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        if not Argument.HasCollectedErrors() then
            if Helper.ResolveActivity(RequestJson, Argument, ActivityHeader) then
                if Helper.ResolveLine(RequestJson, Argument, ActivityHeader, '', -1, ActivityLine) then
                    CheckSplit(Argument, ActivityLine);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('activityTypeOrdinal', ActivityLine."Activity Type".AsInteger());
        Payload.Add('activityNo', ActivityLine."No.");
        Payload.Add('lineNo', ActivityLine."Line No.");
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse ActLine Split Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse ActLine Split Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        Context.TryGetResult(Result);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('activityType', Helper.ActivityTypeName(ActivityHeader.Type));
        ResponseJson.Add('activityNo', ActivityHeader."No.");
        if Result.Get('line', Token) then
            ResponseJson.Add('line', Token);
        if Result.Get('newLine', Token) then
            ResponseJson.Add('newLine', Token);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
        Context.Reset();
    end;

    local procedure CheckSplit(var Argument: Record "Message Argument ori"; ActivityLine: Record "Warehouse Activity Line")
    var
        ZeroLbl: Label 'Line %1 has no quantity to handle, so there is nothing to keep on it.', Comment = '%1 = line no., is-IS=Lína %1 hefur ekkert magn til meðhöndlunar, svo ekkert verður eftir á henni.';
        ZeroNextStepLbl: Label 'Set qtyToHandle above zero with Warehouse.ActivityLine.SetQtyToHandle first.', Comment = 'is-IS=Settu qtyToHandle yfir núll með Warehouse.ActivityLine.SetQtyToHandle fyrst.';
        FullLbl: Label 'Line %1 has quantity to handle equal to its outstanding quantity %2, so there is nothing to split off.', Comment = '%1 = line no., %2 = outstanding, is-IS=Lína %1 hefur magn til meðhöndlunar jafnt útistandandi magni %2, svo ekkert er til að skipta frá.';
        FullNextStepLbl: Label 'Lower qtyToHandle first; BC splits the rest off.', Comment = 'is-IS=Lækkaðu qtyToHandle fyrst; BC skiptir afganginum frá.';
        PutAwayLbl: Label 'Line %1 is a Take or breakbulk line of a put-away; only a Place line of a put-away is split.', Comment = '%1 = line no., is-IS=Lína %1 er Taka- eða brotlína í frágangi; aðeins Setja-línu frágangs er skipt.';
        PutAwayNextStepLbl: Label 'Split the Place line of the put-away.', Comment = 'is-IS=Skiptu Setja-línu frágangsins.';
    begin
        if ActivityLine."Qty. to Handle" = 0 then begin
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(ZeroLbl, ActivityLine."Line No."), 'lineNo', Format(ActivityLine."Line No.", 0, 9), '', ZeroNextStepLbl);
            exit;
        end;
        if ActivityLine."Activity Type" = ActivityLine."Activity Type"::"Put-away" then
            if (ActivityLine."Breakbulk No." <> 0) or (ActivityLine."Action Type" <> ActivityLine."Action Type"::Place) then begin
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(PutAwayLbl, ActivityLine."Line No."), 'lineNo', Format(ActivityLine."Line No.", 0, 9), '', PutAwayNextStepLbl);
                exit;
            end;
        if ActivityLine."Qty. to Handle" = ActivityLine."Qty. Outstanding" then
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(FullLbl, ActivityLine."Line No.", ActivityLine."Qty. Outstanding"), 'lineNo', Format(ActivityLine."Line No.", 0, 9), '', FullNextStepLbl);
    end;
}
