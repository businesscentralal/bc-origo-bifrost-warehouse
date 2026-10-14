namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>Registers Warehouse's own legacy posting permission-set migration pair.</summary>
codeunit 10078460 "Whse PermSet Pairs ori"
{
    Access = Internal;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Take-Over ori", OnRegisterPermissionSetPairs, '', false, false)]
    local procedure OnRegisterPermissionSetPairs(var Registry: Codeunit "TakeOver PermSet Registry ori")
    begin
        Registry.Add('CE Whse Post ori', 'BIFROST WhsePost ori');
    end;
}
