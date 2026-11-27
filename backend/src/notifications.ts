import { Device, NotificationEvent } from "./models";
import { firebaseMessaging } from "./firebase";

const fuelNames: Record<string, string> = {
  E5_RON_92: "xăng E5 RON 92",
  E10_RON_95_III: "xăng E10 RON 95-III",
  E10_RON_95_V: "xăng E10 RON 95-V",
  RON_95_III: "xăng RON 95-III",
  RON_95_V: "xăng RON 95-V",
  DIESEL_001S: "dầu diesel 0,001S",
  DIESEL_005S: "dầu diesel 0,05S",
  KEROSENE: "dầu hỏa",
  MAZUT_180CST_35S: "dầu mazut 180CST 3.5S",
};

export async function dispatchPending(limit = 100) {
  const messaging = firebaseMessaging();
  if (!messaging) {
    return {
      enabled: false,
      delivered: 0,
      pending: await NotificationEvent.countDocuments({ status: "pending" }),
    };
  }
  await NotificationEvent.updateMany(
    {
      status: "processing",
      updatedAt: { $lt: new Date(Date.now() - 5 * 60_000) },
    },
    { $set: { status: "pending" } },
  );
  const events = await NotificationEvent.find({
    status: "pending",
    attempts: { $lt: 5 },
    nextAttemptAt: { $lte: new Date() },
  })
    .sort({ createdAt: 1 })
    .limit(Math.max(1, Math.min(limit, 100)))
    .lean();
  let delivered = 0;
  for (const candidate of events) {
    const event = await NotificationEvent.findOneAndUpdate(
      { _id: candidate._id, status: "pending" },
      { $set: { status: "processing" } },
      { new: true },
    ).lean();
    if (!event) continue;
    let failed = false;
    const directionAllowed =
      event.direction === "increase"
        ? { changeDirection: { $in: ["increase", "both"] } }
        : { changeDirection: { $in: ["decrease", "both"] } };
    const devices = await Device.find({
      active: true,
      notificationsEnabled: true,
      fcmToken: { $ne: null },
      selectedRegion: event.region,
      selectedFuelCodes: event.fuelCode,
      ...directionAllowed,
    }).select("fcmToken");
    if (!devices.length) {
      await NotificationEvent.updateOne(
        { _id: event._id },
        { $set: { status: "completed" } },
      );
      continue;
    }
    for (let start = 0; start < devices.length; start += 500) {
      const batch = devices.slice(start, start + 500);
      const tokens = batch.map((device) => device.fcmToken!).filter(Boolean);
      try {
        const response = await messaging.sendEachForMulticast({
          tokens,
          notification: {
            title: `Giá ${fuelNames[event.fuelCode] ?? event.fuelCode} ${event.direction === "increase" ? "tăng" : "giảm"}`,
            body: `Thay đổi ${Math.abs(event.priceChange).toLocaleString("vi-VN")} đ; giá mới ${event.newPrice.toLocaleString("vi-VN")} đ/${event.fuelCode.startsWith("MAZUT") ? "kg" : "lít"} tại ${event.region === "REGION_1" ? "Vùng 1" : "Vùng 2"}.`,
          },
          data: {
            eventId: String(event._id),
            fuelCode: event.fuelCode,
            region: event.region,
            route: `/prices/${event.fuelCode}`,
          },
        });
        await Promise.all(
          response.responses.map(async (result, index) => {
            if (
              !result.success &&
              [
                "messaging/invalid-registration-token",
                "messaging/registration-token-not-registered",
              ].includes(result.error?.code ?? "")
            ) {
              await Device.updateOne(
                { _id: batch[index]?._id },
                { $set: { fcmToken: null } },
              );
            }
          }),
        );
        delivered += response.successCount;
        const transientFailure = response.responses.some(
          (result) =>
            !result.success &&
            ![
              "messaging/invalid-registration-token",
              "messaging/registration-token-not-registered",
            ].includes(result.error?.code ?? ""),
        );
        if (transientFailure)
          throw new Error(
            `Firebase temporarily rejected ${response.failureCount} notifications`,
          );
      } catch (error) {
        const attempts = event.attempts + 1;
        await NotificationEvent.updateOne(
          { _id: event._id },
          {
            $set: {
              attempts,
              status: attempts >= 5 ? "failed" : "pending",
              nextAttemptAt: new Date(
                Date.now() + Math.min(60, 2 ** attempts) * 60_000,
              ),
              lastError:
                error instanceof Error ? error.message : "Firebase send failed",
            },
          },
        );
        failed = true;
        break;
      }
    }
    if (failed) continue;
    await NotificationEvent.updateOne(
      { _id: event._id },
      { $set: { status: "completed" } },
    );
  }
  return { enabled: true, delivered, processed: events.length };
}
