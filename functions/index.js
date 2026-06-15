const {onSchedule} = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const app = initializeApp({
  projectId: "sandbox-ultra-5c7d5"
});

// ¡LA CLAVE DE TODO EL MISTERIO ESTÁ AQUÍ!
// Pasamos "default" explícitamente porque la base de datos no se llama "(default)"
const db = getFirestore(app, "default");

exports.updateweeklytop = onSchedule("0 0,12 * * *", async (event) => {
  console.log("Iniciando actualización del Top Semanal (vía Admin SDK con Base de Datos corregida)...");

  try {
    const currentWeekId = Math.floor(Date.now() / 1000 / 604800);
    console.log(`Buscando mundos para la semana: ${currentWeekId}`);

    // Obtenemos TODOS los mundos y filtramos en JS para eludir problemas de índices
    const worldsSnapshot = await db.collection("community_worlds").get();

    let allWorlds = [];

    worldsSnapshot.forEach((doc) => {
      const data = doc.data();
      const reports = data.reports || 0;
      
      // Solo aceptamos mundos de esta semana y que NO tengan 5 o más reportes
      if (data.weekly_week_id === currentWeekId && reports < 5) {
        allWorlds.push({
          id: doc.id,
          title: data.title || "Sin título",
          author: data.author || "Anónimo",
          likes: data.likes || 0,
          downloads: data.downloads || 0,
          weekly_score: data.weekly_score || 0,
          thumbnail_url: data.thumbnail_url || "",
          category: data.category || 0,
        });
      }
    });

    // Ordenamos de mayor a menor puntaje
    allWorlds.sort((a, b) => b.weekly_score - a.weekly_score);
    const topWorlds = allWorlds.slice(0, 100);

    console.log(`Se encontraron ${topWorlds.length} mundos en el top para esta semana.`);

    // Guardar toda la lista en la colección cache
    await db.collection("cache").doc("top_semanal").set({
      updated_at: new Date().toISOString(),
      week_id: currentWeekId,
      worlds: topWorlds,
    });

    console.log("¡Caché del Top Semanal actualizado exitosamente!");
  } catch (error) {
    console.error("Error crítico al actualizar el Top Semanal:", error);
  }
});