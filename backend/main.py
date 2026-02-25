"""
MT5 XAUUSD AI Signal Backend
=============================
FastAPI server that receives market data from an MT5 EA,
sends it to OpenAI for analysis, and returns a structured
trading signal using Structured Outputs (JSON schema enforcement).
"""

import os
import traceback
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI
from openai import OpenAI
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Load environment
# ---------------------------------------------------------------------------
load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-2024-08-06")

app = FastAPI(title="MT5 XAUUSD AI Signal", version="1.0.0")

# ---------------------------------------------------------------------------
# Pydantic models — Request
# ---------------------------------------------------------------------------

class CandleData(BaseModel):
    time: str = Field(..., description="Candle open time ISO‑8601")
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0


class Constraints(BaseModel):
    max_spread_points: int = 50
    risk_percent: float = 1.0
    min_rr: float = 1.5
    expiry_minutes: int = 240


class SignalRequest(BaseModel):
    symbol: str = "XAUUSD"
    timeframe: str = "M15"
    server_time_utc: str = ""
    bid: float
    ask: float
    spread_points: int
    digits: int = 2
    point: float = 0.01
    candles: list[CandleData]
    atr: Optional[float] = None
    constraints: Constraints = Constraints()


# ---------------------------------------------------------------------------
# Pydantic models — Response  (also doubles as the JSON schema for OpenAI)
# ---------------------------------------------------------------------------

class BiasEnum(str, Enum):
    bullish = "bullish"
    bearish = "bearish"
    neutral = "neutral"


class OrderTypeEnum(str, Enum):
    buy_stop = "buy_stop"
    sell_stop = "sell_stop"
    none = "none"


class OrderResponse(BaseModel):
    type: OrderTypeEnum
    entry: float
    sl: float
    tp: float
    expiry_minutes: int
    comment: str


class SignalResponse(BaseModel):
    symbol: str
    timestamp_utc: str
    bias: BiasEnum
    order: OrderResponse
    confidence: float = Field(..., ge=0.0, le=1.0)
    veto: bool
    veto_reason: str


# ---------------------------------------------------------------------------
# Helper: compute ATR from candles
# ---------------------------------------------------------------------------

def compute_atr(candles: list[CandleData], period: int = 14) -> float:
    """Compute Average True Range from candle list."""
    if len(candles) < 2:
        return 0.0
    trs: list[float] = []
    for i in range(1, len(candles)):
        high = candles[i].high
        low = candles[i].low
        prev_close = candles[i - 1].close
        tr = max(high - low, abs(high - prev_close), abs(low - prev_close))
        trs.append(tr)
    if not trs:
        return 0.0
    # Simple moving average of the last `period` true ranges
    p = min(period, len(trs))
    return sum(trs[-p:]) / p


# ---------------------------------------------------------------------------
# Helper: build veto response
# ---------------------------------------------------------------------------

def veto_response(symbol: str, reason: str) -> SignalResponse:
    return SignalResponse(
        symbol=symbol,
        timestamp_utc=datetime.now(timezone.utc).isoformat(),
        bias=BiasEnum.neutral,
        order=OrderResponse(
            type=OrderTypeEnum.none,
            entry=0.0,
            sl=0.0,
            tp=0.0,
            expiry_minutes=0,
            comment="",
        ),
        confidence=0.0,
        veto=True,
        veto_reason=reason,
    )


# ---------------------------------------------------------------------------
# Build the JSON schema dict for OpenAI Structured Outputs
# ---------------------------------------------------------------------------

SIGNAL_JSON_SCHEMA = {
    "name": "trading_signal",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "symbol": {"type": "string"},
            "timestamp_utc": {"type": "string"},
            "bias": {"type": "string", "enum": ["bullish", "bearish", "neutral"]},
            "order": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["buy_stop", "sell_stop", "none"]},
                    "entry": {"type": "number"},
                    "sl": {"type": "number"},
                    "tp": {"type": "number"},
                    "expiry_minutes": {"type": "integer"},
                    "comment": {"type": "string"},
                },
                "required": ["type", "entry", "sl", "tp", "expiry_minutes", "comment"],
                "additionalProperties": False,
            },
            "confidence": {"type": "number"},
            "veto": {"type": "boolean"},
            "veto_reason": {"type": "string"},
        },
        "required": [
            "symbol",
            "timestamp_utc",
            "bias",
            "order",
            "confidence",
            "veto",
            "veto_reason",
        ],
        "additionalProperties": False,
    },
}


