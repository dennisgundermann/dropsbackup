/**
 * Drops Cleanup Cloud Functions
 *
 * Scheduled housekeeping that the iOS client shouldn't be responsible for:
 *   - Delete expired drops (expiresAt < now)
 *   - Delete DropIns / JoinRequests belonging to gone drops
 *   - Delete encounters older than 90 days
 *   - Delete phoneIndex / emailIndex entries pointing to gone users
 *   - Delete deletedAccounts tombstones older than 30 days
 *   - Delete Firebase Auth users that have had a tombstone for 90+ days
 *
 * Runs daily at 03:00 Europe/Berlin. Low cost, high reliability.
 *
 * Deploy:
 *   cd functions
 *   npm install
 *   firebase deploy --only functions
 *
 * Requires the Blaze (pay-as-you-go) plan. Free tier: 2M invocations/month —
 * this function runs once per day, well within the free allowance.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onValueCreated, onValueUpdated, onValueWritten } from "firebase-functions/v2/database";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { getMessaging } from "firebase-admin/messaging";
import { getAuth } from "firebase-admin/auth";

const DB_URL = "https://drops-858d1-default-rtdb.europe-west1.firebasedatabase.app";
const TZ = "Europe/Berlin";

initializeApp({ databaseURL: DB_URL });

// ── Main entry — scheduled once per day ──────────────────────────────────────

export const dailyCleanup = onSchedule(
    { schedule: "0 3 * * *", timeZone: TZ, region: "europe-west1", timeoutSeconds: 540 },
    async () => {
        const db = getDatabase();
        const auth = getAuth();
        const now = Date.now();

        const dropsRemoved = await cleanupExpiredDrops(db, now);
        const encountersRemoved = await cleanupOldEncounters(db, now);
        const indexRemoved = await cleanupOrphanedIndex(db);
        const tombstoneUids = await collectExpiredTombstones(db, now);
        const authDeleted = await deleteAuthAccountsForTombstones(auth, tombstoneUids);

        logger.info("dailyCleanup summary", {
            dropsRemoved, encountersRemoved, indexRemoved,
            tombstoneCollected: tombstoneUids.length, authDeleted,
        });
    }
);

// ── Drops older than expiresAt, plus their DropIns/JoinRequests ─────────────

async function cleanupExpiredDrops(db: FirebaseFirestore.Firestore | any, now: number): Promise<number> {
    const ref = db.ref("drops");
    const snap = await ref.once("value");
    if (!snap.exists()) return 0;

    const updates: Record<string, null | number | boolean> = {};
    let count = 0;

    // Ghost-Drops Schema: nach Drop-Ende bleibt der Drop für GHOST_TTL_MS in
    // /drops/ mit endedAt-Timestamp (iOS rendert als verblassten Marker).
    // Erst nach Ablauf des TTLs hartes Delete.
    // 90 Min — kompakt genug damit die Map nicht überquillt, lang genug
    // damit User auch noch was sehen wenn sie 30 Min nach dem Drop schauen.
    const GHOST_TTL_MS      = 90 * 60 * 1000;  // normale Ghost-Drops: 90 Min
    const DEMO_GHOST_TTL_MS = 60 * 60 * 1000;  // Demo-Drops: 60 Min (kürzer)

    snap.forEach((child: any) => {
        const dict = child.val() ?? {};
        const expiresAtSec = dict.expiresAt as number | undefined;
        const tsMs = dict.timestamp as number | undefined;
        const endedAtMs = dict.endedAt as number | undefined;
        const isDemo = (dict.isDemo as boolean | undefined) === true;
        const effectiveTTL = isDemo ? DEMO_GHOST_TTL_MS : GHOST_TTL_MS;

        // 1. Wenn endedAt existiert: löschen wenn TTL abgelaufen.
        if (typeof endedAtMs === "number") {
            if (now - endedAtMs > effectiveTTL) {
                updates[`drops/${child.key}`] = null;
                updates[`dropins/${child.key}`] = null;
                updates[`joinRequests/${child.key}`] = null;
                count++;
            }
            return false;
        }

        // 2. endedAt fehlt — prüfen ob Drop expired ist (Time-Out ohne
        //    aktives Cancellation). Dann endedAt nachziehen damit der
        //    Ghost-Layer für 4h sichtbar wird.
        let isExpired = false;
        if (typeof expiresAtSec === "number") {
            isExpired = now > expiresAtSec * 1000;
        } else if (typeof tsMs === "number") {
            isExpired = now - tsMs > 12 * 60 * 60 * 1000;
        } else {
            isExpired = true; // kein Zeitstempel → sofort löschen
        }

        if (isExpired) {
            // Wenn nie zeitlich verankert: direkt löschen statt Ghost.
            if (typeof expiresAtSec !== "number" && typeof tsMs !== "number") {
                updates[`drops/${child.key}`] = null;
                updates[`dropins/${child.key}`] = null;
                updates[`joinRequests/${child.key}`] = null;
                count++;
            } else {
                // Phase-1: Ghost-Übergang. Marker für iOS-Layer setzen.
                updates[`drops/${child.key}/endedAt`] = now;
                updates[`drops/${child.key}/active`] = false;
            }
        }
        return false;
    });

    if (Object.keys(updates).length > 0) await db.ref().update(updates);
    return count;
}

// ── Encounters older than 90 days ────────────────────────────────────────────

async function cleanupOldEncounters(db: any, now: number): Promise<number> {
    const cutoff = now - 90 * 24 * 60 * 60 * 1000;
    const snap = await db.ref("encounters").once("value");
    if (!snap.exists()) return 0;

    const updates: Record<string, null> = {};
    let count = 0;
    snap.forEach((child: any) => {
        const ts = child.val()?.timestamp as number | undefined;
        const tsMs = typeof ts === "number" ? (ts > 1e12 ? ts : ts * 1000) : 0;
        if (tsMs > 0 && tsMs < cutoff) {
            updates[`encounters/${child.key}`] = null;
            count++;
        }
        return false;
    });
    if (count > 0) await db.ref().update(updates);
    return count;
}

// ── phoneIndex / emailIndex entries whose uid no longer exists ───────────────

async function cleanupOrphanedIndex(db: any): Promise<number> {
    const [phoneSnap, emailSnap, usersSnap] = await Promise.all([
        db.ref("phoneIndex").once("value"),
        db.ref("emailIndex").once("value"),
        db.ref("users").once("value"),
    ]);

    const existingUids = new Set<string>();
    usersSnap.forEach((c: any) => { existingUids.add(c.key); return false; });

    const updates: Record<string, null> = {};
    let count = 0;

    phoneSnap.forEach((c: any) => {
        const uid = c.val()?.uid as string | undefined;
        if (uid && !existingUids.has(uid)) {
            updates[`phoneIndex/${c.key}`] = null;
            count++;
        }
        return false;
    });
    emailSnap.forEach((c: any) => {
        const uid = c.val()?.uid as string | undefined;
        if (uid && !existingUids.has(uid)) {
            updates[`emailIndex/${c.key}`] = null;
            count++;
        }
        return false;
    });

    if (count > 0) await db.ref().update(updates);
    return count;
}

// ── Tombstones older than 30 days → collect uids (for auth deletion) ────────

async function collectExpiredTombstones(db: any, now: number): Promise<string[]> {
    const cutoff = now - 30 * 24 * 60 * 60 * 1000;
    const snap = await db.ref("deletedAccounts").once("value");
    if (!snap.exists()) return [];
    const uids: string[] = [];
    snap.forEach((child: any) => {
        const deletedAt = child.val()?.deletedAt as number | undefined;
        const tsMs = typeof deletedAt === "number" ? (deletedAt > 1e12 ? deletedAt : deletedAt * 1000) : 0;
        if (tsMs > 0 && tsMs < cutoff) uids.push(child.key);
        return false;
    });
    return uids;
}

// ── Delete Firebase Auth accounts for collected tombstones, then drop the
//    tombstone itself (it's fulfilled its purpose).
async function deleteAuthAccountsForTombstones(auth: any, uids: string[]): Promise<number> {
    if (uids.length === 0) return 0;
    const db = getDatabase();
    const updates: Record<string, null> = {};
    let deleted = 0;
    for (const uid of uids) {
        try {
            await auth.deleteUser(uid);
            deleted++;
        } catch (e: any) {
            // user/not-found ist ok — Auth wurde schon gelöscht; tombstone bleibt
            if (e?.code === "auth/user-not-found") {
                deleted++;
            } else {
                logger.warn(`auth.deleteUser failed for ${uid}`, { error: e?.message });
                continue;
            }
        }
        updates[`deletedAccounts/${uid}`] = null;
    }
    if (Object.keys(updates).length > 0) await db.ref().update(updates);
    return deleted;
}

// ── Friend Request Push ────────────────────────────────────────────────────

/**
 * Wenn friendRequests/{recipientUID}/{senderUID} geschrieben wird → Push an
 * recipientUID mit "{senderName} möchte mit dir befreundet sein".
 *
 * Der Client hinterlegt beim Schreiben `fromName` und optional `fromImageURL`
 * als Payload — wir brauchen also keinen separaten users/-Lookup für den Namen.
 */
export const onFriendRequestCreated = onValueCreated(
    { ref: "/friendRequests/{recipientUID}/{senderUID}", region: "europe-west1" },
    async (event) => {
        const { recipientUID, senderUID } = event.params;
        if (recipientUID === senderUID) return;

        const db = getDatabase();
        const tokenSnap = await db.ref(`users/${recipientUID}/fcmToken`).once("value");
        const token = tokenSnap.val() as string | null;
        if (!token) {
            logger.info("onFriendRequestCreated: no FCM token for recipient", { recipientUID });
            return;
        }

        const val = event.data.val() ?? {};
        const senderName = (val.fromName as string | null) ?? "Jemand";

        try {
            await getMessaging().send({
                token,
                notification: {
                    title: "Neue Freundschaftsanfrage",
                    body: `${senderName} möchte mit dir befreundet sein.`,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            category: "FRIEND_REQUEST",
                        },
                    },
                },
                data: {
                    type: "friend_request",
                    senderUID,
                    senderName,
                },
            });
            logger.info("onFriendRequestCreated sent", { recipientUID, senderUID });
        } catch (e: any) {
            logger.warn("FCM send failed", { recipientUID, error: e?.message });
        }
    }
);

// ── Friendship Push ────────────────────────────────────────────────────────

/**
 * Wenn friends/{recipientUID}/{adderUID} = true geschrieben wird → Push an
 * recipientUID mit "{adderName} hat dich als Freund hinzugefügt".
 *
 * Voraussetzung: Der Empfänger hat seinen FCM-Token in users/{uid}/fcmToken
 * hinterlegt (schreibt der iOS-Client beim Launch).
 *
 * Der iOS-Client schreibt die Freundschaft bidirektional — d.h. wenn A B als
 * Freund hinzufügt, werden BEIDE Pfade (friends/A/B und friends/B/A) geschrieben.
 * Wir schicken den Push nur an den Empfänger (der den Add nicht ausgelöst hat),
 * damit der Adder keinen Push für seinen eigenen Add kriegt.
 */
