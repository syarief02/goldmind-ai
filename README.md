# MT5 XAUUSD AI Signal Trading System

An end-to-end system that lets a MetaTrader 5 Expert Advisor request AI-powered trading signals from a Python backend (FastAPI + OpenAI), place breakout-style pending orders on XAUUSD, and refresh every 4 hours.

---

## 📁 File Structure

```
mt5 xauusd/
├── backend/
│   ├── main.py              ← FastAPI server (POST /signal, GET /health)
│   ├── requirements.txt     ← Python dependencies
│   └── .env.example         ← Copy to .env and add your OpenAI API key
├── mt5/
│   ├── Include/
│   │   └── JASONNode.mqh    ← JSON parser for MQL5
│   └── Experts/
│       └── XAUUSD_AI_Signal.mq5  ← The Expert Advisor
└── README.md                ← This file
```

---

## 🔧 Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| **Python** | 3.9 or newer | [python.org/downloads](https://python.org/downloads) |
| **MetaTrader 5** | Any build | Your broker's MT5 terminal |
| **OpenAI API Key** | — | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |

---

## 🚀 Quick Start

### Step 1: Set up the Backend

```powershell
# Navigate to the backend folder
cd "c:\Users\User\OneDrive\Desktop\mt5 xauusd\backend"

# Create a virtual environment (recommended)
python -m venv venv
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy .env.example to .env and add your OpenAI API key
copy .env.example .env
# Then edit .env and replace sk-your-key-here with your actual key

# Start the server
python main.py
```

The server starts at **http://localhost:8000**. You should see:

```
INFO:     Uvicorn running on http://0.0.0.0:8000
```

### Step 2: Verify the Backend

Open another terminal and run:

```powershell
curl http://localhost:8000/health
```

Expected response:
```json
{"status":"ok"}
```

### Step 3: Install the EA in MetaTrader 5

1. **Copy the JSON parser:**
   - Copy `mt5\Include\JASONNode.mqh`
   - Paste into your MT5 data folder: `MQL5\Include\JASONNode.mqh`
   - **To find your data folder:** In MT5, go to **File → Open Data Folder**

2. **Copy the EA:**
   - Copy `mt5\Experts\XAUUSD_AI_Signal.mq5`
   - Paste into: `MQL5\Experts\XAUUSD_AI_Signal.mq5`

3. **Compile the EA:**
   - Open **MetaEditor** (press F4 in MT5)
   - Open `XAUUSD_AI_Signal.mq5`
   - Press **Compile** (F7)
   - Verify: **0 errors** in the output

### Step 4: Allow WebRequest in MT5

This is critical — without this, the EA cannot contact the backend.

1. In MT5, go to: **Tools → Options → Expert Advisors**
2. Check ☑ **Allow WebRequest for listed URL**
3. Click **Add** and type: `http://localhost:8000`
4. Click **OK**

> ⚠️ If your backend runs on a remote server with HTTPS, add that URL instead (e.g., `https://your-server.com`).

### Step 5: Attach the EA to a Chart

1. Open a **XAUUSD M15** chart
2. In the **Navigator** panel (Ctrl+N), expand **Expert Advisors**
3. Drag **XAUUSD_AI_Signal** onto the chart
4. In the dialog:
   - **Common** tab: Check ☑ **Allow Algo Trading**
   - **Inputs** tab: Configure parameters (see table below)
5. Click **OK**

The EA will immediately request a signal and begin operating.

---

## ⚙️ Configuration Reference

These are the EA input parameters you can edit when attaching to a chart:

