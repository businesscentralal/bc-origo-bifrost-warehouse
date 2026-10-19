namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.ActivityLine.SetQtyToHandle (#56).
/// Validates Qty. to Handle on named activity lines, or fills or clears it on every line like the Autofill Qty. to
/// Handle and Delete Qty. to Handle actions.
/// </summary>
codeunit 10078464 "Whse ActLine SetQty Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        LineObject: JsonObject;
        Token: JsonToken;
        ActivityType: Enum "Warehouse Activity Type";
        ActivityNo: Code[20];
        MissingPayloadErr: Label 'The activity line payload was empty.', Comment = 'is-IS=Gögn aðgerðarlínunnar voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        ActivityType := Enum::"Warehouse Activity Type".FromInteger(Values.IntegerValue(Payload, 'activityTypeOrdinal'));
        ActivityNo := CopyStr(Values.TextValue(Payload, 'activityNo'), 1, MaxStrLen(ActivityNo));
        ActivityLine.SetRange("Activity Type", ActivityType);
        ActivityLine.SetRange("No.", ActivityNo);
        case Values.TextValue(Payload, 'mode') of
            'all':
                begin
                    if ActivityLine.FindSet(true) then
                        repeat
                            ActivityLine.Validate("Qty. to Handle", ActivityLine."Qty. Outstanding");
                            if ActivityLine."Qty. to Handle (Base)" <> ActivityLine."Qty. Outstanding (Base)" then
                                ActivityLine.Validate("Qty. to Handle (Base)", ActivityLine."Qty. Outstanding (Base)");
                            ActivityLine.Modify(true);
                        until ActivityLine.Next() = 0;
                    if ActivityHeader.Get(ActivityType, ActivityNo) then
                        if ActivityHeader."Do Not Fill Qty. to Handle" then begin
                            ActivityHeader."Do Not Fill Qty. to Handle" := false;
                            ActivityHeader.Modify(true);
                        end;
                end;
            'none':
                ActivityLine.DeleteQtyToHandle(ActivityLine);
            else
                foreach Token in Values.ArrayValue(Payload, 'lines') do begin
                    LineObject := Token.AsObject();
                    ActivityLine.Get(ActivityType, ActivityNo, Values.IntegerValue(LineObject, 'lineNo'));
                    ActivityLine.Validate("Qty. to Handle", Values.DecimalValue(LineObject, 'qtyToHandle'));
                    ActivityLine.Modify(true);
                end;
        end;
    end;

    /// <summary>Returns whether the caller can write warehouse activity lines.</summary>
    /// <returns>True when the caller can set quantities to handle.</returns>
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

    /// <summary>Returns a short description of Warehouse.ActivityLine.SetQtyToHandle.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Sets the quantity to handle on warehouse activity lines, or fills or clears it on every line.', Comment = 'is-IS=Setur magn til meðhöndlunar á línur vöruhúsaaðgerðar, eða fyllir eða hreinsar það á öllum línum.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'quantity to handle, autofill quantity to handle, delete quantity to handle, partial pick, partial put-away, short pick', Comment = 'is-IS=magn til meðhöndlunar, fylla út magn til meðhöndlunar, eyða magni til meðhöndlunar, hlutatínsla, hlutafrágangur, vöntun í tínslu';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Writes Qty. to Handle through Validate on named activity lines, or on every line with all: true (Autofill Qty. to Handle) or none: true (Delete Qty. to Handle). It registers nothing.', Comment = 'is-IS=Skrifar Magn til meðhöndlunar með Validate á nefndar aðgerðarlínur, eða á allar línur með all: true (Fylla út magn til meðhöndlunar) eða none: true (Eyða magni til meðhöndlunar). Hún skráir ekkert.';
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
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Lines with their quantity to handle. Send lines, all or none, exactly one of them.'));
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', false, 'Line number on a line entry. Required when lineSystemId is empty.'));
        Parameters.Add(ContractMgt.Parameter('lineSystemId', 'string', false, 'SystemId of the activity line on a line entry.'));
        Parameters.Add(ContractMgt.Parameter('qtyToHandle', 'number', true, 'Quantity to handle on a line entry, from zero up to the outstanding quantity.'));
        Parameters.Add(ContractMgt.Parameter('all', 'boolean', false, 'true sets the quantity to handle to the outstanding quantity on every line.'));
        Parameters.Add(ContractMgt.Parameter('none', 'boolean', false, 'true sets the quantity to handle to zero on every line.'));
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
        Fields.Add(Helper.LineField(ContractMgt, 'lines', 'array', 'Every line of the activity after the change.'));
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
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'activityType is not a warehouse activity type, qtyToHandle is negative or above the outstanding quantity, or more than one of lines, all: true and none: true is sent.', 'Send exactly one of lines, all: true or none: true, with quantities from zero up to the outstanding quantity.');
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
        Parts.WriteEffect(Effect, 'Writes Qty. to Handle on activity lines. Nothing is registered.', 'BIFROST Whse - Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.ActivityLine.Split', 'Use it after lowering the quantity to handle to split the rest off.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'Use it, or Warehouse.Putaway.Register or Warehouse.Movement.Register, to register the quantities.'));
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
            'Pick 3 of 5 on the Take and Place lines',
            '{"activityType":"Pick","activityNo":"PI000003","lines":[{"lineNo":10000,"qtyToHandle":3},{"lineNo":20000,"qtyToHandle":3}]}',
            '{"status":"Success","activityType":"Pick","activityNo":"PI000003","lines":[{"lineNo":10000,"actionType":"Take","qtyOutstanding":5,"qtyToHandle":3},{"lineNo":20000,"actionType":"Place","qtyOutstanding":5,"qtyToHandle":3}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Sets the quantity to handle on named warehouse activity lines, or on every line with all: true or none: true, and answers every line of the activity.', Comment = 'is-IS=Setur magn til meðhöndlunar á nefndar línur vöruhúsaaðgerðar, eða á allar línur með all: true eða none: true, og skilar öllum línum aðgerðarinnar.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'A named line is changed alone: send the Take and the Place line of a directed pick or movement when both should change.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the activity, the lines and the quantities and writes them, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        ResponseJson: JsonObject;
        Lines: JsonArray;
        PlannedLines: JsonArray;
        AllowedKeys: List of [Text];
        Mode: Text;
        AllValue: Boolean;
        NoneValue: Boolean;
        AllPresent: Boolean;
        NonePresent: Boolean;
        LinesPresent: Boolean;
        ChoiceCount: Integer;
        DeniedLbl: Label 'You do not have permission to change warehouse activity lines.', Comment = 'is-IS=Þú hefur ekki heimild til að breyta línum vöruhúsaaðgerða.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
        MissingLbl: Label 'Send lines, all: true or none: true.', Comment = 'is-IS=Sendu lines, all: true eða none: true.';
        ChoiceNextStepLbl: Label 'Send exactly one of lines, all: true or none: true.', Comment = 'is-IS=Sendu nákvæmlega eitt af lines, all: true eða none: true.';
        TooManyLbl: Label 'lines, all: true and none: true cannot be combined.', Comment = 'is-IS=Ekki má sameina lines, all: true og none: true.';
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
        AllowedKeys.Add('lines');
        AllowedKeys.Add('all');
        AllowedKeys.Add('none');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Values.ReadArray(RequestJson, 'lines', Argument, Lines, LinesPresent);
        Context.ReadBoolean(RequestJson, 'all', Argument, AllValue, AllPresent, 'all');
        Context.ReadBoolean(RequestJson, 'none', Argument, NoneValue, NonePresent, 'none');
        if not Argument.HasCollectedErrors() then begin
            if LinesPresent then
                ChoiceCount += 1;
            if AllValue then
                ChoiceCount += 1;
            if NoneValue then
                ChoiceCount += 1;
            if ChoiceCount = 0 then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'lines', '', '', ChoiceNextStepLbl);
            if ChoiceCount > 1 then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, TooManyLbl, 'lines', '', '', ChoiceNextStepLbl);
        end;
        if not Argument.HasCollectedErrors() then
            if Helper.ResolveActivity(RequestJson, Argument, ActivityHeader) then
                if LinesPresent then
                    ReadLines(Lines, Argument, ActivityHeader, PlannedLines);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Mode := 'lines';
        if AllValue then
            Mode := 'all';
        if NoneValue then
            Mode := 'none';
        Payload.Add('activityTypeOrdinal', ActivityHeader.Type.AsInteger());
        Payload.Add('activityNo', ActivityHeader."No.");
        Payload.Add('mode', Mode);
        Payload.Add('lines', PlannedLines);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse ActLine SetQty Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse ActLine SetQty Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('activityType', Helper.ActivityTypeName(ActivityHeader.Type));
        ResponseJson.Add('activityNo', ActivityHeader."No.");
        ResponseJson.Add('lines', Helper.LinesJson(ActivityHeader));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
        Context.Reset();
    end;

    local procedure ReadLines(Lines: JsonArray; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; var PlannedLines: JsonArray)
    var
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        LineObject: JsonObject;
        Planned: JsonObject;
        AllowedKeys: List of [Text];
        Index: Integer;
        ErrorCount: Integer;
        Quantity: Decimal;
        QuantityPresent: Boolean;
        MissingLbl: Label 'Line %1 is missing qtyToHandle.', Comment = '%1 = line index, is-IS=Línu %1 vantar qtyToHandle.';
        MissingNextStepLbl: Label 'Send qtyToHandle on every line.', Comment = 'is-IS=Sendu qtyToHandle á hverri línu.';
        RangeLbl: Label 'qtyToHandle on line %1 must be from zero up to the outstanding quantity %2.', Comment = '%1 = line no., %2 = outstanding, is-IS=qtyToHandle á línu %1 verður að vera frá núlli upp í útistandandi magn %2.';
        RangeNextStepLbl: Label 'Send a quantity from zero up to the outstanding quantity.', Comment = 'is-IS=Sendu magn frá núlli upp í útistandandi magn.';
    begin
        AllowedKeys.Add('lineNo');
        AllowedKeys.Add('lineSystemId');
        AllowedKeys.Add('qtyToHandle');
        for Index := 0 to Lines.Count() - 1 do
            if Values.TryGetLineObject(Lines, Index, 'lines', Argument, LineObject) then begin
                ErrorCount := Argument.GetCollectedErrorsJson().Count();
                Values.RefuseUnknownKeys(LineObject, AllowedKeys, Argument, 'lines', Index);
                Context.ReadDecimal(LineObject, 'qtyToHandle', Argument, Quantity, QuantityPresent, Values.LineParameter('lines', Index, 'qtyToHandle'));
                if Argument.GetCollectedErrorsJson().Count() = ErrorCount then
                    if not QuantityPresent then
                        Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index), Values.LineParameter('lines', Index, 'qtyToHandle'), '', '', MissingNextStepLbl)
                    else
                        if Helper.ResolveLine(LineObject, Argument, ActivityHeader, 'lines', Index, ActivityLine) then
                            if (Quantity < 0) or (Quantity > ActivityLine."Qty. Outstanding") then
                                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, ActivityLine."Line No.", ActivityLine."Qty. Outstanding"), Values.LineParameter('lines', Index, 'qtyToHandle'), Format(Quantity, 0, 9), '', RangeNextStepLbl)
                            else begin
                                Clear(Planned);
                                Planned.Add('lineNo', ActivityLine."Line No.");
                                Planned.Add('qtyToHandle', Quantity);
                                PlannedLines.Add(Planned);
                            end;
            end;
    end;
}