export const onFriendshipAdded = onValueCreated(
    { ref: "/friends/{recipientUID}/{adderUID}", region: "europe-west1" },
    async (event) => {
        const { recipientUID, adderUID } = event.params;
        if (recipientUID === adderUID) return;

        const db = getDatabase();

        // Metadaten parallel laden — Token des Empfängers + Name des Adders
        const [tokenSnap, adderSnap, markerSnap] = await Promise.all([
            db.ref(`users/${recipientUID}/fcmToken`).once("value"),
            db.ref(`users/${adderUID}/name`).once("value"),
            db.ref(`friendshipPushSent/${recipientUID}/${adderUID}`).once("value"),
        ]);

        // Der iOS-Client schreibt beide Pfade — wir würden sonst zweimal pushen.
        // Markerwert dedupliziert: der erste der beiden Trigger setzt den Marker,
        // der zweite findet ihn und bricht ab.
        if (markerSnap.exists()) {
            logger.debug("onFriendshipAdded: already sent", { recipientUID, adderUID });
            return;
        }
        await db.ref(`friendshipPushSent/${recipientUID}/${adderUID}`)
            .set({ at: Date.now() });

        const token = tokenSnap.val() as string | null;
        if (!token) {
            logger.info("onFriendshipAdded: no FCM token for recipient", { recipientUID });
            return;
        }
        const adderName = (adderSnap.val() as string | null) ?? "Jemand";

        try {
            await getMessaging().send({
                token,
                notification: {
                    title: "Neuer Freund",
                    body: `${adderName} hat dich als Freund hinzugefügt.`,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            category: "FRIENDSHIP_ADDED",
                        },
                    },
                },
                data: {
                    type: "friendship_added",
                    adderUID,
                    adderName,
                },
            });
            logger.info("onFriendshipAdded sent", { recipientUID, adderUID });
        } catch (e: any) {
            logger.warn("FCM send failed", { recipientUID, error: e?.message });
        }
    }
);

// ── New-Drop Nearby Push ──────────────────────────────────────────────────
//
// Wenn jemand einen Drop erstellt → benachrichtige alle User mit lastLat/lastLng
// im Umkreis von NEARBY_RADIUS_METERS (1500m für Launch-Phase, später runter
// auf 600m). Der Host selbst wird ausgeschlossen.
//
// users/{uid}/lastLat, lastLng werden vom iOS-Client throttled geschrieben
// (1× pro 10 Min, gerundet auf ~110m für Privacy).

const NEARBY_RADIUS_METERS = 1500;

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371000;
    const toRad = (d: number) => (d * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
}

export const onDropCreatedNearbyPush = onValueCreated(
    { ref: "/drops/{dropID}", region: "europe-west1" },
    async (event) => {
        const drop = event.data.val() ?? {};
        // Demo-Drops nie pushen — kein echter User dahinter.
        if (drop.isDemo === true) return;
        // Inaktive Drops (z.B. geplant aber noch nicht gestartet) nicht pushen.
        if (drop.active === false) return;
        // iOS schreibt "lat"/"lng" — NICHT "latitude"/"longitude"
        const dropLat = (drop.lat ?? drop.latitude) as number | undefined;
        const dropLng = (drop.lng ?? drop.longitude) as number | undefined;
        const hostUID = drop.userID as string | undefined;
        const emoji = (drop.emoji as string) || "📍";
        const activity = (drop.activityName as string) || "Drop";

        if (typeof dropLat !== "number" || typeof dropLng !== "number") {
            logger.info("onDropCreatedNearbyPush: drop has no coords, skipping");
            return;
        }

        const db = getDatabase();
        const usersSnap = await db.ref("users").once("value");
        const users = (usersSnap.val() ?? {}) as Record<string, any>;

        const recipients: { uid: string; token: string; distM: number }[] = [];
        for (const [uid, u] of Object.entries(users)) {
            if (uid === hostUID) continue;                  // Host nicht selber benachrichtigen
            if (u?.isBanned === true) continue;
            const token = u?.fcmToken as string | undefined;
            const lat = u?.lastLat as number | undefined;
            const lng = u?.lastLng as number | undefined;
            if (!token || typeof lat !== "number" || typeof lng !== "number") continue;
            const d = haversineMeters(dropLat, dropLng, lat, lng);
            if (d <= NEARBY_RADIUS_METERS) {
                recipients.push({ uid, token, distM: d });
            }
        }

        if (recipients.length === 0) {
            logger.info("onDropCreatedNearbyPush: no nearby users", { hostUID });
            return;
        }

        // Distanz-String pro Empfänger personalisieren ("400 m" / "1.2 km")
        const sends = recipients.map(async (r) => {
            const distStr =
                r.distM < 1000 ? `${Math.round(r.distM)} m` : `${(r.distM / 1000).toFixed(1)} km`;
            try {
                await getMessaging().send({
                    token: r.token,
                    notification: {
                        title: `${emoji} ${activity} in der Nähe`,
                        body: `Nur ${distStr} entfernt — schau auf die Karte.`,
                    },
                    apns: {
                        payload: { aps: { sound: "default", category: "NEARBY_DROP" } },
                    },
                    data: {
                        type: "nearby_drop",
                        dropID: event.params.dropID,
                        hostUID: hostUID ?? "",
                    },
                });
            } catch (e: any) {
                logger.warn("nearby push send failed", { uid: r.uid, error: e?.message });
            }
        });
        await Promise.allSettled(sends);
        logger.info("onDropCreatedNearbyPush done", {
            dropID: event.params.dropID,
            recipients: recipients.length,
        });
    }
);

// ── City Inactivity Push ──────────────────────────────────────────────────
//
// Täglich 18:00 Europe/Berlin: pro Service-Stadt zählen wir aktive Drops der
// letzten 3 Tage. Wenn 0 → einmal pro Stadt einen "Sei der Erste"-Push an
// alle User in dieser Stadt. User-Stadt wird aus letzter bekannter Position
// (lastLat/lastLng) abgeleitet.
//
// Service-Cities (in sync mit iOS Drops/CityGateView.swift)
const SERVICE_CITIES: { name: string; lat: number; lng: number; radiusKm: number }[] = [
    { name: "München",   lat: 48.1371, lng: 11.5754, radiusKm: 25 },
    { name: "Berlin",    lat: 52.5200, lng: 13.4050, radiusKm: 30 },
    { name: "Hamburg",   lat: 53.5511, lng: 9.9937,  radiusKm: 25 },
    { name: "Köln",      lat: 50.9375, lng: 6.9603,  radiusKm: 22 },
    { name: "Frankfurt", lat: 50.1109, lng: 8.6821,  radiusKm: 22 },
];

function cityForCoord(lat: number, lng: number): string | null {
    for (const c of SERVICE_CITIES) {
        const d = haversineMeters(lat, lng, c.lat, c.lng);
        if (d <= c.radiusKm * 1000) return c.name;
    }
    return null;
}

export const cityInactivityPush = onSchedule(
    { schedule: "0 18 * * *", timeZone: TZ, region: "europe-west1" },
    async () => {
        const db = getDatabase();
        const dropsSnap = await db.ref("drops").once("value");
        const usersSnap = await db.ref("users").once("value");
        const now = Date.now();
        const threeDaysAgo = now - 3 * 24 * 60 * 60 * 1000;

        // 1) Pro Stadt: aktive Drops der letzten 3 Tage zählen
        const activityByCity: Record<string, number> = {};
        SERVICE_CITIES.forEach((c) => (activityByCity[c.name] = 0));
        const drops = (dropsSnap.val() ?? {}) as Record<string, any>;
        for (const d of Object.values(drops)) {
            const lat = d?.latitude as number | undefined;
            const lng = d?.longitude as number | undefined;
            const created = d?.createdAt as number | undefined;
            if (typeof lat !== "number" || typeof lng !== "number") continue;
            if (typeof created !== "number" || created < threeDaysAgo) continue;
            const city = cityForCoord(lat, lng);
            if (city) activityByCity[city]++;
        }

        // 2) Pro inaktiver Stadt: Push an alle User dort
        const inactiveCities = SERVICE_CITIES.filter((c) => activityByCity[c.name] === 0);
        if (inactiveCities.length === 0) {
            logger.info("cityInactivityPush: alle Städte aktiv ✓");
            return;
        }

        const users = (usersSnap.val() ?? {}) as Record<string, any>;
        for (const city of inactiveCities) {
            const tokens: string[] = [];
            for (const u of Object.values(users)) {
                if (u?.isBanned === true) continue;
                const token = u?.fcmToken as string | undefined;
                const lat = u?.lastLat as number | undefined;
                const lng = u?.lastLng as number | undefined;
                if (!token || typeof lat !== "number" || typeof lng !== "number") continue;
                if (cityForCoord(lat, lng) === city.name) tokens.push(token);
            }
            if (tokens.length === 0) continue;

            // Batch via sendEachForMulticast (max 500 per call)
            try {
                await getMessaging().sendEachForMulticast({
                    tokens,
                    notification: {
                        title: `${city.name} braucht dich`,
                        body: "Gerade ist hier nix los. Mach den ersten Plan des Abends.",
                    },
                    apns: {
                        payload: { aps: { sound: "default", category: "CITY_INACTIVE" } },
                    },
                    data: { type: "city_inactive", city: city.name },
                });
                logger.info("cityInactivityPush sent", {
                    city: city.name,
                    recipients: tokens.length,
                });
            } catch (e: any) {
                logger.warn("cityInactivityPush failed", { city: city.name, error: e?.message });
            }
        }
    }
);

// ── 30-Min-Reminder vor Drop-Start ────────────────────────────────────────
//
// Läuft alle 5 Minuten: findet Drops mit `startAt` in [now+25min, now+35min]
// und `reminderSent != true`. Sendet Push an Host + alle Joiner (aus dropins/),
// markiert dann `reminderSent: true` damit nicht doppelt gefeuert wird.
//
// startAt wird vom iOS-Client beim Publish geschrieben (parseDropStartAt in
// RealtimeDBManager.swift). Drops mit scheduledTime "Jetzt" haben startAt ≈
// createdAt → fallen NICHT ins 25–35min-Fenster, kein Reminder.

