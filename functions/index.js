const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getDatabase } = require("firebase-admin/database");

const app = initializeApp({
  projectId: "sandbox-ultra-5c7d5",
  databaseURL: "https://sandbox-ultra-5c7d5-default-rtdb.firebaseio.com"
});

// ¡LA CLAVE DE TODO EL MISTERIO ESTÁ AQUÍ!
// Pasamos "default" explícitamente porque la base de datos no se llama "(default)"
const db = getFirestore(app, "default");
const rtdb = getDatabase(app);

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
    historical_score: data.historical_score || 0,
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

exports.updatehistoricaltop = onSchedule("0 0 * * *", async (event) => {
  console.log("Iniciando actualización del Top Histórico...");

  try {
    // OPTIMIZACIÓN DEFINITIVA: Pedimos a Firebase que nos entregue SOLO los 100 mejores mapas
    // ordenados por su 'historical_score'. Costo fijo: 100 lecturas exactas sin importar el tamaño de la DB.
    const worldsSnapshot = await db.collection("community_worlds")
      .orderBy("historical_score", "desc")
      .limit(100)
      .get();
      
    let topWorlds = [];

    worldsSnapshot.forEach((doc) => {
      const data = doc.data();
      const reports = data.reports || 0;
      const downloads = data.downloads || 0;
      const likes = data.likes || 0;
      
      // Filtro de barrera de entrada: Solo entran si cumplen los requisitos mínimos.
      // Si de los top 100 solo 5 cumplen esto (juego nuevo), la lista tendrá 5.
      if (downloads >= 100 && likes >= 10 && reports < 5) {
        topWorlds.push({
          id: doc.id,
          title: data.title || "Sin título",
          author: data.author || "Anónimo",
          likes: likes,
          downloads: downloads,
          reports: reports,
          weekly_score: data.weekly_score || 0,
          historical_score: data.historical_score || 0,
          thumbnail_url: data.thumbnail_url || "",
          category: data.category || 0,
        });
      }
    });

    console.log(`Se filtraron ${topWorlds.length} mundos que superan la barrera inicial.`);

    // Guardar en caché
    await db.collection("cache").doc("top_historico").set({
      updated_at: new Date().toISOString(),
      worlds: topWorlds,
    });

    console.log("¡Caché del Top Histórico actualizado exitosamente!");
  } catch (error) {
    console.error("Error crítico al actualizar el Top Histórico:", error);
  }
});

exports.processactionbuffer = onSchedule("*/10 * * * *", async (event) => {
  console.log("Iniciando procesamiento del Buffer de RTDB...");
  
  try {
    const bufferRef = rtdb.ref("action_buffer");
    const snapshot = await bufferRef.once("value");
    
    if (!snapshot.exists()) {
      console.log("Buffer vacío. No hay nada que procesar.");
      return;
    }

    const actions = snapshot.val();
    // Diccionario para acumular: { "world_id": { likes: 5, downloads: 10 } }
    let aggregated = {};

    for (const pushId in actions) {
      const action = actions[pushId];
      const wId = action.world_id;
      const type = action.type; // "like" o "download"

      if (!wId || !type) continue;
      
      if (!aggregated[wId]) {
        aggregated[wId] = { likes: 0, downloads: 0, reports: 0 };
      }

      if (type === "like") aggregated[wId].likes += 1;
      else if (type === "unlike") aggregated[wId].likes -= 1;
      else if (type === "download") aggregated[wId].downloads += 1;
      else if (type === "report") aggregated[wId].reports += 1;
    }

    // Actualizar en Firestore mediante transacciones (para asegurar incrementos relativos)
    // Usamos batches por eficiencia, pero como solo tenemos el id, un update con FieldValue.increment
    // no gasta lecturas previas.
    const { FieldValue } = require("firebase-admin/firestore");
    const batch = db.batch();
    
    let processedCount = 0;
    for (const wId in aggregated) {
      const stats = aggregated[wId];
      if (stats.likes === 0 && stats.downloads === 0 && stats.reports === 0) continue;

      const worldRef = db.collection("community_worlds").doc(wId);
      const updates = {};
      
      if (stats.likes !== 0) updates.likes = FieldValue.increment(stats.likes);
      if (stats.downloads > 0) updates.downloads = FieldValue.increment(stats.downloads);
      if (stats.reports > 0) updates.reports = FieldValue.increment(stats.reports);
      
      // NOTA: historical_score y weekly_score también deberían incrementarse.
      // 1 like = 10 puntos, 1 download = 1 punto, 1 report = -20 puntos.
      const scoreIncrement = (stats.likes * 10) + (stats.downloads * 1) - (stats.reports * 20);
      if (scoreIncrement !== 0) {
        updates.historical_score = FieldValue.increment(scoreIncrement);
        updates.weekly_score = FieldValue.increment(scoreIncrement);
      }

      batch.update(worldRef, updates);
      processedCount++;
      
      // Si el batch supera los 500, habría que hacer commit y abrir otro, 
      // pero es raro superar 500 mundos en 10 minutos para un indie.
    }

    if (processedCount > 0) {
      await batch.commit();
      console.log(`Procesados y actualizados ${processedCount} mundos con éxito.`);
    }

    // Vaciar el buffer en RTDB
    await bufferRef.remove();
    console.log("Buffer de RTDB vaciado correctamente.");
    
  } catch (error) {
    console.error("Error al procesar el Action Buffer:", error);
  }
});