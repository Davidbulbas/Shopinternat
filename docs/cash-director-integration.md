# Cash și MIA — integrare fără pierderea funcțiilor existente

## Stare
Plan verificat parțial prin tranzacție PostgreSQL cu ROLLBACK. **Nu este activ în producție și nu trebuie prezentat ca finalizat.**

## Principii
- Nu înlocui `review_shop_order_payment` pentru comenzile MIA; păstrează validarea directorului și notificările existente.
- `orders.payment_method` trebuie să fie `mia` implicit pentru toate comenzile istorice; `cash` doar pentru comenzi noi care au fost achitate personal, înainte de confirmare.
- Nu accepta o comandă cash doar pentru că elevul a selectat Cash. Directorul trebuie să confirme încasarea reală.
- Nu permite modificarea metodei de plată după aprobare și nu permite clientului să o schimbe prin update direct.
- Păstrează verificările existente: abonament activ, orar, limită o comandă/zi, produse, telefon, cameră și preț calculat pe server.
- Pentru MIA, fluxul actual trebuie să rămână neschimbat.
- După confirmare, păstrează opțiunile de status și emailurile existente.

## Migrare aditivă — doar după teste și aprobare
```sql
alter table public.orders
 add column if not exists payment_method text not null default 'mia';
alter table public.orders
 add constraint shop_orders_payment_method_check
 check (payment_method in ('mia','cash'));
```

Această schemă a fost testată într-o tranzacție cu ROLLBACK. Pentru activarea cash este necesară și o funcție securizată de plasare a comenzilor cu metoda de plată, fără a slăbi controalele din `place_shop_order`, plus autorizare director și protecție împotriva dublei confirmări. Nu activa cash doar din frontend.

## Teste obligatorii
1. Comenzile MIA vechi rămân MIA, fără modificarea statusului sau sumei.
2. Clientul nu poate confirma singur cash, schimba plata sau accepta o comandă.
3. Directorul poate confirma cash doar după încasare, iar comanda trece din pending în approved o singură dată.
4. Respingerea, anularea, notificările, editarea și statutul continuă să funcționeze.
5. Două confirmări simultane nu produc aprobări duplicate.
6. Toate testele de acceptare folosesc date izolate; nu crea comenzi fictive în baza de producție.

## Interfața curentă
În panoul directorului, selectorul afișează MIA activ și Cash dezactivat până la implementarea backend-ului. Nu publica această modificare ca funcționalitate cash completă.
