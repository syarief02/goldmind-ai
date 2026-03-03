"""
MT5 XAUUSD AI Signal Backend
=============================
FastAPI server that receives market data from an MT5 EA,
sends it to OpenAI for analysis, and returns a structured
trading signal using Structured Outputs (JSON schema enforcement).
"""

import os
import sys
import time
import logging
import traceback
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware
from openai import OpenAI
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Force unbuffered stdout so prints appear immediately in PowerShell
# ---------------------------------------------------------------------------
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(line_buffering=True)
else:
    sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buffering=1)

# ---------------------------------------------------------------------------
# Configure logging (console + file)
# ---------------------------------------------------------------------------
from logging.handlers import RotatingFileHandler

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "goldmind.log")

log_format = logging.Formatter(
    "%(asctime)s | %(levelname)-5s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# Console handler
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(log_format)

# File handler with auto-flush
file_handler = RotatingFileHandler(
    LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8"
)
file_handler.setFormatter(log_format)

# Use force=True to guarantee handlers are set even on uvicorn reload
logging.basicConfig(
    level=logging.INFO,
    handlers=[console_handler, file_handler],
    force=True,   # <-- key: clears & replaces existing handlers on reload
)
logger = logging.getLogger("goldmind")
logger.setLevel(logging.INFO)

# Startup test — verify file logging works
logger.info("=" * 60)
logger.info("GoldMind AI logger initialized — file logging active")
logger.info(f"Log file: {LOG_FILE}")
logger.info("=" * 60)

# ---------------------------------------------------------------------------
# Load environment
# ---------------------------------------------------------------------------
load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.2")
FALLBACK_MODEL = os.getenv("FALLBACK_MODEL", "gpt-5")

app = FastAPI(title="GoldMind AI Signal Backend", version="1.0.0")


# ---------------------------------------------------------------------------
# Middleware — log every incoming request and outgoing response
# ---------------------------------------------------------------------------
class RequestResponseLogger(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # --- Incoming request ---
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        body_size = request.headers.get("content-length", "?")
        logger.info("")
        logger.info("━" * 60)
        logger.info(f"📨 [{now}] INCOMING REQUEST")
        logger.info(f"   {request.method} {request.url.path}")
        logger.info(f"   From: {request.client.host}:{request.client.port}" if request.client else "   From: unknown")
        logger.info(f"   Content-Length: {body_size} bytes")
        sys.stdout.flush()

        # --- Process request ---
        start = time.time()
        response = await call_next(request)
        elapsed = time.time() - start

        # --- Outgoing response ---
        status_emoji = "✅" if response.status_code < 400 else "⚠️" if response.status_code < 500 else "❌"
        logger.info(f"📤 [{now}] OUTGOING RESPONSE")
        logger.info(f"   {status_emoji} Status: {response.status_code}")
        logger.info(f"   ⏱️  Processed in: {elapsed:.2f}s")
        logger.info("━" * 60)
        sys.stdout.flush()

        return response

app.add_middleware(RequestResponseLogger)


# ---------------------------------------------------------------------------
# Startup event — show config banner
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup_banner():
    key_preview = OPENAI_API_KEY[:8] + "..." + OPENAI_API_KEY[-4:] if len(OPENAI_API_KEY) > 12 else "NOT SET"
    print("", flush=True)
    print("=" * 60, flush=True)
    print("  🤖 GoldMind AI Signal Backend", flush=True)
    print("=" * 60, flush=True)
    print(f"  Model:    {OPENAI_MODEL} (fallback: {FALLBACK_MODEL})", flush=True)
    print(f"  API Key:  {key_preview}", flush=True)
    print(f"  Server:   http://127.0.0.1:8000", flush=True)
    print(f"  Health:   http://127.0.0.1:8000/health", flush=True)
    print(f"  Signal:   http://127.0.0.1:8000/signal  (POST)", flush=True)
    print("=" * 60, flush=True)
    print("  Waiting for signal requests from MT5 EA...", flush=True)
    print("=" * 60, flush=True)
    print("", flush=True)

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
# Helper: determine trading session and Malaysia time
# ---------------------------------------------------------------------------

def get_session_info(utc_time: datetime) -> dict:
    """Determine the current trading session and Malaysia local time."""
    myt_time = utc_time + timedelta(hours=8)  # Malaysia is UTC+8
    hour_utc = utc_time.hour

    # Trading sessions (approximate UTC ranges)
    # Asian/Sydney:  22:00 – 07:00 UTC
    # London:        07:00 – 16:00 UTC
    # New York:      13:00 – 22:00 UTC
    # Overlaps:      London-NY 13:00–16:00 UTC
    if 13 <= hour_utc < 16:
        session = "London-New York overlap"
        liquidity = "peak liquidity — highest volume and volatility for gold"
    elif 7 <= hour_utc < 13:
        session = "London session"
        liquidity = "high liquidity — strong gold trading activity"
    elif 16 <= hour_utc < 22:
        session = "New York session"
        liquidity = "good liquidity — active gold trading"
    else:
        session = "Asian/Sydney session"
        liquidity = "lower liquidity — gold typically range-bound, breakouts less reliable"

    return {
        "session": session,
        "liquidity": liquidity,
        "myt_str": myt_time.strftime("%Y-%m-%d %H:%M MYT"),
        "utc_str": utc_time.strftime("%Y-%m-%d %H:%M UTC"),
    }


# ---------------------------------------------------------------------------
# Build system prompt for OpenAI
# ---------------------------------------------------------------------------

def build_system_prompt(req: SignalRequest, atr_value: float) -> str:
    now_utc = datetime.now(timezone.utc)
    session = get_session_info(now_utc)

    return f"""You are a professional XAUUSD (gold spot) trading analyst operating from Malaysia (UTC+8).
You specialize in breakout and momentum trading on gold. Your goal is to find the best available trading opportunity, even if conditions are not absolutely perfect, provided they meet minimum viability.

═══ CURRENT MARKET CONTEXT ═══
- Server time: {session['utc_str']} (Malaysia: {session['myt_str']})
- Trading session: {session['session']} — {session['liquidity']}
- Current price: Bid={req.bid}, Ask={req.ask}, Spread={req.spread_points} pts
- Timeframe: {req.timeframe} ({len(req.candles)} candles provided)
- ATR(14): {atr_value:.5f} (recent average volatility per candle)

═══ ANALYSIS FRAMEWORK ═══
Before making your decision, mentally perform these analysis steps:

1. TECHNICAL ANALYSIS:
   - Identify key support and resistance levels from the candle data
   - Determine the prevailing trend direction (bullish, bearish, or sideways)
   - Look for candlestick patterns (engulfing, pin bars, breakout candles)
   - Use ATR to gauge current volatility and set appropriate distances

2. MACRO / PRICE CONTEXT:
   - Where is price relative to its recent range? Near highs, lows, or mid-range?
   - Is there a clear trending structure (higher highs/lows or lower highs/lows)?
   - Is the market in a consolidation/squeeze that could lead to a breakout?

3. SESSION CONTEXT:
   - Current session: {session['session']}. {session['liquidity']}.
   - During Asian session, prefer wider stops and be cautious with breakouts.
   - During London/NY, breakouts are more reliable — look for momentum.
   - During London-NY overlap, expect the strongest moves.

4. STRATEGY DECISION:
   Based on the above, choose the best approach:
   - BREAKOUT: Place a pending order beyond a key level to catch momentum. This should be your primary action if there's any reasonable technical setup.
   - VETO: Only veto if the market is extremely choppy and completely untradable. Avoid vetoing just because conditions aren't perfectly aligned.

═══ ORDER RULES — follow these exactly ═══
1. Only propose pending orders (buy_stop or sell_stop), never market orders.
2. buy_stop: entry ABOVE Ask + buffer (at least Ask + 1×ATR)
   sell_stop: entry BELOW Bid - buffer (at least Bid - 1×ATR)
3. SL must be on the opposite side of entry:
   - buy_stop: SL < entry (e.g. entry - 1.5×ATR)
   - sell_stop: SL > entry (e.g. entry + 1.5×ATR)
4. TP must respect min R:R of {req.constraints.min_rr}:
   - |TP - entry| >= {req.constraints.min_rr} × |entry - SL|
5. expiry_minutes = {req.constraints.expiry_minutes}.
6. Provide a short comment (max 30 chars) describing the setup.
7. If spread ({req.spread_points} pts) > max allowed ({req.constraints.max_spread_points} pts),
   OR if no clear setup exists, set order.type="none", veto=true,
   veto_reason explaining why.
8. All prices must be rounded to {req.digits} decimal places.
9. symbol = "{req.symbol}". timestamp_utc = current UTC time in ISO-8601.

═══ CONFIDENCE GUIDE ═══
- 0.80–1.00: Strong conviction — clear trend, key level breakout, good session, multiple confirming factors.
- 0.60–0.79: Moderate conviction — decent setup but some uncertainty. Still a viable trade.
- 0.40–0.59: Weak setup — acceptable if you want to test a level, but consider vetoing if conditions are extremely poor.
- Below 0.40: Veto. Do not trade.

Respond ONLY with valid JSON matching the required schema. No extra text."""


# ---------------------------------------------------------------------------
# Build user message with candle data
# ---------------------------------------------------------------------------

def build_user_message(req: SignalRequest) -> str:
    candle_subset = req.candles[-120:]

    # Compute a quick market structure summary from the candles
    if candle_subset:
        highs = [c.high for c in candle_subset]
        lows = [c.low for c in candle_subset]
        recent_high = max(highs)
        recent_low = min(lows)
        price_range = recent_high - recent_low
        mid_price = req.bid
        position_pct = ((mid_price - recent_low) / price_range * 100) if price_range > 0 else 50.0

        # Simple trend from first vs last candle
        first_close = candle_subset[0].close
        last_close = candle_subset[-1].close
        trend_change = last_close - first_close
        trend_dir = "bullish" if trend_change > 0 else "bearish" if trend_change < 0 else "flat"
    else:
        recent_high = recent_low = position_pct = 0
        trend_dir = "unknown"
        trend_change = 0

    lines = [
        "═══ MARKET STRUCTURE SUMMARY ═══",
        f"Recent 120-candle high: {recent_high}",
        f"Recent 120-candle low:  {recent_low}",
        f"Current price position: {position_pct:.0f}% of range (0%=at low, 100%=at high)",
        f"Short-term trend: {trend_dir} (moved {trend_change:+.{req.digits}f} over last 120 candles)",
        "",
        "═══ CANDLE DATA (newest last) ═══",
    ]
    for c in candle_subset:
        lines.append(
            f"  {c.time} O={c.open} H={c.high} L={c.low} C={c.close} V={c.volume}"
        )
    lines.append(f"\nBid={req.bid} Ask={req.ask} Spread={req.spread_points}pts")
    lines.append(f"Digits={req.digits} Point={req.point}")
    lines.append("\nAnalyze the market using the framework above and produce the trading signal.")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/signal", response_model=SignalResponse)
async def generate_signal(req: SignalRequest):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    logger.info("")
    logger.info("─" * 60)
    logger.info(f"📥 [{now}] Signal request received")
    logger.info(f"   Symbol: {req.symbol}  Timeframe: {req.timeframe}")
    logger.info(f"   Bid: {req.bid}  Ask: {req.ask}  Spread: {req.spread_points}pts")
    logger.info(f"   Candles: {len(req.candles)}  ATR: {req.atr}")
    logger.info(f"   Model: {OPENAI_MODEL}")

    # 1. Compute ATR if not provided
    atr_value = req.atr if req.atr is not None else compute_atr(req.candles)

    # 2. Quick spread veto (server-side too, belt-and-suspenders)
    if req.spread_points > req.constraints.max_spread_points:
        logger.warning(f"   🚫 VETO: Spread {req.spread_points} > max {req.constraints.max_spread_points}")
        logger.info("─" * 60)
        return veto_response(req.symbol, f"spread {req.spread_points} > max {req.constraints.max_spread_points}")

    # 3. Call OpenAI with Structured Outputs (with fallback)
    client = OpenAI(api_key=OPENAI_API_KEY, timeout=30.0)
    models_to_try = [OPENAI_MODEL]
    if FALLBACK_MODEL and FALLBACK_MODEL != OPENAI_MODEL:
        models_to_try.append(FALLBACK_MODEL)

    messages = [
        {"role": "system", "content": build_system_prompt(req, atr_value)},
        {"role": "user", "content": build_user_message(req)},
    ]

    last_error = None
    for model in models_to_try:
        try:
            is_fallback = model != OPENAI_MODEL
            if is_fallback:
                logger.warning(f"   🔄 Falling back to {model}...")
            else:
                logger.info(f"   ⏳ Calling OpenAI ({model})...")
            sys.stdout.flush()
            start_time = time.time()

            response = client.chat.completions.create(
                model=model,
                messages=messages,
                response_format={
                    "type": "json_schema",
                    "json_schema": SIGNAL_JSON_SCHEMA,
                },
            )

            elapsed = time.time() - start_time

            # Token usage
            usage = response.usage
            if usage:
                logger.info(f"   📊 Tokens: {usage.prompt_tokens} in + {usage.completion_tokens} out = {usage.total_tokens} total")
            logger.info(f"   ⏱️  Response time: {elapsed:.1f}s")
            if is_fallback:
                logger.info(f"   ℹ️  Used fallback model: {model}")

            # Extract the text output from the response
            raw_json = response.choices[0].message.content

            # Parse into our Pydantic model for validation
            signal = SignalResponse.model_validate_json(raw_json)

            # --- FIX Issue 3: Override timestamp with actual server time ---
            signal.timestamp_utc = datetime.now(timezone.utc).isoformat()

            # --- FIX Issue 1: Server-side R:R auto-correction ---
            if not signal.veto and signal.order.type.value != "none":
                entry = signal.order.entry
                sl = signal.order.sl
                tp = signal.order.tp
                sl_dist = abs(entry - sl)
                tp_dist = abs(tp - entry)
                rr = tp_dist / sl_dist if sl_dist > 0 else 0

                if rr < req.constraints.min_rr and sl_dist > 0:
                    # Auto-correct TP to meet minimum R:R
                    required_tp_dist = sl_dist * req.constraints.min_rr
                    if signal.order.type.value == "buy_stop":
                        new_tp = round(entry + required_tp_dist, req.digits)
                    else:
                        new_tp = round(entry - required_tp_dist, req.digits)

                    logger.warning(f"   ⚠️  R:R {rr:.2f} < min {req.constraints.min_rr} — auto-correcting TP")
                    logger.info(f"      TP: {tp} → {new_tp} (R:R: {rr:.2f} → {req.constraints.min_rr:.2f})")
                    signal.order.tp = new_tp

            # Log the result
            if signal.veto:
                logger.warning(f"   🚫 VETO: {signal.veto_reason}")
            else:
                logger.info(f"   ✅ Signal: {signal.bias.value.upper()} (confidence: {signal.confidence:.0%})")
                logger.info(f"   📋 Order: {signal.order.type.value}")
                logger.info(f"      Entry: {signal.order.entry}  SL: {signal.order.sl}  TP: {signal.order.tp}")
                logger.info(f"      Comment: {signal.order.comment}")
            logger.info("─" * 60)

            return signal

        except Exception as e:
            last_error = e
            logger.error(f"   ❌ {model} failed: {e}")
            if not is_fallback and len(models_to_try) > 1:
                logger.info(f"   ↪ Will try fallback model...")
            continue

    # All models failed
    logger.error(f"   ❌ All models failed. Last error: {last_error}")
    traceback.print_exc()
    logger.info("─" * 60)
    return veto_response(req.symbol, "model_unavailable")


# ---------------------------------------------------------------------------
# Run directly: python main.py
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
    )
