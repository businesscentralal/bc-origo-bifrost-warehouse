namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;

/// <summary>
/// Creates isolated warehouse records for message-type tests.
/// </summary>
codeunit 97002 "Whse Test Data ori"
{
    Access = Internal;

    /// <summary>Creates a Bin Content fixture.</summary>
    /// <param name="LocationCode">The location for the fixture.</param>
    /// <param name="BinCode">The bin for the fixture.</param>
    /// <param name="ItemNo">The item number for the fixture.</param>
    /// <param name="VariantCode">The variant for the fixture.</param>
    /// <param name="UnitOfMeasureCode">The unit of measure for the fixture.</param>
    procedure CreateBinContent(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UnitOfMeasureCode: Code[10])
    var
        BinContent: Record "Bin Content";
    begin
        BinContent.Init();
        BinContent."Location Code" := LocationCode;
        BinContent."Bin Code" := BinCode;
        BinContent."Item No." := ItemNo;
        BinContent."Variant Code" := VariantCode;
        BinContent."Unit of Measure Code" := UnitOfMeasureCode;
        BinContent."Zone Code" := 'ZONE-01';
        BinContent."Bin Type Code" := 'PICK';
        BinContent.Insert(false);
    end;

    /// <summary>Creates an open warehouse activity header and line.</summary>
    /// <param name="ActivityType">The type of warehouse activity.</param>
    /// <param name="ActivityNo">The activity number.</param>
    /// <param name="LocationCode">The activity location.</param>
    /// <param name="AssignedUserId">The assigned user ID.</param>
    /// <param name="WhseDocumentNo">The source warehouse document number.</param>
    procedure CreateActivity(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; LocationCode: Code[10]; AssignedUserId: Code[50]; WhseDocumentNo: Code[20])
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        CreateActivityHeader(ActivityType, ActivityNo, LocationCode, AssignedUserId);
        ActivityLine.Init();
        ActivityLine."Activity Type" := ActivityType;
        ActivityLine."No." := ActivityNo;
        ActivityLine."Line No." := 10000;
        ActivityLine."Item No." := '1000';
        ActivityLine."Bin Code" := 'B-01-01';
        ActivityLine."Zone Code" := 'BULK';
        ActivityLine."Unit of Measure Code" := 'PCS';
        ActivityLine."Qty. to Handle" := 5;
        ActivityLine."Action Type" := Enum::"Warehouse Action Type"::Take;
        ActivityLine."Whse. Document Type" := Enum::"Warehouse Activity Document Type"::Shipment;
        ActivityLine."Whse. Document No." := WhseDocumentNo;
        ActivityLine."Whse. Document Line No." := 10000;
        ActivityLine.Insert(false);
    end;

    /// <summary>Creates an open warehouse activity header without lines.</summary>
    /// <param name="ActivityType">The type of warehouse activity.</param>
    /// <param name="ActivityNo">The activity number.</param>
    /// <param name="LocationCode">The activity location.</param>
    /// <param name="AssignedUserId">The assigned user ID.</param>
    procedure CreateActivityHeader(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; LocationCode: Code[10]; AssignedUserId: Code[50])
    var
        ActivityHeader: Record "Warehouse Activity Header";
    begin
        ActivityHeader.Init();
        ActivityHeader.Type := ActivityType;
        ActivityHeader."No." := ActivityNo;
        ActivityHeader."Location Code" := LocationCode;
        ActivityHeader."Assigned User ID" := AssignedUserId;
        ActivityHeader.Insert(false);
    end;
}