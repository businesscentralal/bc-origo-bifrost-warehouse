# Set up with the wizard

In **Assisted Setup**, open **Set up Bifrost Warehouse** in **Extensions**.

1. Review Warehouse operations: bin content, open activities, receipts and shipments, picks and put-aways. AI assistants and integrations use these operations as the signed-in user, within that user's permissions. **Show operations** opens Bifrost Message Types. **Documentation** opens the Warehouse documentation.
2. Check **HTTP enabled**. **Enable HTTP in Bifrost Setup** opens Foundation's wizard; Foundation owns the HTTP change. Return and choose **Verify** to read the current setting. Ask an administrator if extension settings are restricted.
3. Review access. `BIFROST WhsePost ori` allows warehouse posting and activity registration; `BIFROST WhseInv ori` additionally allows invoicing a posted shipment. Users also need Foundation's Bifrost sets. Assign permissions on **Users** or through an Entra security group. The wizard never assigns them.
4. Review the summary and choose **Finish** to mark this assisted setup complete. Closing early leaves completion unchanged. You may rerun the wizard later.

Warehouse and its test app never write HTTP settings or record consent. Follow Foundation's explicit administrator flow when HTTP needs enabling.

## Setja upp með leiðsögn

Í **Aðstoðaðri uppsetningu**, opnaðu **Setja upp Bifröst vöruhús** undir **Viðbætur**. Farðu yfir vöruhúsaaðgerðir, athugaðu HTTP í gegnum Bifröst uppsetningu og kynntu þér heimildasamstæðurnar. **BIFROST WhsePost ori** heimilar bókun og skráningu vöruhúsaaðgerða; **BIFROST WhseInv ori** heimilar einnig reikningsfærslu afhendinga. Notendur þurfa einnig heimildasamstæður grunnkerfisins. Veldu **Ljúka** til að merkja leiðsögnina sem lokið. Að loka fyrr breytir ekki fyrri lokastöðu. Leiðsögnin úthlutar hvorki heimildum né breytir HTTP-stillingum.
