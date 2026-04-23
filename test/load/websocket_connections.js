/**
 * Load test: 1000 concurrent WebSocket connections
 *
 * Simulates family members holding open WebSocket connections and receiving
 * real-time events. Verifies the server handles fan-out at scale.
 *
 * Run: k6 run test/load/websocket_connections.js \
 *        -e BASE_URL=https://staging.example.com \
 *        -e TOKEN=<user_api_token> \
 *        -e FAMILY_ID=<uuid>
 */

import ws from "k6/ws";
import { check, sleep } from "k6";
import { Counter, Rate } from "k6/metrics";

const connectErrors = new Counter("ws_connect_errors");
const messageReceived = new Counter("ws_messages_received");
const successRate = new Rate("ws_success_rate");

export const options = {
  stages: [
    { duration: "30s", target: 200 },
    { duration: "1m", target: 1000 },
    { duration: "2m", target: 1000 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    ws_success_rate: ["rate>0.99"],
    ws_connect_errors: ["count<10"],
  },
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:4000";
const TOKEN = __ENV.TOKEN;
const FAMILY_ID = __ENV.FAMILY_ID;

export default function () {
  const wsUrl = BASE_URL.replace(/^http/, "ws") + "/socket/websocket";

  const res = ws.connect(`${wsUrl}?token=${TOKEN}`, {}, function (socket) {
    socket.on("open", () => {
      // Join the family channel
      socket.send(
        JSON.stringify({
          topic: `family:${FAMILY_ID}`,
          event: "phx_join",
          payload: {},
          ref: "1",
        })
      );
    });

    socket.on("message", (data) => {
      messageReceived.add(1);
      successRate.add(true);
    });

    socket.on("error", () => {
      connectErrors.add(1);
      successRate.add(false);
    });

    // Hold connection open for the test duration
    socket.setTimeout(() => socket.close(), 180_000);
  });

  check(res, { "connected successfully": (r) => r && r.status === 101 });
}
