namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.ActivityLine.ChangeBin (#56).
/// Validates Bin Code (and Zone Code when the bin is in another zone) on one warehouse activity line. A Take line needs
/// bin content for the outstanding quantity; a Place line needs a bin that accepts stock.
/// </summary>
codeunit 10078463 "Whse ActLine ChgBin Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ActivityLine: Record "Warehouse Activity Line";
        Bin: Record Bin;
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
        Bin.Get(ActivityLine."Location Code", CopyStr(Values.TextValue(Payload, 'binCode'), 1, MaxStrLen(Bin.Code)));
        if ActivityLine."Zone Code" <> Bin."Zone Code" then
            ActivityLine.Validate("Zone Code", Bin."Zone Code");
        ActivityLine.Validate("Bin Code", Bin.Code);
        ActivityLine.Modify(true);
        Result.Add('line', Helper.LineJson(ActivityLine));
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can write warehouse activity lines.</summary>
    /// <returns>True when the caller can change the bin of an activity line.</returns>
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

    /// <summary>Returns a short description of Warehouse.ActivityLine.ChangeBin.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Changes the bin of one warehouse activity line.', Comment = 'is-IS=Breytir hólfi einnar línu vöruhúsaaðgerðar.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'change bin, take from another bin, place in another bin, pick bin, put-away bin, bin code', Comment = 'is-IS=breyta hólfi, taka úr öðru hólfi, setja í annað hólf, tínsluhólf, frágangshólf, hólfakóði';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Changes the bin of one warehouse activity line through Validate. A Take line needs a bin with enough content; a Place line needs a bin that accepts stock. The paired line of the other action type is not changed.', Comment = 'is-IS=Breytir hólfi einnar línu vöruhúsaaðgerðar með Validate. Taka-lína þarf hólf með nægu innihaldi; Setja-lína þarf hólf sem tekur við birgðum. Paraðri línu hinnar aðgerðartegundarinnar er ekki breytt.';
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
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', true, 'The new bin at the location of the activity.'));
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
        Fields.Add(ContractMgt.ResponseField('changed', 'boolean', 'False when the line already had the bin.'));
        Fields.Add(Helper.LineField(ContractMgt, 'line', 'object', 'The changed line.'));
        Fields.Add(ContractMgt.ResponseField('unchangedPairedLineNos', 'array', 'Line numbers of the paired lines of the other action type (the Place lines of a Take line, or the Take lines of a Place line); they keep their bin.'));
        Fields.Add(ContractMgt.ResponseField('note', 'string', 'Says that the paired lines were left unchanged, when there are any.'));
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
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidLine, 'The bin does not hold enough of the item for a Take line, or does not accept stock for a Place line (blocked for inbound movement or the adjustment bin).', 'Read Warehouse.BinContent.Get.');
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
        Parts.WriteEffect(Effect, 'Changes Bin Code, and Zone Code when the bin is in another zone, on one activity line.', 'BIFROST Whse - Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to find a bin with enough content for a Take line.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.ActivityLine.Split', 'Use it first to take only part of the line from another bin.'));
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
            'Take a pick line from another bin',
            '{"activityType":"Pick","activityNo":"PI000003","lineNo":10000,"binCode":"W-01-0002"}',
            '{"status":"Success","activityType":"Pick","activityNo":"PI000003","changed":true,"line":{"lineNo":10000,"actionType":"Take","zoneCode":"PICK","binCode":"W-01-0002","qtyOutstanding":5},"unchangedPairedLineNos":[20000],"note":"Only line 10000 was changed; the paired lines 20000 keep their bin."}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Validates a new bin on one warehouse activity line. A Take line is refused when the bin does not hold the outstanding quantity; a Place line is refused when the bin does not accept stock. Changing the Take line of a pair leaves the Place line unchanged and the answer says so.', Comment = 'is-IS=Staðfestir nýtt hólf á einni línu vöruhúsaaðgerðar. Taka-línu er hafnað þegar hólfið geymir ekki útistandandi magn; Setja-línu er hafnað þegar hólfið tekur ekki við birgðum. Breyting á Taka-línu pars lætur Setja-línuna óbreytta og svarið segir það.';
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

    /// <summary>Validates the activity, the line and the bin and changes the bin, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Bin: Record Bin;
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        Result: JsonObject;
        ResponseJson: JsonObject;
        Token: JsonToken;
        Paired: JsonArray;
        AllowedKeys: List of [Text];
        BinText: Text;
        BinPresent: Boolean;
        Changed: Boolean;
        DeniedLbl: Label 'You do not have permission to change warehouse activity lines.', Comment = 'is-IS=Þú hefur ekki heimild til að breyta línum vöruhúsaaðgerða.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
        MissingLbl: Label 'binCode is required.', Comment = 'is-IS=binCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send the new bin in binCode.', Comment = 'is-IS=Sendu nýja hólfið í binCode.';
        PairedNoteLbl: Label 'Only line %1 was changed; the paired lines %2 keep their bin.', Comment = '%1 = line no., %2 = paired line nos., is-IS=Aðeins línu %1 var breytt; paraðar línur %2 halda hólfi sínu.';
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
        AllowedKeys.Add('binCode');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Context.ReadText(RequestJson, 'binCode', MaxStrLen(Bin.Code), Argument, BinText, BinPresent, 'binCode');
        if not Argument.HasCollectedErrors() then
            if not BinPresent then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'binCode', '', '', MissingNextStepLbl)
            else
                if Helper.ResolveActivity(RequestJson, Argument, ActivityHeader) then
                    if Helper.ResolveLine(RequestJson, Argument, ActivityHeader, '', -1, ActivityLine) then
                        CheckBin(Argument, ActivityLine, BinText);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Changed := UpperCase(ActivityLine."Bin Code") <> UpperCase(BinText);
        if Changed then begin
            Payload.Add('activityTypeOrdinal', ActivityLine."Activity Type".AsInteger());
            Payload.Add('activityNo', ActivityLine."No.");
            Payload.Add('lineNo', ActivityLine."Line No.");
            Payload.Add('binCode', BinText);
            Context.SetPayload(Payload);
            // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
            if Argument."Omit Commit" then
                Codeunit.Run(Codeunit::"Whse ActLine ChgBin Impl ori")
            else
                if not Codeunit.Run(Codeunit::"Whse ActLine ChgBin Impl ori") then begin
                    Context.Reset();
                    Argument.RespondWithLastError();
                    exit;
                end;
            Context.TryGetResult(Result);
        end else
            Result.Add('line', Helper.LineJson(ActivityLine));
        Paired := PairedLineNos(ActivityLine);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('activityType', Helper.ActivityTypeName(ActivityHeader.Type));
        ResponseJson.Add('activityNo', ActivityHeader."No.");
        ResponseJson.Add('changed', Changed);
        if Result.Get('line', Token) then
            ResponseJson.Add('line', Token);
        ResponseJson.Add('unchangedPairedLineNos', Paired);
        if Changed and (Paired.Count() > 0) then
            ResponseJson.Add('note', StrSubstNo(PairedNoteLbl, ActivityLine."Line No.", JoinLineNos(Paired)));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
        Context.Reset();
    end;

    local procedure CheckBin(var Argument: Record "Message Argument ori"; ActivityLine: Record "Warehouse Activity Line"; BinText: Text)
    var
        Bin: Record Bin;
        BinContent: Record "Bin Content";
        Helper: Codeunit "Whse ActLine Helper ori";
        Available: Decimal;
        NotFoundLbl: Label 'Bin %1 was not found at location %2.', Comment = '%1 = bin, %2 = location, is-IS=Hólf %1 fannst ekki á staðsetningu %2.';
        NotFoundNextStepLbl: Label 'Check the bin with Warehouse.Bin.Get.', Comment = 'is-IS=Athugaðu hólfið með Warehouse.Bin.Get.';
        TakeLbl: Label 'Bin %1 holds %2 base units of item %3 that can be taken; line %4 needs %5.', Comment = '%1 = bin, %2 = available, %3 = item, %4 = line no., %5 = needed, is-IS=Hólf %1 geymir %2 grunneiningar af vöru %3 sem má taka; lína %4 þarf %5.';
        PlaceLbl: Label 'Bin %1 does not accept stock: it is blocked for inbound movement or it is the adjustment bin.', Comment = '%1 = bin, is-IS=Hólf %1 tekur ekki við birgðum: það er lokað fyrir innfærslu eða það er leiðréttingarhólfið.';
        BinContentNextStepLbl: Label 'Read Warehouse.BinContent.Get.', Comment = 'is-IS=Lestu Warehouse.BinContent.Get.';
    begin
        if not Bin.Get(ActivityLine."Location Code", CopyStr(BinText, 1, MaxStrLen(Bin.Code))) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, BinText, ActivityLine."Location Code"), 'binCode', BinText, '', NotFoundNextStepLbl);
            exit;
        end;
        if UpperCase(ActivityLine."Bin Code") = UpperCase(BinText) then
            exit;
        if Helper.IsTake(ActivityLine) then begin
            Available := 0;
            if BinContent.Get(ActivityLine."Location Code", Bin.Code, ActivityLine."Item No.", ActivityLine."Variant Code", ActivityLine."Unit of Measure Code") then begin
                if ActivityLine."Lot No." <> '' then
                    BinContent.SetRange("Lot No. Filter", ActivityLine."Lot No.");
                if ActivityLine."Serial No." <> '' then
                    BinContent.SetRange("Serial No. Filter", ActivityLine."Serial No.");
                if ActivityLine."Package No." <> '' then
                    BinContent.SetRange("Package No. Filter", ActivityLine."Package No.");
                Available := BinContent.CalcQtyAvailToTake(0);
            end;
            if Available < ActivityLine."Qty. Outstanding (Base)" then
                Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(TakeLbl, Bin.Code, Available, ActivityLine."Item No.", ActivityLine."Line No.", ActivityLine."Qty. Outstanding (Base)"), 'binCode', BinText, Format(ActivityLine."Qty. Outstanding (Base)", 0, 9), BinContentNextStepLbl);
            exit;
        end;
        Bin.CalcFields("Adjustment Bin");
        if Bin."Adjustment Bin" or (Bin."Block Movement" in [Bin."Block Movement"::Inbound, Bin."Block Movement"::All]) then
            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(PlaceLbl, Bin.Code), 'binCode', BinText, '', BinContentNextStepLbl);
    end;

    local procedure PairedLineNos(ActivityLine: Record "Warehouse Activity Line"): JsonArray
    var
        Other: Record "Warehouse Activity Line";
        LineNos: JsonArray;
    begin
        if ActivityLine."Action Type" = ActivityLine."Action Type"::" " then
            exit(LineNos);
        Other.SetRange("Activity Type", ActivityLine."Activity Type");
        Other.SetRange("No.", ActivityLine."No.");
        Other.SetRange("Item No.", ActivityLine."Item No.");
        Other.SetRange("Variant Code", ActivityLine."Variant Code");
        Other.SetRange("Whse. Document Type", ActivityLine."Whse. Document Type");
        Other.SetRange("Whse. Document No.", ActivityLine."Whse. Document No.");
        Other.SetRange("Whse. Document Line No.", ActivityLine."Whse. Document Line No.");
        Other.SetRange("Source No.", ActivityLine."Source No.");
        Other.SetRange("Source Line No.", ActivityLine."Source Line No.");
        Other.SetFilter("Action Type", '<>%1&<>%2', ActivityLine."Action Type", ActivityLine."Action Type"::" ");
        Other.SetLoadFields("Line No.");
        if Other.FindSet() then
            repeat
                LineNos.Add(Other."Line No.");
            until Other.Next() = 0;
        exit(LineNos);
    end;

    local procedure JoinLineNos(LineNos: JsonArray): Text
    var
        Token: JsonToken;
        Builder: TextBuilder;
    begin
        foreach Token in LineNos do begin
            if Builder.Length() > 0 then
                Builder.Append(', ');
            Builder.Append(Format(Token.AsValue().AsInteger(), 0, 9));
        end;
        exit(Builder.ToText());
    end;
}
