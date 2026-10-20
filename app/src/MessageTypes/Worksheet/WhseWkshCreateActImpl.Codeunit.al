namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Worksheet.CreateActivities (#55).
/// Optionally writes Qty. to Handle on worksheet lines through Validate, then runs report 5754 "Create Pick" for a pick
/// worksheet or report 7305 "Whse.-Source - Create Document" for a put-away worksheet. Lines with nothing to handle
/// stay in the worksheet and are answered under skipped.
/// </summary>
codeunit 10078461 "Whse Wksh CreateAct Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        ActivityHeader: Record "Warehouse Activity Header";
        CreatePick: Report "Create Pick";
        CreateDocument: Report "Whse.-Source - Create Document";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Worksheet Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        LineObject: JsonObject;
        Result: JsonObject;
        Token: JsonToken;
        Created: JsonArray;
        Existing: List of [Code[20]];
        TemplateName: Code[10];
        WorksheetName: Code[10];
        LocationCode: Code[10];
        AssignedUserId: Code[50];
        SortingMethod: Enum "Whse. Activity Sorting Method";
        ActivityType: Enum "Warehouse Activity Type";
        IsPick: Boolean;
        MissingPayloadErr: Label 'The worksheet payload was empty.', Comment = 'is-IS=Gögn vinnublaðsins voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        IsPick := Values.BooleanValue(Payload, 'isPick');
        TemplateName := CopyStr(Values.TextValue(Payload, 'worksheetTemplateName'), 1, MaxStrLen(TemplateName));
        WorksheetName := CopyStr(Values.TextValue(Payload, 'worksheetName'), 1, MaxStrLen(WorksheetName));
        LocationCode := CopyStr(Values.TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        AssignedUserId := CopyStr(Values.TextValue(Payload, 'assignedUserId'), 1, MaxStrLen(AssignedUserId));
        SortingMethod := Enum::"Whse. Activity Sorting Method".FromInteger(Values.IntegerValue(Payload, 'sortingMethodOrdinal'));
        foreach Token in Values.ArrayValue(Payload, 'lines') do begin
            LineObject := Token.AsObject();
            WorksheetLine.Get(TemplateName, WorksheetName, LocationCode, Values.IntegerValue(LineObject, 'lineNo'));
            WorksheetLine.Validate("Qty. to Handle", Values.DecimalValue(LineObject, 'qtyToHandle'));
            WorksheetLine.Modify(true);
        end;
        if IsPick then
            ActivityType := ActivityType::Pick
        else
            ActivityType := ActivityType::"Put-away";
        ActivityHeader.SetRange(Type, ActivityType);
        ActivityHeader.SetRange("Location Code", LocationCode);
        ActivityHeader.SetLoadFields(Type, "No.");
        if ActivityHeader.FindSet() then
            repeat
                Existing.Add(ActivityHeader."No.");
            until ActivityHeader.Next() = 0;
        Clear(WorksheetLine);
        Helper.FilterWorksheet(WorksheetLine, TemplateName, WorksheetName, LocationCode);
        if IsPick then begin
            CreatePick.SetWkshPickLine(WorksheetLine);
            CreatePick.InitializeReport(
                AssignedUserId, 0, 0, SortingMethod,
                Values.BooleanValue(Payload, 'perShipTo'), Values.BooleanValue(Payload, 'perItem'), Values.BooleanValue(Payload, 'perZone'),
                Values.BooleanValue(Payload, 'perBin'), Values.BooleanValue(Payload, 'perWhseDoc'), Values.BooleanValue(Payload, 'perDate'),
                false, false, false);
            CreatePick.UseRequestPage(false);
            CreatePick.RunModal();
        end else begin
            WorksheetLine.SetFilter("Qty. to Handle", '>0');
            WorksheetLine.FindFirst();
            WorksheetLine.SetRange("Qty. to Handle");
            CreateDocument.SetWhseWkshLine(WorksheetLine);
            CreateDocument.Initialize(AssignedUserId, SortingMethod, false, false, false);
            CreateDocument.SetHideValidationDialog(true);
            CreateDocument.UseRequestPage(false);
            CreateDocument.RunModal();
        end;
        Clear(ActivityHeader);
        ActivityHeader.SetRange(Type, ActivityType);
        ActivityHeader.SetRange("Location Code", LocationCode);
        ActivityHeader.SetLoadFields(Type, "No.");
        if ActivityHeader.FindSet() then
            repeat
                if not Existing.Contains(ActivityHeader."No.") then
                    Created.Add(ActivityHeader."No.");
            until ActivityHeader.Next() = 0;
        Result.Add('activityNos', Created);
        Context.SetResult(Result);
    end;

    /// <summary>Returns whether the caller can write worksheet lines and the warehouse activities the reports create.</summary>
    /// <returns>True when the caller can create picks and put-aways from a worksheet.</returns>
    procedure IsEnabled(): Boolean
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
    begin
        exit(WorksheetLine.WritePermission() and ActivityHeader.WritePermission() and ActivityLine.WritePermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse worksheet line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Whse. Worksheet Line");
    end;

    /// <summary>Returns a short description of Warehouse.Worksheet.CreateActivities.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates picks or put-aways from the lines of a pick or put-away worksheet.', Comment = 'is-IS=Stofnar tínslur eða frágang úr línum tínslu- eða frágangsvinnublaðs.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'create pick from worksheet, create put-away from worksheet, pick worksheet, put-away worksheet, wave picking, group picks', Comment = 'is-IS=stofna tínslu úr vinnublaði, stofna frágang úr vinnublaði, tínsluvinnublað, frágangsvinnublað, bylgjutínsla, flokka tínslur';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Creates warehouse picks or put-aways from the worksheet lines with quantity to handle, optionally grouped per ship-to, item, zone, bin, document or date; Business Central commits the documents it creates. Lines with nothing to handle stay in the worksheet.', Comment = 'is-IS=Óafturkræft. Stofnar tínslur eða frágang vöruhúss úr vinnublaðslínum með magni til meðhöndlunar, valfrjálst flokkað eftir sendist-til, vöru, svæði, hólfi, skjali eða dagsetningu; Business Central staðfestir skjölin sem það stofnar. Línur án magns til meðhöndlunar verða eftir á vinnublaðinu.';
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
        Forms.Add('location code');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. The location of the worksheet. Do not send a different location in subject and locationCode.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The location. Optional when locationCode is sent.'));
        Target.Add(ContractMgt.TargetEntry('data.worksheetTemplateName + data.worksheetName + data.locationCode', 'worksheet', 'The pick or put-away worksheet name at the location.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('worksheetType', 'string', true, 'pick or putAway.'));
        Parameters.Add(ContractMgt.Parameter('worksheetTemplateName', 'string', true, 'Worksheet template of the matching type.'));
        Parameters.Add(ContractMgt.Parameter('worksheetName', 'string', true, 'Worksheet name at the location.'));
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location of the worksheet. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Optional quantities to handle per worksheet line, written before the activities are created. Lines that are not sent keep their quantity to handle.'));
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Worksheet line number answered by Warehouse.Worksheet.GetDocuments.'));
        Parameters.Add(ContractMgt.Parameter('qtyToHandle', 'number', true, 'Quantity to handle, from zero up to the outstanding quantity. Zero leaves the line in the worksheet.'));
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'Warehouse employee of the location assigned to the created activities.'));
        Parameters.Add(ContractMgt.Parameter('sortingMethod', 'string', false, 'Sorting method of the created activities, one of "None", "Item", "Document", "Shelf or Bin", "Due Date", "Ship-To", "Bin Ranking" or "Action Type".'));
        Parameters.Add(ContractMgt.Parameter('perShipTo', 'boolean', false, 'pick only. One pick per ship-to address.'));
        Parameters.Add(ContractMgt.Parameter('perItem', 'boolean', false, 'pick only. One pick per item.'));
        Parameters.Add(ContractMgt.Parameter('perZone', 'boolean', false, 'pick only. One pick per zone.'));
        Parameters.Add(ContractMgt.Parameter('perBin', 'boolean', false, 'pick only. One pick per bin.'));
        Parameters.Add(ContractMgt.Parameter('perWhseDoc', 'boolean', false, 'pick only. One pick per warehouse document.'));
        Parameters.Add(ContractMgt.Parameter('perDate', 'boolean', false, 'pick only. One pick per due date.'));
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
        ActivityFields: JsonArray;
        Activities: JsonObject;
        SkippedFields: JsonArray;
        Skipped: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('worksheetType', 'string', 'pick or putAway.'));
        Fields.Add(ContractMgt.ResponseField('worksheetTemplateName', 'string', 'Worksheet template.'));
        Fields.Add(ContractMgt.ResponseField('worksheetName', 'string', 'Worksheet name.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location.'));
        Fields.Add(ContractMgt.ResponseField('activityCount', 'integer', 'Number of picks or put-aways created.'));
        ActivityFields.Add(ContractMgt.ResponseField('activityType', 'string', 'Pick or Put-away.'));
        ActivityFields.Add(ContractMgt.ResponseField('activityNo', 'string', 'Number of the created activity; read it with Warehouse.Activity.Get.'));
        ActivityFields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Lines of the activity.'));
        Activities.Add('name', 'activities');
        Activities.Add('type', 'array');
        Activities.Add('description', 'Created picks or put-aways.');
        Activities.Add('children', ActivityFields);
        Fields.Add(Activities);
        SkippedFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Worksheet line number.'));
        SkippedFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        SkippedFields.Add(ContractMgt.ResponseField('qtyOutstanding', 'number', 'Quantity still in the worksheet.'));
        Skipped.Add('name', 'skipped');
        Skipped.Add('type', 'array');
        Skipped.Add('description', 'Worksheet lines that had quantity to handle zero; they stay in the worksheet.');
        Skipped.Add('children', SkippedFields);
        Fields.Add(Skipped);
        Fields.Add(ContractMgt.ResponseField('remainingLineCount', 'integer', 'Worksheet lines left after the call.'));
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not require pick and shipment (pick) or put-away and receipt (putAway).', 'Use the inventory activities instead.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The worksheet has no lines, or no line has quantity to handle.', 'Fill the worksheet with Warehouse.Worksheet.GetDocuments and send qtyToHandle above zero on at least one line.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The worksheet template or worksheet name was not found at the location, or a line number is not in the worksheet.', 'Create the worksheet name first, and use the line numbers answered by Warehouse.Worksheet.GetDocuments.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'A worksheet key is missing, or a line misses lineNo or qtyToHandle.', 'Send worksheetType, worksheetTemplateName, worksheetName and locationCode, and lineNo and qtyToHandle on every line.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes, an integer lineNo, a number for qtyToHandle and true or false for the grouping options.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'worksheetType is not valid, the template is not of the worksheet type, qtyToHandle is negative or above the outstanding quantity, assignedUserId is not a warehouse employee of the location, or a grouping option is sent for a put-away worksheet.', 'Correct the value as the message says.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'sortingMethod is not a warehouse activity sorting method.', 'Send one of "None", "Item", "Document", "Shelf or Bin", "Due Date", "Ship-To", "Bin Ranking" or "Action Type".');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request or a line contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations.', 'Send one location: subject or locationCode.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write worksheet lines and warehouse activities.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central created nothing, for example when no bin holds the item.', 'Read the returned text and correct the stock or the worksheet. Nothing was written.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Writes quantities to handle on worksheet lines, creates warehouse pick or put-away documents and reduces or deletes the handled worksheet lines. Business Central commits the documents it creates.', 'BIFROST Whse - Full ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Worksheet.GetDocuments', 'Use it to fill the worksheet first.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Get', 'Use it to read the created picks or put-aways.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'Use it to register a created pick.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Putaway.Register', 'Use it to register a created put-away.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>True when a workflow is declared.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    var
        Helper: Codeunit "Whse Worksheet Helper ori";
    begin
        Helper.WorksheetWorkflow(Workflow);
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
            'Create one pick per item, leaving one line in the worksheet',
            '{"worksheetType":"pick","worksheetTemplateName":"PICK","worksheetName":"DEFAULT","locationCode":"WHITE","perItem":true,"lines":[{"lineNo":20000,"qtyToHandle":0}]}',
            '{"status":"Success","worksheetType":"pick","worksheetTemplateName":"PICK","worksheetName":"DEFAULT","locationCode":"WHITE","activityCount":1,"activities":[{"activityType":"Pick","activityNo":"PI000012","lineCount":2}],"skipped":[{"lineNo":20000,"itemNo":"1900-S","qtyOutstanding":3}],"remainingLineCount":1}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Writes the optional quantities to handle, then runs Create Pick or Create Put-away on a pick or put-away worksheet and answers the created activity numbers. Lines with quantity to handle zero are left in the worksheet and listed under skipped.', Comment = 'is-IS=Skrifar valfrjálst magn til meðhöndlunar og keyrir síðan Stofna tínslu eða Stofna frágang á tínslu- eða frágangsvinnublaði og skilar númerum stofnaðra aðgerða. Línur með núll til meðhöndlunar verða eftir á vinnublaðinu og eru taldar undir skipped.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Create Pick commits each pick it creates. The grouping options are the Create Pick request page options; a put-away worksheet accepts assignedUserId and sortingMethod only.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the worksheet, the lines and the options and creates the activities, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Worksheet Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        Lines: JsonArray;
        PlannedLines: JsonArray;
        Skipped: JsonArray;
        AllowedKeys: List of [Text];
        GroupingKeys: List of [Text];
        GroupingKey: Text;
        TemplateName: Code[10];
        WorksheetName: Code[10];
        LocationCode: Code[10];
        AssignedText: Text;
        SortingText: Text;
        SortingOrdinal: Integer;
        IsPick: Boolean;
        LinesPresent: Boolean;
        Present: Boolean;
        Flag: Boolean;
        DeniedLbl: Label 'You do not have permission to create picks or put-aways from a worksheet.', Comment = 'is-IS=Þú hefur ekki heimild til að stofna tínslur eða frágang úr vinnublaði.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
        PickOnlyLbl: Label '%1 applies to a pick worksheet only.', Comment = '%1 = parameter, is-IS=%1 á aðeins við tínsluvinnublað.';
        PickOnlyNextStepLbl: Label 'Remove the grouping option, or use a pick worksheet.', Comment = 'is-IS=Fjarlægðu flokkunarvalið, eða notaðu tínsluvinnublað.';
    begin
        Context.Reset();
        if not IsEnabled() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        if not WhseRecordLookup.TryReadIdentifiers(Argument, '', RequestJson) then
            exit;
        GroupingKeys.Add('perShipTo');
        GroupingKeys.Add('perItem');
        GroupingKeys.Add('perZone');
        GroupingKeys.Add('perBin');
        GroupingKeys.Add('perWhseDoc');
        GroupingKeys.Add('perDate');
        AllowedKeys.Add('worksheetType');
        AllowedKeys.Add('worksheetTemplateName');
        AllowedKeys.Add('worksheetName');
        AllowedKeys.Add('locationCode');
        AllowedKeys.Add('lines');
        AllowedKeys.Add('assignedUserId');
        AllowedKeys.Add('sortingMethod');
        AllowedKeys.AddRange(GroupingKeys);
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        Helper.ReadWorksheetKeys(RequestJson, Argument, IsPick, TemplateName, WorksheetName, LocationCode);
        Context.ReadText(RequestJson, 'assignedUserId', 50, Argument, AssignedText, Present, 'assignedUserId');
        Context.ReadText(RequestJson, 'sortingMethod', 30, Argument, SortingText, Present, 'sortingMethod');
        Values.ReadArray(RequestJson, 'lines', Argument, Lines, LinesPresent);
        foreach GroupingKey in GroupingKeys do begin
            Context.ReadBoolean(RequestJson, GroupingKey, Argument, Flag, Present, GroupingKey);
            Payload.Add(GroupingKey, Flag);
        end;
        if not Argument.HasCollectedErrors() then begin
            if not IsPick then
                foreach GroupingKey in GroupingKeys do
                    if Values.BooleanValue(Payload, GroupingKey) then
                        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(PickOnlyLbl, GroupingKey), GroupingKey, 'true', 'false', PickOnlyNextStepLbl);
            ParseSortingMethod(Argument, SortingText, SortingOrdinal);
        end;
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not Helper.ResolveWorksheet(Argument, IsPick, TemplateName, WorksheetName, LocationCode) then
            exit;
        if not CheckAssignedUser(Argument, AssignedText, LocationCode) then
            exit;
        ReadLines(Lines, Argument, TemplateName, WorksheetName, LocationCode, PlannedLines);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if not CheckSomethingToHandle(Argument, TemplateName, WorksheetName, LocationCode, PlannedLines, Skipped) then
            exit;
        Payload.Add('isPick', IsPick);
        Payload.Add('worksheetTemplateName', TemplateName);
        Payload.Add('worksheetName', WorksheetName);
        Payload.Add('locationCode', LocationCode);
        Payload.Add('assignedUserId', AssignedText);
        Payload.Add('sortingMethodOrdinal', SortingOrdinal);
        Payload.Add('lines', PlannedLines);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Wksh CreateAct Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Wksh CreateAct Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        WriteResponse(Argument, IsPick, TemplateName, WorksheetName, LocationCode, Skipped);
        Context.Reset();
    end;

    local procedure WriteResponse(var Argument: Record "Message Argument ori"; IsPick: Boolean; TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]; Skipped: JsonArray)
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse Worksheet Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Result: JsonObject;
        ResponseJson: JsonObject;
        ActivityJson: JsonObject;
        Token: JsonToken;
        Activities: JsonArray;
        ActivityTypeName: Text;
    begin
        Context.TryGetResult(Result);
        if IsPick then begin
            ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::Pick);
            ActivityTypeName := 'Pick';
        end else begin
            ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Put-away");
            ActivityTypeName := 'Put-away';
        end;
        foreach Token in Values.ArrayValue(Result, 'activityNos') do begin
            Clear(ActivityJson);
            ActivityLine.SetRange("No.", CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(ActivityLine."No.")));
            ActivityJson.Add('activityType', ActivityTypeName);
            ActivityJson.Add('activityNo', Token.AsValue().AsText());
            ActivityJson.Add('lineCount', ActivityLine.Count());
            Activities.Add(ActivityJson);
        end;
        Helper.FilterWorksheet(WorksheetLine, TemplateName, WorksheetName, LocationCode);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('worksheetType', Helper.WorksheetTypeName(IsPick));
        ResponseJson.Add('worksheetTemplateName', TemplateName);
        ResponseJson.Add('worksheetName', WorksheetName);
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('activityCount', Activities.Count());
        ResponseJson.Add('activities', Activities);
        ResponseJson.Add('skipped', Skipped);
        ResponseJson.Add('remainingLineCount', WorksheetLine.Count());
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure ReadLines(Lines: JsonArray; var Argument: Record "Message Argument ori"; TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]; var PlannedLines: JsonArray)
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        LineObject: JsonObject;
        Planned: JsonObject;
        AllowedKeys: List of [Text];
        Index: Integer;
        ErrorCount: Integer;
        LineNo: Integer;
        Quantity: Decimal;
        LinePresent: Boolean;
        QuantityPresent: Boolean;
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line position in the request, counted from 1, %2 = parameter, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send lineNo and qtyToHandle on every line.', Comment = 'is-IS=Sendu lineNo og qtyToHandle á hverri línu.';
        NotFoundLbl: Label 'Worksheet line %1 was not found.', Comment = '%1 = line no., is-IS=Vinnublaðslína %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Use the line numbers answered by Warehouse.Worksheet.GetDocuments.', Comment = 'is-IS=Notaðu línunúmerin sem Warehouse.Worksheet.GetDocuments skilaði.';
        RangeLbl: Label 'qtyToHandle on line %1 must be from zero up to the outstanding quantity %2.', Comment = '%1 = line no., %2 = outstanding, is-IS=qtyToHandle á línu %1 verður að vera frá núlli upp í útistandandi magn %2.';
        RangeNextStepLbl: Label 'Send a quantity from zero up to the outstanding quantity.', Comment = 'is-IS=Sendu magn frá núlli upp í útistandandi magn.';
    begin
        AllowedKeys.Add('lineNo');
        AllowedKeys.Add('qtyToHandle');
        for Index := 0 to Lines.Count() - 1 do
            if Values.TryGetLineObject(Lines, Index, 'lines', Argument, LineObject) then begin
                ErrorCount := Argument.GetCollectedErrorsJson().Count();
                Values.RefuseUnknownKeys(LineObject, AllowedKeys, Argument, 'lines', Index);
                Context.ReadInteger(LineObject, 'lineNo', Argument, LineNo, LinePresent, Values.LineParameter('lines', Index, 'lineNo'));
                Context.ReadDecimal(LineObject, 'qtyToHandle', Argument, Quantity, QuantityPresent, Values.LineParameter('lines', Index, 'qtyToHandle'));
                if Argument.GetCollectedErrorsJson().Count() = ErrorCount then begin
                    if not LinePresent then
                        Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'lineNo'), Values.LineParameter('lines', Index, 'lineNo'), '', '', MissingNextStepLbl);
                    if not QuantityPresent then
                        Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'qtyToHandle'), Values.LineParameter('lines', Index, 'qtyToHandle'), '', '', MissingNextStepLbl);
                    if LinePresent and QuantityPresent then
                        if not WorksheetLine.Get(TemplateName, WorksheetName, LocationCode, LineNo) then
                            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LineNo), Values.LineParameter('lines', Index, 'lineNo'), Format(LineNo, 0, 9), '', NotFoundNextStepLbl)
                        else
                            if (Quantity < 0) or (Quantity > WorksheetLine."Qty. Outstanding") then
                                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(RangeLbl, LineNo, WorksheetLine."Qty. Outstanding"), Values.LineParameter('lines', Index, 'qtyToHandle'), Format(Quantity, 0, 9), '', RangeNextStepLbl)
                            else begin
                                Clear(Planned);
                                Planned.Add('lineNo', LineNo);
                                Planned.Add('qtyToHandle', Quantity);
                                PlannedLines.Add(Planned);
                            end;
                end;
            end;
    end;

    local procedure CheckSomethingToHandle(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]; PlannedLines: JsonArray; var Skipped: JsonArray): Boolean
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        Helper: Codeunit "Whse Worksheet Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Planned: Dictionary of [Integer, Decimal];
        SkippedJson: JsonObject;
        Token: JsonToken;
        Quantity: Decimal;
        HasQuantity: Boolean;
        EmptyLbl: Label 'Worksheet %1 has no lines.', Comment = '%1 = worksheet name, is-IS=Vinnublað %1 hefur engar línur.';
        EmptyNextStepLbl: Label 'Fill the worksheet with Warehouse.Worksheet.GetDocuments first.', Comment = 'is-IS=Fylltu vinnublaðið með Warehouse.Worksheet.GetDocuments fyrst.';
        NothingLbl: Label 'No line of worksheet %1 has quantity to handle.', Comment = '%1 = worksheet name, is-IS=Engin lína á vinnublaði %1 hefur magn til meðhöndlunar.';
        NothingNextStepLbl: Label 'Send qtyToHandle above zero on at least one line.', Comment = 'is-IS=Sendu qtyToHandle stærra en núll á að minnsta kosti einni línu.';
    begin
        Clear(Skipped);
        foreach Token in PlannedLines do
            if not Planned.ContainsKey(Values.IntegerValue(Token.AsObject(), 'lineNo')) then
                Planned.Add(Values.IntegerValue(Token.AsObject(), 'lineNo'), Values.DecimalValue(Token.AsObject(), 'qtyToHandle'));
        Helper.FilterWorksheet(WorksheetLine, TemplateName, WorksheetName, LocationCode);
        WorksheetLine.SetLoadFields("Line No.", "Item No.", "Qty. Outstanding", "Qty. to Handle");
        if not WorksheetLine.FindSet() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(EmptyLbl, WorksheetName), 'worksheetName', WorksheetName, '', EmptyNextStepLbl);
            exit(false);
        end;
        repeat
            if Planned.ContainsKey(WorksheetLine."Line No.") then
                Quantity := Planned.Get(WorksheetLine."Line No.")
            else
                Quantity := WorksheetLine."Qty. to Handle";
            if Quantity > 0 then
                HasQuantity := true
            else begin
                Clear(SkippedJson);
                SkippedJson.Add('lineNo', WorksheetLine."Line No.");
                SkippedJson.Add('itemNo', WorksheetLine."Item No.");
                SkippedJson.Add('qtyOutstanding', WorksheetLine."Qty. Outstanding");
                Skipped.Add(SkippedJson);
            end;
        until WorksheetLine.Next() = 0;
        if HasQuantity then
            exit(true);
        Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NothingLbl, WorksheetName), 'qtyToHandle', '0', '', NothingNextStepLbl);
        exit(false);
    end;

    local procedure CheckAssignedUser(var Argument: Record "Message Argument ori"; AssignedText: Text; LocationCode: Code[10]): Boolean
    var
        WarehouseEmployee: Record "Warehouse Employee";
        NotEmployeeLbl: Label 'User %1 is not a warehouse employee of location %2.', Comment = '%1 = user, %2 = location, is-IS=Notandi %1 er ekki vöruhússtarfsmaður staðsetningar %2.';
        NotEmployeeNextStepLbl: Label 'Send a warehouse employee of the location, or omit assignedUserId.', Comment = 'is-IS=Sendu vöruhússtarfsmann staðsetningarinnar, eða slepptu assignedUserId.';
    begin
        if AssignedText = '' then
            exit(true);
        WarehouseEmployee.SetLoadFields("User ID", "Location Code");
        if WarehouseEmployee.Get(CopyStr(AssignedText, 1, MaxStrLen(WarehouseEmployee."User ID")), LocationCode) then
            exit(true);
        Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(NotEmployeeLbl, AssignedText, LocationCode), 'assignedUserId', AssignedText, '', NotEmployeeNextStepLbl);
        exit(false);
    end;

    local procedure ParseSortingMethod(var Argument: Record "Message Argument ori"; SortingText: Text; var SortingOrdinal: Integer)
    var
        Names: List of [Text];
        Index: Integer;
        InvalidLbl: Label 'sortingMethod %1 is not a warehouse activity sorting method.', Comment = '%1 = value, is-IS=sortingMethod %1 er ekki röðunaraðferð vöruhúsaaðgerða.';
        InvalidNextStepLbl: Label 'Send one of "None", "Item", "Document", "Shelf or Bin", "Due Date", "Ship-To", "Bin Ranking" or "Action Type".', Comment = 'is-IS=Sendu eitt af "None", "Item", "Document", "Shelf or Bin", "Due Date", "Ship-To", "Bin Ranking" eða "Action Type".';
    begin
        SortingOrdinal := 0;
        if SortingText = '' then
            exit;
        Names := Enum::"Whse. Activity Sorting Method".Names();
        for Index := 1 to Names.Count() do
            if LowerCase(Names.Get(Index)) = LowerCase(SortingText) then begin
                SortingOrdinal := Enum::"Whse. Activity Sorting Method".Ordinals().Get(Index);
                exit;
            end;
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(InvalidLbl, SortingText), 'sortingMethod', SortingText, '', InvalidNextStepLbl);
    end;
}