| Parameter | Default | What to Edit |
|-----------|---------|-------------|
| `BackendURL` | `http://localhost:8000/signal` | Change if backend is on another machine or uses HTTPS |
| `MaxSpreadPoints` | `50` | Max allowed spread in points. Lower = stricter |
| `RiskPercent` | `1.0` | % of account **balance** risked per trade. 1.0 = 1% |
| `MinRR` | `1.5` | Minimum reward-to-risk ratio. 1.5 = TP must be 1.5× the SL distance |
| `Timeframe` | `M15` | Must match the chart timeframe you attached to |
| `CandleCount` | `200` | Candles sent to the AI. More = better analysis, slower request |
| `RefreshHours` | `4` | Hours between signal refreshes |
| `MagicNumber` | `20250226` | Unique ID for this EA's orders. Change if running multiple EAs |
| `Timeout` | `10000` | WebRequest timeout in milliseconds |

### Backend Environment Variables (`.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | — | **Required.** Your OpenAI API key |
| `OPENAI_MODEL` | `gpt-4o-2024-08-06` | Model that supports Structured Outputs |

---

## 🧪 Test Plan

### 1. Test Backend Health

```powershell
curl http://localhost:8000/health
# Expected: {"status":"ok"}
```

### 2. Test Signal Endpoint with Sample Data

Save this as `test_payload.json`:

```json
{
  "symbol": "XAUUSD",
  "timeframe": "M15",
  "server_time_utc": "2025-02-26 00:00:00",
  "bid": 2650.50,
  "ask": 2650.80,
  "spread_points": 30,
  "digits": 2,
  "point": 0.01,
  "candles": [
    {"time": "2025-02-25 23:00:00", "open": 2648.00, "high": 2652.00, "low": 2646.50, "close": 2650.20, "volume": 1500},
    {"time": "2025-02-25 23:15:00", "open": 2650.20, "high": 2653.00, "low": 2649.00, "close": 2651.00, "volume": 1200},
    {"time": "2025-02-25 23:30:00", "open": 2651.00, "high": 2654.00, "low": 2650.00, "close": 2652.50, "volume": 1800},
    {"time": "2025-02-25 23:45:00", "open": 2652.50, "high": 2655.00, "low": 2651.00, "close": 2653.80, "volume": 1600},
    {"time": "2025-02-26 00:00:00", "open": 2653.80, "high": 2656.00, "low": 2652.00, "close": 2650.50, "volume": 1400}
  ],
  "constraints": {
    "max_spread_points": 50,
    "risk_percent": 1.0,
    "min_rr": 1.5,
    "expiry_minutes": 240
  }
}
```

Then run:

```powershell
curl -X POST http://localhost:8000/signal -H "Content-Type: application/json" -d @test_payload.json
```

Expected response (example — actual values will vary):
```json
{
  "symbol": "XAUUSD",
  "timestamp_utc": "2025-02-26T00:00:00+00:00",
  "bias": "bullish",
  "order": {
    "type": "buy_stop",
    "entry": 2658.00,
    "sl": 2650.00,
    "tp": 2670.00,
    "expiry_minutes": 240,
    "comment": "Gold breakout above range"
  },
  "confidence": 0.72,
  "veto": false,
  "veto_reason": ""
}
```

### 3. Test in MT5

After attaching the EA to XAUUSD M15:

1. Go to the **Experts** tab at the bottom of MT5
2. You should see logs like:

```
=== XAUUSD AI Signal EA initialized ===
Backend URL: http://localhost:8000/signal
Restored ticket: 0  Last signal: 1970.01.01 00:00:00
>>> No pending order found, requesting new signal...
Sending signal request to: http://localhost:8000/signal
HTTP 200 Response: {"symbol":"XAUUSD",...}
Signal: bias=bullish confidence=0.72 veto=false
Order: type=buy_stop entry=2658.00 SL=2650.00 TP=2670.00 comment=Gold breakout above range
Risk calc: balance=10000.00 risk$=100.00 slDist=8.00 ...
>>> Placing buy_stop entry=2658.00 SL=2650.00 TP=2670.00 lots=0.12
>>> Order placed successfully! Ticket #12345678
```

---

## 🔍 How It Works

