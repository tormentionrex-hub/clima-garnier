-- =====================================================================
-- Encuesta de Clima Garnier 2026 · instalación completa
-- Pegar TODO en Supabase > SQL Editor > New query > Run (una sola vez).
-- ANTES de ejecutar: cambia el correo de la última sección (admins).
-- =====================================================================

-- 1. Tablas ------------------------------------------------------------
create table if not exists public.encuestas (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text,
  estado text not null default 'borrador' check (estado in ('borrador','abierta','cerrada')),
  config jsonb not null default '{}'::jsonb,   -- textos editables: bienvenida, agradecimiento, secciones
  creada_en timestamptz not null default now(),
  actualizada_en timestamptz not null default now()
);

create table if not exists public.preguntas (
  id uuid primary key default gen_random_uuid(),
  encuesta_id uuid not null references public.encuestas(id) on delete cascade,
  orden int not null,
  seccion text,
  descripcion_seccion text,
  tipo text not null check (tipo in ('opcion','multiple','likert','escala','emociones','abierta')),
  titulo text not null,
  ayuda text,
  opciones jsonb not null default '[]'::jsonb,
  obligatoria boolean not null default true,
  config jsonb not null default '{}'::jsonb,   -- escala: min/max/etiquetas/nps · saltos: {"opción": "id de pregunta destino"}
  actualizada_en timestamptz not null default now()
);
create index if not exists preguntas_encuesta_orden on public.preguntas(encuesta_id, orden);

create table if not exists public.unidades (
  id uuid primary key default gen_random_uuid(),
  encuesta_id uuid not null references public.encuestas(id) on delete cascade,
  slug text not null,
  nombre text not null,
  orden int not null default 0,
  unique (encuesta_id, slug)
);

create table if not exists public.respuestas (
  id uuid primary key default gen_random_uuid(),
  encuesta_id uuid not null references public.encuestas(id) on delete cascade,
  unidad text,                                   -- nombre del área (por QR o elegida)
  enviada_en timestamptz not null default now(),
  datos jsonb not null check (pg_column_size(datos) < 40000)  -- { "id de pregunta": respuesta }
);
create index if not exists respuestas_encuesta on public.respuestas(encuesta_id);

create table if not exists public.admins (
  email text primary key
);

-- 2. ¿Quién es administradora? -------------------------------------------
create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins a
                 where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email','')));
$$;

create or replace function public.encuesta_abierta(eid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.encuestas where id = eid and estado = 'abierta');
$$;

-- 3. Seguridad (RLS) -----------------------------------------------------
alter table public.encuestas  enable row level security;
alter table public.preguntas  enable row level security;
alter table public.unidades   enable row level security;
alter table public.respuestas enable row level security;
alter table public.admins     enable row level security;

-- Encuestas: el público solo ve la que está abierta; la admin ve y edita todo
create policy "ver encuesta abierta" on public.encuestas for select to anon, authenticated
  using (estado = 'abierta' or public.es_admin());
create policy "admin crea encuestas" on public.encuestas for insert to authenticated with check (public.es_admin());
create policy "admin edita encuestas" on public.encuestas for update to authenticated using (public.es_admin()) with check (public.es_admin());
create policy "admin borra encuestas" on public.encuestas for delete to authenticated using (public.es_admin());

-- Preguntas
create policy "ver preguntas" on public.preguntas for select to anon, authenticated
  using (public.encuesta_abierta(encuesta_id) or public.es_admin());
create policy "admin crea preguntas" on public.preguntas for insert to authenticated with check (public.es_admin());
create policy "admin edita preguntas" on public.preguntas for update to authenticated using (public.es_admin()) with check (public.es_admin());
create policy "admin borra preguntas" on public.preguntas for delete to authenticated using (public.es_admin());

-- Unidades (áreas)
create policy "ver unidades" on public.unidades for select to anon, authenticated
  using (public.encuesta_abierta(encuesta_id) or public.es_admin());
create policy "admin crea unidades" on public.unidades for insert to authenticated with check (public.es_admin());
create policy "admin edita unidades" on public.unidades for update to authenticated using (public.es_admin()) with check (public.es_admin());
create policy "admin borra unidades" on public.unidades for delete to authenticated using (public.es_admin());

-- Respuestas: cualquiera puede ENVIAR (sin nombre) si la encuesta está abierta; solo la admin las LEE
create policy "enviar respuesta" on public.respuestas for insert to anon, authenticated
  with check (public.encuesta_abierta(encuesta_id));
create policy "admin lee respuestas" on public.respuestas for select to authenticated using (public.es_admin());
create policy "admin borra respuestas" on public.respuestas for delete to authenticated using (public.es_admin());

-- Admins: cada persona solo puede comprobar su propio correo
create policy "ver mi rol" on public.admins for select to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email','')));