export const dropStartReminder = onSchedule(
    { schedule: "every 5 minutes", timeZone: TZ, region: "europe-west1" },
    async () => {
        const db = getDatabase();
        const now = Date.now();
        const windowStart = now + 25 * 60 * 1000;
        const windowEnd   = now + 35 * 60 * 1000;

        const [dropsSnap, usersSnap] = await Promise.all([
            db.ref("drops").once("value"),
            db.ref("users").once("value"),
        ]);
        const drops = (dropsSnap.val() ?? {}) as Record<string, any>;
        const users = (usersSnap.val() ?? {}) as Record<string, any>;

        let triggeredDrops = 0;
        let totalSends = 0;

        for (const [dropID, drop] of Object.entries(drops)) {
            if (!drop || drop.active === false) continue;
            if (drop.reminderSent === true) continue;
            const startAtSec = drop.startAt as number | undefined;
            if (typeof startAtSec !== "number") continue;
            const startAtMs = startAtSec * 1000;
            if (startAtMs < windowStart || startAtMs > windowEnd) continue;

            // Atomarer Check-and-Set via Transaction — verhindert Doppel-Send
            // bei parallelen Function-Invocations oder Retries: nur die erste
            // Instanz die `reminderSent: false` vorfindet, bekommt `committed: true`.
            const reminderRef = db.ref(`drops/${dropID}/reminderSent`);
            const txResult = await reminderRef.transaction((current: boolean | null) => {
                if (current === true) return; // abbrechen → kein Commit
                return true;                  // atomar auf true setzen
            });
            if (!txResult.committed) continue; // andere Instanz war schneller

            const hostUID  = (drop.userID as string | undefined) ?? "";
            const emoji    = (drop.emoji as string) || "📍";
            const activity = (drop.activityName as string) || "Drop";

            // Empfänger sammeln: Host + alle Joiner aus dropins/{dropID}
            const recipientUIDs = new Set<string>();
            if (hostUID) recipientUIDs.add(hostUID);
            const dropinsSnap = await db.ref(`dropins/${dropID}`).once("value");
            dropinsSnap.forEach((c) => {
                if (c.key) recipientUIDs.add(c.key);
                return false;
            });

            const tokenSends: Promise<any>[] = [];
            for (const uid of recipientUIDs) {
                const u = users[uid];
                const token = u?.fcmToken as string | undefined;
                if (!token || u?.isBanned === true) continue;
                const isHost = uid === hostUID;
                tokenSends.push(
                    getMessaging().send({
                        token,
                        notification: {
                            title: isHost
                                ? `Dein Plan startet in 30 Min`
                                : `${emoji} ${activity} startet in 30 Min`,
                            body: isHost
                                ? "Mach dich bereit — die anderen kommen gleich."
                                : "Zeit, sich auf den Weg zu machen.",
                        },
                        apns: {
                            payload: { aps: { sound: "default", category: "DROP_REMINDER" } },
                        },
                        data: {
                            type: "drop_reminder",
                            dropID,
                            hostUID,
                        },
                    }).catch((e: any) => {
                        logger.warn("dropStartReminder send failed", {
                            uid, dropID, error: e?.message,
                        });
                    })
                );
            }

            await Promise.allSettled(tokenSends);
            triggeredDrops++;
            totalSends += tokenSends.length;
        }

        if (triggeredDrops > 0) {
            logger.info("dropStartReminder done", { triggeredDrops, totalSends });
        }
    }
);

// ═══════════════════════════════════════════════════════════════════
// PUBLIC DROP SUMMARY — für drop.html Landing-Page (Universal Link)
// ═══════════════════════════════════════════════════════════════════
//
// HTTP-Endpoint der Drop-Daten als JSON liefert, damit drops-app.de/drop/<id>
// dem geteilten Empfänger schon VOR Install den Drop-Preview zeigen kann
// (Strava-Pattern). Nutzt Admin-SDK → umgeht die DB-Rules (drops/* erfordert
// auth != null). Liefert nur einen minimalen Subset, keine Personen-Daten.
//
// Beispiel-Request:
//   GET https://<region>-drops-858d1.cloudfunctions.net/getDropSummary?id=<uuid>
// Response:
//   { activityName, activityEmoji, locationTitle, hostName, hostEmoji,
//     currentParticipants, maxParticipants, expiresAt, createdAt, isLive }
//
// CORS: erlaubt dazuapp.com + drops-app.de (jeweils mit www) für Browser-Fetch.


// In-Memory Rate-Limiter pro Cloud-Function-Instance.
// Schützt gegen naive Scraper. Für DDoS-Schutz braucht's später App-Check
// oder distributed limiter (Firestore-counter) — diese Variante ist „good
// enough" für eine öffentliche Drop-Preview die kaum Traffic hat.
const summaryRateLimits = new Map<string, { count: number; resetAt: number }>();
const RATE_WINDOW_MS = 60_000;
const RATE_MAX_PER_WINDOW = 60;
function checkRateLimit(ip: string): boolean {
    const now = Date.now();
    const entry = summaryRateLimits.get(ip);
    if (!entry || entry.resetAt < now) {
        summaryRateLimits.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
        return true;
    }
    if (entry.count >= RATE_MAX_PER_WINDOW) return false;
    entry.count++;
    return true;
}
// Strip HTML-Tags und entity-escape — defensive für Clients die data
// versehentlich via innerHTML rendern. Trim auch zu lange Strings.
function sanitizePublic(v: unknown, maxLen = 120): string {
    if (typeof v !== "string") return "";
    return v.replace(/<[^>]*>/g, "")
            .replace(/[<>&"']/g, c => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", "\"": "&quot;", "'": "&#39;" }[c]!))
            .slice(0, maxLen);
}

export const getDropSummary = onRequest(
    { region: "europe-west1", cors: ["https://dazuapp.com", "https://www.dazuapp.com", "https://drops-app.de", "https://www.drops-app.de"] },
    async (req, res) => {
        // Rate-Limit pro IP (x-forwarded-for von Firebase Hosting Proxy, sonst direct).
        const ip = (req.headers["x-forwarded-for"] as string | undefined)?.split(",")[0].trim()
                 || req.ip
                 || "unknown";
        if (!checkRateLimit(ip)) {
            res.status(429).json({ error: "rate limit exceeded" });
            return;
        }

        const dropID = (req.query.id as string | undefined)?.trim();
        if (!dropID || !/^[A-Z0-9-]{8,64}$/i.test(dropID)) {
            res.status(400).json({ error: "missing or invalid id" });
            return;
        }

        try {
            const snap = await getDatabase().ref(`drops/${dropID}`).get();
            if (!snap.exists()) {
                res.status(404).json({ error: "drop not found or expired" });
                return;
            }
            const d = snap.val() as Record<string, unknown>;
            const now = Date.now();
            // RTDB speichert Unix-Timestamps in Sekunden (Swift: Date().timeIntervalSince1970).
            // Für den JS-Client alles in ms-Epoch umrechnen.
            // Robuste Erkennung: Werte < 1e10 sind Sekunden, >= 1e10 bereits ms.
            const toMs = (v: unknown): number => {
                if (typeof v !== "number" || v === 0) return 0;
                return v < 1e10 ? v * 1000 : v;
            };
            const expiresAt = toMs(d.expiresAt);
            const createdAt = toMs(d.createdAt);

            // CDN-Cache 60s — reduziert Backend-Last bei viralen Drops.
            res.set("Cache-Control", "public, max-age=60");
            // Public-Subset — keine Personen-Daten, keine Standort-Koords.
            // Alle user-provided Strings durch sanitizePublic() (HTML-strip + escape).
            res.status(200).json({
                id: dropID,
                activityName:        sanitizePublic(d.activityName)         || "Drop",
                activityEmoji:       sanitizePublic(d.emoji ?? d.activityEmoji, 8) || "📍",
                locationTitle:       sanitizePublic(d.locationTitle),
                hostName:            sanitizePublic(d.displayName ?? d.hostName ?? d.userName, 40) || "Jemand",
                hostEmoji:           sanitizePublic(d.hostEmoji ?? d.userEmoji, 8) || "👤",
                scheduledTime:       sanitizePublic(d.scheduledTime, 40)    || "Jetzt",
                currentParticipants: d.currentParticipants ?? 1,
                maxParticipants:     d.maxParticipants ?? 10,
                createdAt,
                expiresAt,
                isLive: expiresAt > now && createdAt <= now,
            });
        } catch (err) {
            logger.error("getDropSummary failed", { dropID, err });
            res.status(500).json({ error: "internal" });
        }
    }
);


// ═══════════════════════════════════════════════════════════════════
// DROP ENDED — Push an alle Joiner wenn Host den Drop beendet
// ═══════════════════════════════════════════════════════════════════
//
// Trigger: drops/{dropID}/active wird auf false gesetzt (Host hat
// cancelDrop ausgeführt). Wir lesen die Joiner aus dropins/{dropID}
// und schicken jedem einen FCM-Push. Lokaler Push auf Joiner-Seite
// hat den Nachteil dass er nicht greift wenn die App im Background
// gekillt ist — diese Function läuft serverseitig und ist daher
// zuverlässig.
//
// Idempotenz: läuft nur wenn `before == true && after == false`.
// Mehrfache `active: false`-Writes triggern nicht doppelt.

export const onDropEndedPush = onValueUpdated(
    {
        ref: "/drops/{dropID}/active",
        region: "europe-west1",
        timeoutSeconds: 60,
    },
    async (event) => {
        const before = event.data.before.val();
        const after = event.data.after.val();
        // Nur bei echtem Übergang true → false feuern.
        if (before !== true || after !== false) return;

        const dropID = event.params.dropID;
        const db = getDatabase();

        // Drop-Metadaten lesen für Push-Text (Emoji + Activity-Name).
        const dropSnap = await db.ref(`drops/${dropID}`).get();
        if (!dropSnap.exists()) return;
        const drop = dropSnap.val() as Record<string, unknown>;
        const emoji = (drop.activityEmoji as string) || "📍";
        const activity = (drop.activityName as string) || "Drop";
        const hostName = (drop.hostName as string) || (drop.userName as string) || "Host";
        const hostUID = (drop.userID as string | undefined);

        // Ghost-Drops: endedAt setzen damit iOS den Drop für 4h als verblassten
        // Geist auf der Karte weiter zeigen kann ("Hier war was los — neuen
        // Drop starten?"). Idempotent — nur setzen wenn noch nicht da.
        if (!drop.endedAt) {
            try {
                await db.ref(`drops/${dropID}/endedAt`).set(Date.now());
            } catch (err) {
                logger.warn("onDropEndedPush: endedAt write failed", { dropID, err });
            }
        }

        // Joiner-UIDs aus drops/{dropID}/joinerIDs lesen statt aus dropins/.
        // Hintergrund: dropins/ wird vom Joiner-Client aufgeräumt sobald
        // active=false kommt — oft schneller als diese Function die Daten
        // liest (Race Condition). joinerIDs wird beim Accept in den Drop-
        // Node geschrieben und nur beim freiwilligen Leave entfernt, daher
        // stabil zum Zeitpunkt des Drop-Endes.
        const joinerIDsSnap = await db.ref(`drops/${dropID}/joinerIDs`).get();
        if (!joinerIDsSnap.exists()) {
            logger.info("onDropEndedPush: no joinerIDs for drop", { dropID });
            return;
        }

        const joinerUIDs: string[] = [];
        joinerIDsSnap.forEach((child) => {
            const uid = child.key;
            if (uid && uid !== hostUID) joinerUIDs.push(uid);
            return false;
        });

        if (joinerUIDs.length === 0) {
            logger.info("onDropEndedPush: no joiners to notify", { dropID });
            return;
        }

        // FCM-Tokens parallel laden, dann pushen.
        const messaging = getMessaging();
        let sent = 0;
        await Promise.all(joinerUIDs.map(async (uid) => {
            try {
                const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
                const token = tokenSnap.val() as string | undefined;
                if (!token) return;

                await messaging.send({
                    token,
                    notification: {
                        title: `${emoji} Plan abgesagt`,
                        body: `${hostName} hat „${activity}" abgesagt. Du bist raus.`,
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: "default",
                                badge: 1,
                                "thread-id": `drop-${dropID}`,
                                category: "DROP_ENDED",
                            },
                        },
                    },
                    data: {
                        type: "drop_ended",
                        dropID,
                        activityName: activity,
                        activityEmoji: emoji,
                    },
                });
                sent++;
            } catch (err) {
                logger.warn(`onDropEndedPush: send failed for ${uid}`, { err });
            }
        }));

        logger.info("onDropEndedPush done", { dropID, joinerCount: joinerUIDs.length, sent });
    }
);

