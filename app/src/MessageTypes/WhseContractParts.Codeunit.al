namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Shared contract chapters for the Warehouse message types.
/// </summary>
codeunit 10078459 "Whse Contract Parts ori"
{
    Access = Internal;

    internal procedure RecordEnvelope(SubjectForms: List of [Text]; SubjectDescription: Text; DataRequired: Boolean): JsonObject
    var
        Envelope: JsonObject;
        Subject: JsonObject;
        Forms: JsonArray;
        Form: Text;
    begin
        foreach Form in SubjectForms do
            Forms.Add(Form);
        Subject.Add('use', 'optional');
        Subject.Add('forms', Forms);
        Subject.Add('description', SubjectDescription);
        Envelope.Add('subject', Subject);
        Envelope.Add('dataRequired', DataRequired);
        Envelope.Add('version', '1.0');
        Envelope.Add('contentType', 'text/json');
        exit(Envelope);
    end;

    internal procedure RecordTarget(RecordName: Text; DataKeys: Text): JsonArray
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Target: JsonArray;
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the ' + RecordName + '.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'document no.', 'The No. of the ' + RecordName + '.'));
        Target.Add(ContractMgt.TargetEntry('data.' + DataKeys, 'guid or document no.', 'The identifier keys accepted for the ' + RecordName + '. Every supplied identifier is tried; conflicting identifiers are refused.'));
        exit(Target);
    end;

    internal procedure ActivityTarget(ActivityName: Text; NumberKey: Text): JsonArray
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
        Target: JsonArray;
    begin
        Target.Add(ContractMgt.TargetEntry('subject', 'guid', 'The SystemId of the Warehouse Activity Header.'));
        Target.Add(ContractMgt.TargetEntry('subject', 'activity no.', 'The number of the ' + ActivityName + '.'));
        Target.Add(ContractMgt.TargetEntry('data.systemId, data.recordSystemId, data.id', 'guid', 'The SystemId of the Warehouse Activity Header.'));
        Target.Add(ContractMgt.TargetEntry('data.' + NumberKey + ', data.no', 'activity no.', 'The number of the ' + ActivityName + '.'));
        exit(Target);
    end;

    internal procedure AddPagingParameters(var Parameters: JsonArray)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('skip', 'integer', false, 'Number of matching records to skip. Defaults to 0.'));
        Parameters.Add(ContractMgt.Parameter('take', 'integer', false, 'Maximum number of records to return. Defaults to the platform page size.'));
    end;

    internal procedure AddLookupErrors(var Errors: JsonArray; RecordName: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::MissingParameter, 'No ' + RecordName + ' identifier was supplied.', 'Send subject or an identifier under data.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::RecordNotFound, 'The supplied identifier does not match a ' + RecordName + '.', 'Check the value or look the record up first.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::ConflictingIdentifiers, 'Two identifiers point to different records.', 'Send one identifier or identifiers for the same record.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameterFormat, 'An identifier cannot be read in the expected format.', 'Send a GUID for SystemId keys and a document number for No. keys.'));
    end;

    internal procedure AddBusinessCentralError(var Errors: JsonArray; TypicalCauses: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::BusinessCentralError, 'Business Central''s own error text.', 'Read the returned text; it names the field or setup to fix. Typical causes: ' + TypicalCauses));
    end;

    internal procedure AddPermissionError(var Errors: JsonArray; PermissionSetName: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PermissionDenied, 'The caller lacks ' + PermissionSetName + '.', 'Ask an administrator to assign ' + PermissionSetName + '.'));
    end;

    internal procedure AddSourceDocumentErrors(var Errors: JsonArray; SourceKinds: Text)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Errors.Add(ContractMgt.TextErrorEntry('sourceDocuments is required and must contain at least one entry.', 'The request has no source documents.', 'Send at least one source document.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::RecordNotFound, 'A source document does not exist.', 'Check each sourceType and documentNo.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::PreconditionFailed, 'A source document is not Released or cannot be routed to a warehouse document.', 'Release the source and enable the required location routing.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::InvalidParameter, 'sourceType is not one of: ' + SourceKinds + '.', 'Use one of the documented sourceType values.'));
        Errors.Add(ContractMgt.ErrorEntry("Bifrost Error Code ori"::BusinessCentralError, 'Business Central rejected source document creation.', 'Read the returned error text and correct the source document or setup.'));
    end;

    internal procedure AddActivityParameters(var Parameters: JsonArray; IncludeOptions: Boolean)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Parameters.Add(ContractMgt.Parameter('assignedUserId', 'string', false, 'User assigned to the created Warehouse Activity Header.'));
        Parameters.Add(ContractMgt.Parameter('sortingMethod', 'string', false, 'Warehouse activity sorting method.'));
        if IncludeOptions then begin
            Parameters.Add(ContractMgt.Parameter('setBreakbulkFilter', 'boolean', false, 'Must be false; true is rejected because the report request-page option is not supported.'));
            Parameters.Add(ContractMgt.Parameter('doNotFillQtyToHandle', 'boolean', false, 'Must be false; true is rejected because the report request-page option is not supported.'));
        end;
    end;

    internal procedure ReadEffect(var Effect: JsonObject; Changes: Text; PermissionSetName: Text)
    begin
        Effect.Add('effect', 'read');
        Effect.Add('changes', Changes);
        Effect.Add('idempotent', true);
        Effect.Add('permissionSet', PermissionSetName);
    end;

    internal procedure WriteEffect(var Effect: JsonObject; Changes: Text; PermissionSetName: Text; Idempotent: Boolean)
    begin
        Effect.Add('effect', 'write');
        Effect.Add('changes', Changes);
        Effect.Add('idempotent', Idempotent);
        Effect.Add('permissionSet', PermissionSetName);
    end;

    internal procedure IrreversibleEffect(var Effect: JsonObject; Changes: Text; PermissionSetName: Text)
    begin
        Effect.Add('effect', 'irreversible');
        Effect.Add('changes', Changes);
        Effect.Add('idempotent', false);
        Effect.Add('permissionSet', PermissionSetName);
    end;

    internal procedure Response(var Response: JsonObject; Fields: JsonArray)
    begin
        Response.Add('contentType', 'text/json');
        Response.Add('fields', Fields);
    end;

    internal procedure AddStatusField(var Fields: JsonArray)
    var
        ContractMgt: Codeunit "Msg Contract Mgt ori";
    begin
        Fields.Add(ContractMgt.ResponseField('status', 'string', 'Success on a successful call; Error responses use the standard error envelope.'));
    end;
}
