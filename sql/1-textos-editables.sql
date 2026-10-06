-- =====================================================================
-- Actualización 1 · Textos editables desde el panel
-- Pegar en Supabase > SQL Editor > New query > Run (una sola vez).
-- No borra nada: solo agrega un espacio para guardar los mensajes
-- (bienvenida, agradecimiento, introducción de cada sección, etc.).
-- =====================================================================

alter table public.encuestas
  add column if not exists config jsonb not null default '{}'::jsonb;

-- Textos iniciales para la encuesta 2026 (Maylin puede cambiarlos desde el panel)
update public.encuestas
set config = config || jsonb_build_object(
  'boton_inicio', 'Comenzar',
  'pregunta_area', '¿En qué área trabajas?',
  'mensaje_gracias', 'Tu respuesta quedó registrada. Tu opinión ayuda a construir un mejor lugar para trabajar.',
  'mensaje_ya_respondio', 'En este dispositivo ya se envió una respuesta. ¡Gracias por participar!',
  'secciones', jsonb_build_object(
    'Demográfica', 'Unos datos generales para agrupar los resultados. No te pedimos tu nombre.',
    'Percepción del liderazgo', 'Cuéntanos cómo vives el apoyo, la orientación y el reconocimiento de quienes lideran.',
    'Comunicación', 'Sobre cómo te llega la información y cómo puedes expresar tus ideas.',
    'Flexibilidad', 'Sobre el equilibrio entre tu trabajo y tu vida personal.',
    'Bienestar y Beneficios', 'Sobre tu bienestar y el valor de los beneficios que recibes.',
    'Desarrollo y Crecimiento', 'Sobre tus oportunidades de aprender y crecer.',
    'Diversidad e Inclusión', 'Sobre el respeto y la inclusión en el día a día.',
    'Herramientas y Recursos', 'Sobre lo que necesitas para hacer bien tu trabajo.',
    'Estratégicos (Orgullo y Pertenencia)', 'Ya casi terminamos. Unas preguntas sobre cómo te sientes hoy.',
    'Análisis de expectativas', 'Para cerrar, tus ideas en tus propias palabras.'
  )
)
where titulo = 'Encuesta de Clima Organizacional 2026';
