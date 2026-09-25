-- 다원한 일정 v2 : 함께 · 시간 · 매년 반복(기념일/D-day) · 여러 날 · 일정 수정
-- Supabase > SQL Editor 에 통째로 붙여넣고 한 번 실행하세요. (여러 번 실행해도 괜찮아요)
-- 비밀값 확인은 기존 dawon_list / dawon_add 함수를 그대로 거쳐요. 이 파일에는 비밀값이 들어있지 않아요.

-- 1) 새 칸
alter table public.events
  add column if not exists at_time  text,   -- 'HH:MM' (비우면 하루 종일)
  add column if not exists end_date text,   -- 여러 날 일정의 끝나는 날 'YYYY-MM-DD'
  add column if not exists repeat   text;   -- 'y' = 매년 반복

-- 2) who 에 'both'(함께) 허용
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.events'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%who%'
  loop
    execute format('alter table public.events drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.events add constraint events_who_check check (who in ('sw','dy','both'));

-- 3) 이 비밀값으로 볼 수 있는 일정 id 목록 (기존 dawon_list 가 허락한 것만) — 내부용
create or replace function public.dawon_ids(p_secret text)
returns setof text language plpgsql security definer set search_path = public as $$
declare j jsonb;
begin
  execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.dawon_list(p_secret=>%L) as x', p_secret) into j;
  -- dawon_list 가 json 배열 하나를 돌려주는 형태면 풀어줌
  if jsonb_typeof(j->0) = 'array' then j := j->0; end if;
  return query select v->>'id' from jsonb_array_elements(j) v;
end $$;
revoke all on function public.dawon_ids(text) from public, anon, authenticated;

-- 4) 새 칸까지 함께 돌려주는 목록
create or replace function public.dawon_list2(p_secret text)
returns setof public.events language plpgsql security definer set search_path = public as $$
begin
  return query select e.* from public.events e
    where e.id::text in (select public.dawon_ids(p_secret));
end $$;

-- 5) 새 칸까지 함께 저장하는 추가
create or replace function public.dawon_add2(
  p_secret text, p_id text, p_date text, p_who text, p_text text, p_created text,
  p_place text default null, p_time text default null, p_end text default null, p_repeat text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_who not in ('sw','dy','both') then raise exception 'bad who'; end if;
  if not exists (select 1 from public.events where id::text = p_id) then
    -- 저장·비밀값 확인은 기존 함수가 담당 (who 는 잠깐 'sw'로 넣고 아래에서 바꿈)
    execute format('select public.dawon_add(p_secret=>%L, p_id=>%L, p_date=>%L, p_who=>%L, p_text=>%L, p_created=>%L, p_place=>%L)',
                   p_secret, p_id, p_date, 'sw', p_text, p_created, p_place);
  end if;
  if p_id not in (select public.dawon_ids(p_secret)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  execute format('update public.events set who=%L, at_time=%L, end_date=%L, repeat=%L where id::text=%L',
                 p_who, nullif(p_time,''), nullif(p_end,''), nullif(p_repeat,''), p_id);
end $$;

-- 6) 일정 수정
create or replace function public.dawon_update2(
  p_secret text, p_id text, p_date text, p_who text, p_text text, p_created text default null,
  p_place text default null, p_time text default null, p_end text default null, p_repeat text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_who not in ('sw','dy','both') then raise exception 'bad who'; end if;
  if p_id not in (select public.dawon_ids(p_secret)) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  execute format('update public.events set date=%L, who=%L, text=%L, place=%L, at_time=%L, end_date=%L, repeat=%L where id::text=%L',
                 p_date, p_who, p_text, nullif(p_place,''), nullif(p_time,''), nullif(p_end,''), nullif(p_repeat,''), p_id);
end $$;

grant execute on function public.dawon_list2(text) to anon, authenticated;
grant execute on function public.dawon_add2(text,text,text,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.dawon_update2(text,text,text,text,text,text,text,text,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
