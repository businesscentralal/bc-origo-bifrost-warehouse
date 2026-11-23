namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Activity.Assign (#105).
/// Assigns warehouse activities to a warehouse employee, or unassigns them, and optionally re-sorts them and sets the
/// due date of their lines. Every value goes through Validate, so Business Central checks that the user is a warehouse
/// employee at the activity's location. All named activities change in one transaction or none does.
/// </summary>
codeunit 10078442 "Whse Activity Assign Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        Result: JsonObject;
        MissingPayloadErr: Label 'The activity assign payload was empty.', Comment = 'is-IS=Gögnin til að úthluta aðgerð voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        Result := ApplyAssignment(Payload);
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can change warehouse activities.</summary>
    /// <returns>True when the caller can write activity headers and lines.</returns>
    procedure IsEnabled(): Boolean
    var
        Helper: Codeunit "Whse ActLine Helper ori";
    begin
        exit(Helper.HasWritePermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse activity header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Activity Header");
    end;

    /// <summary>Returns a short description of Warehouse.Activity.Assign.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Assigns picks, put-aways and movements to a warehouse employee and re-sorts them.', Comment = 'is-IS=Úthlutar tínslum, frágangi og tilfærslum til starfsmanns vöruhúss og raðar þeim upp á nýtt.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'assign pick, assign put-away, assign warehouse activity, unassign pick, warehouse employee, sort pick, re-sort activity, assigned user', Comment = 'is-IS=úthluta tínslu, úthluta frágangi, úthluta vöruhúsaaðgerð, afturkalla úthlutun tínslu, starfsmaður vöruhúss, raða tínslu, endurraða aðgerð, úthlutaður notandi';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Changes data. Assigns or unassigns warehouse activities and can change their sorting method and line due date.', Comment = 'is-IS=Breytir gögnum. Úthlutar vöruhúsaaðgerðum eða afturkallar úthlutun og getur breytt röðunaraðferð þeirra og gjalddaga lína.';
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
        Forms.Add('none');
        Envelope := Parts.RecordEnvelope(Forms, 'Not used. Name the activities in activities.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('data.activities[].activityType, data.activities[].activityNo, data.activities[].systemId', 'activity type and no., or guid', 'Each warehouse activity to assign.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        ActivitiesParameter: JsonObject;
        Children: JsonArray;
    begin
        Children.Add(ContractMgt.Parameter('activityType', 'string', false, 'Put-away, Pick, Movement, Invt. Put-away, Invt. Pick or Invt. Movement. Needed when the number exists for more than one type.'));
        Children.Add(ContractMgt.Parameter('activityNo', 'string', false, 'The activity number. Or send systemId.'));
        Children.Add(ContractMgt.Parameter('systemId', 'string', false, 'The SystemId of the activity.'));
        ActivitiesParameter := ContractMgt.Parameter('activities', 'array', true, 'The warehouse activities to assign.');
        ActivitiesParameter.Add('children', Children);
        Parameters.Add(ActivitiesParameter);
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', true, 'A warehouse employee at the location of each activity. An empty string unassigns.'));
        Parameters.Add(ContractMgt.Parameter('sortingMethod', 'string', false, 'Warehouse activity sorting method, by name. Re-sorts the lines.'));
        Parameters.Add(ContractMgt.Parameter('dueDate', 'date', false, 'Due date set on every line of each activity.'));
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
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('activities', 'array', 'Each activity as stored: activityType, activityNo, systemId, locationCode, assignedUserId, assignmentDate, sortingMethod.'));
        Fields.Add(ContractMgt.ResponseField('updatedCount', 'integer', 'Number of activities changed.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'activities, assignedUserId or an activity identifier is missing, or an activity number exists for more than one type.', MissingNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'activityType is not a warehouse activity type, or sortingMethod is not a sorting method.', Parts.SortingMethodNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, dueDate is not a date or systemId is not a GUID.', FormatNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request or an activity contains a key this type does not accept.', UnknownNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'A named activity was not found.', 'Check the activity with Warehouse.Activity.Get.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'The identifiers of an activity name different activities.', 'Use the activity no. answered by Warehouse.Activity.Get.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'Business Central refused a value, for example a user who is not a warehouse employee at the location. Nothing is changed.', RefusedNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot change warehouse activities, or the assigned user or sorting method field is closed to writes in this company.', DeniedNextStep());
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one problem was found before anything was written.', 'Correct every listed problem and send the request again.');
        Parts.AddBusinessCentralError(Errors, 'a subscriber that refuses the change');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.WriteEffect(Effect, 'Sets the assigned user, assignment date and optionally the sorting method and line due date of the named warehouse activities. Another assignment changes them back.', 'BIFROST Whse - Full ori', true);
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Get', 'Use it to find activities, and with assignedUserId the activities of one employee.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Document.Update', 'Use it to assign or change an open receipt or shipment.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'Use it when the assigned employee has picked.'));
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
            'Assign pick PI000001 to warehouse employee ANNA and sort it by shelf or bin',
            '{"activities":[{"activityType":"Pick","activityNo":"PI000001"}],"assignedUserId":"ANNA","sortingMethod":"Shelf or Bin"}',
            '{"status":"Success","activities":[{"activityType":"Pick","activityNo":"PI000001","systemId":"6f1c1d2e-0000-0000-0000-000000000001","locationCode":"WHITE","assignedUserId":"ANNA","assignmentDate":"2026-11-23","sortingMethod":"Shelf or Bin"}],"updatedCount":1}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Assigns one or more warehouse activities to a warehouse employee at their location, or unassigns them with an empty user. Optionally re-sorts the activity lines and sets their due date. All or nothing: one refused value leaves every named activity unchanged.', Comment = 'is-IS=Úthlutar einni eða fleiri vöruhúsaaðgerðum til starfsmanns vöruhúss á staðsetningu þeirra, eða afturkallar úthlutun með tómum notanda. Getur einnig raðað línum aðgerðarinnar upp á nýtt og stillt gjalddaga þeirra. Allt eða ekkert: eitt hafnað gildi skilur allar tilgreindar aðgerðir eftir óbreyttar.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True. The notes describe the assignment rules and refusals.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Any warehouse employee at the location of the activity can be assigned, not only the caller. The user must have a warehouse employee row for that location; otherwise Business Central refuses the value and the call answers PreconditionFailed with its reason. ' +
            'An empty assignedUserId unassigns the activities and clears the assignment date. The assignment date is set to today when a user is assigned. ' +
            'sortingMethod re-sorts the lines the same way as changing it on the activity. dueDate is set on every line of each activity. ' +
            'Each activity is named with activityType and activityNo, or with systemId. Problems found before anything is written are answered together as MultipleErrors. ' +
            'All or nothing: when Business Central refuses a value for one activity, no activity is changed. ' +
            'The caller needs BIFROST Whse - Full ori. A field closed to writes in this company is refused as PermissionDenied. Nothing is registered; the change is committed.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the request and assigns the activities, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Parts: Codeunit "Whse Contract Parts ori";
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        RequestValueReader: Codeunit "Request Value Reader ori";
        RequestJson: JsonObject;
        ActivityJson: JsonObject;
        Payload: JsonObject;
        Result: JsonObject;
        Activities: JsonArray;
        SystemIds: JsonArray;
        AllowedKeys: List of [Text];
        ActivityKeys: List of [Text];
        SeenIds: List of [Guid];
        UserText: Text;
        SortingText: Text;
        DueDate: Date;
        UserPresent: Boolean;
        SortingPresent: Boolean;
        DuePresent: Boolean;
        ActivitiesPresent: Boolean;
        Index: Integer;
        SortingOrdinal: Integer;
        DeniedLbl: Label 'You do not have permission to change warehouse activities.', Comment = 'is-IS=Þú hefur ekki heimild til að breyta vöruhúsaaðgerðum.';
        ProblemsLbl: Label 'Nothing was changed.', Comment = 'is-IS=Engu var breytt.';
        UserMissingLbl: Label 'assignedUserId is required; send an empty string to unassign.', Comment = 'is-IS=assignedUserId er nauðsynlegt; sendu tóman streng til að afturkalla úthlutun.';
        ActivitiesMissingLbl: Label 'activities is required and must name at least one activity.', Comment = 'is-IS=activities er nauðsynlegt og verður að nefna að minnsta kosti eina aðgerð.';
        SortingLbl: Label 'sortingMethod %1 is not a warehouse activity sorting method.', Comment = '%1 = value, is-IS=sortingMethod %1 er ekki röðunaraðferð vöruhúsaaðgerðar.';
        RestrictedLbl: Label 'Field %1 is restricted for write on table %2.', Comment = '%1 = field caption, %2 = table caption, is-IS=Ekki er heimilt að skrifa í reitinn %1 í töflunni %2.';
    begin
        Context.Reset();
        if not Helper.HasWritePermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStep());
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        AllowedKeys.Add('activities');
        AllowedKeys.Add('assignedUserId');
        AllowedKeys.Add('sortingMethod');
        AllowedKeys.Add('dueDate');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Context.ReadText(RequestJson, 'assignedUserId', MaxStrLen(ActivityHeader."Assigned User ID"), Argument, UserText, UserPresent, 'assignedUserId');
        Context.ReadText(RequestJson, 'sortingMethod', 50, Argument, SortingText, SortingPresent, 'sortingMethod');
        Context.ReadDate(RequestJson, 'dueDate', Argument, DueDate, DuePresent, 'dueDate');
        Values.ReadArray(RequestJson, 'activities', Argument, Activities, ActivitiesPresent);
        if not UserPresent and not Argument.HasCollectedErrors() then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, UserMissingLbl, 'assignedUserId', '', '', MissingNextStep());
        if UserPresent and RequestValueReader.IsFieldWriteRestricted(Database::"Warehouse Activity Header", ActivityHeader.FieldNo("Assigned User ID")) then
            Argument.AddError("Bifrost Error Code ori"::PermissionDenied, StrSubstNo(RestrictedLbl, ActivityHeader.FieldCaption("Assigned User ID"), ActivityHeader.TableCaption()), 'assignedUserId', '', '', Parts.ClosedFieldNextStep());
        SortingOrdinal := -1;
        if SortingPresent then
            if not TryParseSortingMethod(SortingText, SortingOrdinal) then
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(SortingLbl, SortingText), 'sortingMethod', SortingText, SortingMethodNames(), Parts.SortingMethodNextStep())
            else
                if RequestValueReader.IsFieldWriteRestricted(Database::"Warehouse Activity Header", ActivityHeader.FieldNo("Sorting Method")) then
                    Argument.AddError("Bifrost Error Code ori"::PermissionDenied, StrSubstNo(RestrictedLbl, ActivityHeader.FieldCaption("Sorting Method"), ActivityHeader.TableCaption()), 'sortingMethod', '', '', Parts.ClosedFieldNextStep());
        if (not ActivitiesPresent or (Activities.Count() = 0)) and not Argument.HasCollectedErrors() then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, ActivitiesMissingLbl, 'activities', '', '', MissingNextStep());
        Helper.AddActivityKeys(ActivityKeys);
        if ActivitiesPresent then
            for Index := 0 to Activities.Count() - 1 do
                if Values.TryGetLineObject(Activities, Index, 'activities', Argument, ActivityJson) then begin
                    Values.RefuseUnknownKeys(ActivityJson, ActivityKeys, Argument, 'activities', Index);
                    if Helper.ResolveActivity(ActivityJson, Argument, ActivityHeader) then
                        if not SeenIds.Contains(ActivityHeader.SystemId) then begin
                            SeenIds.Add(ActivityHeader.SystemId);
                            SystemIds.Add(Format(ActivityHeader.SystemId, 0, 4));
                        end;
                end;
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('systemIds', SystemIds);
        Payload.Add('assignedUserId', UserText);
        Payload.Add('sortingMethod', SortingOrdinal);
        if DuePresent then
            Payload.Add('dueDate', Format(DueDate, 0, 9));
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Activity Assign Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Activity Assign Impl ori") then begin
                Context.Reset();
                Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, GetLastErrorText(), 'assignedUserId', UserText, '', RefusedNextStep());
                exit;
            end;
        Context.TryGetResult(Result);
        Context.Reset();
        Result.Add('status', 'Success');
        Argument.SetResponseJson(Result);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ApplyAssignment(Payload: JsonObject) Result: JsonObject
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Values: Codeunit "Whse Msg Values ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Token: JsonToken;
        IdToken: JsonToken;
        SystemIds: JsonArray;
        ResultActivities: JsonArray;
        ResultActivity: JsonObject;
        ActivitySystemId: Guid;
        DueDate: Date;
        HasDueDate: Boolean;
        SortingOrdinal: Integer;
    begin
        Payload.Get('systemIds', Token);
        SystemIds := Token.AsArray();
        SortingOrdinal := Values.IntegerValue(Payload, 'sortingMethod');
        if Payload.Get('dueDate', Token) then begin
            Evaluate(DueDate, Token.AsValue().AsText(), 9);
            HasDueDate := true;
        end;
        foreach IdToken in SystemIds do begin
            Evaluate(ActivitySystemId, IdToken.AsValue().AsText());
            ActivityHeader.GetBySystemId(ActivitySystemId);
            ActivityHeader.Validate("Assigned User ID", CopyStr(Values.TextValue(Payload, 'assignedUserId'), 1, MaxStrLen(ActivityHeader."Assigned User ID")));
            if SortingOrdinal >= 0 then
                ActivityHeader.Validate("Sorting Method", Enum::"Whse. Activity Sorting Method".FromInteger(SortingOrdinal));
            ActivityHeader.Modify(true);
            if HasDueDate then begin
                ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
                ActivityLine.SetRange("No.", ActivityHeader."No.");
                if ActivityLine.FindSet(true) then
                    repeat
                        ActivityLine.Validate("Due Date", DueDate);
                        ActivityLine.Modify(true);
                    until ActivityLine.Next() = 0;
            end;
            ActivityHeader.Get(ActivityHeader.Type, ActivityHeader."No.");
            Clear(ResultActivity);
            ResultActivity.Add('activityType', Helper.ActivityTypeName(ActivityHeader.Type));
            ResultActivity.Add('activityNo', ActivityHeader."No.");
            ResultActivity.Add('systemId', Format(ActivityHeader.SystemId, 0, 4).ToLower());
            ResultActivity.Add('locationCode', ActivityHeader."Location Code");
            ResultActivity.Add('assignedUserId', ActivityHeader."Assigned User ID");
            ResultActivity.Add('assignmentDate', Values.DateText(ActivityHeader."Assignment Date"));
            ResultActivity.Add('sortingMethod', SortingMethodName(ActivityHeader."Sorting Method"));
            ResultActivities.Add(ResultActivity);
        end;
        Result.Add('activities', ResultActivities);
        Result.Add('updatedCount', ResultActivities.Count());
    end;

    local procedure TryParseSortingMethod(Received: Text; var Ordinal: Integer): Boolean
    var
        Context: Codeunit "Whse Write Context ori";
        Name: Text;
        Position: Integer;
    begin
        foreach Name in Enum::"Whse. Activity Sorting Method".Names() do begin
            Position += 1;
            if Context.SameName(Received, Name) then begin
                Ordinal := Enum::"Whse. Activity Sorting Method".Ordinals().Get(Position);
                exit(true);
            end;
        end;
        exit(false);
    end;

    local procedure SortingMethodNames() Names: Text
    var
        Name: Text;
    begin
        foreach Name in Enum::"Whse. Activity Sorting Method".Names() do begin
            if Names <> '' then
                Names += ', ';
            Names += Name;
        end;
    end;

    local procedure SortingMethodName(SortingMethod: Enum "Whse. Activity Sorting Method"): Text
    begin
        exit(Enum::"Whse. Activity Sorting Method".Names().Get(Enum::"Whse. Activity Sorting Method".Ordinals().IndexOf(SortingMethod.AsInteger())));
    end;

    local procedure MissingNextStep(): Text
    var
        NextStepLbl: Label 'Send the missing value; Help.Implementation.Get lists the parameters.', Comment = 'is-IS=Sendu gildið sem vantar; Help.Implementation.Get sýnir viðföngin.';
    begin
        exit(NextStepLbl);
    end;

    local procedure FormatNextStep(): Text
    var
        NextStepLbl: Label 'Send the value in the format listed in expected.', Comment = 'is-IS=Sendu gildið á sniðinu sem tilgreint er í expected.';
    begin
        exit(NextStepLbl);
    end;

    local procedure UnknownNextStep(): Text
    var
        NextStepLbl: Label 'Remove this key or consult Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu þennan lykil eða skoðaðu Help.Implementation.Get til að sjá skilgreind viðföng.';
    begin
        exit(NextStepLbl);
    end;

    local procedure RefusedNextStep(): Text
    var
        NextStepLbl: Label 'Assign a warehouse employee of the activity location, or correct the refused value; nothing was changed.', Comment = 'is-IS=Úthlutaðu starfsmanni vöruhúss á staðsetningu aðgerðarinnar, eða leiðréttu gildið sem var hafnað; engu var breytt.';
    begin
        exit(NextStepLbl);
    end;

    local procedure DeniedNextStep(): Text
    var
        NextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
    begin
        exit(NextStepLbl);
    end;
}
