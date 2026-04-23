/**
 * Load test: 100 messages/second in a single conversation
 *
 * Sends messages via the REST API at sustained throughput and measures
 * p95/p99 latency. Validates the message pipeline (insert → PubSub → fanout)
 * holds up under write pressure.
 *
 * Run: k6 run test/load/chat_throughput.js \
 *        -e BASE_URL=https://staging.example.com \
 *        -e TOKEN=<user_api_token> \
 *        -e CONVERSATION_ID=<uuid>
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const successRate = new Rate("message_success_rate");
const sendLatency = new Trend("message_send_latency", true);

export const options = {
  // Ramp to 100 RPS — each VU sends ~1 req/s
  stages: [
    { duration: "15s", target: 20 },
    { duration: "1m", target: 100 },
    { duration: "2m", target: 100 },
    { duration: "15s", target: 0 },
  ],
  thresholds: {
    message_success_rate: ["rate>0.99"],
    message_send_latency: ["p(95)<500", "p(99)<1000"],
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:4000";
const TOKEN = __ENV.TOKEN;
const CONVERSATION_ID = __ENV.CONVERSATION_ID;

const headers = {
  Authorization: `Bearer ${TOKEN}`,
  "Content-Type": "application/json",
};

export default function () {
  const payload = JSON.stringify({
    message: { body: `Load test message ${Date.now()}` },
  });

  const res = http.post(
    `${BASE_URL}/api/v1/conversations/${CONVERSATION_ID}/messages`,
    payload,
    { headers }
  );

  const ok = check(res, {
    "status 201": (r) => r.status === 201,
    "has message id": (r) => JSON.parse(r.body)?.data?.id !== undefined,
  });

  successRate.add(ok);
  sendLatency.add(res.timings.duration);

  sleep(1);
}
