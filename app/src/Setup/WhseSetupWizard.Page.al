namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;
using System.Security.AccessControl;
using System.Security.User;

/// <summary>Explains Warehouse operations, HTTP through Foundation, and the permissions administrators assign.</summary>
page 10078385 "Whse Setup Wizard ori"
{
    PageType = NavigatePage;
    Extensible = false;
    ApplicationArea = All;
    InsertAllowed = false;
    DeleteAllowed = false;
    ContextSensitiveHelpPage = 'warehouse-setup-wizard';
    Caption = 'Set up Bifrost Warehouse', Comment = 'is-IS=Setja upp Bifröst vöruhús';

    layout
    {
        area(Content)
        {
            group(Welcome)
            {
                Visible = CurrentStep = 1;
                Caption = 'Welcome to Bifrost Warehouse', Comment = 'is-IS=Velkomin í Bifröst vöruhús';
                InstructionalText = 'Warehouse adds bin content and open warehouse activities, receipts and shipments from creation through preview to posting, and picks and put-aways from creation to registering, in the Warehouse domain.', Comment = 'is-IS=Vöruhús bætir við hólfainnihaldi og opnum vöruhúsaaðgerðum, móttökum og afhendingum frá stofnun, í gegnum forskoðun, til bókunar og tínslum og frágangi frá stofnun til skráningar á sviðinu Warehouse.';
                group(AssistantAccess)
                {
                    ShowCaption = false;
                    InstructionalText = 'AI assistants and other systems reach these operations through Bifrost, as the signed-in user and within their permissions. Installed operations are listed on the Bifrost Message Types page.', Comment = 'is-IS=Gervigreindaraðstoð og önnur kerfi nálgast þessar aðgerðir í gegnum Bifröst í nafni innskráðs notanda og innan heimilda hans. Uppsettar aðgerðir eru skráðar á síðunni Skilaboðategundir Bifröst.';
                }
            }
            group(Http)
            {
                Visible = CurrentStep = 2;
                Caption = 'HTTP through Bifrost Setup', Comment = 'is-IS=HTTP í gegnum Bifröst uppsetningu';
                InstructionalText = 'Bifrost needs outbound HTTP for licensing. Foundation enables Allow HttpClient Requests; this wizard only reads the setting for Bifrost Warehouse.', Comment = 'is-IS=Bifröst þarf HTTP út á við fyrir leyfisveitingu. Grunnkerfið virkjar Leyfa HttpClient-beiðnir; þessi leiðsögn les aðeins stillinguna fyrir Bifröst vöruhús.';
                field(HttpEnabled; HttpEnabled)
                {
                    Caption = 'HTTP enabled', Comment = 'is-IS=HTTP virkt';
                    ToolTip = 'Shows whether Allow HttpClient Requests is enabled for Bifrost Warehouse.', Comment = 'is-IS=Sýnir hvort Leyfa HttpClient-beiðnir sé virkt fyrir Bifröst vöruhús.';
                    Editable = false;
                }
                field(HttpPermissionNote; HttpPermissionNoteLbl)
                {
                    ShowCaption = false;
                    Editable = false;
                    MultiLine = true;
                    Visible = not CanWriteAppSetting;
                    ToolTip = 'Explains who can enable HTTP for Bifrost Warehouse.', Comment = 'is-IS=Útskýrir hver getur virkjað HTTP fyrir Bifröst vöruhús.';
                }
            }
            group(Access)
            {
                Visible = CurrentStep = 3;
                Caption = 'User access', Comment = 'is-IS=Aðgangur notenda';
                InstructionalText = 'Users also need the Foundation Bifrost permission sets. Assign sets to users directly or through a Microsoft Entra security group. This wizard does not assign permissions.', Comment = 'is-IS=Notendur þurfa einnig Bifröst-heimildasamstæður grunnkerfisins. Úthlutaðu samstæðum beint til notenda eða í gegnum Microsoft Entra öryggishóp. Þessi leiðsögn úthlutar ekki heimildum.';
                group(PostingAccess)
                {
                    ShowCaption = false;
                    InstructionalText = 'BIFROST WhsePost ori: allows warehouse posting and activity registration.', Comment = 'is-IS=BIFROST WhsePost ori: heimilar bókun vöruhúss og skráningu vöruhúsaaðgerða.';
                }
                group(InvoiceAccess)
                {
                    ShowCaption = false;
                    InstructionalText = 'BIFROST WhseInv ori: additionally allows invoicing when a warehouse shipment is posted.', Comment = 'is-IS=BIFROST WhseInv ori: heimilar einnig reikningsfærslu þegar vöruhúsaafhending er bókuð.';
                }
            }
            group(Summary)
            {
                Visible = CurrentStep = 4;
                Caption = 'Ready to finish', Comment = 'is-IS=Tilbúið til að ljúka';
                InstructionalText = 'Review the summary. Finish marks this assisted setup complete, including when HTTP still needs an administrator. You can run the wizard again later.', Comment = 'is-IS=Farðu yfir yfirlitið. Ljúka merkir þessa leiðsögn sem lokið, einnig þegar HTTP þarfnast enn stjórnanda. Þú getur keyrt leiðsögnina aftur síðar.';
                field(WelcomeSummary; DoneLbl)
                {
                    Caption = 'Warehouse operations', Comment = 'is-IS=Vöruhúsaaðgerðir';
                    ToolTip = 'Confirms that the Warehouse operations have been described.', Comment = 'is-IS=Staðfestir að vöruhúsaaðgerðunum hafi verið lýst.';
                    Editable = false;
                }
                field(HttpSummary; HttpSummary)
                {
                    Caption = 'HTTP', Comment = 'is-IS=HTTP';
                    ToolTip = 'Shows whether HTTP is enabled or needs an administrator.', Comment = 'is-IS=Sýnir hvort HTTP sé virkt eða þarfnist stjórnanda.';
                    Editable = false;
                }
                field(AccessSummary; DoneLbl)
                {
                    Caption = 'Access guidance', Comment = 'is-IS=Leiðbeiningar um aðgang';
                    ToolTip = 'Confirms that the permission sets and assignment options have been described.', Comment = 'is-IS=Staðfestir að heimildasamstæðum og úthlutunarmöguleikum hafi verið lýst.';
                    Editable = false;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Back)
            {
                Caption = 'Back', Comment = 'is-IS=Til baka';
                ToolTip = 'Go to the previous step.', Comment = 'is-IS=Fara í fyrra skref.';
                Image = PreviousRecord;
                InFooterBar = true;
                Visible = CurrentStep > 1;

                trigger OnAction()
                begin
                    CurrentStep -= 1;
                end;
            }
            action(Next)
            {
                Caption = 'Next', Comment = 'is-IS=Áfram';
                ToolTip = 'Go to the next step.', Comment = 'is-IS=Fara í næsta skref.';
                Image = NextRecord;
                InFooterBar = true;
                Visible = CurrentStep < 4;

                trigger OnAction()
                begin
                    CurrentStep += 1;
                    RefreshStatus();
                end;
            }
            action(Finish)
            {
                Caption = 'Finish', Comment = 'is-IS=Ljúka';
                ToolTip = 'Mark the Warehouse assisted setup complete.', Comment = 'is-IS=Merkja leiðsögn Vöruhúss sem lokið.';
                Image = Approve;
                InFooterBar = true;
                Visible = CurrentStep = 4;

                trigger OnAction()
                begin
                    WizardMgt.Finish();
                    CurrPage.Close();
                end;
            }
            action(ShowOperations)
            {
                Caption = 'Show operations', Comment = 'is-IS=Sýna aðgerðir';
                ToolTip = 'Open the installed Bifrost operations.', Comment = 'is-IS=Opna uppsettar Bifröst-aðgerðir.';
                Image = List;
                InFooterBar = true;
                Visible = CurrentStep = 1;

                trigger OnAction()
                begin
                    Page.RunModal(Page::"Message Type List ori");
                end;
            }
            action(Documentation)
            {
                Caption = 'Documentation', Comment = 'is-IS=Skjölun';
                ToolTip = 'Open the Warehouse documentation.', Comment = 'is-IS=Opna skjölun Vöruhúss.';
                Image = Help;
                InFooterBar = true;
                Visible = CurrentStep = 1;

                trigger OnAction()
                begin
                    Hyperlink('https://docs.bifrost.origo.is/en-us/warehouse/');
                end;
            }
            action(EnableHttp)
            {
                Caption = 'Enable HTTP in Bifrost Setup', Comment = 'is-IS=Virkja HTTP í Bifröst uppsetningu';
                ToolTip = 'Open Foundation setup, then refresh this app’s HTTP status.', Comment = 'is-IS=Opna uppsetningu grunnkerfisins og endurnýja svo HTTP-stöðu þessa forrits.';
                Image = Setup;
                InFooterBar = true;
                Visible = (CurrentStep = 2) and not HttpEnabled;

                trigger OnAction()
                begin
                    Page.RunModal(Page::"Setup Wizard ori");
                    RefreshStatus();
                end;
            }
            action(Verify)
            {
                Caption = 'Verify', Comment = 'is-IS=Staðfesta';
                ToolTip = 'Refresh the HTTP status for this app.', Comment = 'is-IS=Endurnýja HTTP-stöðu þessa forrits.';
                Image = Refresh;
                InFooterBar = true;
                Visible = CurrentStep = 2;

                trigger OnAction()
                begin
                    RefreshStatus();
                end;
            }
            action(OpenUsers)
            {
                Caption = 'Open Users', Comment = 'is-IS=Opna notendur';
                ToolTip = 'Open the standard Users page to manage user access.', Comment = 'is-IS=Opna staðlaða notendasíðu til að stjórna aðgangi.';
                Image = Users;
                InFooterBar = true;
                Visible = CurrentStep = 3;

                trigger OnAction()
                begin
                    Page.RunModal(Page::Users);
                end;
            }
            action(OpenPermissionSets)
            {
                Caption = 'Open Permission Sets', Comment = 'is-IS=Opna heimildasamstæður';
                ToolTip = 'Open the standard Permission Sets page.', Comment = 'is-IS=Opna staðlaða síðu heimildasamstæðna.';
                Image = Setup;
                InFooterBar = true;
                Visible = CurrentStep = 3;

                trigger OnAction()
                begin
                    Page.RunModal(Page::"Permission Sets");
                end;
            }
        }
    }

    var
        WizardMgt: Codeunit "Whse Wizard Mgt ori";
        CurrentStep: Integer;
        HttpEnabled: Boolean;
        CanWriteAppSetting: Boolean;
        HttpSummary: Text;
        HttpPermissionNoteLbl: Label 'You do not have permission to change extension settings. Ask an administrator with the SUPER permission set (or write permission on table NAV App Setting) to enable Allow HttpClient Requests for Bifrost Warehouse.', Comment = 'is-IS=Þú hefur ekki heimild til að breyta stillingum viðbóta. Biddu kerfisstjóra sem hefur SUPER heimildasamstæðuna (eða skrifheimild á töfluna NAV App Setting) um að virkja Leyfa HttpClient-beiðnir fyrir Bifröst vöruhús.';
        DoneLbl: Label 'Done', Comment = 'is-IS=Lokið';
        AdministratorLbl: Label 'Needs an administrator', Comment = 'is-IS=Þarf stjórnanda';

    trigger OnOpenPage()
    begin
        CurrentStep := 1;
        RefreshStatus();
    end;

    local procedure RefreshStatus()
    begin
        HttpEnabled := WizardMgt.IsHttpEnabled();
        CanWriteAppSetting := WizardMgt.CanEnableHttp();
        if HttpEnabled then
            HttpSummary := DoneLbl
        else
            HttpSummary := AdministratorLbl;
        CurrPage.Update(false);
    end;
}