// ── Community Push Fan-Out ─────────────────────────────────────────────────
//
// Wenn ein Creator einen Push in `communityPushQueue/{communityID}/{pushID}`
// schreibt, läuft diese Function: holt alle Member-UIDs aus
// `communityMembers/{communityID}/`, lädt deren FCM-Tokens aus
// `users/{uid}/fcmToken` und schickt jedem die Notification.
//
// Der Creator selbst bekommt keinen eigenen Push.
//
// Rate-Limit (3/Tag) wird clientseitig geprüft — hier kein Re-Check,
// aber die Function loggt die Anzahl, sodass Missbrauch auffällt.

export const onCommunityPushQueued = onValueCreated(
    {
        ref: "/communityPushQueue/{communityID}/{pushID}",
        region: "europe-west1",
        timeoutSeconds: 60,
    },
    async (event) => {
        const { communityID, pushID } = event.params;
        const payload = event.data.val() as Record<string, unknown> | null;
        if (!payload) return;

        const title = (payload.title as string | undefined)?.trim() || "Community Update";
        const body  = (payload.body  as string | undefined)?.trim() || "";
        if (!body) {
            logger.info("onCommunityPushQueued: empty body — skipping", { communityID, pushID });
            return;
        }

        const db = getDatabase();

        // Community-Metadaten für Push-Kontext (Activity-Name, Creator).
        const commSnap = await db.ref(`communities/${communityID}`).get();
        if (!commSnap.exists()) {
            logger.warn("onCommunityPushQueued: community missing", { communityID });
            return;
        }
        const comm = commSnap.val() as Record<string, unknown>;
        const activitySlug = (comm.activitySlug as string | undefined) ?? "";
        const creatorUID   = (comm.creatorUID   as string | undefined) ?? communityID;

        // Member-UIDs holen (alle außer dem Creator).
        const membersSnap = await db.ref(`communityMembers/${communityID}`).get();
        if (!membersSnap.exists()) {
            logger.info("onCommunityPushQueued: no members yet", { communityID });
            return;
        }

        const memberUIDs: string[] = [];
        membersSnap.forEach((child) => {
            const uid = child.key;
            if (uid && uid !== creatorUID) memberUIDs.push(uid);
            return false;
        });

        if (memberUIDs.length === 0) {
            logger.info("onCommunityPushQueued: no recipients (only creator)", { communityID });
            return;
        }

        // Tokens parallel laden + pushen.
        const messaging = getMessaging();
        let sent = 0;
        let skipped = 0;
        await Promise.all(memberUIDs.map(async (uid) => {
            try {
                const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
                const token = tokenSnap.val() as string | undefined;
                if (!token) { skipped++; return; }

                await messaging.send({
                    token,
                    notification: { title, body },
                    apns: {
                        payload: {
                            aps: {
                                sound: "default",
                                "thread-id": `community-${communityID}`,
                                category: "COMMUNITY_PUSH",
                            },
                        },
                    },
                    data: {
                        type: "community_push",
                        communityID,
                        pushID,
                        activitySlug,
                    },
                });
                sent++;
            } catch (err) {
                logger.warn(`onCommunityPushQueued: send failed for ${uid}`, { err });
            }
        }));

        logger.info("onCommunityPushQueued done", {
            communityID, pushID, memberCount: memberUIDs.length, sent, skipped,
        });
    }
);

// ── Welcome-Push an den Creator wenn ein Mitglied beitritt ──────────────────
//
// Triggert auf jeden neuen Eintrag in `communityMembers/{communityID}/{joinerUID}`.
// Lädt Community-Daten + Joiner-Name + Creator-Token und sendet eine kurze
// Benachrichtigung an den Creator: "Max ist deiner Tennis-Community beigetreten."
//
// Skip: wenn der Creator selbst joint (Initial bei Approve) → kein Push an sich.

export const onCommunityMemberJoined = onValueCreated(
    {
        ref: "/communityMembers/{communityID}/{joinerUID}",
        region: "europe-west1",
        timeoutSeconds: 30,
    },
    async (event) => {
        const { communityID, joinerUID } = event.params;
        const db = getDatabase();

        // Community-Metadaten laden für Creator-UID + Activity.
        const commSnap = await db.ref(`communities/${communityID}`).get();
        if (!commSnap.exists()) {
            logger.info("onCommunityMemberJoined: community missing", { communityID });
            return;
        }
        const comm = commSnap.val() as Record<string, unknown>;
        const creatorUID   = (comm.creatorUID   as string | undefined) ?? communityID;
        const activitySlug = (comm.activitySlug as string | undefined) ?? "";
        const district     = (comm.district     as string | undefined) ?? "";

        // Skip: Creator joint sich selbst beim Approve.
        if (joinerUID === creatorUID) {
            logger.info("onCommunityMemberJoined: creator self-join — skipping", { communityID });
            return;
        }

        // Joiner-Name aus users-Knoten.
        const joinerSnap = await db.ref(`users/${joinerUID}/name`).get();
        const joinerName = (joinerSnap.val() as string | undefined) ?? "Jemand";

        // Creator-Token holen.
        const tokenSnap = await db.ref(`users/${creatorUID}/fcmToken`).get();
        const token = tokenSnap.val() as string | undefined;
        if (!token) {
            logger.info("onCommunityMemberJoined: no token for creator", { creatorUID });
            return;
        }

        // Activity-Display-Name (Slug capitalize falls kein Mapping).
        const activityDisplay = activitySlug
            ? activitySlug.charAt(0).toUpperCase() + activitySlug.slice(1)
            : "Community";

        try {
            await getMessaging().send({
                token,
                notification: {
                    title: "Neues Community-Mitglied",
                    body: `${joinerName} ist deiner ${activityDisplay}-Community in ${district} beigetreten.`,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            "thread-id": `community-${communityID}`,
                            category: "COMMUNITY_JOIN",
                        },
                    },
                },
                data: {
                    type: "community_join",
                    communityID,
                    joinerUID,
                    joinerName,
                },
            });
            logger.info("onCommunityMemberJoined sent", { communityID, joinerUID, creatorUID });
        } catch (e: any) {
            logger.warn("onCommunityMemberJoined: FCM send failed", { creatorUID, error: e?.message });
        }
    }
);


// ═══════════════════════════════════════════════════════════════════
// USER-FEEDBACK AGGREGATOR
// ═══════════════════════════════════════════════════════════════════
//
// Trigger: jeder Write auf /userFeedback/{ratedUID}/{voteID} (create,
// update, delete). Re-aggregiert alle Votes für den ratedUser und
// schreibt das Ergebnis nach /users/{ratedUID}/feedbackThumbs.
//
// Schema (Aggregat):
//   { up: number, down: number, total: number, lastUpdated: ms-epoch }
//
// Idempotenz: Re-Aggregation aus dem aktuellen Zustand — nicht
// inkrementell. Bei vielen Votes pro User immer noch O(votes),
// aber Votes pro User sind realistisch < 100.
//
// Schreibt mit Admin-SDK → bypassed `feedbackThumbs.write: false`.

export const onFeedbackVoteWritten = onValueWritten(
    {
        ref: "/userFeedback/{ratedUID}/{voteID}",
        region: "europe-west1",
        timeoutSeconds: 60,
    },
    async (event) => {
        const ratedUID = event.params.ratedUID;
        if (!ratedUID) return;

        const db = getDatabase();

        let up = 0;
        let down = 0;
        try {
            const snap = await db.ref(`userFeedback/${ratedUID}`).get();
            if (snap.exists()) {
                snap.forEach((child) => {
                    const v = child.child("vote").val();
                    if (v === "up") up++;
                    else if (v === "down") down++;
                });
            }
        } catch (err) {
            logger.error("onFeedbackVoteWritten read failed", { ratedUID, err });
            return;
        }

        const total = up + down;
        try {
            await db.ref(`users/${ratedUID}/feedbackThumbs`).set({
                up,
                down,
                total,
                lastUpdated: Date.now(),
            });
        } catch (err) {
            logger.error("onFeedbackVoteWritten write failed", { ratedUID, err });
        }
    }
);


// ═══════════════════════════════════════════════════════════════════
// DEMO-DROPS SEEDER
// ═══════════════════════════════════════════════════════════════════
//
// Schreibt stündlich „Demo-Drops" als bereits beendete Geister auf die
// Karte, damit die App in Pre-Launch / Low-Activity-Phasen nicht leer
// wirkt. Pro Stadt 3-5 Drops aus kuratierten ortsbezogenen Aktivitäten
// (Biergarten/München, Mauerpark/Berlin, Hafen/Hamburg etc.). Alle mit
// `isDemo: true` markiert — Admin-Panel und Cleanup respektieren das.
//
// Lebenszyklus pro Demo-Drop:
//   - createdAt = jetzt - random(30 min … 3 h)
//   - endedAt   = jetzt - random(5 min … 90 min)   ← schon vorbei = Ghost
//   - active    = false
//   - Cleanup löscht endedAt > 4h alt → natürlicher Refresh-Zyklus
//
// User können Demo-Drops NICHT joinen (sie sind bereits beendet) und
// nicht antippen (Ghost-Layer ist read-only). Reine optische Wirkung.

/// Wetter-Tauglichkeit eines Spots.
///   `outdoor_warm` → braucht warm + trocken (Strand, Surfen, Grillen, BBQ)
///   `outdoor`      → braucht trocken (Park, Spaziergang, Markt, Joggen)
///   `mixed`        → Indoor-/Outdoor-Optionen, jedes Wetter ok
///   `indoor`       → Indoor, jedes Wetter ok
type WeatherTag = "outdoor_warm" | "outdoor" | "mixed" | "indoor";

interface DemoSpot {
    lat: number;
    lng: number;
    /// Interner Bezeichner des Spots (Park, Platz, Viertel, Venue-Name).
    /// Wird NUR für Dedup und `activityFromEmoji`-Seed verwendet — NICHT
    /// direkt als Drop-Titel oder locationTitle angezeigt.
    activity: string;
    emoji: string;
    /// Echter Venue-Name (Bar, Café, Restaurant) — wird in `locationTitle`
    /// geschrieben und im Sheet angezeigt. Parks, Stadtteile, Straßen → weglassen.
    venue?: string;
    /// Stunden (0-23, lokale Berlin-Zeit) in denen diese Aktivität plausibel ist.
    /// Cluster: morning 8-12, midday 12-15, afternoon 15-18, evening 18-23, night 23-3.
    hours: number[];
    weather: WeatherTag;
}

// Wiederverwendbare Stunden-Sets — vermeidet Tippfehler in den Spot-Listen.
const H_MORNING   = [8, 9, 10, 11, 12];                          // Café, Brunch, Markt
const H_DAY       = [10, 11, 12, 13, 14, 15, 16, 17, 18];        // Park, Spaziergang, Joggen
const H_AFTERNOON = [13, 14, 15, 16, 17, 18];                    // Café-2, Eis, Skating
const H_EVENING   = [17, 18, 19, 20, 21, 22, 23];                // Biergarten, Restaurant
const H_BAR       = [19, 20, 21, 22, 23, 0, 1, 2];               // Bar, Cocktails, Späti
const H_NIGHTLIFE = [21, 22, 23, 0, 1, 2, 3];                    // Club, Karaoke, Reeperbahn
const H_BBQ_BEACH = [12, 13, 14, 15, 16, 17, 18, 19, 20, 21];    // Grillen, Strand, Surfen
const H_SPORT     = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]; // Klettern, Indoor-Sport
const H_YOGA      = [7, 8, 9, 10, 17, 18, 19];                   // Yoga, Morgensport
const H_FOOD      = [12, 13, 14, 19, 20, 21];                    // Ramen, Sushi, Lunch+Dinner
const H_CINEMA    = [14, 15, 16, 17, 18, 19, 20, 21, 22];        // Kino, Museum
const H_BALL      = [14, 15, 16, 17, 18, 19];                    // Fußball, Basketball

