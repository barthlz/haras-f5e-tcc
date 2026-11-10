-- HARAS F5E | Etapa 1 - base do aplicativo Android (projeto Supabase NOVO)
-- Execute UMA VEZ no SQL Editor do novo projeto. Não use o banco do Team Penning.
-- Nunca coloque service_role ou secret key dentro do aplicativo Flutter.

begin;

do $$ begin
  create type public.app_role as enum
    ('administrador', 'gerente', 'financeiro', 'treinador', 'funcionario');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.user_status as enum ('pendente', 'ativo', 'bloqueado');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  role public.app_role not null default 'funcionario',
  status public.user_status not null default 'pendente',
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role public.app_role not null,
  module text not null check (module in (
    'resumo', 'clientes', 'despesas', 'funcionarios', 'animais',
    'pagamentos', 'hospedagem', 'treinamento', 'reproducao', 'exames')),
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  primary key (role, module)
);

-- Inserção de perfil após o cadastro. Metadados do usuário só fornecem o nome.
-- A função NÃO aceita a função/permissão solicitada pelo usuário.
create or replace function public.on_new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 'Novo usuário'), new.email)
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists trg_haras_new_user on auth.users;
create trigger trg_haras_new_user
  after insert on auth.users
  for each row execute function public.on_new_auth_user();

-- Segurança no servidor: verificação real de função e status (RLS).
create or replace function public.is_haras_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.status = 'ativo'
      and p.role = 'administrador'
  );
$$;

create or replace function public.can_haras(
  p_module text, p_action text
)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.profiles p
    join public.role_permissions rp on rp.role = p.role
    where p.id = (select auth.uid())
      and p.status = 'ativo'
      and rp.module = p_module
      and case p_action
        when 'view' then rp.can_view
        when 'create' then rp.can_create
        when 'edit' then rp.can_edit
        when 'delete' then rp.can_delete
        else false
      end
  );
$$;

create or replace function public.my_haras_permissions()
returns table (module text, can_view boolean, can_create boolean,
               can_edit boolean, can_delete boolean)
language sql stable security definer set search_path = '' as $$
  select rp.module, rp.can_view, rp.can_create, rp.can_edit, rp.can_delete
  from public.profiles p
  join public.role_permissions rp on rp.role = p.role
  where p.id = (select auth.uid()) and p.status = 'ativo'
  order by rp.module;
$$;

revoke all on function public.is_haras_admin() from public, anon;
revoke all on function public.can_haras(text, text) from public, anon;
revoke all on function public.my_haras_permissions() from public, anon;
grant execute on function public.is_haras_admin() to authenticated;
grant execute on function public.can_haras(text, text) to authenticated;
grant execute on function public.my_haras_permissions() to authenticated;

-- Matriz de acesso (pode ser revisada posteriormente).
-- Administrador: tudo; controle de contas é exclusivamente administrador.
insert into public.role_permissions (role, module, can_view, can_create, can_edit, can_delete)
select 'administrador', v.module, true, true, true, true
from (values ('resumo'), ('clientes'), ('despesas'), ('funcionarios'),
             ('animais'), ('pagamentos'), ('hospedagem'),
             ('treinamento'), ('reproducao'), ('exames')) as v(module)
on conflict (role, module) do update set
  can_view = excluded.can_view, can_create = excluded.can_create,
  can_edit = excluded.can_edit, can_delete = excluded.can_delete;

-- Gerente: gestão operacional e financeira; não administra contas.
insert into public.role_permissions (role, module, can_view, can_create, can_edit, can_delete)
select 'gerente', v.module, true, true, true, true
from (values ('resumo'), ('clientes'), ('despesas'), ('funcionarios'),
             ('animais'), ('pagamentos'), ('hospedagem'),
             ('treinamento'), ('reproducao'), ('exames')) as v(module)
on conflict (role, module) do update set
  can_view = excluded.can_view, can_create = excluded.can_create,
  can_edit = excluded.can_edit, can_delete = excluded.can_delete;

