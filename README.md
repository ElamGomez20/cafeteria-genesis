# Cafetería Génesis — versión conectada a Supabase

Mantiene Montserrat, los colores cálidos y el acceso por Vendedor / Contador. No requiere correos ni crear usuarios de Supabase Auth. Las contraseñas se verifican en el servidor y la sesión se guarda en una cookie HttpOnly de 8 horas.

## 1. Completar Supabase

Ya debes haber ejecutado los dos bloques anteriores: tablas, bucket privado productos y función registrar_venta.

Abre sql/03_guardar_inventario.sql en VS Code, copia TODO su contenido en una consulta nueva del SQL Editor de Supabase y pulsa Run. Crea el guardado de inventario y la comprobación del total cobrado. RLS permanece activado; no crees políticas públicas ni lo desactives.

## 2. Instalar Node.js

Instala Node.js 22 LTS desde https://nodejs.org/ . Cierra y abre VS Code después de instalarlo.

Abre la carpeta Genesis_Nube en VS Code. Debe verse package.json en la raíz.

## 3. Crear el archivo de configuración

Duplica .env.example y llama a la copia .env (sin .txt).

Completa:

- SUPABASE_URL: URL del proyecto, desde Connect o los ajustes del proyecto.
- SUPABASE_SECRET_KEY: clave Secret de Supabase, desde Settings > API Keys. Normalmente empieza por sb_secret_. Si tu proyecto solo muestra las claves antiguas, puedes usar service_role.
- VENDEDOR_PASSWORD: Genesis1.
- CONTADOR_PASSWORD: Genesis2.
- SESSION_SECRET: un texto aleatorio de al menos 32 caracteres.

Para generar SESSION_SECRET, abre Terminal > Nueva terminal en VS Code y ejecuta:

    node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

Copia el resultado en SESSION_SECRET.

La clave secreta solo se coloca en .env y en las variables de Vercel. Nunca la pongas en public/js, GitHub, capturas o mensajes. .gitignore excluye .env.

## 4. Ejecutar localmente

En la terminal de VS Code:

    npm run dev

Abre http://localhost:3000 . Esta versión usa un servidor: Live Server no ejecuta la API. No necesitas npm install porque no hay dependencias externas.

Entra como vendedor. Abre Inventario. Si está vacío, pulsa Cargar productos del Excel de ejemplo. Revisa precios y escribe las existencias actuales, o crea tus propios productos. Luego guarda.

Registra una venta y comprueba en Supabase Table Editor que aparece en ventas y detalle_ventas, y que productos tiene el stock actualizado. Entra como contador para consultar reportes y descargar Excel.

Los datos del prototipo anterior no se importan automáticamente. El catálogo de ejemplo carga únicamente nombres y precios, con existencias en cero.

## 5. Publicar con GitHub Desktop y Vercel

1. En GitHub Desktop: File > Add local repository y elige Genesis_Nube. Si no existe repositorio, pulsa create a repository here. Revisa que .env NO esté entre los archivos del commit.
2. Haz el commit y pulsa Publish repository. Puedes dejar el repositorio privado.
3. En https://vercel.com/ inicia sesión y usa Add New > Project para importar ese repositorio.
4. Framework Preset: Other. Root Directory: la raíz donde está package.json. El archivo vercel.json define public como salida estática y configura la API; no elijas public como raíz del proyecto.
5. Antes de Deploy, añade estas cinco Environment Variables, con los mismos valores que .env:

   SUPABASE_URL
   SUPABASE_SECRET_KEY
   VENDEDOR_PASSWORD
   CONTADOR_PASSWORD
   SESSION_SECRET

6. Pulsa Deploy. Abre el enlace devuelto por Vercel.
7. Prueba una venta y confirma desde otro navegador o dispositivo que aparece en el panel del contador. Pulsa Actualizar para cargar los movimientos más recientes.

Si agregas o cambias variables después de publicar, vuelve a desplegar el proyecto para aplicarlas.

## Comprobaciones

    npm run check
    npm test

Incluye pruebas de sesión firmada, contraseña incorrecta, cookie HttpOnly, acceso sin sesión, permisos de contador, rechazo de solicitudes desde otros sitios y envío de la venta al RPC verificado.

## Comportamiento

- Productos, movimientos y ventas se leen y guardan en Supabase.
- Fotos se optimizan y suben al bucket privado productos; se muestran mediante enlaces temporales. Pulsa Actualizar si una foto dejó de cargar después de una hora.
- La venta descuenta existencias en la misma transacción y conserva nombres y precios históricos.
- Se rechaza un total si los precios cambiaron en otro equipo antes de registrar la venta.
- Reintentar la misma venta, sin modificar el pedido ni recargar la pestaña, reutiliza el identificador para evitar duplicados. Si se corta Internet al confirmar, revisa el historial antes de volver a vender después de cerrar o recargar la página.
- El inventario exige que sus versiones coincidan con lo cargado al editarlo. Si otro equipo vendió o modificó algo, pulsa Recargar y vuelve a aplicar tus ajustes.
- Eliminar un producto conserva sus ventas y registra una baja; no lo borra físicamente.
- El contador consulta registros. El vendedor modifica inventario y registra ventas.
- Actualizar recarga los datos entre equipos; no es sincronización en tiempo real.
- El cierre de pestañas no elimina registros guardados. Los cambios de inventario sin guardar y pedidos sin registrar no son ventas guardadas.
- Ganancia bruta = ventas menos costo de productos. No incluye egresos, donaciones ni saldos contables de caja. Nequi es una clasificación de pago; no se verifica el pago con Nequi.

## Alcance de la validación

El código JavaScript y las pruebas de servidor con respuestas simuladas están comprobados. No se ha accedido a tu proyecto Supabase ni se ha desplegado en tu Vercel: la prueba de integración real se hace después de configurar .env y ejecutar el SQL adicional.

Las contraseñas compartidas no identifican a una persona específica. El límite de intentos del servidor es por instancia y no sustituye un límite distribuido para alto tráfico. Una foto subida cuyo guardado de inventario falla puede quedar sin usar en Storage; no se elimina automáticamente para no borrar fotos referenciadas.
