namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Setup;
using Origo.Bifrost;

/// <summary>
/// Shared logic for the activity line types Warehouse.ActivityLine.Split, ChangeBin, SetQtyToHandle and
/// AssignTracking (#56, #57): resolves the activity and its lines and writes a line as JSON.
/// </summary>
codeunit 10078466 "Whse ActLine Helper ori"
{
    Access = Internal;

    /// <summary>Adds the activity identifier keys to an allowed-key list.</summary>
    /// <param name="AllowedKeys">The list.</param>
    internal procedure AddActivityKeys(var AllowedKeys: List of [Text])
    begin
        AllowedKeys.Add('activityType');
        AllowedKeys.Add('activityNo');
        AllowedKeys.Add('systemId');
    end;

    /// <summary>
    /// Resolves the activity from activityType, activityNo, systemId or the subject. Collects the errors on Argument.
    /// </summary>
    /// <param name="RequestJson">The request.</param>
    /// <param name="Argument">Collects the errors.</param>
    /// <param name="ActivityHeader">Receives the activity.</param>
    /// <returns>True when exactly one activity was found.</returns>
    internal procedure ResolveActivity(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var ActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        BySystemId: Record "Warehouse Activity Header";
        ByNumber: Record "Warehouse Activity Header";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        ActivityType: Enum "Warehouse Activity Type";
        TypeText: Text;
        NumberText: Text;
        SystemIdText: Text;
        SubjectText: Text;
        TypePresent: Boolean;
        NumberPresent: Boolean;
        SystemPresent: Boolean;
        ParsedId: Guid;
        MissingLbl: Label 'activityNo or systemId is required.', Comment = 'is-IS=activityNo eða systemId er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send activityType and activityNo, or the SystemId of the activity.', Comment = 'is-IS=Sendu activityType og activityNo, eða SystemId aðgerðarinnar.';
        TypeLbl: Label 'activityType %1 is not a warehouse activity type.', Comment = '%1 = value, is-IS=activityType %1 er ekki tegund vöruhúsaaðgerðar.';
        TypeNextStepLbl: Label 'Send Put-away, Pick, Movement, Invt. Put-away, Invt. Pick or Invt. Movement.', Comment = 'is-IS=Sendu Put-away, Pick, Movement, Invt. Put-away, Invt. Pick eða Invt. Movement.';
        FormatLbl: Label 'systemId is not a GUID.', Comment = 'is-IS=systemId er ekki GUID.';
        FormatNextStepLbl: Label 'Send the SystemId as a GUID.', Comment = 'is-IS=Sendu SystemId sem GUID.';
        NotFoundLbl: Label 'Warehouse activity %1 was not found.', Comment = '%1 = identifier, is-IS=Vöruhúsaaðgerð %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the activity with Warehouse.Activity.Get.', Comment = 'is-IS=Athugaðu aðgerðina með Warehouse.Activity.Get.';
        AmbiguousLbl: Label 'Activity number %1 exists for more than one activity type.', Comment = '%1 = activity no., is-IS=Aðgerðarnúmer %1 er til fyrir fleiri en eina tegund aðgerðar.';
        AmbiguousNextStepLbl: Label 'Send activityType with activityNo.', Comment = 'is-IS=Sendu activityType með activityNo.';
        ConflictLbl: Label 'The activity identifiers name different activities.', Comment = 'is-IS=Auðkenni aðgerðarinnar nefna mismunandi aðgerðir.';
        ConflictNextStepLbl: Label 'Use the activity no. answered by Warehouse.Activity.Get.', Comment = 'is-IS=Notaðu aðgerðarnúmerið sem Warehouse.Activity.Get skilaði.';
    begin
        Clear(ActivityHeader);
        Context.ReadText(RequestJson, 'activityType', 30, Argument, TypeText, TypePresent, 'activityType');
        Context.ReadText(RequestJson, 'activityNo', MaxStrLen(ActivityHeader."No."), Argument, NumberText, NumberPresent, 'activityNo');
        Context.ReadText(RequestJson, 'systemId', 50, Argument, SystemIdText, SystemPresent, 'systemId');
        if Argument.HasCollectedErrors() then
            exit(false);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if SubjectText <> '' then
            if Values.IsGuid(SubjectText) then begin
                if SystemPresent and (UpperCase(DelChr(SubjectText, '=', '{}')) <> UpperCase(DelChr(SystemIdText, '=', '{}'))) then begin
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'systemId', SystemIdText, SubjectText, ConflictNextStepLbl);
                    exit(false);
                end;
                SystemIdText := SubjectText;
                SystemPresent := true;
            end else begin
                if NumberPresent and (UpperCase(SubjectText) <> UpperCase(NumberText)) then begin
                    Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'activityNo', NumberText, SubjectText, ConflictNextStepLbl);
                    exit(false);
                end;
                NumberText := SubjectText;
                NumberPresent := StrLen(NumberText) <= MaxStrLen(ActivityHeader."No.");
            end;
        if TypePresent then
            if not TryParseActivityType(TypeText, ActivityType) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TypeLbl, TypeText), 'activityType', TypeText, '', TypeNextStepLbl);
                exit(false);
            end;
        if not NumberPresent and not SystemPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'activityNo', '', '', MissingNextStepLbl);
            exit(false);
        end;
        if SystemPresent then begin
            if not Evaluate(ParsedId, SystemIdText) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'systemId', SystemIdText, 'guid', FormatNextStepLbl);
                exit(false);
            end;
            if not BySystemId.GetBySystemId(ParsedId) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, SystemIdText), 'systemId', SystemIdText, '', NotFoundNextStepLbl);
                exit(false);
            end;
            if TypePresent and (BySystemId.Type <> ActivityType) then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'activityType', TypeText, ActivityTypeName(BySystemId.Type), ConflictNextStepLbl);
                exit(false);
            end;
            ActivityHeader := BySystemId;
        end;
        if NumberPresent then begin
            ByNumber.SetRange("No.", CopyStr(NumberText, 1, MaxStrLen(ByNumber."No.")));
            if TypePresent then
                ByNumber.SetRange(Type, ActivityType);
            if SystemPresent then
                ByNumber.SetRange(Type, BySystemId.Type);
            if not ByNumber.FindFirst() then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, NumberText), 'activityNo', NumberText, '', NotFoundNextStepLbl);
                exit(false);
            end;
            if ByNumber.Count() > 1 then begin
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(AmbiguousLbl, NumberText), 'activityType', '', '', AmbiguousNextStepLbl);
                exit(false);
            end;
            if SystemPresent and (ByNumber.SystemId <> BySystemId.SystemId) then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'activityNo', NumberText, SystemIdText, ConflictNextStepLbl);
                exit(false);
            end;
            ActivityHeader := ByNumber;
        end;
        exit(true);
    end;

    /// <summary>
    /// Resolves one line of the activity from lineNo or lineSystemId in a request object or line object.
    /// A line of another activity answers ConflictingIdentifiers. Collects the errors on Argument.
    /// </summary>
    /// <param name="SourceJson">The request or one line object of it.</param>
    /// <param name="Argument">Collects the errors.</param>
    /// <param name="ActivityHeader">The resolved activity.</param>
    /// <param name="ArrayName">Array name for parameter paths, or empty.</param>
    /// <param name="Index">Line index, or -1.</param>
    /// <param name="ActivityLine">Receives the line.</param>
    /// <returns>True when the line was found in the activity.</returns>
    internal procedure ResolveLine(SourceJson: JsonObject; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; ArrayName: Text; Index: Integer; var ActivityLine: Record "Warehouse Activity Line"): Boolean
    var
        BySystemId: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        LineNo: Integer;
        LineSystemIdText: Text;
        LinePresent: Boolean;
        SystemPresent: Boolean;
        ParsedId: Guid;
        ErrorCount: Integer;
        MissingLbl: Label 'lineNo or lineSystemId is required.', Comment = 'is-IS=lineNo eða lineSystemId er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send the line number of the activity line.', Comment = 'is-IS=Sendu línunúmer aðgerðarlínunnar.';
        FormatLbl: Label 'lineSystemId is not a GUID.', Comment = 'is-IS=lineSystemId er ekki GUID.';
        FormatNextStepLbl: Label 'Send the SystemId as a GUID.', Comment = 'is-IS=Sendu SystemId sem GUID.';
        NotFoundLbl: Label 'Line %1 was not found in warehouse activity %2.', Comment = '%1 = line, %2 = activity no., is-IS=Lína %1 fannst ekki í vöruhúsaaðgerð %2.';
        NotFoundNextStepLbl: Label 'Read the lines with Warehouse.Activity.Get.', Comment = 'is-IS=Lestu línurnar með Warehouse.Activity.Get.';
        OtherActivityLbl: Label 'Line %1 belongs to warehouse activity %2, not to %3.', Comment = '%1 = line, %2 = owning activity, %3 = named activity, is-IS=Lína %1 tilheyrir vöruhúsaaðgerð %2, ekki %3.';
        ConflictNextStepLbl: Label 'Use the activity no. answered by Warehouse.Activity.Get.', Comment = 'is-IS=Notaðu aðgerðarnúmerið sem Warehouse.Activity.Get skilaði.';
    begin
        Clear(ActivityLine);
        ErrorCount := Argument.GetCollectedErrorsJson().Count();
        Context.ReadInteger(SourceJson, 'lineNo', Argument, LineNo, LinePresent, Values.LineParameter(ArrayName, Index, 'lineNo'));
        Context.ReadText(SourceJson, 'lineSystemId', 50, Argument, LineSystemIdText, SystemPresent, Values.LineParameter(ArrayName, Index, 'lineSystemId'));
        if Argument.GetCollectedErrorsJson().Count() <> ErrorCount then
            exit(false);
        if not LinePresent and not SystemPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, Values.LineParameter(ArrayName, Index, 'lineNo'), '', '', MissingNextStepLbl);
            exit(false);
        end;
        if SystemPresent then begin
            if not Evaluate(ParsedId, LineSystemIdText) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, Values.LineParameter(ArrayName, Index, 'lineSystemId'), LineSystemIdText, 'guid', FormatNextStepLbl);
                exit(false);
            end;
            if not BySystemId.GetBySystemId(ParsedId) then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LineSystemIdText, ActivityHeader."No."), Values.LineParameter(ArrayName, Index, 'lineSystemId'), LineSystemIdText, '', NotFoundNextStepLbl);
                exit(false);
            end;
            if (BySystemId."Activity Type" <> ActivityHeader.Type) or (BySystemId."No." <> ActivityHeader."No.") or (LinePresent and (BySystemId."Line No." <> LineNo)) then begin
                Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(OtherActivityLbl, BySystemId."Line No.", BySystemId."No.", ActivityHeader."No."), Values.LineParameter(ArrayName, Index, 'lineSystemId'), LineSystemIdText, ActivityHeader."No.", ConflictNextStepLbl);
                exit(false);
            end;
            ActivityLine := BySystemId;
            exit(true);
        end;
        if ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", LineNo) then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LineNo, ActivityHeader."No."), Values.LineParameter(ArrayName, Index, 'lineNo'), Format(LineNo, 0, 9), '', NotFoundNextStepLbl);
        exit(false);
    end;

    /// <summary>Writes one activity line as JSON.</summary>
    /// <param name="ActivityLine">The line.</param>
    /// <returns>The line object.</returns>
    internal procedure LineJson(ActivityLine: Record "Warehouse Activity Line"): JsonObject
    var
        Values: Codeunit "Whse Msg Values ori";
        LineObject: JsonObject;
    begin
        LineObject.Add('lineNo', ActivityLine."Line No.");
        LineObject.Add('systemId', Format(ActivityLine.SystemId, 0, 4));
        LineObject.Add('actionType', Enum::"Warehouse Action Type".Names().Get(Enum::"Warehouse Action Type".Ordinals().IndexOf(ActivityLine."Action Type".AsInteger())));
        LineObject.Add('itemNo', ActivityLine."Item No.");
        LineObject.Add('variantCode', ActivityLine."Variant Code");
        LineObject.Add('unitOfMeasureCode', ActivityLine."Unit of Measure Code");
        LineObject.Add('zoneCode', ActivityLine."Zone Code");
        LineObject.Add('binCode', ActivityLine."Bin Code");
        LineObject.Add('quantity', ActivityLine.Quantity);
        LineObject.Add('qtyOutstanding', ActivityLine."Qty. Outstanding");
        LineObject.Add('qtyToHandle', ActivityLine."Qty. to Handle");
        LineObject.Add('qtyHandled', ActivityLine."Qty. Handled");
        LineObject.Add('lotNo', ActivityLine."Lot No.");
        LineObject.Add('serialNo', ActivityLine."Serial No.");
        LineObject.Add('packageNo', ActivityLine."Package No.");
        LineObject.Add('expirationDate', Values.DateText(ActivityLine."Expiration Date"));
        exit(LineObject);
    end;

    /// <summary>Writes every line of the activity as JSON.</summary>
    /// <param name="ActivityHeader">The activity.</param>
    /// <returns>The lines.</returns>
    internal procedure LinesJson(ActivityHeader: Record "Warehouse Activity Header"): JsonArray
    var
        ActivityLine: Record "Warehouse Activity Line";
        Lines: JsonArray;
    begin
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if ActivityLine.FindSet() then
            repeat
                Lines.Add(LineJson(ActivityLine));
            until ActivityLine.Next() = 0;
        exit(Lines);
    end;

    /// <summary>Returns the English name of an activity type, as Warehouse.Activity.Get answers it.</summary>
    /// <param name="ActivityType">The type.</param>
    /// <returns>The enum name.</returns>
    internal procedure ActivityTypeName(ActivityType: Enum "Warehouse Activity Type"): Text
    begin
        exit(Enum::"Warehouse Activity Type".Names().Get(Enum::"Warehouse Activity Type".Ordinals().IndexOf(ActivityType.AsInteger())));
    end;

    /// <summary>Returns true when the line takes stock out of its bin.</summary>
    /// <param name="ActivityLine">The line.</param>
    /// <returns>True for a Take line or an inventory pick line.</returns>
    internal procedure IsTake(ActivityLine: Record "Warehouse Activity Line"): Boolean
    begin
        if ActivityLine."Action Type" = ActivityLine."Action Type"::Take then
            exit(true);
        exit((ActivityLine."Action Type" = ActivityLine."Action Type"::" ") and (ActivityLine."Activity Type" = ActivityLine."Activity Type"::"Invt. Pick"));
    end;

    /// <summary>Adds the response field list of an activity line.</summary>
    /// <param name="ContractMgt">Contract builder.</param>
    /// <param name="Name">Field name.</param>
    /// <param name="JsonType">object or array.</param>
    /// <param name="Description">Field description.</param>
    /// <returns>The response field with children.</returns>
    internal procedure LineField(ContractMgt: Codeunit "Msg Contract Mgt ori"; Name: Text; JsonType: Text; Description: Text): JsonObject
    var
        LineFields: JsonArray;
        Field: JsonObject;
    begin
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Activity line number.'));
        LineFields.Add(ContractMgt.ResponseField('systemId', 'string', 'SystemId of the line.'));
        LineFields.Add(ContractMgt.ResponseField('actionType', 'string', 'Take, Place or blank.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('zoneCode', 'string', 'Zone.'));
        LineFields.Add(ContractMgt.ResponseField('binCode', 'string', 'Bin.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity of the line.'));
        LineFields.Add(ContractMgt.ResponseField('qtyOutstanding', 'number', 'Outstanding quantity.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle.'));
        LineFields.Add(ContractMgt.ResponseField('lotNo', 'string', 'Lot number.'));
        LineFields.Add(ContractMgt.ResponseField('serialNo', 'string', 'Serial number.'));
        LineFields.Add(ContractMgt.ResponseField('packageNo', 'string', 'Package number.'));
        LineFields.Add(ContractMgt.ResponseField('expirationDate', 'string', 'Expiration date, YYYY-MM-DD.'));
        Field.Add('name', Name);
        Field.Add('type', JsonType);
        Field.Add('description', Description);
        Field.Add('children', LineFields);
        exit(Field);
    end;

    /// <summary>Adds the activity identifier parameters.</summary>
    /// <param name="Parameters">The parameters chapter.</param>
    internal procedure AddActivityParameters(var Parameters: JsonArray)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('activityType', 'string', false, 'Put-away, Pick, Movement, Invt. Put-away, Invt. Pick or Invt. Movement. Needed with activityNo when the number exists for more than one type.'));
        Parameters.Add(ContractMgt.Parameter('activityNo', 'string', false, 'Activity number. Required when subject and systemId are empty.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'SystemId of the warehouse activity header.'));
    end;

    /// <summary>Adds the activity identifier target entries.</summary>
    /// <param name="Target">The target chapter.</param>
    internal procedure AddActivityTarget(var Target: JsonArray)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'activity no. or SystemId', 'The warehouse activity.'));
        Target.Add(ContractMgt.TargetEntry('data.activityType + data.activityNo', 'activity type and no.', 'The warehouse activity.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId', 'guid', 'SystemId of the warehouse activity header.'));
    end;

    /// <summary>Adds the errors every activity line type answers.</summary>
    /// <param name="Errors">The errors chapter.</param>
    internal procedure AddActivityErrors(var Errors: JsonArray)
    var
        Values: Codeunit "Whse Msg Values ori";
    begin
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MissingParameter, 'activityNo and systemId are both missing, activityType is needed for a number used by several types, or a line misses lineNo.', 'Send the activity and the line number.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type, is too long, or a SystemId is not a GUID.', 'Send text for codes and GUIDs, an integer lineNo and numbers for quantities.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::RecordNotFound, 'The activity or a line was not found.', 'Check the activity with Warehouse.Activity.Get.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::ConflictingIdentifiers, 'The identifiers name different activities, or a line belongs to a different activity than the one named.', 'Use the activity no. answered by Warehouse.Activity.Get.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::UnknownParameter, 'The request or a line contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write warehouse activity lines.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the change.', 'Read the returned text and correct the line. Nothing was written.');
    end;

    /// <summary>Returns whether the caller can write warehouse activity lines.</summary>
    /// <returns>True when the caller can write the activity tables.</returns>
    internal procedure HasWritePermission(): Boolean
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
    begin
        exit(ActivityHeader.WritePermission() and ActivityLine.WritePermission());
    end;

    /// <summary>The activity line flow: read, set quantities, split, change bins, assign tracking, register.</summary>
    /// <param name="Workflow">Receives the workflow chapter.</param>
    internal procedure ActivityLineWorkflow(var Workflow: JsonObject)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Steps: JsonArray;
    begin
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Activity.Get', 'Read the activity with its lines.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.ActivityLine.SetQtyToHandle', 'Set the quantity to handle per line.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.ActivityLine.Split', 'Split a line; the new line takes the rest.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.ActivityLine.ChangeBin', 'Give a line another bin.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.ActivityLine.AssignTracking', 'Assign lot, serial or package numbers.'));
        Steps.Add(ContractMgt.WorkflowStep('Warehouse.Pick.Register', 'Register the activity; Warehouse.Putaway.Register and Warehouse.Movement.Register for the other types.'));
        Workflow.Add('steps', Steps);
    end;

    local procedure TryParseActivityType(Value: Text; var ActivityType: Enum "Warehouse Activity Type"): Boolean
    var
        Names: List of [Text];
        Index: Integer;
    begin
        Names := Enum::"Warehouse Activity Type".Names();
        for Index := 1 to Names.Count() do
            if (Names.Get(Index) <> ' ') and (LowerCase(Names.Get(Index)) = LowerCase(Value)) then begin
                ActivityType := Enum::"Warehouse Activity Type".FromInteger(Enum::"Warehouse Activity Type".Ordinals().Get(Index));
                exit(true);
            end;
        exit(false);
    end;
}