const DEMO_SPOTS: Record<string, DemoSpot[]> = {
    berlin: [
        // Parks & Outdoor
        { lat: 52.543716, lng: 13.401933, activity: "Mauerpark",               emoji: "🎤", hours: H_NIGHTLIFE, weather: "outdoor" },
        { lat: 52.474419, lng: 13.402601, activity: "Tempelhofer Feld",        emoji: "🏃", hours: H_DAY, weather: "outdoor" },
        { lat: 52.493400, lng: 13.466100, activity: "Treptower Park",           emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 52.496831, lng: 13.440538, activity: "Görlitzer Park",          emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 52.514411, lng: 13.350111, activity: "Tiergarten",              emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 52.527040, lng: 13.432450, activity: "Volkspark Friedrichshain",emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 52.543021, lng: 13.419033, activity: "Helmholtzplatz",          emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 52.487484, lng: 13.419139, activity: "Hasenheide",              emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 52.516270, lng: 13.377703, activity: "Brandenburger Tor",       emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 52.521400, lng: 13.410500, activity: "Monbijoupark",            emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 52.505200, lng: 13.440500, activity: "East Side Gallery",       emoji: "📸", hours: H_DAY, weather: "outdoor" },
        { lat: 52.541500, lng: 13.428700, activity: "Prenzlauer Berg",         emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        // Cafés & Frühstück
        { lat: 52.519900, lng: 13.295600, activity: "Kleine Orangerie",        emoji: "☕", venue: "Kleine Orangerie",    hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 52.512600, lng: 13.342900, activity: "Café am Neuen See",       emoji: "☕", venue: "Café am Neuen See",   hours: [9,10,11,12,13,14,15,16,17], weather: "mixed" },
        { lat: 52.489800, lng: 13.396500, activity: "Bergmannstraße",          emoji: "☕", venue: "Café Nook",           hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 52.536990, lng: 13.418250, activity: "Kollwitzplatz",           emoji: "☕", venue: "Anna Blume",          hours: H_MORNING.concat(H_AFTERNOON), weather: "indoor" },
        { lat: 52.498300, lng: 13.352700, activity: "Winterfeldtplatz",        emoji: "☕", venue: "Café Winterfeldt",    hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 52.538600, lng: 13.407600, activity: "Eis Prenzlauer Berg",     emoji: "🍦", venue: "Eis Storch",          hours: H_AFTERNOON, weather: "outdoor_warm" },
        // Bars & Abend
        { lat: 52.512760, lng: 13.417230, activity: "Holzmarkt",               emoji: "🍻", venue: "Holzmarkt 25",        hours: H_BAR, weather: "mixed" },
        { lat: 52.481920, lng: 13.430750, activity: "Klunkerkranich",          emoji: "🍹", venue: "Klunkerkranich",      hours: [17,18,19,20,21,22,23], weather: "outdoor_warm" },
        { lat: 52.512570, lng: 13.457050, activity: "Boxi STOP",               emoji: "🍺", venue: "Boxi STOP",           hours: [17,18,19,20,21,22,23,0,1], weather: "outdoor" },
        { lat: 52.513222, lng: 13.456947, activity: "Boxhagener Platz",        emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 52.511570, lng: 13.460090, activity: "Café Dachkammer",         emoji: "🍻", venue: "Café Dachkammer",     hours: H_BAR, weather: "indoor" },
        { lat: 52.507661, lng: 13.454537, activity: "RAW Gelände",             emoji: "🎵", hours: H_NIGHTLIFE, weather: "mixed" },
        { lat: 52.537300, lng: 13.413300, activity: "Kulturbrauerei",          emoji: "🎸", venue: "Kulturbrauerei",      hours: H_BAR, weather: "mixed" },
        // Essen
        { lat: 52.499130, lng: 13.431540, activity: "Markthalle Neun",         emoji: "🍕", venue: "Markthalle Neun",     hours: [11,12,13,14,15,16,17,18,19,20], weather: "indoor" },
        { lat: 52.519700, lng: 13.452100, activity: "Ramen Friedrichshain",    emoji: "🍜", venue: "Cocolo Ramen",         hours: H_FOOD, weather: "indoor" },
        { lat: 52.493700, lng: 13.450200, activity: "Sushi Neukölln",          emoji: "🍣", venue: "Sasaya",              hours: H_FOOD, weather: "indoor" },
        // Sport & Aktivität
        { lat: 52.497500, lng: 13.446800, activity: "Badeschiff",              emoji: "🏊", venue: "Badeschiff Arena",    hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 52.527000, lng: 13.475300, activity: "Weißensee Baden",         emoji: "🏊", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 52.508900, lng: 13.391200, activity: "Magic Mountain",          emoji: "🧗", venue: "Magic Mountain Bouldering", hours: H_SPORT, weather: "indoor" },
        { lat: 52.493800, lng: 13.402500, activity: "Skatepark Kreuzberg",     emoji: "🛹", hours: H_DAY, weather: "outdoor" },
        { lat: 52.495600, lng: 13.370900, activity: "Fahrrad Tour Spree",      emoji: "🚴", hours: H_DAY, weather: "outdoor" },
        { lat: 52.499000, lng: 13.360700, activity: "Yoga Gleisdreieck",       emoji: "🧘", hours: H_YOGA, weather: "outdoor" },
        { lat: 52.487200, lng: 13.418500, activity: "Fußball Hasenheide",      emoji: "⚽", hours: H_BALL, weather: "outdoor" },
        { lat: 52.491200, lng: 13.388300, activity: "Basketball Hasenheide",   emoji: "🏀", hours: H_BALL, weather: "outdoor" },
        // Kultur
        { lat: 52.521200, lng: 13.393700, activity: "Kunst & Kultur Mitte",    emoji: "🎨", hours: H_CINEMA, weather: "indoor" },
        { lat: 52.523600, lng: 13.387900, activity: "Spielwiese Berlin",       emoji: "🎲", venue: "Spielwiese Berlin",   hours: H_CINEMA, weather: "indoor" },
    ],
    muenchen: [
        // Parks & Outdoor
        { lat: 48.149880, lng: 11.590921, activity: "Englischer Garten",       emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 48.172429, lng: 11.550746, activity: "Olympiapark",             emoji: "🏃", hours: H_DAY, weather: "outdoor" },
        { lat: 48.090170, lng: 11.537520, activity: "Flaucher Grillen",        emoji: "🔥", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 48.184200, lng: 11.575300, activity: "Luitpoldpark",            emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 48.107200, lng: 11.617300, activity: "Ostpark",                 emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 48.117986, lng: 11.516253, activity: "Westpark",                emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 48.146058, lng: 11.564255, activity: "Königsplatz",             emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 48.158000, lng: 11.503500, activity: "Nymphenburger Park",      emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 48.096820, lng: 11.548640, activity: "Isarauen",                emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 48.141344, lng: 11.596993, activity: "Friedensengel",           emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 48.134357, lng: 11.596073, activity: "Wiener Platz",            emoji: "🍻", hours: H_BAR, weather: "mixed" },
        // Cafés & Essen
        { lat: 48.142990, lng: 11.600380, activity: "Eisbach surfen",          emoji: "🏄", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 48.135150, lng: 11.576350, activity: "Viktualienmarkt",         emoji: "🥨", venue: "Café Frischhut",      hours: H_MORNING, weather: "outdoor" },
        { lat: 48.162759, lng: 11.587211, activity: "Münchner Freiheit",       emoji: "☕", venue: "Café Münchner Freiheit", hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 48.150590, lng: 11.579180, activity: "Café Amalien",            emoji: "☕", venue: "Café Amalien",        hours: H_MORNING.concat(H_AFTERNOON), weather: "indoor" },
        { lat: 48.148600, lng: 11.582100, activity: "Schwabing Jasmin",        emoji: "☕", venue: "Café Jasmin",         hours: H_MORNING.concat(H_AFTERNOON), weather: "indoor" },
        { lat: 48.152900, lng: 11.579500, activity: "Eis Schwabing",           emoji: "🍦", hours: H_AFTERNOON, weather: "outdoor_warm" },
        { lat: 48.131200, lng: 11.575700, activity: "Ramen Takumi",            emoji: "🍜", venue: "Takumi",              hours: H_FOOD, weather: "indoor" },
        { lat: 48.136100, lng: 11.572400, activity: "Sushi Innenstadt",        emoji: "🍣", venue: "Sushi & Soul",        hours: H_FOOD, weather: "indoor" },
        // Bars & Abend
        { lat: 48.143477, lng: 11.551380, activity: "Augustiner Biergarten",   emoji: "🍺", venue: "Augustiner-Keller",   hours: H_EVENING, weather: "outdoor_warm" },
        { lat: 48.149440, lng: 11.511054, activity: "Hirschgarten",            emoji: "🍺", venue: "Hirschgarten Biergarten", hours: H_EVENING, weather: "outdoor_warm" },
        { lat: 48.125359, lng: 11.605287, activity: "Werksviertel",            emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 48.124038, lng: 11.605952, activity: "WerksBAR",               emoji: "🍹", venue: "WerksBAR",            hours: H_BAR, weather: "outdoor_warm" },
        { lat: 48.130906, lng: 11.570573, activity: "Glockenbachviertel",      emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 48.118300, lng: 11.527700, activity: "Feierwerk",               emoji: "🎸", venue: "Feierwerk",           hours: H_BAR, weather: "indoor" },
        { lat: 48.129700, lng: 11.576100, activity: "Gärtnerplatz",            emoji: "🍻", hours: H_BAR, weather: "mixed" },
        // Sport
        { lat: 48.112700, lng: 11.568000, activity: "Isar Baden",              emoji: "🏊", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 48.171400, lng: 11.508200, activity: "Dantebad",                emoji: "🏊", venue: "Dantebad",            hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 48.105100, lng: 11.687000, activity: "Riemer See",              emoji: "🏊", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 48.130700, lng: 11.548200, activity: "Boulderwelt",             emoji: "🧗", venue: "Boulderwelt München West", hours: H_SPORT, weather: "indoor" },
        { lat: 48.153700, lng: 11.565000, activity: "Radtour Isar",            emoji: "🚴", hours: H_DAY, weather: "outdoor" },
        { lat: 48.161900, lng: 11.584300, activity: "Yoga Englischer Garten",  emoji: "🧘", hours: H_YOGA, weather: "outdoor_warm" },
        { lat: 48.127600, lng: 11.594500, activity: "Fußball Ostpark",         emoji: "⚽", hours: H_BALL, weather: "outdoor" },
        { lat: 48.137800, lng: 11.539100, activity: "Basketball Neuhausen",    emoji: "🏀", hours: H_BALL, weather: "outdoor" },
        { lat: 48.120000, lng: 11.555700, activity: "Skatepark München",       emoji: "🛹", hours: H_DAY, weather: "outdoor" },
        // Kultur
        { lat: 48.147900, lng: 11.570300, activity: "Alte Pinakothek",         emoji: "🎨", venue: "Alte Pinakothek",     hours: H_CINEMA, weather: "indoor" },
        { lat: 48.135000, lng: 11.566000, activity: "Brettspiele Café",        emoji: "🎲", venue: "Spielkiste München",  hours: H_CINEMA, weather: "indoor" },
        { lat: 48.133200, lng: 11.565900, activity: "Kino Sendlinger Tor",     emoji: "🎭", hours: H_CINEMA, weather: "indoor" },
    ],
    hamburg: [
        // Outdoor & Parks
        { lat: 53.545740, lng:  9.970716, activity: "Landungsbrücken",         emoji: "🚢", hours: H_DAY, weather: "outdoor" },
        { lat: 53.593199, lng: 10.025393, activity: "Stadtpark",               emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 53.545274, lng:  9.935832, activity: "Altonaer Balkon",         emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 53.561958, lng:  9.981331, activity: "Planten un Blomen",       emoji: "🌹", hours: H_DAY, weather: "outdoor" },
        { lat: 53.566880, lng:  9.962750, activity: "Schanzenpark",            emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 53.543845, lng:  9.915851, activity: "Övelgönne Elbufer",       emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 53.542403, lng:  9.992564, activity: "HafenCity",               emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 53.557322, lng:  9.808019, activity: "Treppenviertel Blankenese",emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 53.541900, lng:  9.924800, activity: "Blankenese Elbstrand",    emoji: "🏖️", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 53.550500, lng:  9.995200, activity: "Alster Joggen",           emoji: "🏃", hours: H_DAY, weather: "outdoor" },
        // Cafés & Essen
        { lat: 53.563680, lng:  9.964520, activity: "Schanzenviertel Kaffee",  emoji: "☕", venue: "Nord Coast Coffee Roastery", hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 53.583990, lng:  9.983905, activity: "Elbgold Eppendorf",       emoji: "☕", venue: "Elbgold Eppendorf",   hours: H_MORNING.concat(H_AFTERNOON), weather: "indoor" },
        { lat: 53.583400, lng: 10.009540, activity: "Elbgold Winterhude",      emoji: "☕", venue: "Elbgold Winterhude",  hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 53.549900, lng:  9.994000, activity: "Jungfernstieg Café Paris",emoji: "☕", venue: "Café Paris",          hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 53.571300, lng: 10.072100, activity: "Wandsbek Café",           emoji: "☕", hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 53.544465, lng:  9.938360, activity: "Fischmarkt",              emoji: "🐟", hours: [6,7,8,9,10], weather: "outdoor" },
        { lat: 53.572100, lng: 10.024500, activity: "Ramen Barmbek",           emoji: "🍜", hours: H_FOOD, weather: "indoor" },
        { lat: 53.560300, lng: 10.020600, activity: "Sushi Uhlenhorst",        emoji: "🍣", hours: H_FOOD, weather: "indoor" },
        // Bars & Abend
        { lat: 53.549548, lng:  9.964671, activity: "Reeperbahn",              emoji: "🍻", hours: H_NIGHTLIFE, weather: "indoor" },
        { lat: 53.548868, lng:  9.961000, activity: "St. Pauli Bar",           emoji: "🍺", hours: H_BAR, weather: "indoor" },
        { lat: 53.543940, lng:  9.904730, activity: "Strandperle",             emoji: "🏖️", venue: "Strandperle",         hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 53.559800, lng: 10.003500, activity: "Alster Paddeln",          emoji: "🛶", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 53.551599, lng:  9.930507, activity: "Ottensen Abend",          emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 53.557420, lng:  9.968763, activity: "Karoviertel",             emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 53.558600, lng:  9.951600, activity: "Eimsbüttel Kneipe",       emoji: "🍺", hours: H_BAR, weather: "indoor" },
        // Sport
        { lat: 53.596600, lng: 10.020800, activity: "Stadtparksee Baden",      emoji: "🏊", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        { lat: 53.574200, lng:  9.969200, activity: "Boulderwelt Hamburg",     emoji: "🧗", venue: "Boulderwelt Hamburg", hours: H_SPORT, weather: "indoor" },
        { lat: 53.565800, lng:  9.963200, activity: "Yoga Schanzenpark",       emoji: "🧘", hours: H_YOGA, weather: "outdoor_warm" },
        { lat: 53.545100, lng:  9.993800, activity: "HafenCity Radtour",       emoji: "🚴", hours: H_DAY, weather: "outdoor" },
        { lat: 53.567000, lng: 10.013000, activity: "Fußball Eimsbüttel",      emoji: "⚽", hours: H_BALL, weather: "outdoor" },
        { lat: 53.569900, lng:  9.973000, activity: "Skatepark Sternschanze",  emoji: "🛹", hours: H_DAY, weather: "outdoor" },
        // Kultur
        { lat: 53.570300, lng:  9.978300, activity: "Kunsthalle Hamburg",      emoji: "🎨", venue: "Kunsthalle Hamburg",  hours: H_CINEMA, weather: "indoor" },
        { lat: 53.570200, lng: 10.044300, activity: "Brettspiele Barmbek",     emoji: "🎲", hours: H_CINEMA, weather: "indoor" },
        { lat: 53.564800, lng:  9.960100, activity: "Kino Schanze",            emoji: "🎭", hours: H_CINEMA, weather: "indoor" },
    ],
    koeln: [
        // Parks & Outdoor
        { lat: 50.927424, lng:  6.972276, activity: "Rheinpromenade",          emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 50.921229, lng:  6.947428, activity: "Volksgarten",             emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 50.942986, lng:  6.935160, activity: "Stadtgarten",             emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 50.935256, lng:  6.927625, activity: "Aachener Weiher",         emoji: "🦆", hours: H_DAY, weather: "outdoor" },
        { lat: 50.947148, lng:  6.943195, activity: "Mediapark",               emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 50.891000, lng:  6.967000, activity: "Rodenkirchen Rheinufer",  emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 50.934200, lng:  6.973800, activity: "Deutz Rheinufer",         emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 50.924200, lng:  6.948100, activity: "Rheinpark Grillen",       emoji: "🔥", hours: H_BBQ_BEACH, weather: "outdoor_warm" },
        // Cafés & Essen
        { lat: 50.937200, lng:  6.928200, activity: "Brüsseler Platz",         emoji: "☕", venue: "Café Schmitz",        hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 50.949500, lng:  6.914200, activity: "Ehrenfeld Bäckerei",      emoji: "☕", venue: "Bäckerei Merzenich",  hours: H_MORNING.concat(H_AFTERNOON), weather: "indoor" },
        { lat: 50.957100, lng:  6.925400, activity: "Nippes Café",             emoji: "☕", venue: "Café Rösterei Nippes",hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 50.921100, lng:  6.959800, activity: "Eis Südstadt",            emoji: "🍦", hours: H_AFTERNOON, weather: "outdoor_warm" },
        { lat: 50.937600, lng:  6.940700, activity: "Sushi Innenstadt",        emoji: "🍣", hours: H_FOOD, weather: "indoor" },
        { lat: 50.941000, lng:  6.939500, activity: "Ramen Köln",              emoji: "🍜", venue: "Ramen Yuki",          hours: H_FOOD, weather: "indoor" },
        // Bars & Abend
        { lat: 50.939870, lng:  6.956730, activity: "Früh am Dom",             emoji: "🍺", venue: "Früh am Dom",         hours: [16,17,18,19,20,21,22], weather: "indoor" },
        { lat: 50.936492, lng:  6.933550, activity: "Belgisches Viertel",      emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 50.935027, lng:  6.942312, activity: "Schaafenstraße",          emoji: "🍷", hours: H_EVENING, weather: "mixed" },
        { lat: 50.925978, lng:  6.966788, activity: "Rheinauhafen",            emoji: "🍷", hours: H_EVENING, weather: "mixed" },
        { lat: 50.921073, lng:  6.959645, activity: "Südstadt Brauhaus",       emoji: "🍺", venue: "Südstadt Brauhaus",   hours: H_EVENING, weather: "indoor" },
        { lat: 50.923038, lng:  6.963009, activity: "Severinsviertel",         emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 50.929900, lng:  6.938100, activity: "Zülpicher Viertel",       emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 50.965300, lng:  6.993500, activity: "Mülheimer Hafen",         emoji: "🍺", hours: H_BAR, weather: "mixed" },
        // Sport
        { lat: 50.946900, lng:  6.898700, activity: "Kletterhalle Ehrenfeld",  emoji: "🧗", hours: H_SPORT, weather: "indoor" },
        { lat: 50.935000, lng:  6.927500, activity: "Yoga Aachener Weiher",    emoji: "🧘", hours: H_YOGA, weather: "outdoor_warm" },
        { lat: 50.938600, lng:  6.942400, activity: "Radtour Grüngürtel",      emoji: "🚴", hours: H_DAY, weather: "outdoor" },
        { lat: 50.925000, lng:  6.955000, activity: "Fußball Südstadt",        emoji: "⚽", hours: H_BALL, weather: "outdoor" },
        // Kultur
        { lat: 50.949300, lng:  6.947000, activity: "Skulpturenpark Köln",     emoji: "🎨", hours: H_CINEMA, weather: "outdoor" },
        { lat: 50.937000, lng:  6.934000, activity: "Kino Belgisches Viertel", emoji: "🎭", hours: H_CINEMA, weather: "indoor" },
        { lat: 50.938200, lng:  6.968000, activity: "Brettspiele Deutz",       emoji: "🎲", hours: H_CINEMA, weather: "indoor" },
    ],
    frankfurt: [
        // Parks & Outdoor
        { lat: 50.107462, lng:  8.685359, activity: "Mainufer Spaziergang",    emoji: "🚶", hours: H_DAY, weather: "outdoor" },
        { lat: 50.121567, lng:  8.655717, activity: "Palmengarten",            emoji: "🌹", hours: H_DAY, weather: "mixed" },
        { lat: 50.116843, lng:  8.692288, activity: "Friedberger Anlage",      emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 50.110597, lng:  8.614421, activity: "Rebstockpark",            emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 50.121500, lng:  8.654700, activity: "Grüneburgpark Picknick",  emoji: "🌳", hours: H_DAY, weather: "outdoor" },
        { lat: 50.107686, lng:  8.694829, activity: "Mainufer Open Air",       emoji: "🎵", hours: [18,19,20,21,22,23], weather: "outdoor" },
        // Cafés & Essen
        { lat: 50.100730, lng:  8.679560, activity: "Sachsenhausen Apfelwein", emoji: "🍷", venue: "Zum Wagner",          hours: H_EVENING, weather: "indoor" },
        { lat: 50.122625, lng:  8.645500, activity: "Bockenheim Café",         emoji: "☕", venue: "Fridas Café",         hours: H_MORNING.concat(H_AFTERNOON), weather: "indoor" },
        { lat: 50.121460, lng:  8.695180, activity: "Bornheim Kaffee",         emoji: "☕", venue: "Bitter & Zart",       hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 50.124727, lng:  8.664298, activity: "Park Café Grüneburgpark", emoji: "☕", venue: "Park Café Grüneburgpark", hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 50.113800, lng:  8.678200, activity: "Hauptwache Café",         emoji: "☕", venue: "Café Hauptwache",     hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 50.099400, lng:  8.548200, activity: "Höchster Altstadt",       emoji: "☕", hours: H_MORNING.concat(H_AFTERNOON), weather: "mixed" },
        { lat: 50.122100, lng:  8.686900, activity: "Nordend Eis",             emoji: "🍦", hours: H_AFTERNOON, weather: "outdoor_warm" },
        { lat: 50.119500, lng:  8.699300, activity: "Ramen Bornheim",          emoji: "🍜", venue: "Ramen House Frankfurt",hours: H_FOOD, weather: "indoor" },
        { lat: 50.098600, lng:  8.680300, activity: "Sushi Sachsenhausen",     emoji: "🍣", hours: H_FOOD, weather: "indoor" },
        // Bars & Abend
        { lat: 50.112542, lng:  8.672196, activity: "Skyline Rooftop Drinks",  emoji: "🍸", hours: [18,19,20,21,22,23], weather: "outdoor_warm" },
        { lat: 50.125825, lng:  8.707291, activity: "Berger Straße Bar",       emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 50.119977, lng:  8.695082, activity: "Merianplatz Kneipen",     emoji: "🍻", hours: H_BAR, weather: "mixed" },
        { lat: 50.116200, lng:  8.659800, activity: "Bockenheim Pub",          emoji: "🍺", hours: H_BAR, weather: "indoor" },
        { lat: 50.134200, lng:  8.783100, activity: "Bergen-Enkheim Abend",    emoji: "🍻", hours: H_BAR, weather: "mixed" },
        // Sport
        { lat: 50.128200, lng:  8.666800, activity: "Kletterzentrum Frankfurt",emoji: "🧗", venue: "Kletterzentrum Frankfurt", hours: H_SPORT, weather: "indoor" },
        { lat: 50.109600, lng:  8.682000, activity: "Mainufer Radtour",        emoji: "🚴", hours: H_DAY, weather: "outdoor" },
        { lat: 50.107000, lng:  8.686000, activity: "Yoga am Main",            emoji: "🧘", hours: H_YOGA, weather: "outdoor_warm" },
        { lat: 50.112700, lng:  8.694200, activity: "Fußball Ostend",          emoji: "⚽", hours: H_BALL, weather: "outdoor" },
        { lat: 50.115200, lng:  8.671800, activity: "Basketball Innenstadt",   emoji: "🏀", hours: H_BALL, weather: "outdoor" },
        { lat: 50.099300, lng:  8.679000, activity: "Skatepark Sachsenhausen", emoji: "🛹", hours: H_DAY, weather: "outdoor" },
        // Kultur
        { lat: 50.105400, lng:  8.682500, activity: "Museumsufer",             emoji: "🎨", hours: H_CINEMA, weather: "indoor" },
        { lat: 50.110300, lng:  8.649400, activity: "Kino Frankfurt",          emoji: "🎭", hours: H_CINEMA, weather: "indoor" },
        { lat: 50.107800, lng:  8.665300, activity: "Brettspiele Sachsenhausen",emoji: "🎲", hours: H_CINEMA, weather: "indoor" },
    ],
};

/// Mapping von Stadt-ID auf Koordinaten (für Wetter-Abruf).
const CITY_COORDS: Record<string, { lat: number; lng: number }> = {
    berlin:    { lat: 52.520,  lng: 13.405 },
    muenchen:  { lat: 48.137,  lng: 11.576 },
    hamburg:   { lat: 53.551,  lng:  9.993 },
    koeln:     { lat: 50.937,  lng:  6.960 },
    frankfurt: { lat: 50.110,  lng:  8.682 },
};

/// Holt aktuelles Wetter via Open-Meteo (kostenlos, ohne API-Key). Bei Fehler
/// → Fallback auf gemäßigt-trocken damit der Seeder weiterläuft.
async function fetchCityWeather(lat: number, lng: number): Promise<{ tempC: number; precipMm: number }> {
    try {
        const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lng}&current=temperature_2m,precipitation`;
        const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
        if (!res.ok) throw new Error(`status ${res.status}`);
        const json = await res.json() as { current?: { temperature_2m?: number; precipitation?: number } };
        const tempC = json.current?.temperature_2m ?? 12;
        const precipMm = json.current?.precipitation ?? 0;
        return { tempC, precipMm };
    } catch (err) {
        logger.warn("fetchCityWeather failed, using fallback", { lat, lng, err });
        return { tempC: 12, precipMm: 0 };
    }
}

/// Bestimmt welche Wetter-Tags zur aktuellen Bedingung passen.
///   warm + trocken     → alle 4 Tags
///   kühl/lau + trocken → outdoor, mixed, indoor (kein outdoor_warm)
///   nass/sehr kalt     → nur mixed, indoor
function allowedWeatherTags(tempC: number, precipMm: number): WeatherTag[] {
    const isWet = precipMm >= 0.5;
    if (isWet || tempC < 5)  return ["mixed", "indoor"];
    if (tempC >= 18)         return ["outdoor_warm", "outdoor", "mixed", "indoor"];
    return ["outdoor", "mixed", "indoor"];
}

const DEMO_HOST_NAMES = [
    // weiblich
    "Lena", "Sophie", "Anna", "Lisa", "Marie", "Hannah", "Emma", "Mia",
    "Sarah", "Lara", "Klara", "Nina", "Julia", "Laura", "Charlotte",
    "Lina", "Leonie", "Lea", "Pia", "Tina", "Eva", "Maja", "Vera",
    "Helena", "Greta", "Frieda", "Carla", "Ida", "Olivia", "Romy",
    // männlich
    "Max", "Tim", "Jonas", "Felix", "Paul", "Leon", "Noah", "Ben",
    "Luca", "Erik", "David", "Niklas", "Lukas", "Finn", "Florian",
    "Jakob", "Marvin", "Simon", "Tom", "Daniel", "Jan", "Marco",
    "Henri", "Til", "Theo", "Mats", "Anton", "Lasse", "Linus", "Mika",
];

/// Activity-Variants gemischt: neutral, casual und Jugendsprache durcheinander.
/// Damit fühlt sich der Pool natürlich an statt einheitlich slangy oder formal.
/// Deterministisch gepickt über Seed damit selber Demo-Slot → selbe Variante.
function activityFromEmoji(emoji: string, hour: number, seed: number): string {
    const variants = (() => {
        switch (emoji) {
            case "☕":
                if (hour <= 10) return ["Brunch", "Frühstück", "Morgenkaffee", "Kaffee + Croissant", "Wochenend Brunch", "kaffee zum wachwerden"];
                if (hour <= 14) return ["Mittagspause", "Café Stop", "Kaffeeklatsch", "Kaffee + Kuchen", "schnelle pause", "kurz kaffee"];
                if (hour <= 17) return ["Nachmittagskaffee", "Café Treff", "Kaffee + Tratsch", "café chillen", "Kaffee Runde"];
                return ["Spätkaffee", "Café Date", "kurz noch nen kaffee"];
            case "🍺":
                if (hour <= 19) return ["Feierabend Bier", "Kaltes Bier", "After Work Bier", "Bier im Biergarten", "wer hat bock auf bier", "Bier nach der Arbeit"];
                if (hour <= 22) return ["Bier mit Aussicht", "Abendbier", "Biergarten Hangout", "Bier am Wasser", "ne runde bier"];
                return ["Letztes Bier", "Spätbier", "Bier zum Runterkommen"];
            case "🍻":
                if (hour <= 19) return ["Drinks nach Feierabend", "After Work Drinks", "Spontane Drinks", "kurz was trinken", "wer kommt mit"];
                if (hour <= 22) return ["Cocktail Abend", "Bar Hopping", "Drinks + Quatschen", "bar time", "drinks?"];
                return ["Bar Tour", "Spät Drinks", "wir gehen aus"];
            case "🍹":  return ["Sundowner", "Sommer Cocktails", "Cocktails mit Aussicht", "Spritz Time", "drinks in der sonne"];
            case "🍷":  return ["Wein Abend", "Glas Wein", "Weinprobe", "Wein + Käse", "ne flasche wein"];
            case "🍸":  return ["Rooftop Drink", "Sundowner mit Aussicht", "Sky Bar", "drinks über den dächern", "Cocktails oben"];
            case "🌳":  return ["Park Hangout", "Picknick", "Decke + Park", "Sonne tanken", "Im Grünen chillen", "park vibes", "rumhängen im park"];
            case "🌹":  return ["Blumen Walk", "Garten Runde", "Botanik Tour"];
            case "🚶":  return ["Spaziergang", "Stadtbummel", "Foto Walk", "Erkundungstour", "kurze runde", "ne runde drehen"];
            case "🏃":  return ["Joggen", "Park Lauf", "Lockerer Run", "Easy Run", "Lauftraining", "kurzer run"];
            case "🍕":
                if (hour <= 14) return ["Lunch", "Pizza Time", "Pasta Lunch", "Spontanes Essen", "schneller lunch"];
                return ["Pizza Abend", "Pasta + Wein", "Spontanes Dinner", "Abendessen", "pizza?"];
            case "🥨":  return ["Brezn Frühstück", "Markt Tour", "Markt Runde", "Frühstück am Markt"];
            case "🐟":  return ["Fisch + Brötchen", "Markt Tour", "Fischmarkt klassisch"];
            case "🎤":  return ["Karaoke Abend", "Open Mic", "Singen unter Sternen", "Karaoke Session", "wer singt mit"];
            case "🎵":  return ["Live Konzert", "Open Air Musik", "Live Musik am Wasser", "Bands hören", "konzert!"];
            case "🛶":  return ["Paddeln", "SUP Tour", "Tretboot Runde", "Aufs Wasser"];
            case "🏖️":  return ["Strand Hangout", "Beach Day", "Strand Picknick", "Sonne + Liege"];
            case "🏄":  return ["Surfen", "Eisbach Session", "Welle reiten", "Surf Session"];
            case "🔥":  return ["Grillen", "BBQ", "Spontaner Grill", "Würstchen + Kaltes", "Grill + Chill"];
            case "🚢":  return ["Hafen Tour", "Hafenrundgang", "Schiff gucken"];
            case "🦆":  return ["Park am Wasser", "Wasser Spaziergang", "Enten füttern"];
            case "🏊":  return ["Baden gehen", "Schwimmen", "See-Abkühlung", "Freibad Session", "kurz ins Wasser", "Baden im See"];
            case "🧗":  return ["Bouldern", "Klettern", "Boulder Session", "Kletterhalle", "wer klettert mit", "Bouldern gehen"];
            case "🚴":  return ["Radtour", "Fahrrad Runde", "Stadtradeln", "Radeln an der Spree", "kurze Radtour", "Radfahren"];
            case "🛹":  return ["Skaten", "Skatepark Session", "Skateboard Runde", "wer skatet mit", "Skate Session"];
            case "🧘":  return ["Yoga", "Outdoor Yoga", "Yoga im Park", "Morning Yoga", "Yoga Session", "meditieren + strecken"];
            case "📸":  return ["Foto Walk", "Fotografie Tour", "Shooting gehen", "Stadtfotografie", "Foto Spaziergang", "Fotos machen"];
            case "🎨":  return ["Museum", "Ausstellung", "Galerie Runde", "Kunst gucken", "Museo Besuch", "Ausstellung checken"];
            case "🎭":  return ["Kino", "Film gucken", "Kinoabend", "Netflix irl", "ins Kino gehen", "Film + Popcorn"];
            case "🎸":  return ["Live Musik", "Konzert", "Bands schauen", "Live Show", "Musik Abend", "gig heute?"];
            case "🎲":  return ["Brettspiele", "Game Night", "Spieleabend", "Catan oder so", "Brettspiel Runde", "Spielen"];
            case "🍜":  return ["Ramen", "Ramen essen gehen", "Nudeln", "Pho Abend", "Ramen Spot", "Ramen Date"];
            case "🍣":  return ["Sushi", "Sushi essen", "Sushi Abend", "All you can eat Sushi", "Sushi Date", "Omakase?"];
            case "🍦":  return ["Eis essen", "Eisrunde", "Eis holen gehen", "Frozen Yogurt", "Eis + Spaziergang", "Gelato?"];
            case "🏀":  return ["Basketball", "Körbe werfen", "Hoops", "Basketball Runde", "Pick-up Basketball", "wer spielt mit"];
            case "⚽":  return ["Fußball", "Kicken", "Fußball spielen", "Pick-up Fußball", "Fußball Runde", "wer kickt mit"];
            default:    return ["Treffen", "Spontaner Hangout"];
        }
    })();
    return variants[Math.abs(seed) % variants.length];
}

function randomInt(min: number, max: number): number {
    return Math.floor(Math.random() * (max - min + 1)) + min;
}
/// Liefert die lokale Berlin-Stunde (0-23) für einen ms-epoch Timestamp.
/// Robust für DST — nutzt Intl.DateTimeFormat statt manueller Offset-Mathematik.
function berlinHour(tsMs: number): number {
    const parts = new Intl.DateTimeFormat("de-DE", {
        timeZone: "Europe/Berlin",
        hour: "2-digit",
        hour12: false,
    }).formatToParts(new Date(tsMs));
    const h = parts.find(p => p.type === "hour")?.value ?? "0";
    return parseInt(h, 10) % 24;
}

export const seedDemoDrops = onSchedule(
    {
        // Alle 20 Min — sonst wirkt der HH:00-Sprung auffällig (zwischen
        // den Stunden wird der jüngste Ghost immer älter, dann poppen
        // schlagartig 15+ "frische" Drops auf). 3 Wellen pro Stunde mit
        // je 1-2 Drops/Stadt = gleicher Gesamtbestand, aber natürlich
        // verteilt. Open-Meteo: 5×3×24 = 360 Calls/Tag (free tier OK).
        schedule: "*/20 * * * *",
        timeZone: TZ,
        region: "europe-west1",
        timeoutSeconds: 120,
    },
    async () => {
        const db = getDatabase();

        // Admin-Toggle prüfen — /config/demoDropsEnabled. Default = true (an).
        // Admin kann im AdminPanel den Schalter umlegen, dann läuft nichts mehr.
        const enabledSnap = await db.ref("config/demoDropsEnabled").get();
        const enabledVal = enabledSnap.val();
        const enabled = enabledVal === undefined || enabledVal === null ? true : enabledVal === true;
        if (!enabled) {
            logger.info("seedDemoDrops disabled via config/demoDropsEnabled");
            return;
        }

        const now = Date.now();
        const updates: Record<string, any> = {};
        let created = 0;
        let skipped = 0;

        // Wetter pro Stadt parallel abrufen — Open-Meteo, kein API-Key.
        const weatherByCity: Record<string, { allowed: Set<WeatherTag>; tempC: number; precipMm: number }> = {};
        await Promise.all(Object.entries(CITY_COORDS).map(async ([cityID, coord]) => {
            const w = await fetchCityWeather(coord.lat, coord.lng);
            weatherByCity[cityID] = {
                allowed: new Set(allowedWeatherTags(w.tempC, w.precipMm)),
                tempC: w.tempC,
                precipMm: w.precipMm,
            };
        }));
        logger.info("seedDemoDrops weather", weatherByCity);

        // Cross-Run-Deduplication: bereits laufende Demo-Drops lesen damit
        // der nächste Run nicht den gleichen Spot nochmal wählt.
        // Nur Demo-Drops innerhalb der 1h-TTL werden berücksichtigt.
        const dropsSnap = await getDatabase().ref("drops").once("value");
        const recentDemoByCity: Record<string, Set<string>> = {};
        dropsSnap.forEach((child: any) => {
            const d = child.val();
            if (!d?.isDemo || !d.endedAt) return;
            const dedupKey = (d.demoKey || d.locationTitle) as string | undefined;
            if (!dedupKey) return;
            if (now - (d.endedAt as number) > 60 * 60_000) return;
            const cityPart = String(d.userID ?? "").split(":")[1] ?? "";
            if (!cityPart) return;
            if (!recentDemoByCity[cityPart]) recentDemoByCity[cityPart] = new Set();
            recentDemoByCity[cityPart].add(dedupKey);
        });

        for (const [cityID, spots] of Object.entries(DEMO_SPOTS)) {
            const weather = weatherByCity[cityID];
            // Pro Stadt 3-5 Drops planen. Zeit-Layout (alles relativ zu NOW):
            //   endedAt   = 5 – 90 min vor jetzt   (Drop ist gerade vorbei)
            //   duration  = 30 – 90 min            (Drop hat so lange gedauert)
            //   createdAt = endedAt - duration     (Drop hat damals begonnen)
            //
            // Hour-Filter nutzt createdAt-Stunde → Aktivität muss zum Start-
            // Zeitpunkt plausibel gewesen sein (z.B. Café um 09:00 das um
            // 10:30 endete → ok, weil Café-Hours 8-17 die 9 enthält).
            // Garantiert: endedAt liegt IMMER in der Vergangenheit.
            // Pro Run 1-2 Drops/Stadt (3 Runs/Stunde ⇒ 3-6/Stadt/h).
            const targetCount = randomInt(1, 2);
            const usedKeys = new Set<string>();
            for (let i = 0; i < targetCount; i++) {
                // 5-45 min vor jetzt: deutlich unter TTL (90min) damit der Ghost
                // nicht direkt nach Erstellung wieder verschwindet.
                const endedAtMs   = now - randomInt(5 * 60_000, 45 * 60_000);
                const durationMs  = randomInt(30 * 60_000, 90 * 60_000);
                const createdAtMs = endedAtMs - durationMs;
                const hour = berlinHour(createdAtMs);
                // Kandidaten: nach Uhrzeit + Wetter filtern, bereits aktive
                // Spots dieser Stadt ausschließen (Cross-Run-Dedup).
                // Fallback auf alle Stunde/Wetter-Kandidaten wenn nach Dedup
                // nichts übrig bleibt (z.B. alle Spots gerade aktiv).
                const recentlyUsed = recentDemoByCity[cityID] ?? new Set<string>();
                const baseFilter = (s: DemoSpot) =>
                    s.hours.includes(hour)
                    && weather.allowed.has(s.weather)
                    && !usedKeys.has(s.activity);
                const candidates =
                    spots.filter(s => baseFilter(s) && !recentlyUsed.has(s.activity))
                    .length > 0
                        ? spots.filter(s => baseFilter(s) && !recentlyUsed.has(s.activity))
                        : spots.filter(s => baseFilter(s)); // Fallback ohne Dedup
                if (candidates.length === 0) { skipped++; continue; }
                const spot = candidates[randomInt(0, candidates.length - 1)];
                usedKeys.add(spot.activity);

                const dropID = `demo_${cityID}_${now}_${randomInt(1000, 9999)}_${i}`;
                // Coord-Jitter ~10m — Pins stapeln nicht exakt aber bleiben
                // erkennbar am Spot (vorher 50m → konnten über Straße landen).
                const jitterLat = (Math.random() - 0.5) * 0.00009;   // ±~5 m
                const jitterLng = (Math.random() - 0.5) * 0.00009;   // ±~5 m
                const expiresAtSec = Math.floor(endedAtMs / 1000);
                const hostName = DEMO_HOST_NAMES[randomInt(0, DEMO_HOST_NAMES.length - 1)];

                // Host-Profil: variiert damit Pin-Farbe (= Altersgruppen-Color)
                // pro Demo unterschiedlich ist. hostAge 22-45 deckt die
                // 4 Altersgruppen (18-24, 25-34, 35-44, 45+) ab.
                const hostAge = randomInt(22, 45);
                const hostGender = ["männlich", "weiblich", "divers"][randomInt(0, 2)];
                // Reliability-Points: Mehrheit im "Stammgast"-Tier 200-500
                // damit Demos den Eindruck etablierter Hosts geben.
                const hostReliabilityPoints = randomInt(50, 480);
                // Teilnehmer-Zähler: realistische Verteilung — meistens
                // 2-4 (klein, intim), gelegentlich 5-8 (vollere Gruppe).
                const currentParticipants = Math.random() < 0.75
                    ? randomInt(2, 4)
                    : randomInt(5, 8);
                const maxParticipants = Math.max(currentParticipants + randomInt(1, 4), randomInt(4, 12));

                updates[`drops/${dropID}`] = {
                    isDemo:               true,
                    active:               false,
                    lat:                  spot.lat + jitterLat,
                    lng:                  spot.lng + jitterLng,
                    displayName:          hostName,
                    emoji:                spot.emoji,
                    // Activity wird aus Emoji+Stunde abgeleitet, mit Variants-Pool
                    // (z.B. "Feierabend-Bier" vs "Kaltes Bier"). Seed = endedAt+i
                    // damit verschiedene Drops gleicher Kategorie auch verschiedene
                    // Bezeichner kriegen statt 5× "Bier" am selben Platz.
                    activityName:         activityFromEmoji(spot.emoji, hour, endedAtMs + i),
                    locationTitle:        spot.venue ?? "",
                    demoKey:              spot.activity,
                    scheduledTime:        "Jetzt",
                    maxParticipants,
                    currentParticipants,
                    hostAge,
                    hostGender,
                    hostReliabilityPoints,
                    userID:               `demo:${cityID}:${dropID}`,
                    timestamp:            createdAtMs,
                    createdAt:            createdAtMs,
                    expiresAt:            expiresAtSec,
                    endedAt:              endedAtMs,
                };
                created++;
            }
        }

        if (Object.keys(updates).length > 0) {
            await db.ref().update(updates);
        }
        logger.info("seedDemoDrops created", { count: created, skipped });
    }
);

// ── Admin: alle Demo-Drops sofort löschen ─────────────────────────────────────
// GET https://europe-west1-drops-858d1.cloudfunctions.net/purgeDemoDrops?secret=drops-admin-purge
export const purgeDemoDrops = onRequest(
    { region: "europe-west1", cors: false },
    async (req, res) => {
        if (req.query.secret !== "drops-admin-purge") {
            res.status(403).json({ error: "forbidden" });
            return;
        }
        const db = getDatabase();
        const snap = await db.ref("drops").once("value");
        const toDelete: Record<string, null> = {};
        snap.forEach((child: any) => {
            if (child.val()?.isDemo === true) {
                toDelete[`drops/${child.key}`] = null;
            }
        });
        const count = Object.keys(toDelete).length;
        if (count > 0) await db.ref().update(toDelete);
        logger.info("purgeDemoDrops", { deleted: count });
        res.status(200).json({ deleted: count });
    }
);
