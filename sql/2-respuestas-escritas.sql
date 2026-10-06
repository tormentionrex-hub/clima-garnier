-- =====================================================================
-- Actualización 2 · Respuestas escritas obligatorias
-- Pegar en Supabase > SQL Editor > New query > Run (una sola vez).
-- =====================================================================

-- Las preguntas de respuesta escrita pasan a ser obligatorias,
-- con un mínimo de 10 caracteres (Maylin puede cambiarlo en el panel).
update public.preguntas
set obligatoria = true,
    config = config || '{"minimo": 10}'::jsonb
where tipo = 'abierta';

-- Elimina las preguntas de prueba que quedaron sin escribir
-- (las que todavía dicen "Escribe aquí tu pregunta").
delete from public.preguntas
where lower(trim(titulo)) in ('escribe aquí tu pregunta', 'nueva pregunta');
