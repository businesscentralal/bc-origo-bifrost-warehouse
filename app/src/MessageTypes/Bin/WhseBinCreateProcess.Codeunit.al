namespace Origo.Bifrost.Warehouse;

using Microsoft.Warehouse.Structure;

/// <summary>
/// Inserts already validated bins. Runs through Codeunit.Run so a platform error rolls the inserts back.
/// </summary>
codeunit 10078462 "Whse Bin Create Process ori"
{
    Access = Internal;

    trigger OnRun()
    var
        Context: Codeunit "Whse Bin Write Context ori";
        Payload: JsonObject;
        Bins: JsonArray;
        BinToken: JsonToken;
        MissingPayloadErr: Label 'The bin create payload was empty.', Comment = 'is-IS=Gögnin til að stofna hólf voru tóm.';
    begin
        if not Context.TryGetPayload(Payload) then
            Error(MissingPayloadErr);
        if not Payload.Get('bins', BinToken) then
            Error(MissingPayloadErr);
        Bins := BinToken.AsArray();
        foreach BinToken in Bins do
            InsertBin(Payload, BinToken.AsObject());
    end;

    local procedure InsertBin(Payload: JsonObject; BinObject: JsonObject)
    var
        Bin: Record Bin;
        LocationToken: JsonToken;
        Token: JsonToken;
    begin
        Bin.Init();
        Payload.Get('locationCode', LocationToken);
        Bin.Validate("Location Code", CopyStr(LocationToken.AsValue().AsText(), 1, MaxStrLen(Bin."Location Code")));
        BinObject.Get('code', Token);
        Bin.Validate(Code, CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin.Code)));
        if BinObject.Get('description', Token) then
            if Token.AsValue().AsText() <> '' then
                Bin.Validate(Description, CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin.Description)));
        if BinObject.Get('zoneCode', Token) then
            if Token.AsValue().AsText() <> '' then
                Bin.Validate("Zone Code", CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin."Zone Code")));
        if BinObject.Get('binTypeCode', Token) then
            if Token.AsValue().AsText() <> '' then
                Bin.Validate("Bin Type Code", CopyStr(Token.AsValue().AsText(), 1, MaxStrLen(Bin."Bin Type Code")));
        if BinObject.Get('ranking', Token) then
            Bin.Validate("Bin Ranking", Token.AsValue().AsInteger());
        if BinObject.Get('blockMovement', Token) then
            ValidateBlockMovement(Bin, Token.AsValue().AsText());
        if BinObject.Get('dedicated', Token) then
            if Token.AsValue().AsBoolean() then
                Bin.Validate(Dedicated, true);
        Bin.Insert(true);
    end;

    local procedure ValidateBlockMovement(var Bin: Record Bin; BlockText: Text)
    begin
        case UpperCase(BlockText) of
            'INBOUND':
                Bin.Validate("Block Movement", Bin."Block Movement"::Inbound);
            'OUTBOUND':
                Bin.Validate("Block Movement", Bin."Block Movement"::Outbound);
            'ALL':
                Bin.Validate("Block Movement", Bin."Block Movement"::All);
            else
                Bin.Validate("Block Movement", Bin."Block Movement"::" ");
        end;
    end;
}
