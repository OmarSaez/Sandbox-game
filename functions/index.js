const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
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

exports.onworldcreated = onDocumentCreated({
  document: "community_worlds/{worldId}",
  database: "default"
}, async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("No hay datos asociados al evento.");
    return;
  }
  
  const data = snapshot.data();
  const worldId = event.params.worldId;
  console.log(`Nuevo mundo detectado: ${worldId}`);

  const newWorldInfo = {
    id: worldId,
    title: data.title || "Sin título",
    author: data.author || "Anónimo",
    likes: data.likes || 0,
    downloads: data.downloads || 0,
    weekly_score: data.weekly_score || 0,
    thumbnail_url: data.thumbnail_url || "",
    category: data.category || 0,
    timestamp: data.timestamp || Date.now()
  };

  const cacheRef = db.collection("cache").doc("recientes");

  try {
    await db.runTransaction(async (transaction) => {
      const cacheDoc = await transaction.get(cacheRef);
      let worldsArray = [];
      
      if (cacheDoc.exists) {
        const cacheData = cacheDoc.data();
        if (cacheData.worlds && Array.isArray(cacheData.worlds)) {
          worldsArray = cacheData.worlds;
        }
      }
      
      // Inyectar al principio
      worldsArray.unshift(newWorldInfo);
      
      // Limitar a los 200 más recientes
      if (worldsArray.length > 200) {
        worldsArray = worldsArray.slice(0, 200);
      }
      
      transaction.set(cacheRef, {
        updated_at: new Date().toISOString(),
        worlds: worldsArray
      });
    });
    console.log(`Caché de recientes actualizado exitosamente con el mundo ${worldId}.`);
  } catch (error) {
    console.error("Error al actualizar la caché de recientes:", error);
  }
});