-- 4. Encuesta 2026 con las 36 preguntas del cuestionario -----------------
do $$
declare e uuid; p10 uuid;
begin
  insert into public.encuestas (titulo, descripcion, estado)
  values ('Encuesta de Clima Organizacional 2026',
          'Queremos conocer tu experiencia en Garnier & Garnier: lo que recibes, lo que esperas y lo que sientes. La información se administrará con confidencialidad para fines laborales y académicos.',
          'borrador')
  returning id into e;

  insert into public.preguntas (encuesta_id, orden, seccion, descripcion_seccion, tipo, titulo, opciones, obligatoria, config) values
  (e, 1, 'Demográfica', '0. Demográficos', 'opcion', 'Género', '["Masculino", "Femenino"]'::jsonb, true, '{}'::jsonb),
  (e, 2, 'Demográfica', '0. Demográficos', 'opcion', '¿Cuál es su rango de edad?', '["24 años o menos", "25 a 34 años", "35 a 44 años", "45 a 54 años", "55 años o más"]'::jsonb, true, '{}'::jsonb),
  (e, 3, 'Demográfica', '0. Demográficos', 'opcion', '¿Cuál es su antigüedad en la empresa?', '["Menos de 1 año", "1 – 3 años", "4 – 6 años", "7 – 9 años", "Más de 10 años"]'::jsonb, true, '{}'::jsonb),
  (e, 4, 'Percepción del liderazgo', '1. Indice de Liderazgo y gestión: Evaluar la efectividad percibida del liderazgo y la gestión de las jefaturas, considerando su capacidad para apoyar, orientar, comunicar, reconocer, generar confianza y favorecer un ambiente de trabajo colaborativo y alineado con los objetivos organizacionales', 'likert', '¿Mi jefatura inmediata me brinda el apoyo necesario para realizar bien mi trabajo?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 5, 'Percepción del liderazgo', '1. Indice de Liderazgo y gestión: Evaluar la efectividad percibida del liderazgo y la gestión de las jefaturas, considerando su capacidad para apoyar, orientar, comunicar, reconocer, generar confianza y favorecer un ambiente de trabajo colaborativo y alineado con los objetivos organizacionales', 'likert', 'Recibo orientación y retroalimentación que me ayude a mejorar mi desempeño', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 6, 'Percepción del liderazgo', '1. Indice de Liderazgo y gestión: Evaluar la efectividad percibida del liderazgo y la gestión de las jefaturas, considerando su capacidad para apoyar, orientar, comunicar, reconocer, generar confianza y favorecer un ambiente de trabajo colaborativo y alineado con los objetivos organizacionales', 'likert', '¿Mi jefatura promueve un ambiente de respeto y colaboración?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 7, 'Percepción del liderazgo', '1. Indice de Liderazgo y gestión: Evaluar la efectividad percibida del liderazgo y la gestión de las jefaturas, considerando su capacidad para apoyar, orientar, comunicar, reconocer, generar confianza y favorecer un ambiente de trabajo colaborativo y alineado con los objetivos organizacionales', 'likert', '¿Confío en las decisiones que toman las personas en roles de liderazgo en la organización?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 8, 'Percepción del liderazgo', '1. Indice de Liderazgo y gestión: Evaluar la efectividad percibida del liderazgo y la gestión de las jefaturas, considerando su capacidad para apoyar, orientar, comunicar, reconocer, generar confianza y favorecer un ambiente de trabajo colaborativo y alineado con los objetivos organizacionales', 'likert', 'Me siento orgulloso (a) de trabajar en GGDI/ZFLL', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 9, 'Percepción del liderazgo', '1. Indice de Liderazgo y gestión: Evaluar la efectividad percibida del liderazgo y la gestión de las jefaturas, considerando su capacidad para apoyar, orientar, comunicar, reconocer, generar confianza y favorecer un ambiente de trabajo colaborativo y alineado con los objetivos organizacionales', 'likert', 'Entiendo cómo mi trabajo contribuye a los objetivos de la organización', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 10, 'Percepción del liderazgo', '1. Indice de Liderazgo y gestión: Evaluar la efectividad percibida del liderazgo y la gestión de las jefaturas, considerando su capacidad para apoyar, orientar, comunicar, reconocer, generar confianza y favorecer un ambiente de trabajo colaborativo y alineado con los objetivos organizacionales', 'likert', '¿Cuando realizo un buen trabajo o hago una contribución se me reconoce?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 11, 'Comunicación', '2. Efectividad de la comunicación organizacional, lineal y bidireccional', 'likert', '¿Recibo información de manera oportuna sobre cambios o temas relevantes en la empresa que afectan mi trabajo de manera directa o indirecta?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 12, 'Comunicación', '2. Efectividad de la comunicación organizacional, lineal y bidireccional', 'likert', '¿Puedo expresar dudas, inquietudes o desacuerdos y recibir una respuesta clara y respetuosa?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 13, 'Flexibilidad', '3. Medir el equilibrio vida - trabajo (Efectividad de las prácticas actuales)', 'likert', 'La empresa brinda condiciones que favorecen el equilibrio entre mi vida laboral y personal', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 14, 'Flexibilidad', '3. Medir el equilibrio vida - trabajo (Efectividad de las prácticas actuales)', 'likert', '¿Cuando tengo necesidades personales o familiares que atender siento comprensión y apoyo por parte de la empresa?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 15, 'Flexibilidad', '3. Medir el equilibrio vida - trabajo (Efectividad de las prácticas actuales)', 'likert', 'La flexibilidad que ofrece la empresa actualmente responde adecuadamente a mis necesidades', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 16, 'Flexibilidad', '3. Medir el equilibrio vida - trabajo (Efectividad de las prácticas actuales)', 'likert', '¿La cantidad de trabajo diaria me permite cumplir con el horario habitual de trabajo?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 17, 'Bienestar y Beneficios', '4. La percepción de las personas sobre el apoyo de la organización a su bienestar integral y el valor que generan los beneficios y la propuesta de valor al empleado en su experiencia laboral.', 'likert', 'La empresa promueve activamente el bienestar físico, emocional y mental de las personas trabajadoras', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 18, 'Bienestar y Beneficios', '4. La percepción de las personas sobre el apoyo de la organización a su bienestar integral y el valor que generan los beneficios y la propuesta de valor al empleado en su experiencia laboral.', 'likert', 'Los beneficios que ofrece la empresa actualmente aportan valor a mi bienestar y calidad de vida', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 19, 'Bienestar y Beneficios', '4. La percepción de las personas sobre el apoyo de la organización a su bienestar integral y el valor que generan los beneficios y la propuesta de valor al empleado en su experiencia laboral.', 'likert', 'Más allá de la compensación, la propuesta de valor de la empresa hace que mi experiencia laboral sea positiva', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 20, 'Desarrollo y Crecimiento', '5. La percepción de las personas sobre las oportunidades de aprendizaje, desarrollo y crecimiento profesional que ofrece la organización, así como la equidad y transparencia con que se gestionan estas oportunidades.”', 'likert', '¿Tengo oportunidades de aprender y de desarrollar nuevos conocimientos?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 21, 'Desarrollo y Crecimiento', '5. La percepción de las personas sobre las oportunidades de aprendizaje, desarrollo y crecimiento profesional que ofrece la organización, así como la equidad y transparencia con que se gestionan estas oportunidades.”', 'likert', '¿Considero que existen oportunidades de crecimiento y desarrollo dentro de la empresa?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 22, 'Desarrollo y Crecimiento', '5. La percepción de las personas sobre las oportunidades de aprendizaje, desarrollo y crecimiento profesional que ofrece la organización, así como la equidad y transparencia con que se gestionan estas oportunidades.”', 'likert', '¿Cuando se han brindado oportunidades de crecimiento considera que han sido justas y transparentes?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 23, 'Diversidad e Inclusión', '6. Medir la percepción de las personas sobre el nivel de inclusión, pertenencia, equidad, respeto y seguridad para expresarse dentro de la organización.', 'likert', '¿En la empresa las personas son tratadas con respeto independientemente de su posición y condiciones personales?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 24, 'Diversidad e Inclusión', '6. Medir la percepción de las personas sobre el nivel de inclusión, pertenencia, equidad, respeto y seguridad para expresarse dentro de la organización.', 'likert', '¿Me siento incluido (a) y valorado (a) por quién soy?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 25, 'Diversidad e Inclusión', '6. Medir la percepción de las personas sobre el nivel de inclusión, pertenencia, equidad, respeto y seguridad para expresarse dentro de la organización.', 'likert', '¿La empresa promueve un ambiente inclusivo y de respeto?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 26, 'Herramientas y Recursos', '7. Percepción sonbre la disponibilidad de herramientas y recursos necesarios para desempeñar el trabajo.', 'likert', '¿Cuento con las herramientas y recursos adecuados para realizar bien mi trabajo?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 27, 'Herramientas y Recursos', '7. Percepción sonbre la disponibilidad de herramientas y recursos necesarios para desempeñar el trabajo.', 'likert', '¿Los procesos internos facilitan mi trabajo y no generan obstáculos innecesarios?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 28, 'Estratégicos (Orgullo y Pertenencia)', '8 . Cómo se siente el personal actualmente en la organización', 'likert', '¿Crees que la empresa se esfuerza por mejorar tu experiencia como persona trabajadora?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 29, 'Estratégicos (Orgullo y Pertenencia)', '8 . Cómo se siente el personal actualmente en la organización', 'escala', 'Tomando en cuenta tu experiencia general en la empresa ¿Qué tan probable es que recomiendes a un amigo (a) o familiar trabajar aquí?', '[]'::jsonb, true, '{"min": 1, "max": 10, "etiqueta_min": "Nada probable", "etiqueta_max": "Muy probable", "nps": true}'::jsonb),
  (e, 30, 'Estratégicos (Orgullo y Pertenencia)', '8 . Cómo se siente el personal actualmente en la organización', 'escala', '¿Qué tan probable es que continúe trabajando en la organización durante los próximos dos años?', '[]'::jsonb, true, '{"min": 1, "max": 10, "etiqueta_min": "Nada probable", "etiqueta_max": "Muy probable", "nps": false}'::jsonb),
  (e, 31, 'Estratégicos (Orgullo y Pertenencia)', '8 . Cómo se siente el personal actualmente en la organización', 'emociones', '¿Qué sentimiento refleja mejor como te sientes actualmente?', '["Feliz", "Comprometido", "Motivado", "Satisfecho", "Indiferente", "Decepcionado", "Frustrado", "Aburrido", "Estresado", "Enfadado"]'::jsonb, true, '{}'::jsonb),
  (e, 32, 'Estratégicos (Orgullo y Pertenencia)', '8 . Cómo se siente el personal actualmente en la organización', 'likert', '¿Te sientes seguro (a) al reconocer un error o pedir ayuda sin temor a consecuencias negativas?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 33, 'Estratégicos (Orgullo y Pertenencia)', '8 . Cómo se siente el personal actualmente en la organización', 'likert', '¿Consideras que puedes plantear inquietudes o desacuerdos a tu equipo o jefatura con confianza y respeto?', '["Totalmente de acuerdo", "De acuerdo", "Indiferente", "En desacuerdo", "Totalmente en desacuerdo"]'::jsonb, true, '{}'::jsonb),
  (e, 34, 'Análisis de expectativas', '9. Recopilar información adicional importante para mejorar el clima, procesos y nuestra propuesta de valor', 'abierta', '¿Qué es lo que más valoras de trabajar en esta empresa?', '[]'::jsonb, false, '{}'::jsonb),
  (e, 35, 'Análisis de expectativas', '9. Recopilar información adicional importante para mejorar el clima, procesos y nuestra propuesta de valor', 'abierta', '¿Qué debería mejorar la empresa para ofrecer una mejor experiencia a las personas trabajadoras?', '[]'::jsonb, false, '{}'::jsonb),
  (e, 36, 'Análisis de expectativas', '9. Recopilar información adicional importante para mejorar el clima, procesos y nuestra propuesta de valor', 'abierta', 'Si pudieras implementar una sola mejora durante el próximo año ¿Cuál sería?', '[]'::jsonb, false, '{}'::jsonb);

  -- Salto condicional del cuestionario: más de 3 años de antigüedad -> pregunta 10
  select id into p10 from public.preguntas where encuesta_id = e and orden = 10;
  update public.preguntas
     set config = jsonb_build_object('saltos', jsonb_build_object(
           '4 – 6 años', p10, '7 – 9 años', p10, 'Más de 10 años', p10))
   where encuesta_id = e and orden = 3;

  insert into public.unidades (encuesta_id, slug, nombre, orden) values
  (e, 'contabilidad', 'Contabilidad', 1),
  (e, 'finanzas', 'Finanzas', 2),
  (e, 'gerencia-general', 'Gerencia General', 3),
  (e, 'gerencia-nuevos-proyectos', 'Gerencia Nuevos Proyectos', 4),
  (e, 'ingenieria', 'Ingeniería', 5),
  (e, 'legal', 'Legal', 6),
  (e, 'mercadeo-y-ventas', 'Mercadeo y Ventas', 7),
  (e, 'presidencia', 'Presidencia', 8),
  (e, 'proyectos', 'Proyectos', 9),
  (e, 'recursos-humanos', 'Recursos Humanos', 10),
  (e, 'servicios-generales', 'Servicios Generales', 11),
  (e, 'tesoreria', 'Tesorería', 12),
  (e, 'ti', 'TI', 13),
  (e, 'zfll', 'ZFLL', 14);
end $$;

-- 5. Administradora del panel --------------------------------------------
-- Cambia el correo por el de Maylin (y agrega otros si hace falta).
-- Luego crea ese mismo usuario en Authentication > Users > Add user (con contraseña).
insert into public.admins (email) values ('CAMBIAR_POR_CORREO_DE_MAYLIN@ejemplo.com')
on conflict do nothing;
