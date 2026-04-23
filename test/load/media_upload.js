/**
 * Load test: media upload throughput
 *
 * Exercises the full two-phase upload flow:
 *   1. POST /api/v1/families/:id/uploads/init  → presigned PUT URL
 *   2. PUT  <presigned_url>                     → store file bytes
 *   3. POST /api/v1/uploads/:id/complete        → create media_item
 *
 * Run: k6 run test/load/media_upload.js \
 *        -e BASE_URL=https://staging.example.com \
 *        -e TOKEN=<user_api_token> \
 *        -e FAMILY_ID=<uuid>
 */

import http from "k6/http";
import { check } from "k6";
import { Rate, Trend } from "k6/metrics";

const successRate = new Rate("upload_success_rate");
const uploadLatency = new Trend("upload_total_latency", true);

export const options = {
  stages: [
    { duration: "30s", target: 10 },
    { duration: "2m", target: 50 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    upload_success_rate: ["rate>0.95"],
    upload_total_latency: ["p(95)<10000"],
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:4000";
const TOKEN = __ENV.TOKEN;
const FAMILY_ID = __ENV.FAMILY_ID;

const apiHeaders = {
  Authorization: `Bearer ${TOKEN}`,
  "Content-Type": "application/json",
};

// Generate a minimal valid JPEG (~1KB) for testing
function fakeJpeg() {
  // 1x1 white JPEG
  const bytes = [
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
    0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
    0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29,
    0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32,
    0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x1f, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0a, 0x0b, 0xff, 0xc4, 0x00, 0xb5, 0x10, 0x00, 0x02, 0x01, 0x03,
    0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7d,
    0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0xfb, 0x00,
    0xff, 0xd9,
  ];
  return new Uint8Array(bytes).buffer;
}

export default function () {
  const start = Date.now();

  // Phase 1: initiate upload
  const initRes = http.post(
    `${BASE_URL}/api/v1/families/${FAMILY_ID}/uploads/init`,
    JSON.stringify({
      filename: "test.jpg",
      mime_type: "image/jpeg",
      byte_size: 141,
    }),
    { headers: apiHeaders }
  );

  if (!check(initRes, { "init 201": (r) => r.status === 201 })) {
    successRate.add(false);
    return;
  }

  const { upload_url, upload_id } = JSON.parse(initRes.body).data;

  // Phase 2: PUT file to presigned URL
  const putRes = http.put(upload_url, fakeJpeg(), {
    headers: { "Content-Type": "image/jpeg" },
  });

  if (!check(putRes, { "put 2xx": (r) => r.status >= 200 && r.status < 300 })) {
    successRate.add(false);
    return;
  }

  // Phase 3: complete upload
  const completeRes = http.post(
    `${BASE_URL}/api/v1/uploads/${upload_id}/complete`,
    "{}",
    { headers: apiHeaders }
  );

  const ok = check(completeRes, { "complete 201": (r) => r.status === 201 });
  successRate.add(ok);
  uploadLatency.add(Date.now() - start);
}