-- Financeiro: pagamentos, despesas e clientes; consulta cadastro dos animais.
insert into public.role_permissions (role, module, can_view, can_create, can_edit, can_delete)
values
  ('financeiro','resumo',true,false,false,false),
  ('financeiro','clientes',true,true,true,false),
  ('financeiro','despesas',true,true,true,false),
  ('financeiro','pagamentos',true,true,true,false),
  ('financeiro','animais',true,false,false,false)
on conflict (role, module) do update set
  can_view=excluded.can_view, can_create=excluded.can_create,
  can_edit=excluded.can_edit, can_delete=excluded.can_delete;

-- Treinador: manejo dos animais; sem acesso a salários, pagamentos ou despesas.
insert into public.role_permissions (role, module, can_view, can_create, can_edit, can_delete)
values
  ('treinador','resumo',true,false,false,false),
  ('treinador','clientes',true,false,false,false),
  ('treinador','animais',true,true,true,false),
  ('treinador','hospedagem',true,true,true,false),
  ('treinador','treinamento',true,true,true,false),
  ('treinador','reproducao',true,true,true,false),
  ('treinador','exames',true,true,true,false)
on conflict (role, module) do update set
  can_view=excluded.can_view, can_create=excluded.can_create,
  can_edit=excluded.can_edit, can_delete=excluded.can_delete;

-- Funcionário: consulta, sem permissão de alterar ou excluir.
insert into public.role_permissions (role, module, can_view, can_create, can_edit, can_delete)
values
  ('funcionario','resumo',true,false,false,false),
  ('funcionario','animais',true,false,false,false),
  ('funcionario','hospedagem',true,false,false,false),
  ('funcionario','treinamento',true,false,false,false),
  ('funcionario','exames',true,false,false,false)
on conflict (role, module) do update set
  can_view=excluded.can_view, can_create=excluded.can_create,
  can_edit=excluded.can_edit, can_delete=excluded.can_delete;

-- Cadastros da planilha
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  birth_date date,
  cpf text,
  address text,
  created_at timestamptz not null default now()
);
create table if not exists public.client_dependents (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  name text not null,
  birth_date date
);
create table if not exists public.animals (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  sex text check (sex is null or sex in ('Macho','Fêmea')),
  birth_date date,
  owner_client_id uuid references public.clients(id) on delete set null,
  arrival_date date,
  training_enabled boolean not null default false,
  breeding_enabled boolean not null default false,
  lodging_enabled boolean not null default false,
  departure_date date,
  created_at timestamptz not null default now()
);
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id),
  payment_date date not null,
  reference_month date,
  due_date date,
  amount numeric(12,2) not null check (amount >= 0),
  note text,
  created_at timestamptz not null default now()
);
create table if not exists public.payment_animals (
  payment_id uuid not null references public.payments(id) on delete cascade,
  animal_id uuid not null references public.animals(id),
  primary key (payment_id, animal_id)
);
create table if not exists public.lodgings (
  id uuid primary key default gen_random_uuid(),
  animal_id uuid not null references public.animals(id),
  diet text,
  location text,
  start_date date,
  end_date date,
  created_at timestamptz not null default now()
);
create table if not exists public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  animal_id uuid not null references public.animals(id),
  training_type text not null,
  training_days integer check (training_days is null or training_days >= 0),
  diet text,
  start_date date,
  end_date date,
  created_at timestamptz not null default now()
);
create table if not exists public.breeding_records (
  id uuid primary key default gen_random_uuid(),
  animal_id uuid not null references public.animals(id),
  season text,
  cover_date date,
  stallion text,
  pregnancy_confirmed boolean not null default false,
  te_result text,
  foaling_date date,
  foal_sex text,
  created_at timestamptz not null default now()
);
create table if not exists public.embryo_transfers (
  id uuid primary key default gen_random_uuid(),
  animal_id uuid not null references public.animals(id),
  breeding_record_id uuid references public.breeding_records(id) on delete set null,
  recipient_name text not null,
  confirmed boolean not null default false,
  foaling_date date,
  foal_sex text,
  created_at timestamptz not null default now()
);
create table if not exists public.animal_exams (
  id uuid primary key default gen_random_uuid(),
  animal_id uuid not null references public.animals(id),
  exam_name text not null,
  sample_date date,
  expires_on date,
  created_at timestamptz not null default now()
);