```
┌──────────────┐     HTTPS POST      ┌──────────────┐     API Call      ┌──────────┐
│   MT5 EA     │ ──────────────────→  │   FastAPI    │ ───────────────→  │  OpenAI  │
│  (XAUUSD)    │  candles + prices    │   Backend    │  structured JSON  │  GPT-4o  │
│              │ ←──────────────────  │              │ ←───────────────  │          │
│  Places      │    JSON signal       │  Validates   │   trading signal  │ Analyzes │
│  pending     │                      │  & formats   │                   │ candles  │
│  order       │                      │              │                   │          │
└──────────────┘                      └──────────────┘                   └──────────┘
```

**Every 60 seconds the EA checks:**
1. Do I have an open position? → If yes, do nothing
2. Has 4 hours passed since last signal? → Cancel old pending order, request new signal
3. No pending order and no position? → Request new signal

**Safety filters applied before every order:**
- Spread ≤ max allowed
- Entry respects broker stop level / freeze level
- buy_stop entry > Ask, sell_stop entry < Bid
- SL on correct side of entry
- R:R meets minimum threshold
- Lot size calculated from risk % and SL distance

---

## ❗ Troubleshooting

### WebRequest Error 4014
**Cause:** The backend URL is not whitelisted in MT5.
**Fix:** Go to **Tools → Options → Expert Advisors → Allow WebRequest** and add your backend URL exactly as typed in the EA inputs.

### WebRequest Error 4060 / Timeout
**Cause:** Backend is not running, or firewall is blocking the connection.
**Fix:**
- Make sure the backend is running (`python main.py`)
- Check that no firewall blocks port 8000
- Try `curl http://localhost:8000/health` from the same machine

### SSL / HTTPS Errors
**Cause:** MT5 cannot verify the SSL certificate of a remote server.
**Fix:**
- For local development, use `http://` (not `https://`)
- For production, ensure your server has a valid SSL certificate (e.g., from Let's Encrypt)

### JSON Parse Failure in EA
**Cause:** Backend returned unexpected text (HTML error page, empty body, etc.)
**Fix:**
- Check the **Experts** tab for the raw response
- Verify the backend is returning valid JSON by testing with `curl`
- Check backend logs for errors

### Stop Level Errors (Retcode 10016 / TRADE_RETCODE_INVALID_STOPS)
**Cause:** Entry, SL, or TP is too close to current price.
**Fix:**
- The EA already adjusts for stop levels, but some brokers have very large minimum distances
- Check `SymbolInfoInteger(SYMBOL_TRADE_STOPS_LEVEL)` in MT5 → right-click XAUUSD → **Specification**
- If the model proposes very tight levels, increase the ATR buffer by adjusting the AI prompt in `main.py`

### Lot Size is 0 or Too Small
**Cause:** Account balance is too low for the risk parameters, or SL distance is too large.
**Fix:**
- Increase `RiskPercent` or decrease SL distance
- Check minimum lot size for your broker: right-click XAUUSD → **Specification** → Volume section

### Backend Returns Veto with "model_unavailable"
**Cause:** OpenAI API call failed (key invalid, quota exceeded, network error).
**Fix:**
- Verify your API key in `.env` is correct and active
- Check your OpenAI usage at [platform.openai.com/usage](https://platform.openai.com/usage)
- Check backend terminal for detailed error messages

---

## ⚠️ Important Notes

- **Risk Warning:** Algorithmic trading involves significant risk. Test thoroughly on a demo account before using real money.
- **API Costs:** Each signal request costs approximately $0.01–$0.05 in OpenAI API usage (varies by model and token count).
- **Latency:** The AI analysis typically takes 2–10 seconds. The EA has a 10-second timeout by default.
- **One Order at a Time:** The EA ensures at most 1 pending order exists for this strategy at any time.
- **Persistence:** The current pending ticket and last signal time are stored in MT5 GlobalVariables, so they survive EA restarts and terminal restarts.
