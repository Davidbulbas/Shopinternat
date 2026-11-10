# ShopInternat — sistem reduceri (implementare de test)

## Reguli confirmate
- O singură reducere pe comandă; automat cea mai mare, cu opțiune de selectare a altei reduceri sau de eliminare.
- Fidelitate: câte 10 MDL pentru fiecare 5 comenzi cu status delivered și payment_status approved. Fiecare grup de 5 comenzi poate genera o singură recompensă, care poate fi folosită o singură dată.
- Invitație: 5 MDL pentru persoana care invită și 5 MDL pentru persoana invitată după prima comandă eligibilă a invitatului, achitată și livrată; fără auto-invitații și fără recompense duplicate.
- Bun venit: 5 MDL pentru prima comandă de cel puțin 50 MDL, eligibilitatea verificată pe server. Pragul se calculează înaintea reducerii.
- Reducerea nu poate depăși valoarea produselor. Toate sumele în MDL, rotunjite la 2 zecimale.
- La checkout: subtotal, denumire reducere, valoare reducere, total de transferat prin MIA. Suma trebuie calculată server-side, nu acceptată de la client.
- La anulare: eliberează recompensa rezervată; la editare: recalculează subtotalul și eligibilitatea. Nu schimba retroactiv istoricul comenzilor deja livrate.
- Confirmarea plății de către director trebuie să compare suma transferată cu totalul final, nu cu subtotalul.
- Coduri de invitație unice per utilizator, asociere doar la un client nou, protecție împotriva auto-invitării, tranzacții idempotente și restricții unice în DB.
- Nu publica și nu aplica modificări asupra fluxului live până la validare.

## Arhitectură sigură
1. Creează mediu Supabase de test separat ori funcții/tabele izolate care nu afectează RPC-ul public place_shop_order.
2. Creează tabele pentru reward entitlements, referral codes, referral relationships, discount redemptions; RLS și politici restrictive.
3. RPC server-side quote_cart pentru calcul, selectare, dezactivare și reactivare reducere.
4. RPC tranzacțional pentru plasare comandă cu rezervare discount; suport pentru anulare/editare și finalizare.
5. Evenimente idempotente după delivered + approved pentru fidelitate și invitații.
6. UI în meniul Client fidel / Invită un prieten, în coșul obișnuit și în popup, plus în panoul director.
7. Teste: prima comandă sub/peste prag, 5 comenzi, invitație validă/invalidă, mai multe reduceri, anulare, editare, retry, concurență, 0 MDL, status plată.
