namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;
using Origo.Bifrost;

/// <summary>
/// Implements Warehouse.InventoryMovement.Register.
/// Registration runs codeunit 7307, which commits. A movement with nothing to handle is refused.
/// </summary>
codeunit 10078428 "Whse InvtMove Reg Impl ori" implements "Msg Interface ori", "Msg Contract ori", "Msg Discovery ori"
{
    Access = Internal;

    trigger OnRun()
    var
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        Payload: JsonObject;
        MovementNo: Code[20];
        RegisteredQty: Decimal;
        MissingPayloadErr: Label 'The inventory movement register payload was empty.', Comment = 'is-IS=Gögnin til að skrá birgðafærslu voru tóm.';
        NothingErr: Label 'There is nothing to register.', Comment = 'is-IS=Ekkert er til að skrá.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        MovementNo := CopyStr(TextValue(Payload, 'movementNo'), 1, MaxStrLen(MovementNo));
        ApplyQuantities(Payload, MovementNo);
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Invt. Movement");
        ActivityLine.SetRange("No.", MovementNo);
        ActivityLine.SetRange("Action Type", ActivityLine."Action Type"::Take);
        if not ActivityLine.FindSet() then
            Error(NothingErr);
        RegisteredQty := 0;
        repeat
            RegisteredQty += ActivityLine."Qty. to Handle";
        until ActivityLine.Next() = 0;
        if RegisteredQty = 0 then
            Error(NothingErr);
        ActivityLine.SetRange("Action Type");
        ActivityLine.FindFirst();
        RegisterActivity(ActivityLine);
        Context.SetResult(FindRegisteredNo(MovementNo), RegisteredQty);
    end;

    /// <summary>Returns whether the caller can write the documents and holds the warehouse posting gate.</summary>
    /// <returns>True when the caller can write the activity tables and holds BIFROST WhsePost ori.</returns>
    procedure IsEnabled(): Boolean
    var
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
    begin
        if not HasWritePermission() then
            exit(false);
        exit(WhsePostingGate.HasPostingPermission());
    end;

    /// <summary>Returns the table this message type filters.</summary>
    /// <returns>The warehouse activity line table.</returns>
    procedure GetFilterTableNo(): Integer
    begin
        exit(Database::"Warehouse Activity Line");
    end;

    /// <summary>Returns a short description of Warehouse.InventoryMovement.Register.</summary>
    /// <returns>Description of this message type.</returns>
    procedure GetDescription(): Text[250]
    var
        DescriptionLbl: Label 'Registers an inventory movement and returns the registered quantity.', Comment = 'is-IS=Skráir birgðafærslu og skilar skráða magninu.';
    begin
        exit(DescriptionLbl);
    end;

    /// <summary>Returns search keywords for this message type.</summary>
    /// <returns>Comma-separated keywords.</returns>
    procedure GetKeywords(): Text
    var
        KeywordsLbl: Label 'register inventory movement, move stock, basic warehouse, confirm bin move', Comment = 'is-IS=skrá birgðafærslu, færa birgðir, einfalt vöruhús, staðfesta hólfafærslu';
    begin
        exit(KeywordsLbl);
    end;

    /// <summary>Returns the selection description shown before the caller runs the type.</summary>
    /// <returns>Selection description.</returns>
    procedure GetSelectionDescription(): Text
    var
        SelectionLbl: Label 'Irreversible. Registers the inventory movement and Business Central commits the warehouse entries. A partial quantity leaves the rest on the movement.', Comment = 'is-IS=Óafturkræft. Skráir birgðafærsluna og Business Central staðfestir vöruhúsfærslurnar. Hluta magn skilur afganginn eftir á færslunni.';
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
        Forms.Add('movement no.');
        Forms.Add('guid');
        Envelope := Parts.RecordEnvelope(Forms, 'The inventory movement number or its SystemId. Do not send a different movement in movementNo or systemId as well.', true);
        exit(true);
    end;

    /// <summary>Returns the target chapter.</summary>
    /// <param name="Target">Receives the target entries.</param>
    /// <returns>True when a target is declared.</returns>
    procedure GetTarget(var Target: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'movement no. or SystemId', 'The inventory movement to register.'));
        Target.Add(ContractMgt.TargetEntry('data.movementNo', 'movement no.', 'The inventory movement number.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId', 'SystemId', 'The inventory movement SystemId.'));
        exit(true);
    end;

    /// <summary>Returns the parameter chapter.</summary>
    /// <param name="Parameters">Receives the parameters.</param>
    /// <returns>True when parameters are declared.</returns>
    procedure GetParameters(var Parameters: JsonArray): Boolean
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('movementNo', 'string', false, 'Inventory movement number. Required when subject and systemId are empty.'));
        Parameters.Add(ContractMgt.Parameter('systemId', 'string', false, 'Inventory movement SystemId.'));
        Parameters.Add(ContractMgt.Parameter('lines', 'array', false, 'Optional per-line quantities to handle. Omitted lines keep the quantity already on the movement.'));
        Parameters.Add(ContractMgt.Parameter('lineNo', 'integer', true, 'Inventory movement line number.'));
        Parameters.Add(ContractMgt.Parameter('qtyToHandle', 'number', true, 'Quantity to handle on that line. Zero on every line is refused.'));
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
        Fields.Add(ContractMgt.ResponseField('movementNo', 'string', 'Inventory movement number that was registered.'));
        Fields.Add(ContractMgt.ResponseField('registeredMovementNo', 'string', 'Registered inventory movement number.'));
        Fields.Add(ContractMgt.ResponseField('registeredMovementSystemId', 'string', 'Registered inventory movement SystemId.'));
        Fields.Add(ContractMgt.ResponseField('totalQtyRegistered', 'number', 'Quantity registered from the take lines.'));
        Fields.Add(ContractMgt.ResponseField('remainingLineCount', 'integer', 'Activity lines still open after a partial register.'));
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
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::RecordNotFound, 'The movement number or SystemId was not found.', 'Check the identifier with Warehouse.InventoryMovement.Create.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'The activity is not an inventory movement.', 'Use Warehouse.Movement.Register for a directed movement.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PreconditionFailed, 'Every line has zero quantity to handle.', 'Set Qty. to Handle on at least one movement line.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MissingParameter, 'movementNo and systemId are both missing.', 'Send the movement number or its SystemId.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameterFormat, 'A value has the wrong JSON type.', 'Send text for the movement number, an integer line number and a number for the quantity.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::UnknownParameter, 'The request contains a key this type does not accept.', 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::ConflictingIdentifiers, 'movementNo and systemId name different movements.', 'Send one movement.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::InvalidParameter, 'qtyToHandle is negative or greater than the outstanding quantity.', 'Send a quantity from zero up to the outstanding quantity.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::PermissionDenied, 'The caller cannot write the warehouse documents, or does not hold the warehouse posting gate.', 'Ask an administrator to assign BIFROST Whse - Full ori and BIFROST WhsePost ori.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::MultipleErrors, 'More than one value failed validation.', 'Correct every listed value and send the request again. Nothing was registered.');
        AddDeclaredError(Errors, Entry, ContractMgt, "Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected the registration.', 'Read the returned text and correct the movement.');
        exit(true);
    end;

    /// <summary>Returns the effect chapter.</summary>
    /// <param name="Effect">Receives the effect.</param>
    /// <returns>True when an effect is declared.</returns>
    procedure GetEffect(var Effect: JsonObject): Boolean
    var
        Parts: Codeunit "Whse Contract Parts ori";
    begin
        Parts.IrreversibleEffect(Effect, 'Registers an inventory movement. Business Central commits the warehouse entries.', 'BIFROST Whse - Full ori and BIFROST WhsePost ori');
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
        Related.Add(ContractMgt.RelatedEntry('Warehouse.InventoryMovement.Create', 'Use it to create the inventory movement before registering it.'));
        Related.Add(ContractMgt.RelatedEntry('Warehouse.Activity.Get', 'Use it to read an open warehouse activity.'));
        exit(true);
    end;

    /// <summary>Returns the workflow chapter.</summary>
    /// <param name="Workflow">Receives the workflow.</param>
    /// <returns>False. Inventory movement register has no separate workflow chapter.</returns>
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
            'Register inventory movement IM000001',
            '{"movementNo":"IM000001"}',
            '{"status":"Success","movementNo":"IM000001","registeredMovementNo":"RIM000001","totalQtyRegistered":1,"remainingLineCount":0}'));
        exit(true);
    end;

    /// <summary>Returns the overview.</summary>
    /// <param name="Overview">Receives the overview.</param>
    /// <returns>True when an overview is declared.</returns>
    procedure GetOverview(var Overview: Text): Boolean
    var
        OverviewLbl: Label 'Registers an inventory movement. Business Central commits the registration. Zero quantity to handle on every line registers nothing.', Comment = 'is-IS=Skráir birgðafærslu. Business Central staðfestir skráninguna. Núllmagn til meðhöndlunar á hverri línu skráir ekkert.';
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

    /// <summary>Validates the inventory movement and registers it.</summary>
    /// <param name="Argument">The request and response message argument.</param>
    procedure ExecuteBifrostTask(var Argument: Record "Message Argument ori")
    var
        ActivityHeader: Record "Warehouse Activity Header";
        Context: Codeunit "Whse Write Context ori";
        WhsePostingGate: Codeunit "Whse Posting Gate ori";
        RequestJson: JsonObject;
        Payload: JsonObject;
        PlannedLines: JsonArray;
        DeniedLbl: Label 'You do not have permission to register an inventory movement.', Comment = 'is-IS=Þú hefur ekki heimild til að skrá birgðafærslu.';
        DeniedNextStepLbl: Label 'Ask an administrator to assign BIFROST Whse - Full ori.', Comment = 'is-IS=Biddu stjórnanda um að úthluta BIFROST Whse - Full ori.';
        ProblemsLbl: Label 'Nothing was registered.', Comment = 'is-IS=Ekkert var skráð.';
        NothingLbl: Label 'Inventory movement %1 has zero quantity to handle on every line.', Comment = '%1 = movement no., is-IS=Birgðafærsla %1 er með núllmagn til meðhöndlunar á hverri línu.';
        NothingNextStepLbl: Label 'Set Qty. to Handle on at least one movement line.', Comment = 'is-IS=Settu magn til meðhöndlunar á að minnsta kosti eina færslulínu.';
    begin
        Context.Reset();
        if not HasWritePermission() then begin
            Argument.RespondWithError("Bifrost Error Code ori"::PermissionDenied, DeniedLbl, '', '', '', DeniedNextStepLbl);
            exit;
        end;
        if not WhsePostingGate.AssertCanPost(Argument) then
            exit;
        Argument.AssertIsLicensed();
        Argument.AssertVersion1();
        RequestJson := Argument.GetRequestJson();
        RefuseUnknownKeys(RequestJson, Argument);
        if not TryResolveMovement(RequestJson, Argument, ActivityHeader) then begin
            if Argument.HasCollectedErrors() then
                Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        ReadLines(RequestJson, Argument, ActivityHeader, PlannedLines);
        if not Argument.HasCollectedErrors() then
            if not HasQuantityToHandle(ActivityHeader, PlannedLines) then
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(NothingLbl, ActivityHeader."No."), 'qtyToHandle', '0', '', NothingNextStepLbl);
        if Argument.HasCollectedErrors() then begin
            Context.Reset();
            Argument.RespondWithCollectedErrors("Bifrost Error Code ori"::MultipleErrors, ProblemsLbl);
            exit;
        end;
        Payload.Add('movementNo', ActivityHeader."No.");
        Payload.Add('lines', PlannedLines);
        Context.SetPayload(Payload);
        if not Codeunit.Run(Codeunit::"Whse InvtMove Reg Impl ori") then begin
            Context.Reset();
            Argument.RespondWithLastError();
            exit;
        end;
        WriteRegisteredMovement(Argument, ActivityHeader."No.");
        Context.Reset();
    end;

    local procedure WriteRegisteredMovement(var Argument: Record "Message Argument ori"; MovementNo: Code[20])
    var
        RegisteredHeader: Record "Registered Invt. Movement Hdr.";
        ActivityLine: Record "Warehouse Activity Line";
        Context: Codeunit "Whse Write Context ori";
        ResponseJson: JsonObject;
        RegisteredNo: Code[20];
        RegisteredQty: Decimal;
    begin
        Context.TryGetResult(RegisteredNo, RegisteredQty);
        ResponseJson.Add('status', 'Success');
        ResponseJson.Add('movementNo', MovementNo);
        ResponseJson.Add('registeredMovementNo', RegisteredNo);
        RegisteredHeader.SetRange("No.", RegisteredNo);
        if RegisteredHeader.FindFirst() then
            ResponseJson.Add('registeredMovementSystemId', Format(RegisteredHeader.SystemId, 0, 4))
        else
            ResponseJson.Add('registeredMovementSystemId', '');
        ResponseJson.Add('totalQtyRegistered', RegisteredQty);
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Invt. Movement");
        ActivityLine.SetRange("No.", MovementNo);
        ResponseJson.Add('remainingLineCount', ActivityLine.Count());
        Argument.SetResponseJson(ResponseJson);
        Argument."Content Type" := Argument.GetContentTypeJson();
    end;

    local procedure HasQuantityToHandle(ActivityHeader: Record "Warehouse Activity Header"; PlannedLines: JsonArray): Boolean
    var
        ActivityLine: Record "Warehouse Activity Line";
        Token: JsonToken;
        LineObject: JsonObject;
        LineNo: Integer;
        Quantity: Decimal;
        Seen: List of [Integer];
    begin
        foreach Token in PlannedLines do begin
            LineObject := Token.AsObject();
            LineObject.Get('lineNo', Token);
            LineNo := Token.AsValue().AsInteger();
            LineObject.Get('qtyToHandle', Token);
            Quantity := Token.AsValue().AsDecimal();
            if not Seen.Contains(LineNo) then
                Seen.Add(LineNo);
            if Quantity <> 0 then
                exit(true);
        end;
        ActivityLine.SetRange("Activity Type", ActivityHeader.Type);
        ActivityLine.SetRange("No.", ActivityHeader."No.");
        if ActivityLine.FindSet() then
            repeat
                if not Seen.Contains(ActivityLine."Line No.") then
                    if ActivityLine."Qty. to Handle" <> 0 then
                        exit(true);
            until ActivityLine.Next() = 0;
        exit(false);
    end;

    local procedure TryResolveMovement(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; var ActivityHeader: Record "Warehouse Activity Header"): Boolean
    var
        ByNumber: Record "Warehouse Activity Header";
        BySystemId: Record "Warehouse Activity Header";
        Readers: Codeunit "Whse Write Context ori";
        MovementNo: Text;
        SystemIdText: Text;
        SubjectText: Text;
        Parsed: Guid;
        NumberPresent: Boolean;
        SystemPresent: Boolean;
        HasNumber: Boolean;
        HasSystem: Boolean;
        MissingLbl: Label 'movementNo or systemId is required.', Comment = 'is-IS=movementNo eða systemId er nauðsynlegt.';
        MissingNextStepLbl: Label 'Send the movement number or its SystemId.', Comment = 'is-IS=Sendu númer færslunnar eða SystemId hennar.';
        FormatLbl: Label 'systemId is not a GUID.', Comment = 'is-IS=systemId er ekki GUID.';
        FormatNextStepLbl: Label 'Send text for the movement number, an integer line number and a number for the quantity.', Comment = 'is-IS=Sendu texta fyrir færslunúmer, heiltölu fyrir línunúmer og tölu fyrir magnið.';
        NotFoundLbl: Label 'Inventory movement %1 was not found.', Comment = '%1 = identifier, is-IS=Birgðafærsla %1 fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the identifier with Warehouse.InventoryMovement.Create.', Comment = 'is-IS=Athugaðu auðkennið með Warehouse.InventoryMovement.Create.';
        ConflictLbl: Label 'movementNo and systemId name different movements.', Comment = 'is-IS=movementNo og systemId nefna mismunandi færslur.';
        ConflictNextStepLbl: Label 'Send one movement.', Comment = 'is-IS=Sendu eina færslu.';
        WrongTypeLbl: Label 'Warehouse activity %1 is not an inventory movement.', Comment = '%1 = activity no., is-IS=Vöruhúsavirkni %1 er ekki birgðafærsla.';
        WrongTypeNextStepLbl: Label 'Use Warehouse.Movement.Register for a directed movement.', Comment = 'is-IS=Notaðu Warehouse.Movement.Register fyrir beina færslu.';
    begin
        Clear(ActivityHeader);
        SubjectText := DelChr(Argument.Subject, '<>', ' ');
        if not Readers.ReadText(RequestJson, 'movementNo', MaxStrLen(ActivityHeader."No."), Argument, MovementNo, NumberPresent, 'movementNo') then
            exit(false);
        if not Readers.ReadText(RequestJson, 'systemId', 50, Argument, SystemIdText, SystemPresent, 'systemId') then
            exit(false);
        if (SubjectText <> '') and IsGuid(SubjectText) and not SystemPresent then begin
            SystemIdText := SubjectText;
            SystemPresent := true;
        end;
        if (SubjectText <> '') and (not IsGuid(SubjectText)) and (not NumberPresent) then begin
            MovementNo := SubjectText;
            NumberPresent := true;
        end;
        if NumberPresent and (SubjectText <> '') and (not IsGuid(SubjectText)) and (UpperCase(SubjectText) <> UpperCase(MovementNo)) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'movementNo', MovementNo, SubjectText, ConflictNextStepLbl);
            exit(false);
        end;
        if SystemPresent and (SubjectText <> '') and IsGuid(SubjectText) and (UpperCase(DelChr(SubjectText, '=', '{}')) <> UpperCase(DelChr(SystemIdText, '=', '{}'))) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'systemId', SystemIdText, SubjectText, ConflictNextStepLbl);
            exit(false);
        end;
        if not NumberPresent and not SystemPresent then begin
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, MissingLbl, 'movementNo', '', '', MissingNextStepLbl);
            exit(false);
        end;
        if SystemPresent then begin
            if not Evaluate(Parsed, SystemIdText) then begin
                Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'systemId', SystemIdText, 'guid', FormatNextStepLbl);
                exit(false);
            end;
            HasSystem := BySystemId.GetBySystemId(Parsed);
            if not HasSystem then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, SystemIdText), 'systemId', SystemIdText, '', NotFoundNextStepLbl);
                exit(false);
            end;
            if BySystemId.Type <> BySystemId.Type::"Invt. Movement" then begin
                Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, StrSubstNo(WrongTypeLbl, BySystemId."No."), 'systemId', SystemIdText, '', WrongTypeNextStepLbl);
                exit(false);
            end;
        end;
        if NumberPresent then begin
            HasNumber := ByNumber.Get(ByNumber.Type::"Invt. Movement", CopyStr(MovementNo, 1, MaxStrLen(ByNumber."No.")));
            if not HasNumber then begin
                Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, MovementNo), 'movementNo', MovementNo, '', NotFoundNextStepLbl);
                exit(false);
            end;
        end;
        if HasNumber and HasSystem and (ByNumber.SystemId <> BySystemId.SystemId) then begin
            Argument.AddError("Bifrost Error Code ori"::ConflictingIdentifiers, ConflictLbl, 'movementNo', MovementNo, SystemIdText, ConflictNextStepLbl);
            exit(false);
        end;
        if HasNumber then
            ActivityHeader := ByNumber
        else
            ActivityHeader := BySystemId;
        exit(true);
    end;

    local procedure ReadLines(RequestJson: JsonObject; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; var PlannedLines: JsonArray)
    var
        Token: JsonToken;
        Lines: JsonArray;
        Index: Integer;
        FormatLbl: Label 'lines must be an array of line objects.', Comment = 'is-IS=lines verður að vera fylki línuhluta.';
        FormatNextStepLbl: Label 'Send text for the movement number, an integer line number and a number for the quantity.', Comment = 'is-IS=Sendu texta fyrir færslunúmer, heiltölu fyrir línunúmer og tölu fyrir magnið.';
    begin
        Clear(PlannedLines);
        if not RequestJson.Get('lines', Token) then
            exit;
        if not Token.IsArray() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, 'lines', '', 'array', FormatNextStepLbl);
            exit;
        end;
        Lines := Token.AsArray();
        for Index := 0 to Lines.Count() - 1 do begin
            Lines.Get(Index, Token);
            ReadOneLine(Token, Index, Argument, ActivityHeader, PlannedLines);
        end;
    end;

    local procedure ReadOneLine(Token: JsonToken; Index: Integer; var Argument: Record "Message Argument ori"; ActivityHeader: Record "Warehouse Activity Header"; var PlannedLines: JsonArray)
    var
        ActivityLine: Record "Warehouse Activity Line";
        Readers: Codeunit "Whse Write Context ori";
        LineObject: JsonObject;
        PlannedLine: JsonObject;
        LineNo: Integer;
        LinePresent: Boolean;
        Quantity: Decimal;
        QuantityPresent: Boolean;
        FormatLbl: Label 'Each line must be an object.', Comment = 'is-IS=Hver lína verður að vera hlutur.';
        FormatNextStepLbl: Label 'Send text for the movement number, an integer line number and a number for the quantity.', Comment = 'is-IS=Sendu texta fyrir færslunúmer, heiltölu fyrir línunúmer og tölu fyrir magnið.';
        MissingLbl: Label 'Line %1 is missing %2.', Comment = '%1 = line index, %2 = field, is-IS=Línu %1 vantar %2.';
        MissingNextStepLbl: Label 'Send lineNo and qtyToHandle on every line.', Comment = 'is-IS=Sendu lineNo og qtyToHandle á hverri línu.';
        NotFoundLbl: Label 'Inventory movement line %1 was not found.', Comment = '%1 = line no., is-IS=Lína %1 í birgðafærslu fannst ekki.';
        NotFoundNextStepLbl: Label 'Check the identifier with Warehouse.InventoryMovement.Create.', Comment = 'is-IS=Athugaðu auðkennið með Warehouse.InventoryMovement.Create.';
        RangeLbl: Label 'qtyToHandle must be from zero up to the outstanding quantity.', Comment = 'is-IS=qtyToHandle verður að vera frá núlli upp í útistandandi magn.';
        RangeNextStepLbl: Label 'Send a quantity from zero up to the outstanding quantity.', Comment = 'is-IS=Sendu magn frá núlli upp í útistandandi magn.';
    begin
        if not Token.IsObject() then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameterFormat, FormatLbl, LineParameter(Index, 'lineNo'), '', 'object', FormatNextStepLbl);
            exit;
        end;
        LineObject := Token.AsObject();
        RefuseUnknownLineKeys(LineObject, Index, Argument);
        Readers.ReadInteger(LineObject, 'lineNo', Argument, LineNo, LinePresent, LineParameter(Index, 'lineNo'));
        Readers.ReadDecimal(LineObject, 'qtyToHandle', Argument, Quantity, QuantityPresent, LineParameter(Index, 'qtyToHandle'));
        if not LinePresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'lineNo'), LineParameter(Index, 'lineNo'), '', '', MissingNextStepLbl);
        if not QuantityPresent then
            Argument.AddError("Bifrost Error Code ori"::MissingParameter, StrSubstNo(MissingLbl, Index, 'qtyToHandle'), LineParameter(Index, 'qtyToHandle'), '', '', MissingNextStepLbl);
        if not LinePresent or not QuantityPresent then
            exit;
        if not ActivityLine.Get(ActivityHeader.Type, ActivityHeader."No.", LineNo) then begin
            Argument.AddError("Bifrost Error Code ori"::RecordNotFound, StrSubstNo(NotFoundLbl, LineNo), LineParameter(Index, 'lineNo'), Format(LineNo), '', NotFoundNextStepLbl);
            exit;
        end;
        if (Quantity < 0) or (Quantity > ActivityLine."Qty. Outstanding") then begin
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, RangeLbl, LineParameter(Index, 'qtyToHandle'), Format(Quantity), Format(ActivityLine."Qty. Outstanding"), RangeNextStepLbl);
            exit;
        end;
        PlannedLine.Add('lineNo', LineNo);
        PlannedLine.Add('qtyToHandle', Quantity);
        PlannedLines.Add(PlannedLine);
    end;

    local procedure RefuseUnknownKeys(RequestJson: JsonObject; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in RequestJson.Keys() do
            if not (KeyName in ['movementNo', 'systemId', 'lines']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), KeyName, KeyName, '', UnknownNextStepLbl);
    end;

    local procedure RefuseUnknownLineKeys(LineObject: JsonObject; Index: Integer; var Argument: Record "Message Argument ori")
    var
        KeyName: Text;
        UnknownLbl: Label 'The key %1 is not a parameter of this message type.', Comment = '%1 = key, is-IS=Lykillinn %1 er ekki færibreyta þessarar skilaboðagerðar.';
        UnknownNextStepLbl: Label 'Remove the unknown key. Read Help.Implementation.Get for the declared parameters.', Comment = 'is-IS=Fjarlægðu óþekkta lykilinn. Lestu Help.Implementation.Get fyrir skilgreindar færibreytur.';
    begin
        foreach KeyName in LineObject.Keys() do
            if not (KeyName in ['lineNo', 'qtyToHandle']) then
                Argument.AddError("Bifrost Error Code ori"::UnknownParameter, StrSubstNo(UnknownLbl, KeyName), LineParameter(Index, KeyName), KeyName, '', UnknownNextStepLbl);
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
        exit(StrSubstNo(LineParameterLbl, Index, KeyName));
    end;

    local procedure AddDeclaredError(var Errors: JsonArray; var Entry: JsonObject; ContractMgt: Codeunit "Msg Contract Mgt ori"; ErrorCode: Enum "Bifrost Error Code ori"; WhenText: Text; NextStep: Text)
    begin
        Clear(Entry);
        Entry := ContractMgt.ErrorEntry(ErrorCode, WhenText, NextStep);
        Entry.Add('nextStep', NextStep);
        Errors.Add(Entry);
    end;

    local procedure RegisterActivity(var ActivityLine: Record "Warehouse Activity Line")
    var
        WhseActivityRegister: Codeunit "Whse.-Activity-Register";
    begin
        // Hide the dialog so a partial line is reduced without a UI confirm after codeunit 7307 commits.
        WhseActivityRegister.ShowHideDialog(true);
        WhseActivityRegister.Run(ActivityLine);
    end;

    local procedure ApplyQuantities(Payload: JsonObject; MovementNo: Code[20])
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
            ApplyOneQuantity(LineObject, MovementNo);
        end;
    end;

    local procedure ApplyOneQuantity(LineObject: JsonObject; MovementNo: Code[20])
    var
        ActivityLine: Record "Warehouse Activity Line";
        Sibling: Record "Warehouse Activity Line";
        Outstanding: Decimal;
        MatchCount: Integer;
        MatchLineNo: Integer;
    begin
        ActivityLine.Get(ActivityLine."Activity Type"::"Invt. Movement", MovementNo, IntegerValue(LineObject, 'lineNo'));
        Outstanding := ActivityLine."Qty. Outstanding";
        ActivityLine.Validate("Qty. to Handle", DecimalValue(LineObject, 'qtyToHandle'));
        ActivityLine.Modify(true);
        Sibling.SetRange("Activity Type", ActivityLine."Activity Type");
        Sibling.SetRange("No.", ActivityLine."No.");
        Sibling.SetRange("Item No.", ActivityLine."Item No.");
        Sibling.SetRange("Variant Code", ActivityLine."Variant Code");
        Sibling.SetRange("Unit of Measure Code", ActivityLine."Unit of Measure Code");
        if not Sibling.FindSet() then
            exit;
        repeat
            if (Sibling."Line No." <> ActivityLine."Line No.") and (Sibling."Qty. Outstanding" = Outstanding) then begin
                MatchCount += 1;
                MatchLineNo := Sibling."Line No.";
            end;
        until Sibling.Next() = 0;
        if MatchCount <> 1 then
            exit;
        Sibling.Get(ActivityLine."Activity Type", ActivityLine."No.", MatchLineNo);
        Sibling.Validate("Qty. to Handle", ActivityLine."Qty. to Handle");
        Sibling.Modify(true);
    end;

    local procedure FindRegisteredNo(MovementNo: Code[20]): Code[20]
    var
        RegisteredHeader: Record "Registered Invt. Movement Hdr.";
    begin
        RegisteredHeader.SetRange("Invt. Movement No.", MovementNo);
        if RegisteredHeader.FindLast() then
            exit(RegisteredHeader."No.");
        exit('');
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
        exit(Token.AsValue().AsDecimal());
    end;

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(0);
        exit(Token.AsValue().AsInteger());
    end;

    local procedure HasWritePermission(): Boolean
    var
        ActivityHeader: Record "Warehouse Activity Header";
        ActivityLine: Record "Warehouse Activity Line";
        RegisteredHeader: Record "Registered Invt. Movement Hdr.";
    begin
        exit(ActivityHeader.WritePermission() and ActivityLine.WritePermission() and RegisteredHeader.WritePermission());
    end;
}
