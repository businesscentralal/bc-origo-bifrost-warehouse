namespace Origo.Bifrost.Warehouse;

using System.Environment.Configuration;
using System.Media;

/// <summary>Registers Warehouse assisted setup without changing any application settings.</summary>
codeunit 10078385 "Whse Wizard Reg. ori"
{
    Access = Internal;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Guided Experience", OnRegisterAssistedSetup, '', false, false)]
    local procedure RegisterWizard()
    var
        GuidedExperience: Codeunit "Guided Experience";
        TitleLbl: Label 'Set up Bifrost Warehouse', Comment = 'is-IS=Setja upp Bifröst vöruhús';
        ShortTitleLbl: Label 'Bifrost Warehouse', Comment = 'is-IS=Bifröst vöruhús';
        DescriptionLbl: Label 'Learn what Warehouse adds to Bifrost, check HTTP through Bifrost Setup, and review user access.', Comment = 'is-IS=Kynntu þér hvað Vöruhús bætir við Bifröst, athugaðu HTTP í Bifröst uppsetningu og farðu yfir aðgang notenda.';
    begin
        GuidedExperience.InsertAssistedSetup(TitleLbl, ShortTitleLbl, DescriptionLbl, 5,
            ObjectType::Page, Page::"Whse Setup Wizard ori", Enum::"Assisted Setup Group"::Extensions,
            '', Enum::"Video Category"::Uncategorized, 'https://docs.bifrost.origo.is/en-us/warehouse/');
    end;
}
