namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Tracking;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.ActivityLine.AssignTracking (#57).
/// Validates Lot No., Serial No., Package No. and Expiration Date on warehouse activity lines. A line with several
/// entries is split per entry through SplitLine, as a warehouse worker splits the line on the page.
/// </summary>
codeunit 10078465 "Whse ActLine Track Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Write Context ori";
        Values: Codeunit "Whse Msg Values ori";
        Payload: JsonObject;
        Group: JsonObject;
        Token: JsonToken;
        ActivityType: Enum "Warehouse Activity Type";
        ActivityNo: Code[20];
        MissingPayloadErr: Label 'The activity line payload was empty.', Comment = 'is-IS=Gögn aðgerðarlínunnar voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        ActivityType := Enum::"Warehouse Activity Type".FromInteger(Values.IntegerValue(Payload, 'activityTypeOrdinal'));
        ActivityNo := CopyStr(Values.TextValue(Payload, 'activityNo'), 1, MaxStrLen(ActivityNo));
        foreach Token in Values.ArrayValue(Payload, 'groups') do begin
            Group := Token.AsObject();
            AssignLine(ActivityType, ActivityNo, Values.IntegerValue(Group, 'lineNo'), Values.ArrayValue(Group, 'entries'));
        end;
    end;

    /// <summary>Returns whether the caller can write warehouse activity lines.</summary>
    /// <returns>True when the caller can assign item tracking on activity lines.</returns>
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

    /// <summary>Returns a short description of Warehouse.ActivityLine.AssignTracking.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Assigns lot, serial and package numbers on warehouse activity lines, splitting a line per entry.', Comment = 'is-IS=Úthlutar lotu-, rað- og pakkanúmerum á línur vöruhúsaaðgerðar og skiptir línu eftir færslum.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'assign lot, assign serial number, item tracking on pick, lot number, serial number, package number, expiration date', Comment = 'is-IS=úthluta lotu, úthluta raðnúmeri, vörurakning í tínslu, lotunúmer, raðnúmer, pakkanúmer, fyrningardagsetning';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Writes lot, serial and package numbers through Validate on warehouse activity lines of an item with warehouse item tracking. Several entries for one line split it, one line per entry. A Take line needs the lot or serial number in its bin. It registers nothing.', Comment = 'is-IS=Skrifar lotu-, rað- og pakkanúmer með Validate á línur vöruhúsaaðgerðar fyrir vöru með vörurakningu í vöruhúsi. Margar færslur fyrir eina línu skipta henni, ein lína fyrir hverja færslu. Taka-lína þarf lotuna eða raðnúmerið í hólfinu sínu. Hún skráir ekkert.';
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
        Parameters.Add(ContractMgt.Parameter('entries', 'array', true, 'Tracking entries, in order. Several entries for one line split the line, one line per entry.'));
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', false, 'Line number on an entry. Required when lineSystemId is empty.'));
        Parameters.Add(ContractMgt.Parameter('lineSystemId', 'string', false, 'SystemId of the activity line on an entry.'));
        Parameters.Add(ContractMgt.Parameter('lotNo', 'string', false, 'Lot number on an entry.'));
        Parameters.Add(ContractMgt.Parameter('serialNo', 'string', false, 'Serial number on an entry; its quantity must be one base unit.'));
        Parameters.Add(ContractMgt.Parameter('packageNo', 'string', false, 'Package number on an entry.'));
        Parameters.Add(ContractMgt.Parameter('quantity', 'number', false, 'Quantity of the entry in the line unit of measure. Optional when the line has one entry: the outstanding quantity.'));
        Parameters.Add(ContractMgt.Parameter('expirationDate', 'string', false, 'Expiration date of a new lot or serial number on a put-away, written as YYYY-MM-DD.'));
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
        Fields.Add(ContractMgt.ResponseField('changed', 'boolean', 'False when every line already carried the sent numbers for its whole outstanding quantity.'));
        Fields.Add(Helper.LineField(ContractMgt, 'lines', 'array', 'Every line of the activity after the change, including the lines the split created.'));
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
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidLine, 'A serial number entry has a quantity other than one base unit.', 'One entry per serial no.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidLine, 'The lot, serial or package number is not available in the bin of a Take line.', 'Read Inventory.TrackingAvailability.Get for the item.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::PreconditionFailed, 'The item of the line has no item tracking code that requires warehouse tracking.', 'No tracking is needed on this line.');
        Values.AddDeclaredError(Errors, "Bifrost Error Code ori"::InvalidParameter, 'activityType is not valid, an entry has no tracking number, a quantity is zero or negative, the entries of a line exceed its outstanding quantity, or a line with several entries misses a quantity.', 'Send a lot, serial or package number and a positive quantity on every entry, at most the outstanding quantity per line.');
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
        Parts.WriteEffect(Effect, 'Writes lot, serial and package numbers and expiration dates on activity lines and splits a line per entry. Nothing is registered.', 'BIFROST Whse - Full ori', false);
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
        Related.Add(ContractMgt.RelatedEntry('Inventory.TrackingAvailability.Get', 'Use it to find the lots and serial numbers available for the item.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.ActivityLine.Split', 'Use it to split a line without assigning tracking.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Pick.Register', 'Use it, or Warehouse.Putaway.Register or Warehouse.Movement.Register, to register the activity.'));
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
            'Put away 5 units as two lots',
            '{"activityType":"Put-away","activityNo":"PU000004","entries":[{"lineNo":20000,"lotNo":"LOT-A","quantity":3},{"lineNo":20000,"lotNo":"LOT-B","quantity":2}]}',
            '{"status":"Success","activityType":"Put-away","activityNo":"PU000004","changed":true,"lines":[{"lineNo":20000,"actionType":"Place","quantity":3,"lotNo":"LOT-A"},{"lineNo":30000,"actionType":"Place","quantity":2,"lotNo":"LOT-B"}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Assigns lot, serial and package numbers on warehouse activity lines through Validate. Several entries for one line split it, one line per entry. Sending the lot a line already has answers success with changed false.', Comment = 'is-IS=Úthlutar lotu-, rað- og pakkanúmerum á línur vöruhúsaaðgerðar með Validate. Margar færslur fyrir eina línu skipta henni, ein lína fyrir hverja færslu. Ef send er lotan sem línan hefur þegar er svarað með árangri og changed false.';
    begin
        Overview := OverviewLbl;
        exit(true);
    end;

    /// <summary>Returns the notes chapter.</summary>
    /// <param name="Notes">Receives the notes.</param>
    /// <returns>True when notes are declared.</returns>
    procedure GetNotes(var Notes: Text): Boolean
    begin
        Notes := 'Only the named lines change. On a directed pick or movement send entries for the Take line and for its Place line; the numbers are not copied to the paired line. A split Take line keeps its bin on the new line.';
        exit(true);
    end;

    /// <summary>Returns the inbound direction of this message type.</summary>
    /// <returns>Inbound.</returns>
    procedure GetMessageDirection(): Enum "Msg Direction ori"
    begin
        exit(Enum::"Msg Direction ori"::Inbound);
    end;

    /// <summary>Validates the activity, the lines and the entries and assigns the tracking, or writes nothing.</summary>
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
        Entries: JsonArray;
        Groups: JsonArray;
        AllowedKeys: List of [Text];
        EntriesPresent: Boolean;
        Changed: Boolean;
        DeniedLbl: Label 'You do not have permission to change warehouse activity lines.', Comment = 'is-IS=Þú hefur ekki heimild til að breyta línum vöruhúsaaðgerða.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
        MissingLbl: Label 'entries is required and must hold at least one entry.', Comment = 'is-IS=entries er nauðsynlegt og verður að innihalda að minnsta kosti eina færslu.';
        MissingNextStepLbl: Label 'Send at least one entry with lineNo and a lot, serial or package number.', Comment = 'is-IS=Sendu að minnsta kosti eina færslu með lineNo og lotu-, rað- eða pakkanúmeri.';
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
        AllowedKeys.Add('entries');
        Values.RefuseUnknownKeys(RequestJson, AllowedKeys, Argument, '', -1);
        if Values.ReadArray(RequestJson, 'entries', Argument, Entries, EntriesPresent) then
            if (not EntriesPresent) or (Entries.Count() = 0) then
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'entries', '', '', MissingNextStepLbl);
        if not Argument.HasCollectedErrors() then
            if Helper.ResolveActivity(RequestJson, Argument, ActivityHeader) then
                ReadEntries(Entries, Argument, ActivityHeader, Groups, Changed);
        if Argument.HasCollectedErrors() then begin
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if Changed then begin
            Payload.Add('activityTypeOrdinal', ActivityHeader.Type.AsInteger());
            Payload.Add('activityNo', ActivityHeader."No.");
            Payload.Add('groups', Groups);
            Context.SetPayload(Payload);
            // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
            if Argument."Omit Commit" then
                Codeunit.Run(Codeunit::"Whse ActLine Track Impl ori")
            else
                if not Codeunit.Run(Codeunit::"Whse ActLine Track Impl ori") then begin
                    Context.Reset();
                    Argument.RespondWithLastError();
                    exit;
                end;
        end;
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('activityType', Helper.ActivityTypeName(ActivityHeader.Type));
        ResponseJson.Add('activityNo', ActivityHeader."No.");
        ResponseJson.Add('changed', Changed);
        ResponseJson.Add('lines', Helper.LinesJson(ActivityHeader));
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
        Context.Reset();
    end;

    local procedure ReadEntries(Entries: JsonArray; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; var Groups: JsonArray; var Changed: Boolean)
    var
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        Helper: Codeunit "Whse ActLine Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        EntryObject: JsonObject;
        Planned: JsonObject;
        AllowedKeys: List of [Text];
        LineOrder: List of [Integer];
        LineEntries: Dictionary of [Integer, Text];
        LineIndexes: Dictionary of [Integer, Integer];
        Index: Integer;
        ErrorCount: Integer;
        LotText: Text;
        SerialText: Text;
        PackageText: Text;
        EntriesText: Text;
        Quantity: Decimal;
        ExpirationDate: Date;
        Present: Boolean;
        QuantityPresent: Boolean;
        NoNumberLbl: Label 'Entry %1 has no lot, serial or package number.', Comment = '%1 = entry index, is-IS=Færsla %1 hefur ekkert lotu-, rað- eða pakkanúmer.';
        NoNumberNextStepLbl: Label 'Send lotNo, serialNo or packageNo on every entry.', Comment = 'is-IS=Sendu lotNo, serialNo eða packageNo á hverri færslu.';
        QuantityLbl: Label 'quantity on entry %1 must be above zero.', Comment = '%1 = entry index, is-IS=quantity á færslu %1 verður að vera stærra en núll.';
        QuantityNextStepLbl: Label 'Send a positive quantity.', Comment = 'is-IS=Sendu jákvætt magn.';
    begin
        AllowedKeys.Add('lineNo');
        AllowedKeys.Add('lineSystemId');
        AllowedKeys.Add('lotNo');
        AllowedKeys.Add('serialNo');
        AllowedKeys.Add('packageNo');
        AllowedKeys.Add('quantity');
        AllowedKeys.Add('expirationDate');
        for Index := 0 to Entries.Count() - 1 do
            if Values.TryGetLineObject(Entries, Index, 'entries', Argument, EntryObject) then begin
                ErrorCount := Argument.GetCollectedErrorsJson().Count();
                Values.RefuseUnknownKeys(EntryObject, AllowedKeys, Argument, 'entries', Index);
                Context.ReadText(EntryObject, 'lotNo', 50, Argument, LotText, Present, Values.LineParameter('entries', Index, 'lotNo'));
                Context.ReadText(EntryObject, 'serialNo', 50, Argument, SerialText, Present, Values.LineParameter('entries', Index, 'serialNo'));
                Context.ReadText(EntryObject, 'packageNo', 50, Argument, PackageText, Present, Values.LineParameter('entries', Index, 'packageNo'));
                Context.ReadDecimal(EntryObject, 'quantity', Argument, Quantity, QuantityPresent, Values.LineParameter('entries', Index, 'quantity'));
                Values.ReadDate(EntryObject, 'expirationDate', Argument, ExpirationDate, Present, Values.LineParameter('entries', Index, 'expirationDate'));
                if Argument.GetCollectedErrorsJson().Count() = ErrorCount then
                    if Helper.ResolveLine(EntryObject, Argument, ActivityHeader, 'entries', Index, ActivityLine) then
                        if (LotText = '') and (SerialText = '') and (PackageText = '') then
                            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(NoNumberLbl, Index), Values.LineParameter('entries', Index, 'lotNo'), '', '', NoNumberNextStepLbl)
                        else
                            if QuantityPresent and (Quantity <= 0) then
                                Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(QuantityLbl, Index), Values.LineParameter('entries', Index, 'quantity'), Format(Quantity, 0, 9), '', QuantityNextStepLbl)
                            else begin
                                Clear(Planned);
                                Planned.Add('index', Index);
                                Planned.Add('lotNo', LotText);
                                Planned.Add('serialNo', SerialText);
                                Planned.Add('packageNo', PackageText);
                                if QuantityPresent then
                                    Planned.Add('quantity', Quantity);
                                Planned.Add('expirationDate', Values.DateText(ExpirationDate));
                                AddToGroup(ActivityLine."Line No.", Index, Planned, LineOrder, LineEntries, LineIndexes);
                            end;
            end;
        if Argument.HasCollectedErrors() then
            exit;
        foreach Index in LineOrder do begin
            LineEntries.Get(Index, EntriesText);
            ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", Index);
            CheckGroup(Argument, ActivityLine, LineIndexes.Get(Index), EntriesText, Groups, Changed);
        end;
    end;

    local procedure AddToGroup(LineNo: Integer; Index: Integer; Planned: JsonObject; var LineOrder: List of [Integer]; var LineEntries: Dictionary of [Integer, Text]; var LineIndexes: Dictionary of [Integer, Integer])
    var
        Group: JsonArray;
        GroupText: Text;
    begin
        if LineEntries.ContainsKey(LineNo) then begin
            Group.ReadFrom(LineEntries.Get(LineNo));
            Group.Add(Planned);
            Group.WriteTo(GroupText);
            LineEntries.Set(LineNo, GroupText);
            exit;
        end;
        LineOrder.Add(LineNo);
        Group.Add(Planned);
        Group.WriteTo(GroupText);
        LineEntries.Add(LineNo, GroupText);
        LineIndexes.Add(LineNo, Index);
    end;

    local procedure CheckGroup(var Argument: Record "Message Argument ori"; ActivityLine: Record "Warehouse Activity Line"; FirstIndex: Integer; EntriesText: Text; var Groups: JsonArray; var Changed: Boolean)
    var
        TempWhseItemTrackingSetup: Record "Item Tracking Setup" temporary;
        ItemTrackingMgt: Codeunit "Item Tracking Management";
        Helper: Codeunit "Whse ActLine Helper ori";
        Values: Codeunit "Whse Msg Values ori";
        Group: JsonObject;
        Entry: JsonObject;
        Token: JsonToken;
        Entries: JsonArray;
        Normalized: JsonArray;
        Taken: Dictionary of [Text, Decimal];
        Quantity: Decimal;
        Total: Decimal;
        EntryIndex: Integer;
        NoTrackingLbl: Label 'Item %1 on line %2 has no item tracking code that requires warehouse tracking.', Comment = '%1 = item, %2 = line no., is-IS=Vara %1 á línu %2 hefur engan vörurakningarkóða sem krefst rakningar í vöruhúsi.';
        NoTrackingNextStepLbl: Label 'No tracking is needed on this line.', Comment = 'is-IS=Engin rakning er nauðsynleg á þessari línu.';
        NeedQuantityLbl: Label 'Line %1 has several entries, so every entry needs a quantity.', Comment = '%1 = line no., is-IS=Lína %1 hefur margar færslur, svo hver færsla þarf magn.';
        NeedQuantityNextStepLbl: Label 'Send quantity on every entry of the line.', Comment = 'is-IS=Sendu quantity á hverja færslu línunnar.';
        TooMuchLbl: Label 'The entries of line %1 hold %2, more than its outstanding quantity %3.', Comment = '%1 = line no., %2 = total, %3 = outstanding, is-IS=Færslur línu %1 eru samtals %2, meira en útistandandi magn hennar %3.';
        TooMuchNextStepLbl: Label 'Send at most the outstanding quantity per line.', Comment = 'is-IS=Sendu mest útistandandi magn fyrir hverja línu.';
        SerialLbl: Label 'Entry %1 gives serial number %2 more than one base unit.', Comment = '%1 = entry index, %2 = serial no., is-IS=Færsla %1 gefur raðnúmeri %2 meira en eina grunneiningu.';
        SerialNextStepLbl: Label 'One entry per serial no.', Comment = 'is-IS=Ein færsla fyrir hvert raðnúmer.';
    begin
        Entries.ReadFrom(EntriesText);
        if not ItemTrackingMgt.GetWhseItemTrkgSetup(ActivityLine."Item No.", TempWhseItemTrackingSetup) then begin
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NoTrackingLbl, ActivityLine."Item No.", ActivityLine."Line No."), Values.LineParameter('entries', FirstIndex, 'lineNo'), Format(ActivityLine."Line No.", 0, 9), '', NoTrackingNextStepLbl);
            exit;
        end;
        foreach Token in Entries do begin
            Entry := Token.AsObject();
            EntryIndex := Values.IntegerValue(Entry, 'index');
            if Entry.Contains('quantity') then
                Quantity := Values.DecimalValue(Entry, 'quantity')
            else
                if Entries.Count() = 1 then
                    Quantity := ActivityLine."Qty. Outstanding"
                else begin
                    Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(NeedQuantityLbl, ActivityLine."Line No."), Values.LineParameter('entries', EntryIndex, 'quantity'), '', '', NeedQuantityNextStepLbl);
                    exit;
                end;
            if (Values.TextValue(Entry, 'serialNo') <> '') and (Quantity * ActivityLine."Qty. per Unit of Measure" <> 1) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(SerialLbl, EntryIndex, Values.TextValue(Entry, 'serialNo')), Values.LineParameter('entries', EntryIndex, 'quantity'), Format(Quantity, 0, 9), '1', SerialNextStepLbl);
                exit;
            end;
            Total += Quantity;
            Entry.Remove('quantity');
            Entry.Add('quantity', Quantity);
            Normalized.Add(Entry);
        end;
        if Total > ActivityLine."Qty. Outstanding" then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TooMuchLbl, ActivityLine."Line No.", Total, ActivityLine."Qty. Outstanding"), Values.LineParameter('entries', FirstIndex, 'quantity'), Format(Total, 0, 9), Format(ActivityLine."Qty. Outstanding", 0, 9), TooMuchNextStepLbl);
            exit;
        end;
        if IsUnchanged(ActivityLine, Normalized) then
            exit;
        if Helper.IsTake(ActivityLine) then
            foreach Token in Normalized do
                if not CheckAvailable(Argument, ActivityLine, Token.AsObject(), Taken) then
                    exit;
        Group.Add('lineNo', ActivityLine."Line No.");
        Group.Add('entries', Normalized);
        Groups.Add(Group);
        Changed := true;
    end;

    local procedure IsUnchanged(ActivityLine: Record "Warehouse Activity Line"; Entries: JsonArray): Boolean
    var
        Values: Codeunit "Whse Msg Values ori";
        Token: JsonToken;
        Entry: JsonObject;
    begin
        if Entries.Count() <> 1 then
            exit(false);
        Entries.Get(0, Token);
        Entry := Token.AsObject();
        if Values.DecimalValue(Entry, 'quantity') <> ActivityLine."Qty. Outstanding" then
            exit(false);
        if Values.DateValue(Entry, 'expirationDate') <> 0D then
            if Values.DateValue(Entry, 'expirationDate') <> ActivityLine."Expiration Date" then
                exit(false);
        exit(
            (UpperCase(Values.TextValue(Entry, 'lotNo')) = UpperCase(ActivityLine."Lot No.")) and
            (UpperCase(Values.TextValue(Entry, 'serialNo')) = UpperCase(ActivityLine."Serial No.")) and
            (UpperCase(Values.TextValue(Entry, 'packageNo')) = UpperCase(ActivityLine."Package No.")));
    end;

    local procedure CheckAvailable(var Argument: Record "Message Argument ori"; ActivityLine: Record "Warehouse Activity Line"; Entry: JsonObject; var Taken: Dictionary of [Text, Decimal]): Boolean
    var
        BinContent: Record "Bin Content";
        Values: Codeunit "Whse Msg Values ori";
        Available: Decimal;
        Requested: Decimal;
        AlreadyTaken: Decimal;
        TakenKey: Text;
        NotAvailableLbl: Label 'Bin %1 holds %2 base units of item %3 with lot %4, serial %5, package %6 that can be taken; entry %7 needs %8.', Comment = '%1 = bin, %2 = available, %3 = item, %4 = lot, %5 = serial, %6 = package, %7 = entry index, %8 = needed, is-IS=Hólf %1 geymir %2 grunneiningar af vöru %3 með lotu %4, raðnúmeri %5, pakka %6 sem má taka; færsla %7 þarf %8.';
        NotAvailableNextStepLbl: Label 'Read Inventory.TrackingAvailability.Get for the item.', Comment = 'is-IS=Lestu Inventory.TrackingAvailability.Get fyrir vöruna.';
    begin
        Requested := Values.DecimalValue(Entry, 'quantity') * ActivityLine."Qty. per Unit of Measure";
        TakenKey := Values.TextValue(Entry, 'lotNo') + '|' + Values.TextValue(Entry, 'serialNo') + '|' + Values.TextValue(Entry, 'packageNo');
        if Taken.ContainsKey(TakenKey) then
            AlreadyTaken := Taken.Get(TakenKey);
        if BinContent.Get(ActivityLine."Location Code", ActivityLine."Bin Code", ActivityLine."Item No.", ActivityLine."Variant Code", ActivityLine."Unit of Measure Code") then begin
            if Values.TextValue(Entry, 'lotNo') <> '' then
                BinContent.SetRange("Lot No. Filter", Values.TextValue(Entry, 'lotNo'));
            if Values.TextValue(Entry, 'serialNo') <> '' then
                BinContent.SetRange("Serial No. Filter", Values.TextValue(Entry, 'serialNo'));
            if Values.TextValue(Entry, 'packageNo') <> '' then
                BinContent.SetRange("Package No. Filter", Values.TextValue(Entry, 'packageNo'));
            Available := BinContent.CalcQtyAvailToTake(0);
        end;
        if Requested + AlreadyTaken > Available then begin
            Argument.AddError(
                "Bifrost Error Code ori"::InvalidLine,
                StrSubstNo(NotAvailableLbl, ActivityLine."Bin Code", Available - AlreadyTaken, ActivityLine."Item No.", Values.TextValue(Entry, 'lotNo'), Values.TextValue(Entry, 'serialNo'), Values.TextValue(Entry, 'packageNo'), Values.IntegerValue(Entry, 'index'), Requested),
                Values.LineParameter('entries', Values.IntegerValue(Entry, 'index'), 'lotNo'), Values.TextValue(Entry, 'lotNo') + Values.TextValue(Entry, 'serialNo') + Values.TextValue(Entry, 'packageNo'), '', NotAvailableNextStepLbl);
            exit(false);
        end;
        if Taken.ContainsKey(TakenKey) then
            Taken.Set(TakenKey, AlreadyTaken + Requested)
        else
            Taken.Add(TakenKey, Requested);
        exit(true);
    end;

    local procedure AssignLine(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; LineNo: Integer; Entries: JsonArray)
    var
        ActivityLine: Record "Warehouse Activity Line";
        NewActivityLine: Record "Warehouse Activity Line";
        Values: Codeunit "Whse Msg Values ori";
        Token: JsonToken;
        Entry: JsonObject;
        Quantity: Decimal;
        ZoneCode: Code[10];
        BinCode: Code[20];
    begin
        ActivityLine.Get(ActivityType, ActivityNo, LineNo);
        ZoneCode := ActivityLine."Zone Code";
        BinCode := ActivityLine."Bin Code";
        foreach Token in Entries do begin
            Entry := Token.AsObject();
            Quantity := Values.DecimalValue(Entry, 'quantity');
            if Quantity < ActivityLine."Qty. Outstanding" then begin
                ActivityLine.Validate("Qty. to Handle", Quantity);
                ActivityLine.Modify(true);
                ActivityLine.SplitLine(ActivityLine, NewActivityLine);
                ActivityLine.Get(ActivityLine."Activity Type", ActivityLine."No.", ActivityLine."Line No.");
                ApplyTracking(ActivityLine, Entry);
                NewActivityLine.Get(NewActivityLine."Activity Type", NewActivityLine."No.", NewActivityLine."Line No.");
                if (NewActivityLine."Bin Code" = '') and (BinCode <> '') then begin
                    NewActivityLine.Validate("Zone Code", ZoneCode);
                    NewActivityLine.Validate("Bin Code", BinCode);
                    NewActivityLine.Modify(true);
                end;
                ActivityLine := NewActivityLine;
            end else
                ApplyTracking(ActivityLine, Entry);
        end;
    end;

    local procedure ApplyTracking(var ActivityLine: Record "Warehouse Activity Line"; Entry: JsonObject)
    var
        Values: Codeunit "Whse Msg Values ori";
    begin
        if Values.TextValue(Entry, 'serialNo') <> '' then
            ActivityLine.Validate("Serial No.", CopyStr(Values.TextValue(Entry, 'serialNo'), 1, MaxStrLen(ActivityLine."Serial No.")));
        if Values.TextValue(Entry, 'lotNo') <> '' then
            ActivityLine.Validate("Lot No.", CopyStr(Values.TextValue(Entry, 'lotNo'), 1, MaxStrLen(ActivityLine."Lot No.")));
        if Values.TextValue(Entry, 'packageNo') <> '' then
            ActivityLine.Validate("Package No.", CopyStr(Values.TextValue(Entry, 'packageNo'), 1, MaxStrLen(ActivityLine."Package No.")));
        if Values.DateValue(Entry, 'expirationDate') <> 0D then
            ActivityLine.Validate("Expiration Date", Values.DateValue(Entry, 'expirationDate'));
        ActivityLine.Modify(true);
    end;
}
