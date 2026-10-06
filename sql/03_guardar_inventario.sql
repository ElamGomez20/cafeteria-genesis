begin;
alter table public.productos enable row level security;
alter table public.ventas enable row level security;
alter table public.detalle_ventas enable row level security;
alter table public.movimientos_inventario enable row level security;
create or replace function public.guardar_inventario(
 p_fecha date, p_motivo text, p_productos jsonb, p_base jsonb
) returns void language plpgsql security invoker set search_path = '' as $$
declare
 v record; old public.productos%rowtype; v_id uuid; v_delta integer;
begin
 if p_fecha is null or p_fecha > (now() at time zone 'America/Bogota')::date
   or p_motivo is null or length(trim(p_motivo)) = 0 then
  raise exception 'Selecciona una fecha valida y escribe el motivo';
 end if;
 if p_productos is null or jsonb_typeof(p_productos)<>'array'
   or p_base is null or jsonb_typeof(p_base)<>'array' then
  raise exception 'Inventario invalido';
 end if;
 if jsonb_array_length(p_productos)>500 then
  raise exception 'Maximo 500 productos';
 end if;
 -- Bloquea en el mismo orden utilizado por registrar_venta.
 perform id from public.productos where activo order by id for update;
 if (select count(*) from public.productos where activo) <> jsonb_array_length(p_base)
 or exists (
  select 1 from public.productos p where p.activo and not exists (
   select 1 from jsonb_to_recordset(p_base) as b(id uuid, version bigint)
   where b.id=p.id and b.version=p.version
  )
 ) then
  raise exception 'El inventario cambio en otro equipo o por una venta. Recarga el inventario y vuelve a aplicar tus ajustes';
 end if;
 if (select count(distinct b.id) from jsonb_to_recordset(p_base) as b(id uuid))<>jsonb_array_length(p_base) then
  raise exception 'Base de inventario invalida';
 end if;
 if (select count(distinct p.id) from jsonb_to_recordset(p_productos) as p(id uuid))<>jsonb_array_length(p_productos)
 or (select count(distinct lower(trim(p.name))) from jsonb_to_recordset(p_productos) as p(name text))<>jsonb_array_length(p_productos) then
  raise exception 'Hay productos sin identificador o con nombres repetidos';
 end if;
 for v in select * from jsonb_to_recordset(p_productos)
  as p(id uuid, name text, category text, cost numeric, price numeric,
       stock numeric, minimum numeric, "photoPath" text) order by id
 loop
  if v.name is null or length(trim(v.name))=0 or length(v.name)>100
   or v.category is null or v.category not in ('Comidas','Bebidas')
   or v.cost is null or v.cost<0 or v.cost<>trunc(v.cost)
   or v.price is null or v.price<=0 or v.price<>trunc(v.price)
   or v.stock is null or v.stock<0 or v.stock<>trunc(v.stock)
   or v.minimum is null or v.minimum<0 or v.minimum<>trunc(v.minimum)
   or (v."photoPath" is not null and v."photoPath" !~ '^[a-f0-9-]{36}\.jpg$') then
   raise exception 'Revisa el nombre, categoria, cantidades, precios y fotografia';
  end if;
  select * into old from public.productos where id=v.id;
  if found then
   if not old.activo then raise exception 'Un producto eliminado no puede reutilizarse'; end if;
   if old.nombre is distinct from trim(v.name) or old.categoria is distinct from v.category
    or old.stock is distinct from v.stock or old.stock_minimo is distinct from v.minimum
    or old.costo_unitario is distinct from v.cost or old.precio_unitario is distinct from v.price
    or old.foto_path is distinct from v."photoPath" then
    update public.productos set nombre=trim(v.name),categoria=v.category,
      costo_unitario=v.cost,precio_unitario=v.price,stock=v.stock::integer,
      stock_minimo=v.minimum::integer,foto_path=v."photoPath",
      version=version+1,actualizado_en=now() where id=v.id;
    insert into public.movimientos_inventario
      (producto_id,nombre_producto,fecha,tipo,cantidad,stock_anterior,stock_nuevo,motivo)
      values(v.id,trim(v.name),p_fecha,'ajuste',v.stock::integer-old.stock,old.stock,v.stock::integer,p_motivo);
   end if;
  else
   insert into public.productos(id,nombre,categoria,costo_unitario,precio_unitario,stock,stock_minimo,foto_path)
   values(v.id,trim(v.name),v.category,v.cost,v.price,v.stock::integer,v.minimum::integer,v."photoPath");
   insert into public.movimientos_inventario
     (producto_id,nombre_producto,fecha,tipo,cantidad,stock_anterior,stock_nuevo,motivo)
     values(v.id,trim(v.name),p_fecha,'nuevo',v.stock::integer,0,v.stock::integer,p_motivo);
  end if;
 end loop;
 for old in select * from public.productos p where p.activo
   and not exists(select 1 from jsonb_to_recordset(p_productos) as x(id uuid) where x.id=p.id)
 loop
  update public.productos set activo=false,stock=0,version=version+1,actualizado_en=now() where id=old.id;
  insert into public.movimientos_inventario
    (producto_id,nombre_producto,fecha,tipo,cantidad,stock_anterior,stock_nuevo,motivo)
    values(old.id,old.nombre,p_fecha,'eliminacion',-old.stock,old.stock,0,p_motivo);
 end loop;
end;
$$;
revoke all on function public.guardar_inventario(date,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.guardar_inventario(date,text,jsonb,jsonb) to service_role;
commit;

-- Verifica que el total cobrado coincide con los precios actuales.
create or replace function public.registrar_venta_verificada(
 p_venta_id uuid,p_metodo_pago text,p_items jsonb,p_total numeric
) returns uuid language plpgsql security invoker set search_path='' as $$
declare v_total numeric; v_old public.ventas%rowtype;
begin
 if p_venta_id is null or p_total is null then raise exception 'Venta invalida'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_venta_id::text,0));
 select * into v_old from public.ventas where id=p_venta_id;
 if found then
  if v_old.total<>p_total then raise exception 'El identificador pertenece a otra venta'; end if;
  return public.registrar_venta(p_venta_id,p_metodo_pago,p_items);
 end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Lista de productos invalida'; end if;
 perform p.id from public.productos p where p.activo and p.id in
  (select x.producto_id from jsonb_to_recordset(p_items) as x(producto_id uuid))
  order by p.id for update;
 select sum(p.precio_unitario*x.cantidad) into v_total
  from jsonb_to_recordset(p_items) as x(producto_id uuid,cantidad numeric)
  join public.productos p on p.id=x.producto_id and p.activo;
 if v_total is distinct from p_total then
  raise exception 'Los precios cambiaron. Actualiza la pantalla y confirma el nuevo total antes de cobrar';
 end if;
 return public.registrar_venta(p_venta_id,p_metodo_pago,p_items);
end;
$$;
revoke all on function public.registrar_venta_verificada(uuid,text,jsonb,numeric) from public,anon,authenticated;
grant execute on function public.registrar_venta_verificada(uuid,text,jsonb,numeric) to service_role;