# ---------------------------------------------------------------------------
# Build system prompt for OpenAI
# ---------------------------------------------------------------------------

def build_system_prompt(req: SignalRequest, atr_value: float) -> str:
    return f"""You are a professional XAUUSD (gold) trading analyst.

RULES — follow these exactly:
1. The current price is Bid={req.bid}, Ask={req.ask}. Do NOT browse the web.
2. You receive {len(req.candles)} candles on timeframe {req.timeframe}.
3. The ATR(14) is {atr_value:.5f}. Use it to set buffer distances.
4. Propose a BREAKOUT-style pending order:
   - buy_stop: entry ABOVE Ask + buffer  (at least Ask + 1*ATR above Ask)
   - sell_stop: entry BELOW Bid - buffer  (at least Bid - 1*ATR below Bid)
5. SL must be on the opposite side of entry:
   - For buy_stop: SL < entry  (e.g. entry - 1.5*ATR)
   - For sell_stop: SL > entry  (e.g. entry + 1.5*ATR)
6. TP must respect min R:R of {req.constraints.min_rr}:
   - |TP - entry| >= {req.constraints.min_rr} * |entry - SL|
7. expiry_minutes = {req.constraints.expiry_minutes}.
8. Provide a short comment (max 30 chars) describing the setup.
9. confidence is 0.0 to 1.0 — your conviction level.
10. If spread ({req.spread_points} pts) > max allowed ({req.constraints.max_spread_points} pts),
    OR if no clear breakout setup exists, set order.type="none", veto=true,
    and veto_reason explaining why.
11. All prices must be rounded to {req.digits} decimal places.
12. symbol must be "{req.symbol}".
13. timestamp_utc must be the current UTC time in ISO-8601 format.

Respond ONLY with valid JSON matching the required schema. No extra text."""


# ---------------------------------------------------------------------------
# Build user message with candle data
# ---------------------------------------------------------------------------

def build_user_message(req: SignalRequest) -> str:
    # Send the last 50 candles as text to keep token usage reasonable
    candle_subset = req.candles[-50:]
    lines = ["Recent candles (newest last):"]
    for c in candle_subset:
        lines.append(
            f"  {c.time} O={c.open} H={c.high} L={c.low} C={c.close} V={c.volume}"
        )
    lines.append(f"\nBid={req.bid} Ask={req.ask} Spread={req.spread_points}pts")
    lines.append(f"Digits={req.digits} Point={req.point}")
    lines.append("Analyze and produce the trading signal.")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/signal", response_model=SignalResponse)
async def generate_signal(req: SignalRequest):
    # 1. Compute ATR if not provided
    atr_value = req.atr if req.atr is not None else compute_atr(req.candles)

    # 2. Quick spread veto (server-side too, belt-and-suspenders)
    if req.spread_points > req.constraints.max_spread_points:
        return veto_response(req.symbol, f"spread {req.spread_points} > max {req.constraints.max_spread_points}")

    # 3. Call OpenAI with Structured Outputs
    try:
        client = OpenAI(api_key=OPENAI_API_KEY, timeout=30.0)

        response = client.responses.create(
            model=OPENAI_MODEL,
            input=[
                {"role": "system", "content": build_system_prompt(req, atr_value)},
                {"role": "user", "content": build_user_message(req)},
            ],
            text={
                "format": {
                    "type": "json_schema",
                    "json_schema": SIGNAL_JSON_SCHEMA,
                }
            },
        )

        # Extract the text output from the response
        raw_json = response.output_text

        # Parse into our Pydantic model for validation
        signal = SignalResponse.model_validate_json(raw_json)
        return signal

    except Exception as e:
        print(f"[ERROR] OpenAI call failed: {e}")
        traceback.print_exc()
        return veto_response(req.symbol, "model_unavailable")


# ---------------------------------------------------------------------------
# Run directly: python main.py
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
