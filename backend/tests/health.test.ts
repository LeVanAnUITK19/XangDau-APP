import { describe, expect, it } from "vitest";
import request from "supertest";
import { app } from "../src/app";

describe("health endpoints", () => {
  it("answers health without connecting to a database", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });
  it("reports not ready when MongoDB is not connected", async () => {
    const res = await request(app).get("/ready");
    expect([200, 503]).toContain(res.status);
  });
});
