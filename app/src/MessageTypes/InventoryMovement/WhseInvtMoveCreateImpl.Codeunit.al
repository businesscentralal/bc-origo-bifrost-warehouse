namespace Origo.Bifrost.Warehouse;

using Microsoft.Assembly.Document;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InternalDocument;
using Microsoft.Warehouse.Request;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.InventoryMovement.Create.
/// Inline lines become an internal movement, then an inventory movement.
/// Assembly consumption uses report 7323. A directed location is refused.
/// </summary>
codeunit 10078441 "Whse InvtMove Create Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    /// <summary>Returns whether the caller can create an inventory movement.</summary>
    /// <returns>True when the caller can write the internal movement and the activity it creates.</returns>
    procedure IsEnabled(): Boolean
    var
        InternalHeader: Record "Internal Movement Header";
        InternalLine: Record "Internal Movement Line";
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        Location: Record Location;
        BinContent: Record "Bin Content";
        Item: Record Item;
        WarehouseRequest: Record "Warehouse Request";
    begin
        exit(InternalHeader.WritePermission() and InternalLine.WritePermission() and ActivityHeader.WritePermission() and ActivityLine.WritePermission() and Location.ReadPermission() and BinContent.ReadPermission() and Item.ReadPermission() and WarehouseRequest.ReadPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse activity header table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Activity Header");
    end;

    /// <summary>Returns a short description of Warehouse.InventoryMovement.Create.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Creates an inventory movement from inline bin lines or from assembly consumption.', Comment = 'is-IS=Stofnar birgðafærslu úr línum milli hólfa eða úr samsetningarnotkun.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'inventory movement, move between bins, basic warehouse, internal movement, assembly consumption', Comment = 'is-IS=birgðafærsla, færa milli hólfa, einfalt vöruhús, innri færsla, samsetningarnotkun';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Creates an inventory movement at a location with bins and without directed put-away and pick. Assembly consumption is committed by Business Central. Use Warehouse.Movement.Create for a directed location.', Comment = 'is-IS=Stofnar birgðafærslu á staðsetningu með hólfum og án beinnar innsetningar og tínslu. Business Central staðfestir samsetningarnotkun. Notaðu Warehouse.Movement.Create fyrir beina staðsetningu.';
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
        Forms.Add('assembly order no.');
        Envelope := Parts.RecordEnvelope(Forms, 'Optional. With lines, subject is the location. With sourceDocument, subject is the assembly order number. Do not send a different value in both places.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'location code or assembly order no.', 'The basic location, or the assembly order when sourceDocument is sent.'));
        Target.Add(ContractMgt.TargetEntry('data.locationCode', 'location code', 'The basic location the movement belongs to.'));
        Target.Add(ContractMgt.TargetEntry('data.sourceNo', 'assembly order no.', 'The assembly order to move components for.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId', 'guid', 'The assembly order SystemId.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('locationCode', 'string', false, 'Location with bins and without directed put-away and pick. Required for inline lines when subject is empty.'));
        Parameters.Add(ContractMgt.Parameter('sourceDocument', 'string', false, 'Assembly Consumption. Required when lines are omitted.'));
        Parameters.Add(ContractMgt.Parameter('sourceNo', 'string', false, 'Assembly order number. Required when sourceDocument is sent and systemId and subject are empty.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'Assembly order SystemId. Used only with sourceDocument.'));
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Inline lines. Required when sourceDocument is omitted.'));
        Parameters.Add(ContractMgt.Parameter('itemNo', 'string', true, 'Item number on an inline line.'));
        Parameters.Add(ContractMgt.Parameter('variantCode', 'string', false, 'Item variant. Optional.'));
        Parameters.Add(ContractMgt.Parameter('unitOfMeasureCode', 'string', false, 'Unit of measure. Defaults to the item base unit.'));
        Parameters.Add(ContractMgt.Parameter('quantity', 'number', true, 'Quantity to move, in the line unit of measure.'));
        Parameters.Add(ContractMgt.Parameter('fromBin', 'string', true, 'Bin the quantity is taken from.'));
        Parameters.Add(ContractMgt.Parameter('toBin', 'string', true, 'Bin the quantity is placed in. Must differ from fromBin.'));
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
        Fields.Add(ContractMgt.ResponseField('movementNo', 'string', 'Created inventory movement number.'));
        Fields.Add(ContractMgt.ResponseField('movementSystemId', 'string', 'Created inventory movement SystemId.'));
        Fields.Add(ContractMgt.ResponseField('locationCode', 'string', 'Location code.'));
        Fields.Add(ContractMgt.ResponseField('sourceDocument', 'string', 'Assembly Consumption when the movement came from a source document. Empty for inline lines.'));
        Fields.Add(ContractMgt.ResponseField('sourceNo', 'string', 'Assembly order number when the movement came from a source document.'));
        Fields.Add(ContractMgt.ResponseField('lineCount', 'integer', 'Number of movement lines, one for each from-bin and to-bin pair.'));
        LineFields.Add(ContractMgt.ResponseField('lineNo', 'integer', 'Take line number.'));
        LineFields.Add(ContractMgt.ResponseField('itemNo', 'string', 'Item number.'));
        LineFields.Add(ContractMgt.ResponseField('fromBin', 'string', 'Bin the quantity is taken from.'));
        LineFields.Add(ContractMgt.ResponseField('toBin', 'string', 'Bin the quantity is placed in.'));
        LineFields.Add(ContractMgt.ResponseField('quantity', 'number', 'Quantity on the line.'));
        LineFields.Add(ContractMgt.ResponseField('qtyToHandle', 'number', 'Quantity to handle.'));
        Lines.Add('name', 'lines');
        Lines.Add('type', 'array');
        Lines.Add('description', 'Created inventory movement lines.');
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
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The location uses directed put-away and pick.', 'Use Warehouse.Movement.Create.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The location does not use bins.', 'Moves between bins need Bin Mandatory on the location.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidLine, 'A line asks for more than the bin content in fromBin.', 'Read Warehouse.BinContent.Get and lower the quantity.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidLine, 'fromBin and toBin are the same bin.', 'Send a toBin that is different from fromBin.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The item, bin or assembly order was not found.', 'Check the identifier and send the request again.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'lines, or sourceDocument and a document number, is missing.', 'Send inline lines or an assembly consumption source document.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type or is too long.', 'Send text for codes and numbers for quantities.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'sourceDocument is not Assembly Consumption, or a quantity is not greater than zero.', 'Send Assembly Consumption, or a quantity greater than zero.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'Two identifiers name different locations or documents, or lines and a source document were both sent.', 'Send inline lines or one assembly order, not both.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot create an inventory movement.', 'Ask an administrator to assign BIFROST Whse - Full ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one line failed validation.', 'Correct every listed line and send the request again. Nothing was written.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the movement.', 'Read the returned text and correct the bins or the assembly order.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Creates an inventory movement. Business Central commits a movement created from assembly consumption, so a later failure does not roll that movement back.', 'BIFROST Whse - Full ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.InventoryMovement.Register', 'Use it to register the inventory movement.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.BinContent.Get', 'Use it to read the quantity in the from-bin before creating a movement.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Movement.Create', 'Use it instead when the location uses directed put-away and pick.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>False. Inventory movement create has no separate workflow chapter.</returns>
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
            '{"locationCode":"BASIC","lines":[{"itemNo":"WRB-1000","quantity":1,"fromBin":"A-01","toBin":"B-01"}]}',
            '{"status":"Success","movementNo":"IM000001","locationCode":"BASIC","sourceDocument":"","sourceNo":"","lineCount":1,"lines":[{"lineNo":10000,"itemNo":"WRB-1000","fromBin":"A-01","toBin":"B-01","quantity":1,"qtyToHandle":1}]}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Creates an inventory movement at a basic location with bins. One failed line writes nothing on the inline path. Assembly consumption is committed when Business Central creates the movement.', Comment = 'is-IS=Stofnar birgðafærslu á einfaldri staðsetningu með hólfum. Ein lína sem mistekst skrifar ekkert á línuleiðinni. Samsetningarnotkun er staðfest þegar Business Central stofnar færsluna.';
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

    /// <summary>Validates the request and creates the inventory movement, or writes nothing on the inline path.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        Context: Codeunit "Whse InvtMove Context ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        LocationCode: Code[10];
        SourceNo: Code[20];
        SourceMode: Boolean;
        LinesMode: Boolean;
        LocationOk: Boolean;
        DeniedLbl: Label 'You do not have permission to create an inventory movement.', Comment = 'is-IS=Þú hefur ekki heimild til að stofna birgðafærslu.';
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
        RequestJson := Argument.GetRequestJson();
        RefuseUnknownKeys(RequestJson, Argument);
        ResolveMode(RequestJson, Argument, SourceMode, LinesMode);
        Clear(LocationCode);
        Clear(SourceNo);
        LocationOk := false;
        if LinesMode then
            LocationOk := TryResolveLocation(RequestJson, Argument, LocationCode);
        if SourceMode then
            LocationOk := TryResolveAssembly(RequestJson, Argument, LocationCode, SourceNo);
        if LocationOk then
            EnsureBasicBins(Argument, LocationCode);
        if LinesMode and LocationOk and (not Argument.HasCollectedErrors()) then
            ReadLines(RequestJson, Argument, LocationCode, Payload);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        if SourceMode then begin
            Clear(Payload);
            Payload.Add('sourceDocument', 'Assembly Consumption');
            Payload.Add('sourceNo', SourceNo);
            Payload.Add('locationCode', LocationCode);
        end else
            Payload.Add('locationCode', LocationCode);
        Context.SetPayload(Payload);
        if not Codeunit.Run(Codeunit::"Whse InvtMove Create Proc ori") then begin
            Context.Reset();
            Argument.RespondWithLastError();
            exit;
        end;
        WriteCreatedMovement(Argument, SourceMode, SourceNo);
        Context.Reset();
    end;

    local procedure WriteCreatedMovement(var Argument: Record "Message Argument ori"; SourceMode: Boolean; SourceNo: Code[20])
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Context: Codeunit "Whse InvtMove Context ori";
        ResponseJson: JsonObject;
        Lines: JsonArray;
        MovementNo: Code[20];
        IgnoredQty: Decimal;
        MissingResultErr: Label 'The inventory movement was created but its number was not returned.', Comment = 'is-IS=Birgðafærslan var stofnuð en númer hennar skilaði sér ekki.';
        MissingResultNextStepLbl: Label 'Read the returned text and correct the bins or the assembly order.', Comment = 'is-IS=Lestu textann sem skilaði sér og leiðréttu hólfin eða samsetningarpöntunina.';
    begin
        if not Context.TryGetResult(MovementNo, IgnoredQty) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'movementNo', '', '', MissingResultNextStepLbl);
            exit;
        end;
        if not ActivityHeader.Get(ActivityHeader.Type::"Invt. Movement", MovementNo) then begin
            Argument.RespondWithError("Bifrost Error Code ori"::BusinessCentralError, MissingResultErr, 'movementNo', MovementNo, '', MissingResultNextStepLbl);
            exit;
        end;
        BuildLines(ActivityHeader, Lines);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('movementNo', ActivityHeader."No.");
        ResponseJson.Add('movementSystemId', Format(ActivityHeader.SystemId, 0, 4));
        ResponseJson.Add('locationCode', ActivityHeader."Location Code");
        if SourceMode then
            ResponseJson.Add('sourceDocument', 'Assembly Consumption')
        else
            ResponseJson.Add('sourceDocument', '');
        ResponseJson.Add('sourceNo', SourceNo);
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

    local procedure ResolveMode(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var SourceMode: Boolean; var LinesMode: Boolean)
    var
        Readers: Codeunit "Whse Movement Context ori";
        Token: JsonToken;
        SourceText: Text;
        SourcePresent: Boolean;
        HasLines: Boolean;
        BothLbl: Label 'Send lines or a source document, not both.', Comment = 'is-IS=Sendu línur eða upprunaskjal, ekki bæði.';
        BothNextStepLbl: Label 'Send inline lines or one assembly order, not both.', Comment = 'is-IS=Sendu línur eða eina samsetningarpöntun, ekki bæði.';
        MissingLbl: Label 'lines or sourceDocument is required.', Comment = 'is-IS=lines eða sourceDocument er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send inline lines or an assembly consumption source document.', Comment = 'is-IS=Sendu línur eða upprunaskjal um samsetningarnotkun.';
        InvalidLbl: Label 'sourceDocument %1 is not supported.', Comment = '%1 = source document, is-IS=sourceDocument %1 er ekki stutt.';
        InvalidNextStepLbl: Label 'Send Assembly Consumption, or inline lines.', Comment = 'is-IS=Sendu Assembly Consumption, eða línur.';
    begin
        SourceMode := false;
        LinesMode := false;
        HasLines := false;
        if RequestJson.Get('lines', Token) then
            if Token.IsArray() then
                HasLines := Token.AsArray().Count() > 0;
        if not Readers.ReadText(RequestJson, 'sourceDocument', 50, Argument, SourceText, SourcePresent, 'sourceDocument') then
            exit;
        if SourcePresent and HasLines then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, BothLbl, 'lines', '', SourceText, BothNextStepLbl);
            exit;
        end;
        if not SourcePresent and not HasLines then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'lines', '', '', MissingNextStepLbl);
            exit;
        end;
        if HasLines then begin
            LinesMode := true;
            exit;
        end;
        if not IsAssemblyConsumption(SourceText) then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, StrSubstNo(InvalidLbl, SourceText), 'sourceDocument', SourceText, 'Assembly Consumption', InvalidNextStepLbl);
            exit;
        end;
        SourceMode := true;
    end;

    local procedure TryResolveLocation(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        Readers: Codeunit "Whse Movement Context ori";
        LocationText: Text;
        Present: Boolean;
        SubjectText: Text;
        MissingLbl: Label 'locationCode is required.', Comment = 'is-IS=locationCode er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send locationCode and at least one line.', Comment = 'is-IS=Sendu locationCode og að minnsta kosti eina línu.';
        ConflictLbl: Label 'subject and locationCode name different locations.', Comment = 'is-IS=subject og locationCode nefna mismunandi staðsetningar.';
        ConflictNextStepLbl: Label 'Send one location: subject or locationCode.', Comment = 'is-IS=Sendu eina staðsetningu: subject eða locationCode.';
        NotFoundLbl: Label 'Location %1 was not found.', Comment = '%1 = location code, is-IS=Staðsetning %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the location code and send the request again.', Comment = 'is-IS=Athugaðu staðsetningarkóðann og sendu beiðnina aftur.';
    begin
        Clear(LocationCode);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Readers.ReadText(RequestJson, 'locationCode', MaxStrLen(Location.Code), Argument, LocationText, Present, 'locationCode') then
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

    local procedure TryResolveAssembly(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var LocationCode: Code[10]; var SourceNo: Code[20]): Boolean
    var
        AssemblyHeader: Record "Assembly Header";
        BySystemId: Record "Assembly Header";
        Readers: Codeunit "Whse Movement Context ori";
        SourceText: Text;
        SystemIdText: Text;
        LocationText: Text;
        SubjectText: Text;
        Parsed: Guid;
        SourcePresent: Boolean;
        SystemPresent: Boolean;
        LocationPresent: Boolean;
        HasNumber: Boolean;
        HasSystem: Boolean;
        MissingLbl: Label 'sourceNo or systemId is required.', Comment = 'is-IS=sourceNo eða systemId er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send sourceDocument and sourceNo or systemId.', Comment = 'is-IS=Sendu sourceDocument og sourceNo eða systemId.';
        FormatLbl: Label 'systemId is not a GUID.', Comment = 'is-IS=systemId er ekki GUID.';
        FormatNextStepLbl: Label 'Send text for codes and a GUID for systemId.', Comment = 'is-IS=Sendu texta fyrir kóða og GUID fyrir systemId.';
        NotFoundLbl: Label 'Assembly order %1 was not found.', Comment = '%1 = identifier, is-IS=Samsetningarpöntun %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check sourceDocument and the document number or SystemId.', Comment = 'is-IS=Athugaðu sourceDocument og skjalnúmer eða SystemId.';
        ConflictLbl: Label 'subject, sourceNo and systemId name different documents.', Comment = 'is-IS=subject, sourceNo og systemId nefna mismunandi skjöl.';
        ConflictNextStepLbl: Label 'Send one assembly order: subject, sourceNo or systemId.', Comment = 'is-IS=Sendu eina samsetningarpöntun: subject, sourceNo eða systemId.';
        LocationConflictLbl: Label 'locationCode is not the assembly order location.', Comment = 'is-IS=locationCode er ekki staðsetning samsetningarpöntunarinnar.';
        NotReleasedLbl: Label 'Assembly order %1 is not released.', Comment = '%1 = order no., is-IS=Samsetningarpöntun %1 er ekki staðfest.';
        NotReleasedNextStepLbl: Label 'Release the assembly order and send the request again.', Comment = 'is-IS=Staðfestu samsetningarpöntunina og sendu beiðnina aftur.';
    begin
        Clear(LocationCode);
        Clear(SourceNo);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Readers.ReadText(RequestJson, 'sourceNo', MaxStrLen(AssemblyHeader."No."), Argument, SourceText, SourcePresent, 'sourceNo') then
            exit(false);
        if not Readers.ReadText(RequestJson, 'systemId', 50, Argument, SystemIdText, SystemPresent, 'systemId') then
            exit(false);
        if not Readers.ReadText(RequestJson, 'locationCode', MaxStrLen(LocationCode), Argument, LocationText, LocationPresent, 'locationCode') then
            exit(false);
        if (SubjectText <> '') and IsGuid(SubjectText) and not SystemPresent then begin
            SystemIdText := SubjectText;
            SystemPresent := true;
        end;
        if (SubjectText <> '') and (not IsGuid(SubjectText)) and (not SourcePresent) then begin
            SourceText := SubjectText;
            SourcePresent := true;
        end;
        if SourcePresent and (SubjectText <> '') and (not IsGuid(SubjectText)) and (UpperCase(SubjectText) <> UpperCase(SourceText)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'sourceNo', SourceText, SubjectText, ConflictNextStepLbl);
            exit(false);
        end;
        if not SourcePresent and not SystemPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'sourceNo', '', '', MissingNextStepLbl);
            exit(false);
        end;
        if SystemPresent then begin
            if not Evaluate(Parsed, SystemIdText) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'systemId', SystemIdText, 'guid', FormatNextStepLbl);
                exit(false);
            end;
            HasSystem := BySystemId.GetBySystemId(Parsed);
            if HasSystem then
                HasSystem := BySystemId."Document Type" = BySystemId."Document Type"::Order;
            if not HasSystem then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, SystemIdText), 'systemId', SystemIdText, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        if SourcePresent then begin
            HasNumber := AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, CopyStr(SourceText, 1, MaxStrLen(AssemblyHeader."No.")));
            if not HasNumber then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, SourceText), 'sourceNo', SourceText, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        if HasNumber and HasSystem and (AssemblyHeader.SystemId <> BySystemId.SystemId) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'sourceNo', SourceText, SystemIdText, ConflictNextStepLbl);
            exit(false);
        end;
        if HasSystem and not HasNumber then
            AssemblyHeader := BySystemId;
        if AssemblyHeader.Status <> AssemblyHeader.Status::Released then begin
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NotReleasedLbl, AssemblyHeader."No."), 'sourceNo', AssemblyHeader."No.", '', NotReleasedNextStepLbl);
            exit(false);
        end;
        if LocationPresent and (UpperCase(LocationText) <> UpperCase(AssemblyHeader."Location Code")) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, LocationConflictLbl, 'locationCode', LocationText, AssemblyHeader."Location Code", ConflictNextStepLbl);
            exit(false);
        end;
        if not EnsureAssemblyHandling(Argument, AssemblyHeader."Location Code") then
            exit(false);
        LocationCode := AssemblyHeader."Location Code";
        SourceNo := AssemblyHeader."No.";
        exit(true);
    end;

    local procedure EnsureAssemblyHandling(var Argument: Record "Message Argument ori"; LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        HandlingLbl: Label 'Location %1 does not create an inventory movement for assembly consumption.', Comment = '%1 = location, is-IS=Staðsetning %1 stofnar ekki birgðafærslu fyrir samsetningarnotkun.';
        HandlingNextStepLbl: Label 'Set assembly consumption warehouse handling to inventory movement.', Comment = 'is-IS=Stilltu vöruhúsameðhöndlun samsetningarnotkunar á birgðafærslu.';
    begin
        Location.SetLoadFields(Code, "Asm. Consump. Whse. Handling", "Bin Mandatory", "Directed Put-away and Pick");
        if not Location.Get(LocationCode) then
            exit(false);
        if not EnsureBasicBins(Argument, LocationCode) then
            exit(false);
        if Location."Asm. Consump. Whse. Handling" <> Location."Asm. Consump. Whse. Handling"::"Inventory Movement" then begin
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(HandlingLbl, LocationCode), 'sourceDocument', LocationCode, '', HandlingNextStepLbl);
            exit(false);
        end;
        exit(not Argument.HasCollectedErrors());
    end;

    local procedure EnsureBasicBins(var Argument: Record "Message Argument ori"; LocationCode: Code[10]): Boolean
    var
        Location: Record Location;
        DirectedLbl: Label 'Location %1 uses directed put-away and pick.', Comment = '%1 = location, is-IS=Staðsetning %1 notar beina innsetningu og tínslu.';
        DirectedNextStepLbl: Label 'Use Warehouse.Movement.Create.', Comment = 'is-IS=Notaðu Warehouse.Movement.Create.';
        BinsLbl: Label 'Location %1 does not use bins.', Comment = '%1 = location, is-IS=Staðsetning %1 notar ekki hólf.';
        BinsNextStepLbl: Label 'Moves between bins need Bin Mandatory on the location.', Comment = 'is-IS=Færslur milli hólfa þurfa Bin Mandatory á staðsetningunni.';
    begin
        Location.SetLoadFields("Directed Put-away and Pick", "Bin Mandatory");
        if not Location.Get(LocationCode) then
            exit(false);
        if Location."Directed Put-away and Pick" then begin
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(DirectedLbl, LocationCode), 'locationCode', LocationCode, '', DirectedNextStepLbl);
            exit(false);
        end;
        if not Location."Bin Mandatory" then begin
            Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(BinsLbl, LocationCode), 'locationCode', LocationCode, '', BinsNextStepLbl);
            exit(false);
        end;
        exit(true);
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
        Payload.Add('sourceDocument', '');
        Payload.Add('lines', Planned);
    end;

    local procedure ReadOneLine(Token: JsonToken; Index: Integer; var Argument: Record "Message Argument ori"; LocationCode: Code[10]; var Planned: JsonArray)
    var
        Readers: Codeunit "Whse Movement Context ori";
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
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line index, %2 = field, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send itemNo, quantity, fromBin and toBin on every line.', Comment = 'is-IS=Sendu itemNo, quantity, fromBin og toBin á hverri línu.';
    begin
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, LineParameter(Index, 'itemNo'), '', 'object', FormatNextStepLbl);
            exit;
        end;
        LineObject := Token.AsObject();
        RefuseUnknownLineKeys(LineObject, Index, Argument);
        Readers.ReadText(LineObject, 'itemNo', 20, Argument, ItemNo, ItemPresent, LineParameter(Index, 'itemNo'));
        Readers.ReadText(LineObject, 'variantCode', 10, Argument, VariantCode, VariantPresent, LineParameter(Index, 'variantCode'));
        Readers.ReadText(LineObject, 'unitOfMeasureCode', 10, Argument, UnitCode, UnitPresent, LineParameter(Index, 'unitOfMeasureCode'));
        Readers.ReadText(LineObject, 'fromBin', 20, Argument, FromBin, FromPresent, LineParameter(Index, 'fromBin'));
        Readers.ReadText(LineObject, 'toBin', 20, Argument, ToBin, ToPresent, LineParameter(Index, 'toBin'));
        Readers.ReadDecimal(LineObject, 'quantity', Argument, Quantity, QuantityPresent, LineParameter(Index, 'quantity'));
        if not ItemPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'itemNo'), LineParameter(Index, 'itemNo'), '', '', MissingNextStepLbl);
        if not FromPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'fromBin'), LineParameter(Index, 'fromBin'), '', '', MissingNextStepLbl);
        if not ToPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'toBin'), LineParameter(Index, 'toBin'), '', '', MissingNextStepLbl);
        if not QuantityPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'quantity'), LineParameter(Index, 'quantity'), '', '', MissingNextStepLbl);
        if QuantityPresent and (Quantity <= 0) then
            RefuseQuantity(Argument, Index, Quantity);
        if FromPresent and ToPresent and (UpperCase(FromBin) = UpperCase(ToBin)) then
            RefuseSameBin(Argument, Index);
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
        SameBin: Boolean;
        NotFoundLbl: Label '%1 %2 was not found.', Comment = '%1 = table, %2 = value, is-IS=%1 %2 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the identifier and send the request again.', Comment = 'is-IS=Athugaðu auðkennið og sendu beiðnina aftur.';
        ShortLbl: Label 'Bin %1 does not contain enough of item %2.', Comment = '%1 = bin, %2 = item, is-IS=Hólf %1 inniheldur ekki nóg af vöru %2.';
        ShortNextStepLbl: Label 'Read Warehouse.BinContent.Get and lower the quantity.', Comment = 'is-IS=Lestu Warehouse.BinContent.Get og lækkaðu magnið.';
    begin
        SameBin := FromPresent and ToPresent and (UpperCase(FromBin) = UpperCase(ToBin));
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
                    if QuantityPresent and FromPresent and not SameBin then begin
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
        if ToPresent and not SameBin then
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

    local procedure RefuseQuantity(var Argument: Record "Message Argument ori"; Index: Integer; Quantity: Decimal)
    var
        QuantityLbl: Label 'Quantity must be greater than zero.', Comment = 'is-IS=Magn verður að vera stærra en núll.';
        QuantityNextStepLbl: Label 'Send a quantity greater than zero.', Comment = 'is-IS=Sendu magn sem er stærra en núll.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, QuantityLbl, LineParameter(Index, 'quantity'), Format(Quantity), '', QuantityNextStepLbl);
    end;

    local procedure RefuseSameBin(var Argument: Record "Message Argument ori"; Index: Integer)
    var
        SameLbl: Label 'Line %1 uses the same fromBin and toBin.', Comment = '%1 = line index, is-IS=Lína %1 notar sama fromBin og toBin.';
        SameNextStepLbl: Label 'Send a toBin that is different from fromBin.', Comment = 'is-IS=Sendu toBin sem er annað en fromBin.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidLine, StrSubstNo(SameLbl, Index), LineParameter(Index, 'toBin'), '', '', SameNextStepLbl);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['locationCode', 'sourceDocument', 'sourceNo', 'systemId', 'lines']) then
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

    local procedure IsAssemblyConsumption(SourceText: Text): Boolean
    begin
        exit(UpperCase(DelChr(SourceText, '=', ' ')) in ['ASSEMBLYCONSUMPTION']);
    end;

    local procedure IsGuid(Value: Text): Boolean
    var
        Parsed: Guid;
    begin
        if Value = '' then
            exit(false);
        exit(Evaluate(Parsed, Value));
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
}
