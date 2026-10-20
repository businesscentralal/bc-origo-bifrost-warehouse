namespace Origo.Bifrost.Warehouse;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.Movement.Create.
/// Inline lines are written to a movement worksheet, then report 7305 creates the movement.
/// A basic location is refused so this type does not create an inventory movement.
/// </summary>
codeunit 10078421 "Whse Movement Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        MissingPayloadErr: Label 'The movement create payload was empty.', Comment = 'is-IS=Gögnin til að stofna færslu voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        CreateMovement(Payload, ActivityHeader);
        Context.SetResult(ActivityHeader."No.", 0);
    end;

    /// <summary>Returns whether the caller can create a warehouse movement.</summary>
    /// <returns>True when the caller can write the worksheet and the activity the report creates.</returns>
    procedure IsEnabled(): Boolean
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Location: Record Location;
    begin
        exit(WorksheetLine.WritePermission() and ActivityHeader.WritePermission() and ActivityLine.WritePermission() and Location.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse worksheet line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Whse. Worksheet Line");
    end;

    /// <summary>Returns a short description of Warehouse.Movement.Create.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates a warehouse movement from a movement worksheet or from inline lines.', Comment = 'is-IS=Stofnar vöruhúsafærslu úr færslublaði eða úr línum í beiðninni.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'create movement, warehouse movement, move between bins, bin transfer, directed movement, movement worksheet', Comment = 'is-IS=stofna færslu, vöruhúsafærsla, færa milli hólfa, hólfaflutningur, bein færsla, færslublað';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Business Central commits the warehouse movement it creates. Use Warehouse.InventoryMovement.Create for a location without directed put-away and pick.', Comment = 'is-IS=Óafturkræft. Business Central staðfestir vöruhúsafærsluna sem það stofnar. Notaðu Warehouse.InventoryMovement.Create fyrir staðsetningu án beinnar innsetningar og tínslu.';
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
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. A location code selects the same location as locationCode. Do not send a different location in both places.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code', 'The directed location the movement belongs to.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode', 'location code', 'The directed location the movement belongs to.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', true, 'Directed put-away and pick location. Required when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('worksheetTemplateName', 'string', false, 'Movement worksheet template. Required when lines are omitted.'));
        Parameters.Add(ContractMgt.Parameter('worksheetName', 'string', false, 'Movement worksheet name. Required when lines are omitted.'));
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Inline lines. Written to the worksheet before the movement is created. Required when no worksheet is named.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', true, 'Item number on an inline line.'));
        Parameters.Add(ContractMgt.Parameter('variantCode', 'string', false, 'Item variant. Optional.'));
        Parameters.Add(ContractMgt.Parameter('unitOfMeasureCode', 'string', false, 'Unit of measure. Defaults to the item base unit.'));
        Parameters.Add(ContractMgt.Parameter('quantity', 'number', true, 'Quantity to move, in the line unit of measure.'));
        Parameters.Add(ContractMgt.Parameter('fromBin', 'string', true, 'Bin the quantity is taken from.'));
        Parameters.Add(ContractMgt.Parameter('toBin', 'string', true, 'Bin the quantity is placed in.'));
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
        Fields.Add(ContractMgt.ResponseField('movementNo', 'string', 'Created warehouse movement number.'));
        Fields.Add(ContractMgt.ResponseField('movementSystemId', 'string', 'Created warehouse movement SystemId.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        Fields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of movement lines, one for each from-bin and to-bin pair.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Take line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('fromBin', 'string', 'Bin the quantity is taken from.'));
        LineFields.Add(ContractMgt.ResponseField('toBin', 'string', 'Bin the quantity is placed in.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity on the line.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Created movement lines.');
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
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use directed put-away and pick.', 'Use Warehouse.InventoryMovement.Create for basic warehouse locations.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidLine, 'A line asks for more than the bin content in fromBin.', 'Read Warehouse.BinContent.Get for the bin and lower the quantity.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The item or bin was not found.', 'Check the identifier with Warehouse.Activity.Get (activityType Movement).');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'locationCode, or a worksheet, or the lines array is missing.', 'Send locationCode and either a movement worksheet or at least one line.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'worksheetTemplateName is not a movement worksheet template.', 'Send a movement worksheet template.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'A line quantity is zero or negative.', 'Send a quantity greater than zero.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes and numbers for quantities.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'subject and locationCode name different locations.', 'Send one location: subject or locationCode.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot create a warehouse movement.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one line failed validation.', 'Correct every listed line and send the request again. Nothing was written.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the movement.', 'Read the returned text and correct the worksheet or the bin content.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Creates a warehouse movement. Business Central commits the movement when it is created, so a later failure does not roll it back.', 'BIFROST Whse - Full ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Movement.Register', 'Use it to register the movement after the quantity to handle is set.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read the quantity in the from-bin before creating a movement.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Get', 'Use it to read the movement, with activityType Movement.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>False. Movement create has no separate workflow chapter.</returns>
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
            'Move one piece from A-01 to B-01',
            '{"locationCode":"WHITE","lines":[{"itemNo":"WRB-1000","quantity":1,"fromBin":"W-01-0001","toBin":"W-04-0001"}]}',
            '{"status":"Success","movementNo":"WM000001","locationCode":"WHITE","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"WRB-1000","fromBin":"W-01-0001","toBin":"W-04-0001","quantity":1,"qtyToHandle":1}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Creates a warehouse movement at a directed location. Business Central commits the movement. One failed line writes none of the new worksheet lines.', Comment = 'is-IS=Stofnar vöruhúsafærslu á beinni staðsetningu. Business Central staðfestir færsluna. Ein lína sem mistekst skrifar enga af nýju blaðlínunum.';
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

    /// <summary>Validates the request and creates the movement, or writes nothing.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        WhseRecordLookup: Codeunit "Whse Record Lookup ori";
        Context: Codeunit "Whse Write Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        LocationCode: Code[10];
        TemplateName: Code[10];
        BatchName: Code[10];
        Directed: Boolean;
        DeniedLbl: Label 'You do not have permission to create a warehouse movement.', Comment = 'is-IS=Þú hefur ekki heimild til að stofna vöruhúsafærslu.';
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
        if not TryResolveLocation(RequestJson, Argument, LocationCode) then
            LocationCode := '';
        Directed := (LocationCode <> '') and LocationIsDirected(LocationCode);
        if (LocationCode <> '') and (not Directed) then
            EnsureDirected(Argument, LocationCode);
        // A basic location is the whole answer. Further line errors would hide the required next step.
        if Directed then begin
            ResolveWorksheet(RequestJson, Argument, TemplateName, BatchName);
            ReadLines(RequestJson, Argument, LocationCode, Payload);
            if (TemplateName <> '') and (BatchName <> '') and (LocationCode <> '') then
                CheckExistingLines(Argument, TemplateName, BatchName, LocationCode);
        end;
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('locationCode', LocationCode);
        Payload.Add('worksheetTemplateName', TemplateName);
        Payload.Add('worksheetName', BatchName);
        Context.SetPayload(Payload);
        // Codeunit.Run with a return value is illegal inside the Omit Commit write transaction (#18).
        if Argument."Omit Commit" then
            Codeunit.Run(Codeunit::"Whse Movement Create Impl ori")
        else
            if not Codeunit.Run(Codeunit::"Whse Movement Create Impl ori") then begin
                Context.Reset();
                Argument.RespondWithLastError();
                exit;
            end;
        WriteCreatedMovement(Argument);
        Context.Reset();
    end;

    local procedure WriteCreatedMovement(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Context: Codeunit "Whse Write Context ori";
        ResponseJson: JsonObject;
        Lines: JsonArray;
        MovementNo: Code[20];
        IgnoredQty: Decimal;
        MissingResultErr: Label 'The movement was created but its number was not returned.', Comment = 'is-IS=Færslan var stofnuð en númer hennar skilaði sér ekki.';
        MissingResultNextStepLbl: Label 'Read the returned text and correct the worksheet or the bin content.', Comment = 'is-IS=Lestu textann sem skilaði sér og leiðréttu blað eða hólfainnihald.';
    begin
        if not Context.TryGetResult(MovementNo, IgnoredQty) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'movementNo', '', '', MissingResultNextStepLbl);
            exit;
        end;
        if not ActivityHeader.Get(ActivityHeader.Type::Movement, MovementNo) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'movementNo', MovementNo, '', MissingResultNextStepLbl);
            exit;
        end;
        BuildLines(ActivityHeader, Lines);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('movementNo', ActivityHeader."No.");
        ResponseJson.Add('movementSystemId', Format(ActivityHeader.SystemId, 0, 4));
        ResponseJson.Add('locationCode', ActivityHeader."Location Code");
        ResponseJson.Add('lineCount', Lines.Count());
        ResponseJson.Add('lines', Lines);
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure BuildLines(ActivityHeader: Record "Warehouse Activity Header"; var Lines: JsonArray)
    var
        TakeLine: Record "Warehouse Activity Line";
        PlaceLine: Record "Warehouse Activity Line";
        LineJson: JsonObject;
    begin
        Clear(Lines);
        TakeLine.SetRange("Activity Type", ActivityHeader.Type);
        TakeLine.SetRange("No.", ActivityHeader."No.");
        TakeLine.SetRange("Action Type", TakeLine."Action Type"::Take);
        if not TakeLine.FindSet() then
            exit;
        repeat
            Clear(LineJson);
            LineJson.Add('lineNo', TakeLine."Line No.");
            LineJson.Add('itemNo', TakeLine."Item No.");
            LineJson.Add('fromBin', TakeLine."Bin Code");
            LineJson.Add('toBin', PairedPlaceBin(TakeLine, PlaceLine));
            LineJson.Add('quantity', TakeLine.Quantity);
            LineJson.Add('qtyToHandle', TakeLine."Qty. to Handle");
            Lines.Add(LineJson);
        until TakeLine.Next() = 0;
    end;

    local procedure PairedPlaceBin(TakeLine: Record "Warehouse Activity Line"; var PlaceLine: Record "Warehouse Activity Line"): Code[20]
    begin
        PlaceLine.SetRange("Activity Type", TakeLine."Activity Type");
        PlaceLine.SetRange("No.", TakeLine."No.");
        PlaceLine.SetRange("Action Type", PlaceLine."Action Type"::Place);
        PlaceLine.SetRange("Item No.", TakeLine."Item No.");
        PlaceLine.SetRange("Variant Code", TakeLine."Variant Code");
        PlaceLine.SetRange(Quantity, TakeLine.Quantity);
        PlaceLine.SetFilter("Line No.", '>%1', TakeLine."Line No.");
        if PlaceLine.FindFirst() then
            exit(PlaceLine."Bin Code");
        exit('');
    end;

    local procedure LocationIsDirected(LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
    begin
        Location.SetLoadFields("Directed Put-away and Pick");
        if not Location.Get(LocationCode) then
            exit(false);
        exit(Location."Directed Put-away and Pick");
    end;

    local procedure EnsureDirected(var Argument: Record "Message Argument ori"; LocationCode: Code[10])
    var
        DirectedLbl: Label 'Location %1 does not use directed put-away and pick.', Comment = '%1 = location, is-IS=Staðsetning %1 notar ekki beina innsetningu og tínslu.';
        DirectedNextStepLbl: Label 'Use Warehouse.InventoryMovement.Create for basic warehouse locations.', Comment = 'is-IS=Notaðu Warehouse.InventoryMovement.Create fyrir einfaldar vöruhúsastaðsetningar.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(DirectedLbl, LocationCode), 'locationCode', LocationCode, '', DirectedNextStepLbl);
    end;

    local procedure TryResolveLocation(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        Context: Codeunit "Whse Write Context ori";
        LocationText: Text;
        Present: Boolean;
        SubjectText: Text;
        MissingLbl: Label 'locationCode is required.', Comment = 'is-IS=locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode and either a movement worksheet or at least one line.', Comment = 'is-IS=Sendu locationCode og annaðhvort færslublað eða að minnsta kosti eina línu.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        NotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the identifier with Warehouse.Activity.Get (activityType Movement).', Comment = 'is-IS=Athugaðu auðkennið með Warehouse.Activity.Get (activityType Movement).';
    begin
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Context.ReadText(RequestJson, 'locationCode', MaxStrLen(Location.Code), Argument, LocationText, Present, 'locationCode') then
            exit(false);
        if Present and (SubjectText <> '') and (UpperCase(SubjectText) <> UpperCase(LocationText)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'locationCode', LocationText, SubjectText, ConflictNextStepLbl);
            exit(false);
        end;
        if not Present then
            LocationText := SubjectText;
        if LocationText = '' then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'locationCode', '', '', MissingNextStepLbl);
            exit(false);
        end;
        LocationCode := CopyStr(LocationText, 1, MaxStrLen(Location.Code));
        Location.SetLoadFields(Code);
        if Location.Get(LocationCode) then
            exit(true);
        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LocationCode), 'locationCode', LocationCode, '', NotFoundNextStepLbl);
        Clear(LocationCode);
        exit(false);
    end;

    local procedure ResolveWorksheet(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var TemplateName: Code[10]; var BatchName: Code[10])
    var
        WorksheetTemplate: Record "Whse. Worksheet Template";
        Context: Codeunit "Whse Write Context ori";
        TemplateText: Text;
        BatchText: Text;
        TemplatePresent: Boolean;
        BatchPresent: Boolean;
        HasLines: Boolean;
        Token: JsonToken;
        MissingLbl: Label 'worksheetTemplateName and worksheetName are required when lines are omitted.', Comment = 'is-IS=worksheetTemplateName og worksheetName eru nauðsynleg þegar línur eru sleppt.';
        MissingNextStepLbl: Label 'Send locationCode and either a movement worksheet or at least one line.', Comment = 'is-IS=Sendu locationCode og annaðhvort færslublað eða að minnsta kosti eina línu.';
        NotFoundLbl: Label 'Movement worksheet template %1 was not found.', Comment = '%1 = template, is-IS=Færslublaðssniðmát %1 fannst ekki.';
        NoTemplateLbl: Label 'No movement worksheet template was found.', Comment = 'is-IS=Ekkert færslublaðssniðmát fannst.';
        NotFoundNextStepLbl: Label 'Check the identifier with Warehouse.Activity.Get (activityType Movement).', Comment = 'is-IS=Athugaðu auðkennið með Warehouse.Activity.Get (activityType Movement).';
        TypeLbl: Label 'Worksheet template %1 is not a movement template.', Comment = '%1 = template, is-IS=Blaðssniðmát %1 er ekki færslusniðmát.';
        TypeNextStepLbl: Label 'Send a movement worksheet template.', Comment = 'is-IS=Sendu sniðmát fyrir færslublað.';
    begin
        Clear(TemplateName);
        Clear(BatchName);
        HasLines := false;
        if RequestJson.Get('lines', Token) then
            if Token.IsArray() then
                HasLines := Token.AsArray().Count() > 0;
        if not Context.ReadText(RequestJson, 'worksheetTemplateName', MaxStrLen(WorksheetTemplate.Name), Argument, TemplateText, TemplatePresent, 'worksheetTemplateName') then
            TemplatePresent := false;
        if not Context.ReadText(RequestJson, 'worksheetName', 10, Argument, BatchText, BatchPresent, 'worksheetName') then
            BatchPresent := false;
        if not TemplatePresent and not BatchPresent then begin
            if not HasLines then begin
                Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'lines', '', '', MissingNextStepLbl);
                exit;
            end;
            WorksheetTemplate.SetRange(Type, WorksheetTemplate.Type::Movement);
            if not WorksheetTemplate.FindFirst() then begin
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NoTemplateLbl, 'worksheetTemplateName', '', '', NotFoundNextStepLbl);
                exit;
            end;
            TemplateName := WorksheetTemplate.Name;
            BatchName := CopyStr('M' + DelChr(Format(CreateGuid()), '=', '{}-'), 1, MaxStrLen(BatchName));
            exit;
        end;
        if not TemplatePresent or not BatchPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'worksheetTemplateName', '', '', MissingNextStepLbl);
            exit;
        end;
        TemplateName := CopyStr(TemplateText, 1, MaxStrLen(TemplateName));
        BatchName := CopyStr(BatchText, 1, MaxStrLen(BatchName));
        WorksheetTemplate.SetLoadFields(Name, Type);
        if not WorksheetTemplate.Get(TemplateName) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, TemplateName), 'worksheetTemplateName', TemplateName, '', NotFoundNextStepLbl);
            exit;
        end;
        if WorksheetTemplate.Type <> WorksheetTemplate.Type::Movement then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(TypeLbl, TemplateName), 'worksheetTemplateName', TemplateName, '', TypeNextStepLbl);
    end;

    local procedure ReadLines(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; var Payload: JsonObject)
    var
        Token: JsonToken;
        Lines: JsonArray;
        Planned: JsonArray;
        Index: Integer;
        FormatLbl: Label 'lines must be an array of line objects.', Comment = 'is-IS=lines verður að vera fylki línuhluta.';
        FormatNextStepLbl: Label 'Send text for codes and numbers for quantities.', Comment = 'is-IS=Sendu texta fyrir kóða og tölur fyrir magn.';
    begin
        Clear(Payload);
        if not RequestJson.Get('lines', Token) then
            exit;
        if not Token.IsArray() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'lines', '', 'array', FormatNextStepLbl);
            exit;
        end;
        Lines := Token.AsArray();
        for Index := 0 to Lines.Count() - 1 do begin
            Lines.Get(Index, Token);
            ReadOneLine(Token, Index, Argument, LocationCode, Planned);
        end;
        Payload.Add('lines', Planned);
    end;

    local procedure ReadOneLine(Token: JsonToken; Index: Integer; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; var Planned: JsonArray)
    var
        Context: Codeunit "Whse Write Context ori";
        LineObject: JsonObject;
        PlannedLine: JsonObject;
        ItemNo: Text;
        VariantCode: Text;
        UnitCode: Text;
        FromBin: Text;
        ToBin: Text;
        ItemPresent: Boolean;
        VariantPresent: Boolean;
        UnitPresent: Boolean;
        FromPresent: Boolean;
        ToPresent: Boolean;
        Quantity: Decimal;
        QuantityPresent: Boolean;
        FormatLbl: Label 'Each line must be an object.', Comment = 'is-IS=Hver lína verður að vera hlutur.';
        FormatNextStepLbl: Label 'Send text for codes and numbers for quantities.', Comment = 'is-IS=Sendu texta fyrir kóða og tölur fyrir magn.';
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line position in the request, counted from 1, %2 = field, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send itemNo, quantity, fromBin and toBin on every line.', Comment = 'is-IS=Sendu itemNo, quantity, fromBin og toBin á hverri línu.';
    begin
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, LineParameter(Index, 'itemNo'), '', 'object', FormatNextStepLbl);
            exit;
        end;
        LineObject := Token.AsObject();
        RefuseUnknownLineKeys(LineObject, Index, Argument);
        Context.ReadText(LineObject, 'itemNo', 20, Argument, ItemNo, ItemPresent, LineParameter(Index, 'itemNo'));
        Context.ReadText(LineObject, 'variantCode', 10, Argument, VariantCode, VariantPresent, LineParameter(Index, 'variantCode'));
        Context.ReadText(LineObject, 'unitOfMeasureCode', 10, Argument, UnitCode, UnitPresent, LineParameter(Index, 'unitOfMeasureCode'));
        Context.ReadText(LineObject, 'fromBin', 20, Argument, FromBin, FromPresent, LineParameter(Index, 'fromBin'));
        Context.ReadText(LineObject, 'toBin', 20, Argument, ToBin, ToPresent, LineParameter(Index, 'toBin'));
        Context.ReadDecimal(LineObject, 'quantity', Argument, Quantity, QuantityPresent, LineParameter(Index, 'quantity'));
        if not ItemPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'itemNo'), LineParameter(Index, 'itemNo'), '', '', MissingNextStepLbl);
        if not FromPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'fromBin'), LineParameter(Index, 'fromBin'), '', '', MissingNextStepLbl);
        if not ToPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'toBin'), LineParameter(Index, 'toBin'), '', '', MissingNextStepLbl);
        if not QuantityPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index + 1, 'quantity'), LineParameter(Index, 'quantity'), '', '', MissingNextStepLbl);
        if QuantityPresent and (Quantity <= 0) then
            RefuseQuantity(Argument, Index, Quantity);
        if LocationCode <> '' then
            ValidateLineAgainstLocation(Argument, LocationCode, Index, ItemNo, ItemPresent, VariantCode, VariantPresent, UnitCode, FromBin, FromPresent, ToBin, ToPresent, Quantity, QuantityPresent);
        if not ItemPresent or not FromPresent or not ToPresent or not QuantityPresent then
            exit;
        PlannedLine.Add('itemNo', UpperCase(ItemNo));
        PlannedLine.Add('variantCode', UpperCase(VariantCode));
        PlannedLine.Add('unitOfMeasureCode', UpperCase(UnitCode));
        PlannedLine.Add('fromBin', UpperCase(FromBin));
        PlannedLine.Add('toBin', UpperCase(ToBin));
        PlannedLine.Add('quantity', Quantity);
        Planned.Add(PlannedLine);
    end;

    local procedure ValidateLineAgainstLocation(var Argument: Record "Message Argument ori"; LocationCode: Code[10]; Index: Integer; ItemNo: Text; ItemPresent: Boolean; VariantCode: Text; VariantPresent: Boolean; UnitCode: Text; FromBin: Text; FromPresent: Boolean; ToBin: Text; ToPresent: Boolean; Quantity: Decimal; QuantityPresent: Boolean)
    var
        Item: Record Item;
        ItemVariant: Record "Item Variant";
        ItemUnit: Record "Item Unit of Measure";
        Bin: Record Bin;
        BinContent: Record "Bin Content";
        RequestedBase: Decimal;
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table, %2 = value, is-IS=%1 %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the identifier with Warehouse.Activity.Get (activityType Movement).', Comment = 'is-IS=Athugaðu auðkennið með Warehouse.Activity.Get (activityType Movement).';
        ShortLbl: Label 'Bin %1 does not contain enough of item %2.', Comment = '%1 = bin, %2 = item, is-IS=Hólf %1 inniheldur ekki nóg af vöru %2.';
        ShortNextStepLbl: Label 'Read Warehouse.BinContent.Get for the bin and lower the quantity.', Comment = 'is-IS=Lestu Warehouse.BinContent.Get fyrir hólfið og lækkaðu magnið.';
    begin
        if ItemPresent then begin
            Item.SetLoadFields("No.", "Base Unit of Measure");
            if not Item.Get(CopyStr(ItemNo, 1, MaxStrLen(Item."No."))) then
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Item.TableCaption(), ItemNo), LineParameter(Index, 'itemNo'), ItemNo, '', NotFoundNextStepLbl)
            else begin
                if VariantPresent then begin
                    ItemVariant.SetLoadFields("Item No.", Code);
                    if not ItemVariant.Get(Item."No.", CopyStr(VariantCode, 1, MaxStrLen(ItemVariant.Code))) then
                        Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ItemVariant.TableCaption(), VariantCode), LineParameter(Index, 'variantCode'), VariantCode, '', NotFoundNextStepLbl);
                end;
                if UnitCode = '' then
                    UnitCode := Item."Base Unit of Measure";
                ItemUnit.SetLoadFields("Item No.", Code, "Qty. per Unit of Measure");
                if not ItemUnit.Get(Item."No.", CopyStr(UnitCode, 1, MaxStrLen(ItemUnit.Code))) then
                    Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, ItemUnit.TableCaption(), UnitCode), LineParameter(Index, 'unitOfMeasureCode'), UnitCode, '', NotFoundNextStepLbl)
                else
                    if QuantityPresent and FromPresent then begin
                        RequestedBase := Quantity * ItemUnit."Qty. per Unit of Measure";
                        BinContent.SetRange("Location Code", LocationCode);
                        BinContent.SetRange("Bin Code", CopyStr(FromBin, 1, MaxStrLen(BinContent."Bin Code")));
                        BinContent.SetRange("Item No.", Item."No.");
                        BinContent.SetRange("Variant Code", CopyStr(VariantCode, 1, MaxStrLen(BinContent."Variant Code")));
                        if SumQuantityBase(BinContent) < RequestedBase then
                            Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(ShortLbl, FromBin, ItemNo), LineParameter(Index, 'quantity'), Format(Quantity), '', ShortNextStepLbl);
                    end;
            end;
        end;
        Bin.SetLoadFields(Code);
        if FromPresent then
            if not Bin.Get(LocationCode, CopyStr(FromBin, 1, MaxStrLen(Bin.Code))) then
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), FromBin), LineParameter(Index, 'fromBin'), FromBin, '', NotFoundNextStepLbl);
        if ToPresent then
            if not Bin.Get(LocationCode, CopyStr(ToBin, 1, MaxStrLen(Bin.Code))) then
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, Bin.TableCaption(), ToBin), LineParameter(Index, 'toBin'), ToBin, '', NotFoundNextStepLbl);
    end;

    local procedure SumQuantityBase(var BinContent: Record "Bin Content"): Decimal
    var
        AvailableBase: Decimal;
    begin
        BinContent.SetAutoCalcFields("Quantity (Base)");
        if BinContent.FindSet() then
            repeat
                AvailableBase += BinContent."Quantity (Base)";
            until BinContent.Next() = 0;
        exit(AvailableBase);
    end;

    local procedure CheckExistingLines(var Argument: Record "Message Argument ori"; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        WorksheetName: Record "Whse. Worksheet Name";
    begin
        if not WorksheetName.Get(TemplateName, BatchName, LocationCode) then
            exit;
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, BatchName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        WorksheetLine.SetFilter(Quantity, '>0');
        if not WorksheetLine.FindSet() then
            exit;
        repeat
            ValidateLineAgainstLocation(Argument, LocationCode, -1, WorksheetLine."Item No.", true, WorksheetLine."Variant Code", WorksheetLine."Variant Code" <> '', WorksheetLine."Unit of Measure Code", WorksheetLine."From Bin Code", WorksheetLine."From Bin Code" <> '', WorksheetLine."To Bin Code", WorksheetLine."To Bin Code" <> '', WorksheetLine.Quantity, true);
        until WorksheetLine.Next() = 0;
    end;

    local procedure RefuseQuantity(var Argument: Record "Message Argument ori"; Index: Integer; Quantity: Decimal)
    var
        QuantityLbl: Label 'Quantity must be greater than zero.', Comment = 'is-IS=Magn verður að vera stærra en núll.';
        QuantityNextStepLbl: Label 'Send a quantity greater than zero.', Comment = 'is-IS=Sendu magn sem er stærra en núll.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, QuantityLbl, LineParameter(Index, 'quantity'), Format(Quantity), '', QuantityNextStepLbl);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['locationCode', 'worksheetTemplateName', 'worksheetName', 'lines']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure RefuseUnknownLineKeys(LineObject: JsonObject; Index: Integer; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in LineObject.Keys() do
            if not (KeyName in ['itemNo', 'variantCode', 'unitOfMeasureCode', 'quantity', 'fromBin', 'toBin']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), LineParameter(Index, KeyName), KeyName, '', UnknownNextStepLbl);
    end;

    local procedure LineParameter(Index: Integer; KeyName: Text): Text
    var
        LineParameterLbl: Label 'lines[%1].%2', Locked = true;
    begin
        if Index < 0 then
            exit(KeyName);
        exit(StrSubstNo(LineParameterLbl, Index, KeyName));
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;

    local procedure CreateMovement(Payload: JsonObject; var ActivityHeader: Record "Warehouse Activity Header")
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        CreateDocument: Report "Whse.-Source - Create Document";
        MovementOption: Option " ","Put-away",Pick,Movement,"Invt. Put-away","Invt. Pick","Invt. Movement";
        TemplateName: Code[10];
        BatchName: Code[10];
        LocationCode: Code[10];
        WorksheetCreated: Boolean;
        NothingErr: Label 'No warehouse movement was created.', Comment = 'is-IS=Engin vöruhúsafærsla var stofnuð.';
    begin
        TemplateName := CopyStr(TextValue(Payload, 'worksheetTemplateName'), 1, MaxStrLen(TemplateName));
        BatchName := CopyStr(TextValue(Payload, 'worksheetName'), 1, MaxStrLen(BatchName));
        LocationCode := CopyStr(TextValue(Payload, 'locationCode'), 1, MaxStrLen(LocationCode));
        WorksheetCreated := EnsureWorksheetName(TemplateName, BatchName, LocationCode);
        InsertInlineLines(Payload, TemplateName, BatchName, LocationCode);
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, BatchName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        WorksheetLine.SetFilter(Quantity, '>0');
        if not WorksheetLine.FindFirst() then
            Error(NothingErr);

        CreateDocument.SetHideValidationDialog(true);
        CreateDocument.UseRequestPage(false);
        CreateDocument.SetWhseWkshLine(WorksheetLine);
        CreateDocument.RunModal();
        CreateDocument.GetActivityHeader(ActivityHeader, MovementOption::Movement);
        if ActivityHeader."No." = '' then
            Error(NothingErr);
        if WorksheetCreated then
            DeleteWorksheetName(TemplateName, BatchName, LocationCode);
    end;

    local procedure DeleteWorksheetName(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        WorksheetName: Record "Whse. Worksheet Name";
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        // The worksheet name was generated for inline lines only; drop it so calls do not leave names behind.
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, BatchName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        WorksheetLine.DeleteAll(true);
        if WorksheetName.Get(TemplateName, BatchName, LocationCode) then
            WorksheetName.Delete(true);
    end;

    local procedure EnsureWorksheetName(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]): Boolean
    var
        WorksheetName: Record "Whse. Worksheet Name";
    begin
        if WorksheetName.Get(TemplateName, BatchName, LocationCode) then
            exit(false);
        WorksheetName.Init();
        WorksheetName.Validate("Worksheet Template Name", TemplateName);
        WorksheetName.Validate(Name, BatchName);
        WorksheetName.Validate("Location Code", LocationCode);
        WorksheetName.Insert(true);
        exit(true);
    end;

    local procedure InsertInlineLines(Payload: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        Token: JsonToken;
        Lines: JsonArray;
        LineObject: JsonObject;
    begin
        if not Payload.Get('lines', Token) then
            exit;
        if not Token.IsArray() then
            exit;
        Lines := Token.AsArray();
        foreach Token in Lines do begin
            LineObject := Token.AsObject();
            InsertOneLine(LineObject, TemplateName, BatchName, LocationCode);
        end;
    end;

    local procedure InsertOneLine(LineObject: JsonObject; TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10])
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        LineNo: Integer;
    begin
        LineNo := NextLineNo(TemplateName, BatchName, LocationCode);
        WorksheetLine.Init();
        WorksheetLine.Validate("Worksheet Template Name", TemplateName);
        WorksheetLine.Validate(Name, BatchName);
        WorksheetLine.Validate("Location Code", LocationCode);
        WorksheetLine.Validate("Line No.", LineNo);
        WorksheetLine.Insert(true);
        WorksheetLine.Validate("Whse. Document Type", WorksheetLine."Whse. Document Type"::" ");
        WorksheetLine.Validate("Item No.", CopyStr(TextValue(LineObject, 'itemNo'), 1, MaxStrLen(WorksheetLine."Item No.")));
        if TextValue(LineObject, 'variantCode') <> '' then
            WorksheetLine.Validate("Variant Code", CopyStr(TextValue(LineObject, 'variantCode'), 1, MaxStrLen(WorksheetLine."Variant Code")));
        if TextValue(LineObject, 'unitOfMeasureCode') <> '' then
            WorksheetLine.Validate("Unit of Measure Code", CopyStr(TextValue(LineObject, 'unitOfMeasureCode'), 1, MaxStrLen(WorksheetLine."Unit of Measure Code")));
        ApplyBin(WorksheetLine, LocationCode, TextValue(LineObject, 'fromBin'), true);
        ApplyBin(WorksheetLine, LocationCode, TextValue(LineObject, 'toBin'), false);
        WorksheetLine.Validate(Quantity, DecimalValue(LineObject, 'quantity'));
        WorksheetLine.Modify(true);
    end;

    local procedure ApplyBin(var WorksheetLine: Record "Whse. Worksheet Line"; LocationCode: Code[10]; BinCode: Text; FromBin: Boolean)
    var
        Bin: Record Bin;
    begin
        if not Bin.Get(LocationCode, CopyStr(BinCode, 1, MaxStrLen(Bin.Code))) then
            exit;
        if FromBin then begin
            WorksheetLine.Validate("From Zone Code", Bin."Zone Code");
            WorksheetLine.Validate("From Bin Code", Bin.Code);
        end else begin
            WorksheetLine.Validate("To Zone Code", Bin."Zone Code");
            WorksheetLine.Validate("To Bin Code", Bin.Code);
        end;
    end;

    local procedure NextLineNo(TemplateName: Code[10]; BatchName: Code[10]; LocationCode: Code[10]): Integer
    var
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        WorksheetLine.SetRange("Worksheet Template Name", TemplateName);
        WorksheetLine.SetRange(Name, BatchName);
        WorksheetLine.SetRange("Location Code", LocationCode);
        if WorksheetLine.FindLast() then
            exit(WorksheetLine."Line No." + 10000);
        exit(10000);
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

    local procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        if not Token.IsValue() then
            exit(0);
        exit(Token.AsValue().AsDecimal());
    end;
}
