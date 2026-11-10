-- Execute no SQL Editor DEPOIS de cadastrar a sua conta no aplicativo.
-- Troque SEU_EMAIL_AQUI@EXEMPLO.COM pelo seu e-mail real.
-- Cuidado: conceda acesso de administrador SOMENTE à sua própria conta.
update public.profiles
set role = 'administrador', status = 'ativo'
where id = (
  select id from auth.users
  where lower(email) = lower('SEU_EMAIL_AQUI@EXEMPLO.COM')
);

-- Confira o resultado. Se retornar zero linhas, revise o e-mail do cadastro.
select p.id, u.email, p.full_name, p.role, p.status
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = lower('SEU_EMAIL_AQUI@EXEMPLO.COM');
