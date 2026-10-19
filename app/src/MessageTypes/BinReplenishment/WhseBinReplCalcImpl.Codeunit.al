namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.BinReplenishment.Calculate.
/// Calculate Bin Replenishment writes movement worksheet lines. It does not create a warehouse movement.
/// </summary>
codeunit 10078429 "Whse Bin Repl Calc Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        BinContent: Record "Bin Content";
        WorksheetLine: Record "Whse. Worksheet Line";
        CalculateReplenishment: Report "Calculate Bin Replenishment";
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        LocationCode: Code[10];
        TemplateName: Code[10];
        WorksheetName: Code[10];
        ZoneCode: Code[10];
        BinCode: Code[20];
        ItemNo: Code[20];
        SnapshotLineNo: Integer;
        MissingPayloadErr: Label 'The bin replenishment payload was empty.', Comment = 'is-IS=Gögnin fyrir endurnýjun hólfa voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        TemplateName := CopyStr(TextValue(Payload, 'worksheetTemplateName'), 1, MaxStrLen(TemplateName));
        WorksheetName := CopyStr(TextValue(Payload, 'worksheetName'), 1, MaxStrLen(WorksheetName));
        ZoneCode := CopyStr(TextValue(Payload, 'zoneCode'), 1, MaxStrLen(ZoneCode));
        BinCode := CopyStr(TextValue(Payload, 'binCode'), 1, MaxStrLen(BinCode));
        ItemNo := CopyStr(TextValue(Payload, 'itemNo'), 1, MaxStrLen(ItemNo));
        SnapshotLineNo := Snapshot(TemplateName, WorksheetName, LocationCode, WorksheetLine);
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange(Fixed, true);
        if ZoneCode <> '' then
            BinContent.SetRange("Zone Code", ZoneCode);
        if BinCode <> '' then
            BinContent.SetRange("Bin Code", BinCode);
        if ItemNo <> '' then
            BinContent.SetRange("Item No.", ItemNo);
        CalculateReplenishment.UseRequestPage(false);
        CalculateReplenishment.InitializeRequest(TemplateName, WorksheetName, LocationCode, BooleanValue(Payload, 'allowBreakbulk'), true, BooleanValue(Payload, 'doNotFillQtyToHandle'));
        CalculateReplenishment.SetTableView(BinContent);
        CalculateReplenishment.Run();
        Context.SetSnapshot(SnapshotLineNo);
    end;

    /// <summary>Returns whether the caller can calculate bin replenishment.</summary>
    /// <returns>True when the caller can write worksheet lines and read the location, bins and worksheet name.</returns>
    procedure IsEnabled(): Boolean
    var
        Location: Record Location;
        Item: Record Item;
        Zone: Record Zone;
        Bin: Record Bin;
        BinContent: Record "Bin Content";
        WorksheetTemplate: Record "Whse. Worksheet Template";
        WorksheetName: Record "Whse. Worksheet Name";
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        exit(WorksheetLine.WritePermission() and Location.ReadPermission() and Item.ReadPermission() and Zone.ReadPermission() and Bin.ReadPermission() and BinContent.ReadPermission() and WorksheetTemplate.ReadPermission() and WorksheetName.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse worksheet line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Whse. Worksheet Line");
    end;

    /// <summary>Returns a short description of Warehouse.BinReplenishment.Calculate.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Calculates bin replenishment into a movement worksheet.', Comment = 'is-IS=Reiknar endurnýjun hólfa inn á færsluvinnublað.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'bin replenishment, movement worksheet, directed put-away and pick, minimum quantity, pick bin', Comment = 'is-IS=endurnýjun hólfa, færsluvinnublað, bein innsetning og tínsla, lágmarksmagn, tínsluhólf';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Calculates replenishment for fixed bins below their minimum at a directed location and writes movement worksheet lines. It does not create the warehouse movement. Nothing to replenish is a success with an empty line list.', Comment = 'is-IS=Reiknar endurnýjun fyrir föst hólf undir lágmarki á beinni staðsetningu og skrifar línur á færsluvinnublað. Hún stofnar ekki vöruhúsafærsluna. Ekkert til að endurnýja er árangur með tóman línulista.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. The directed location. Do not send a different location in subject and locationCode.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The directed location. Optional when locationCode is sent.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode', 'location code', 'The directed location the replenishment belongs to.'));
        Target.Add(ContractMgt.TargetEntry('data.worksheetTemplateName', 'worksheet template name', 'The movement worksheet template.'));
        Target.Add(ContractMgt.TargetEntry('data.worksheetName', 'worksheet name', 'The movement worksheet name at the location.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Directed put-away and pick location. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('worksheetTemplateName', 'string', true, 'Movement worksheet template name.'));
        Parameters.Add(ContractMgt.Parameter('worksheetName', 'string', true, 'Movement worksheet name at the location.'));
        Parameters.Add(ContractMgt.Parameter('zoneCode', 'string', false, 'Limits the calculation to one zone. Optional.'));
        Parameters.Add(ContractMgt.Parameter('binCode', 'string', false, 'Limits the calculation to one bin. Optional.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', false, 'Limits the calculation to one item. Optional.'));
        Parameters.Add(ContractMgt.Parameter('allowBreakbulk', 'boolean', false, 'Replenish from another unit of measure when the original unit is not available. Defaults to false.'));
        Parameters.Add(ContractMgt.Parameter('doNotFillQtyToHandle', 'boolean', false, 'Leave quantity to handle at zero on the new worksheet lines. Defaults to false.'));
        Parameters.Add(ContractMgt.Parameter('autoCreateMovement', 'boolean', false, 'Must be false or omitted. This type only writes worksheet lines. Defaults to false.'));
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
        LineFields: JsonArray;
        Lines: JsonObject;
    begin
        Parts.AddStatusField(Fields);
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        Fields.Add(ContractMgt.ResponseField('worksheetTemplateName', 'string', 'Movement worksheet template name.'));
        Fields.Add(ContractMgt.ResponseField('worksheetName', 'string', 'Movement worksheet name.'));
        Fields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of worksheet lines created by this call. An empty replenishment returns zero.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Worksheet line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('fromBin', 'string', 'Bin the quantity is taken from.'));
        LineFields.Add(ContractMgt.ResponseField('toBin', 'string', 'Bin the quantity is placed in.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity on the worksheet line.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle. Zero when doNotFillQtyToHandle is true.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Worksheet lines created by this call.');
        Lines.Add('children', LineFields);
        Fields.Add(Lines);
        Parts.Response(Response, Fields);
        exit(true);
    end;

    /// <summary>Returns the error chapter.</summary>
    /// <param name="Errors">Receives the errors.</param>
    /// <returns>True when errors are declared.</returns>
    procedure GetErrors(var Errors: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Entry: JsonObject;
    begin
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use directed put-away and pick.', 'Bin replenishment needs a directed location.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The worksheet template or worksheet name was not found.', 'Create the movement worksheet name first.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The location, zone, bin or item was not found.', 'Check the identifier and send the request again.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'locationCode, worksheetTemplateName or worksheetName is missing.', 'Send locationCode, worksheetTemplateName and worksheetName.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes and true or false for options.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'autoCreateMovement is true, or the worksheet template is not a movement template.', 'Leave autoCreateMovement false. Use Warehouse.Movement.Create after the worksheet lines exist.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations, or the bin is not in the named zone.', 'Send one location, and a bin that belongs to the named zone.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot calculate bin replenishment.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was written.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the replenishment.', 'Read the returned text and correct the bins or the worksheet.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Writes movement worksheet lines for fixed bins below their minimum. It does not create a warehouse movement. Nothing to replenish writes no lines.', 'BIFROST Whse - Full ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Movement.Create', 'Use it to create the warehouse movement from the worksheet lines.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read the quantity in a bin before calculating replenishment.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>False. Bin replenishment has no separate workflow chapter.</returns>
    procedure GetWorkflow(var Workflow: JsonObject): Boolean
    begin
        exit(false);
    end;

    /// <summary>Returns an example request and response.</summary>
    /// <param name="Examples">Receives the examples.</param>
    /// <returns>True when an example is declared.</returns>
    procedure GetExamples(var Examples: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Examples.Add(ContractMgt.Example(
            'Replenish one directed location',
            '{"locationCode":"WHITE","worksheetTemplateName":"MOVEMENT","worksheetName":"DEFAULT","autoCreateMovement":false}',
            '{"status":"Success","locationCode":"WHITE","worksheetTemplateName":"MOVEMENT","worksheetName":"DEFAULT","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"WRB-1000","fromBin":"BULK-01","toBin":"PICK-01","quantity":5,"qtyToHandle":5}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Calculates bin replenishment at a directed location and returns the movement worksheet lines created by this call. An empty replenishment is a success. The warehouse movement is a separate step.', Comment = 'is-IS=Reiknar endurnýjun hólfa á beinni staðsetningu og skilar línum færsluvinnublaðsins sem þetta kall stofnaði. Tóm endurnýjun er árangur. Vöruhúsafærslan er sér skref.';
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

    /// <summary>Validates the request and calculates bin replenishment, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        LocationCode: Code[10];
        TemplateName: Code[10];
        WorksheetName: Code[10];
        ZoneCode: Code[10];
        BinCode: Code[20];
        ItemNo: Code[20];
        AllowBreakbulk: Boolean;
        DoNotFillQtyToHandle: Boolean;
        AutoCreateMovement: Boolean;
        DeniedLbl: Label 'You do not have permission to calculate bin replenishment.', Comment = 'is-IS=Þú hefur ekki heimild til að reikna endurnýjun hólfa.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was written.', Comment = 'is-IS=Ekkert var skrifað.';
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
        RefuseUnknownKeys(RequestJson, Argument);
        ReadRequest(RequestJson, Argument, LocationCode, TemplateName, WorksheetName, ZoneCode, BinCode, ItemNo, AllowBreakbulk, DoNotFillQtyToHandle, AutoCreateMovement);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if AutoCreateMovement then begin
            RefuseAutoCreate(Argument);
            exit;
        end;
        if not ResolveLocation(Argument, LocationCode) then
            exit;
        if not EnsureDirected(Argument, LocationCode) then
            exit;
        if not EnsureWorksheet(Argument, TemplateName, WorksheetName, LocationCode) then
            exit;
        if not EnsureFilters(Argument, LocationCode, ZoneCode, BinCode, ItemNo) then
            exit;
        Clear(Payload);
        Payload.Add('locationCode', LocationCode);
        Payload.Add('worksheetTemplateName', TemplateName);
        Payload.Add('worksheetName', WorksheetName);
        Payload.Add('zoneCode', ZoneCode);
        Payload.Add('binCode', BinCode);
        Payload.Add('itemNo', ItemNo);
        Payload.Add('allowBreakbulk', AllowBreakbulk);
        Payload.Add('doNotFillQtyToHandle', DoNotFillQtyToHandle);
        Context.SetPayload(Payload);
        if not Codeunit.Run(Codeunit::"Whse Bin Repl Calc Impl ori") then begin
            Context.Reset();
            Argument.RespondWithLastError();
            exit;
        end;
        WriteCreatedLines(Argument, LocationCode, TemplateName, WorksheetName);
        Context.Reset();
    end;

    local procedure WriteCreatedLines(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; TemplateName: Code[10]; WorksheetName: Code[10])
    var
        Context: Codeunit "Whse Write Context ori";
        ResponseJson: JsonObject;
        Lines: JsonArray;
        SnapshotLineNo: Integer;
        MissingResultErr: Label 'The replenishment finished but the worksheet snapshot was not returned.', Comment = 'is-IS=Endurnýjuninni lauk en skyndimynd vinnublaðsins skilaði sér ekki.';
        MissingResultNextStepLbl: Label 'Read the returned text and correct the bins or the worksheet.', Comment = 'is-IS=Lestu textann sem skilaði sér og leiðréttu hólfin eða vinnublaðið.';
    begin
        if not Context.TryGetSnapshot(SnapshotLineNo) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'lines', '', '', MissingResultNextStepLbl);
            exit;
        end;
        BuildLines(TemplateName, WorksheetName, LocationCode, SnapshotLineNo, Lines);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('locationCode', LocationCode);
        ResponseJson.Add('worksheetTemplateName', TemplateName);
        ResponseJson.Add('worksheetName', WorksheetName);
        ResponseJson.Add('lineCount', Lines.Count());
        ResponseJson.Add('lines', Lines);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure BuildLines(TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]; SnapshotLineNo: Integer; var Lines: JsonArray)
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        LineJson: JsonObject;
    begin
        Clear(Lines);
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, WorksheetName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        WorksheetLine.SetFilter("Line No.", '>%1', SnapshotLineNo);
        if not WorksheetLine.FindSet() then
            exit;
        repeat
            Clear(LineJson);
            LineJson.Add('lineNo', WorksheetLine."Line No.");
            LineJson.Add('itemNo', WorksheetLine."Item No.");
            LineJson.Add('fromBin', WorksheetLine."From Bin Code");
            LineJson.Add('toBin', WorksheetLine."To Bin Code");
            LineJson.Add('quantity', WorksheetLine.Quantity);
            LineJson.Add('qtyToHandle', WorksheetLine."Qty. to Handle");
            Lines.Add(LineJson);
        until WorksheetLine.Next() = 0;
    end;

    local procedure ReadRequest(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10]; var TemplateName: Code[10]; var WorksheetName: Code[10]; var ZoneCode: Code[10]; var BinCode: Code[20]; var ItemNo: Code[20]; var AllowBreakbulk: Boolean; var DoNotFillQtyToHandle: Boolean; var AutoCreateMovement: Boolean)
    var
        Readers: Codeunit "Whse Write Context ori";
        LocationText: Text;
        TemplateText: Text;
        WorksheetText: Text;
        ZoneText: Text;
        BinText: Text;
        ItemText: Text;
        SubjectText: Text;
        LocationPresent: Boolean;
        TemplatePresent: Boolean;
        WorksheetPresent: Boolean;
        ZonePresent: Boolean;
        BinPresent: Boolean;
        ItemPresent: Boolean;
        AllowPresent: Boolean;
        DoNotFillPresent: Boolean;
        AutoPresent: Boolean;
        MissingLbl: Label '%1 is required.', Comment = '%1 = parameter, is-IS=%1 er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode, worksheetTemplateName and worksheetName.', Comment = 'is-IS=Sendu locationCode, worksheetTemplateName og worksheetName.';
    begin
        Clear(LocationCode);
        Clear(TemplateName);
        Clear(WorksheetName);
        Clear(ZoneCode);
        Clear(BinCode);
        Clear(ItemNo);
        AllowBreakbulk := false;
        DoNotFillQtyToHandle := false;
        AutoCreateMovement := false;
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Readers.ReadText(RequestJson, 'locationCode', MaxStrLen(LocationCode), Argument, LocationText, LocationPresent, 'locationCode') then
            exit;
        if not Readers.ReadText(RequestJson, 'worksheetTemplateName', MaxStrLen(TemplateName), Argument, TemplateText, TemplatePresent, 'worksheetTemplateName') then
            exit;
        if not Readers.ReadText(RequestJson, 'worksheetName', MaxStrLen(WorksheetName), Argument, WorksheetText, WorksheetPresent, 'worksheetName') then
            exit;
        if not Readers.ReadText(RequestJson, 'zoneCode', MaxStrLen(ZoneCode), Argument, ZoneText, ZonePresent, 'zoneCode') then
            exit;
        if not Readers.ReadText(RequestJson, 'binCode', MaxStrLen(BinCode), Argument, BinText, BinPresent, 'binCode') then
            exit;
        if not Readers.ReadText(RequestJson, 'itemNo', MaxStrLen(ItemNo), Argument, ItemText, ItemPresent, 'itemNo') then
            exit;
        if not Readers.ReadBoolean(RequestJson, 'allowBreakbulk', Argument, AllowBreakbulk, AllowPresent, 'allowBreakbulk') then
            exit;
        if not Readers.ReadBoolean(RequestJson, 'doNotFillQtyToHandle', Argument, DoNotFillQtyToHandle, DoNotFillPresent, 'doNotFillQtyToHandle') then
            exit;
        if not Readers.ReadBoolean(RequestJson, 'autoCreateMovement', Argument, AutoCreateMovement, AutoPresent, 'autoCreateMovement') then
            exit;
        if not LocationPresent then
            LocationText := SubjectText;
        if LocationText = '' then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'locationCode'), 'locationCode', '', '', MissingNextStepLbl);
        if not TemplatePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'worksheetTemplateName'), 'worksheetTemplateName', '', '', MissingNextStepLbl);
        if not WorksheetPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, 'worksheetName'), 'worksheetName', '', '', MissingNextStepLbl);
        if Argument.HasCollectedErrors() then
            exit;
        LocationCode := CopyStr(LocationText, 1, MaxStrLen(LocationCode));
        TemplateName := CopyStr(TemplateText, 1, MaxStrLen(TemplateName));
        WorksheetName := CopyStr(WorksheetText, 1, MaxStrLen(WorksheetName));
        ZoneCode := CopyStr(ZoneText, 1, MaxStrLen(ZoneCode));
        BinCode := CopyStr(BinText, 1, MaxStrLen(BinCode));
        ItemNo := CopyStr(ItemText, 1, MaxStrLen(ItemNo));
    end;

    local procedure ResolveLocation(var Argument: Record "Message Argument ori"; LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        SubjectText: Text;
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        NotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the identifier and send the request again.', Comment = 'is-IS=Athugaðu auðkennið og sendu beiðnina aftur.';
    begin
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(LocationCode)) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationCode, SubjectText, ConflictNextStepLbl);
            exit(false);
        end;
        Location.SetLoadFields(Code);
        if Location.Get(LocationCode) then
            exit(true);
        Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LocationCode), 'locationCode', LocationCode, '', NotFoundNextStepLbl);
        exit(false);
    end;

    local procedure EnsureDirected(var Argument: Record "Message Argument ori"; LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        DirectedLbl: Label 'Location %1 does not use directed put-away and pick.', Comment = '%1 = location, is-IS=Staðsetning %1 notar ekki beina innsetningu og tínslu.';
        DirectedNextStepLbl: Label 'Bin replenishment needs a directed location.', Comment = 'is-IS=Endurnýjun hólfa þarf beina staðsetningu.';
    begin
        Location.SetLoadFields("Directed Put-away and Pick");
        if not Location.Get(LocationCode) then
            exit(false);
        if Location."Directed Put-away and Pick" then
            exit(true);
        Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(DirectedLbl, LocationCode), 'locationCode', LocationCode, '', DirectedNextStepLbl);
        exit(false);
    end;

    local procedure EnsureWorksheet(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]): Boolean
    var
        WorksheetTemplate: Record "Whse. Worksheet Template";
        NameRecord: Record "Whse. Worksheet Name";
        NotFoundLbl: Label 'Worksheet template %1 or name %2 was not found.', Comment = '%1 = template, %2 = name, is-IS=Vinnublaðssniðmát %1 eða nafn %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Create the movement worksheet name first.', Comment = 'is-IS=Stofnaðu nafn færsluvinnublaðsins fyrst.';
        TypeLbl: Label 'Worksheet template %1 is not a movement template.', Comment = '%1 = template, is-IS=Vinnublaðssniðmát %1 er ekki færslusniðmát.';
        TypeNextStepLbl: Label 'Use a movement worksheet template.', Comment = 'is-IS=Notaðu sniðmát fyrir færsluvinnublað.';
    begin
        WorksheetTemplate.SetLoadFields(Name, Type);
        if not WorksheetTemplate.Get(TemplateName) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, TemplateName, WorksheetName), 'worksheetTemplateName', TemplateName, '', NotFoundNextStepLbl);
            exit(false);
        end;
        if WorksheetTemplate.Type <> WorksheetTemplate.Type::Movement then begin
            Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TypeLbl, TemplateName), 'worksheetTemplateName', TemplateName, 'Movement', TypeNextStepLbl);
            exit(false);
        end;
        NameRecord.SetLoadFields("Worksheet Template Name", Name, "Location Code");
        if NameRecord.Get(TemplateName, WorksheetName, LocationCode) then
            exit(true);
        Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, TemplateName, WorksheetName), 'worksheetName', WorksheetName, '', NotFoundNextStepLbl);
        exit(false);
    end;

    local procedure EnsureFilters(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; ZoneCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]): Boolean
    var
        Zone: Record Zone;
        Bin: Record Bin;
        Item: Record Item;
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table, %2 = value, is-IS=%1 %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the identifier and send the request again.', Comment = 'is-IS=Athugaðu auðkennið og sendu beiðnina aftur.';
        ZoneConflictLbl: Label 'Bin %1 is not in zone %2.', Comment = '%1 = bin, %2 = zone, is-IS=Hólf %1 er ekki á svæði %2.';
        ZoneConflictNextStepLbl: Label 'Send a bin in the named zone, or omit one of them.', Comment = 'is-IS=Sendu hólf á nefndu svæði, eða slepptu öðru hvoru.';
    begin
        if ZoneCode <> '' then begin
            Zone.SetLoadFields("Location Code", Code);
            if not Zone.Get(LocationCode, ZoneCode) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Zone.TableCaption(), ZoneCode), 'zoneCode', ZoneCode, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        if BinCode <> '' then begin
            Bin.SetLoadFields(Code, "Zone Code");
            if not Bin.Get(LocationCode, BinCode) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), BinCode), 'binCode', BinCode, '', NotFoundNextStepLbl);
                exit(false);
            end;
            if (ZoneCode <> '') and (UpperCase(Bin."Zone Code") <> UpperCase(ZoneCode)) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::ConflictingIdentifiers, StrSubstNo(ZoneConflictLbl, BinCode, ZoneCode), 'binCode', BinCode, ZoneCode, ZoneConflictNextStepLbl);
                exit(false);
            end;
        end;
        if ItemNo <> '' then begin
            Item.SetLoadFields("No.");
            if not Item.Get(ItemNo) then begin
                Argument.RespondWithError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemNo), 'itemNo', ItemNo, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        exit(true);
    end;

    local procedure RefuseAutoCreate(var Argument: Record "Message Argument ori")
    var
        AutoLbl: Label 'autoCreateMovement must be false. This type only writes worksheet lines.', Comment = 'is-IS=autoCreateMovement verður að vera false. Þessi gerð skrifar aðeins línur á vinnublað.';
        AutoNextStepLbl: Label 'Use Warehouse.Movement.Create after the worksheet lines exist.', Comment = 'is-IS=Notaðu Warehouse.Movement.Create eftir að línur vinnublaðsins eru til.';
    begin
        Argument.RespondWithError("Bifrost Error Code ori"::InvalidParameter, AutoLbl, 'autoCreateMovement', 'true', 'false', AutoNextStepLbl);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['locationCode', 'worksheetTemplateName', 'worksheetName', 'zoneCode', 'binCode', 'itemNo', 'allowBreakbulk', 'doNotFillQtyToHandle', 'autoCreateMovement']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;

    local procedure Snapshot(TemplateName: Code[10]; WorksheetName: Code[10]; LocationCode: Code[10]; var WorksheetLine: Record "Whse. Worksheet Line"): Integer
    begin
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, WorksheetName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        if WorksheetLine.FindLast() then
            exit(WorksheetLine."Line No.");
        exit(0);
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    local procedure BooleanValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        if Token.AsValue().IsNull() then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;
}