-- Módulos adicionados à planilha
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date date not null,
  category text not null,
  description text not null,
  amount numeric(12,2) not null check (amount >= 0),
  paid boolean not null default false,
  note text,
  created_at timestamptz not null default now()
);
create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  job_title text not null,
  hire_date date,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_animals_owner on public.animals(owner_client_id);
create index if not exists idx_payments_client on public.payments(client_id);
create index if not exists idx_payments_date on public.payments(payment_date desc);
create index if not exists idx_exams_expiry on public.animal_exams(expires_on);
create index if not exists idx_expenses_date on public.expenses(expense_date desc);

-- Perfil: o próprio usuário pode LER seu status; apenas admin pode editar perfis.
alter table public.profiles enable row level security;
drop policy if exists haras_profiles_select on public.profiles;
create policy haras_profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_haras_admin()));
drop policy if exists haras_profiles_admin_update on public.profiles;
create policy haras_profiles_admin_update on public.profiles
  for update to authenticated
  using ((select public.is_haras_admin()))
  with check ((select public.is_haras_admin()));

-- Não existe leitura pública da matriz de funções: obtida pela RPC autenticada.
alter table public.role_permissions enable row level security;
revoke all on public.role_permissions from anon, authenticated;

-- Políticas de acesso banco-a-banco para TODOS os módulos.
do $do$
declare rec record;
begin
  for rec in
    select * from (values
      ('clients','clientes'), ('client_dependents','clientes'),
      ('animals','animais'), ('expenses','despesas'),
      ('employees','funcionarios'), ('payments','pagamentos'),
      ('payment_animals','pagamentos'), ('lodgings','hospedagem'),
      ('training_sessions','treinamento'), ('breeding_records','reproducao'),
      ('embryo_transfers','reproducao'), ('animal_exams','exames')
    ) as x(tbl, mod)
  loop
    execute format('alter table public.%I enable row level security', rec.tbl);
    execute format('drop policy if exists haras_read on public.%I', rec.tbl);
    execute format('drop policy if exists haras_insert on public.%I', rec.tbl);
    execute format('drop policy if exists haras_edit on public.%I', rec.tbl);
    execute format('drop policy if exists haras_delete on public.%I', rec.tbl);
    execute format(
      'create policy haras_read on public.%I for select to authenticated using ((select public.can_haras(%L, %L)))',
      rec.tbl, rec.mod, 'view');
    execute format(
      'create policy haras_insert on public.%I for insert to authenticated with check ((select public.can_haras(%L, %L)))',
      rec.tbl, rec.mod, 'create');
    execute format(
      'create policy haras_edit on public.%I for update to authenticated using ((select public.can_haras(%L, %L))) with check ((select public.can_haras(%L, %L)))',
      rec.tbl, rec.mod, 'edit', rec.mod, 'edit');
    execute format(
      'create policy haras_delete on public.%I for delete to authenticated using ((select public.can_haras(%L, %L)))',
      rec.tbl, rec.mod, 'delete');
    execute format('revoke all on public.%I from anon', rec.tbl);
    execute format('grant select, insert, update, delete on public.%I to authenticated', rec.tbl);
  end loop;
end $do$;

grant select, update on public.profiles to authenticated;
revoke all on public.profiles from anon;

commit;

-- IMPORTANTE: após cadastrar sua conta pelo app, execute APENAS o arquivo
-- 02_promover_primeiro_administrador.sql, após substituir o e-mail no exemplo.
