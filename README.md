# 🤖 MT5 GoldMind AI Trading System

> **What is this?** This is a tool that uses AI (ChatGPT) to analyze gold (XAUUSD) price charts and automatically place trades for you in MetaTrader 5. It runs on your own computer — you just need to start two things: a small Python server and the EA in MT5.

---

## 📖 Table of Contents

1. [How Does This Work?](#-how-does-this-work)
2. [What You Need Before Starting](#-what-you-need-before-starting)
3. [Step 1: Set Up the Python Backend](#-step-1-set-up-the-python-backend-server)
4. [Step 2: Start the Server](#-step-2-start-the-server)
5. [Step 3: Install the EA in MetaTrader 5](#-step-3-install-the-ea-in-metatrader-5)
6. [Step 4: Allow WebRequest in MT5](#-step-4-allow-webrequest-in-mt5-very-important)
7. [Step 5: Attach the EA to a Chart](#-step-5-attach-the-ea-to-a-chart)
8. [Step 6: Watch It Work](#-step-6-watch-it-work)
9. [Understanding the EA Settings](#-understanding-the-ea-settings)
10. [How to Stop the EA](#-how-to-stop-the-ea)
11. [How to Restart Everything](#-how-to-restart-everything-after-pc-reboot)
12. [Troubleshooting Common Problems](#-troubleshooting-common-problems)
13. [Frequently Asked Questions](#-frequently-asked-questions)

---

## 🔄 How Does This Work?

Here's the simple version:

```
YOU START THE SERVER         THE EA IN MT5              OPENAI (CHATGPT)
on your computer             runs on XAUUSD chart       analyzes the market
        │                           │                          │
        │    1. EA sends price      │                          │
        │    data every 4 hours     │                          │
        │◄──────────────────────────│                          │
        │                           │                          │
        │    2. Server forwards     │                          │
        │    data to ChatGPT        │                          │
        │──────────────────────────────────────────────────────►│
        │                           │                          │
        │    3. ChatGPT sends       │                          │
        │    back a trade signal    │                          │
        │◄──────────────────────────────────────────────────────│
        │                           │                          │
        │    4. Server sends        │                          │
        │    signal back to EA      │                          │
        │──────────────────────────►│                          │
        │                           │                          │
        │                    5. EA places a                    │
        │                    pending order                     │
        │                    (if signal is good)               │
```

**In plain English:**
- Every **4 hours**, the EA in MT5 collects the latest candle data (prices) and sends it to your local Python server
- The server sends that data to OpenAI (ChatGPT) and asks it to analyze the chart
- ChatGPT responds with a trading signal: "place a buy stop here" or "place a sell stop here" or "don't trade right now"
- The EA checks the signal for safety (is the spread too wide? is the risk too high?) and if everything looks good, it places a pending order
- After 4 hours, if the pending order hasn't been triggered, the EA cancels it and asks for a fresh signal
- If the EA already has an open position, it **skips** the request entirely to save API costs

### 🧠 How the AI Analysis Works

The server sends **two things** to OpenAI:

**1. A set of rules** telling the AI how to behave:
- "You are a professional XAUUSD trading analyst"
- Use ATR (volatility indicator) to set price buffers
- Propose breakout-style pending orders only
- Entry must be above Ask (for buys) or below Bid (for sells)
- Stop loss and take profit must respect minimum risk-reward ratio
- If no clear setup exists, veto (don't trade)

**2. The latest market data** from MT5:
- Last 50 candles (open, high, low, close, volume for each)
- Current bid/ask prices and spread
- ATR value (measures how much the price typically moves)

**What comes back** — a structured JSON response:
```json
{
  "bias": "bullish",
  "confidence": 0.72,
  "order": {
    "type": "buy_stop",
    "entry": 5205.18,
    "sl": 5191.08,
    "tp": 5220.68,
    "comment": "bullish breakout potential"
  },
  "veto": false
}
```

The EA then runs this through **6 safety filters** before placing any order:
1. ✅ Spread check — is the spread reasonable?
2. ✅ Stop level check — does the broker allow this entry distance?
3. ✅ Entry price validation — is entry above/below current price?
4. ✅ SL direction check — is the stop loss on the correct side?
5. ✅ Risk-reward ratio — is the potential profit worth the risk?
6. ✅ Lot size calculation — how much to risk based on your account balance?

Only if **all 6 filters pass** will the EA place the pending order.

### 💰 How Lot Size Is Calculated

The EA automatically calculates the correct lot size based on your `RiskPercent` setting and the stop loss distance:

```
lots = (balance × risk%) / (SL distance in ticks × tick value per tick)
```

**Example:** You have a $1,000 account with `RiskPercent = 1.0` (1%):
- Risk budget = $1,000 × 1% = **$10**
- AI suggests SL = 10 points away (100 ticks for XAUUSD)
- Tick value = $0.01 per tick per 0.01 lot
- Lots = $10 / (100 × $1.00) = **0.10 lots**

**What if the calculated lot is too small?** If your account is small or the SL distance is large, the calculated lot may fall below your broker's minimum (usually 0.01 lots). In this case, the EA will:
1. Use the **broker's minimum lot** (e.g., 0.01) instead
2. Log a warning: `"Using minimum lot"`
3. Tell you the **actual dollar risk** and **actual risk %** so you know exactly what you're risking

This means your actual risk per trade may be **higher** than your configured `RiskPercent` — but it's the smallest trade your broker allows. If the risk is too high for your comfort, deposit more funds to bring the percentage down.

---

## 📋 What You Need Before Starting

Before you begin, make sure you have these three things:

### 1. Python (programming language)
- **Download from:** https://www.python.org/downloads/
- Click the big yellow **"Download Python"** button
- During installation, **CHECK THE BOX** that says **"Add Python to PATH"** — this is very important!
- Click "Install Now"

### 2. MetaTrader 5 (your broker's version)
- You should already have this installed from your broker
- Make sure you can log in and see XAUUSD charts

### 3. OpenAI API Key
- **What is this?** It's like a password that lets your server talk to ChatGPT
- **Where to get it:** https://platform.openai.com/api-keys
- Sign up / log in → click **"+ Create new secret key"** → copy the key (starts with `sk-`)
- **You need credits!** Go to https://platform.openai.com/settings/organization/billing/overview → add $5-10
  - Each trade signal costs about $0.01–$0.05, so $5 lasts a very long time

---

## 🖥️ Step 1: Set Up the Python Backend (Server)

The "backend" is a small program that runs on your computer. It receives data from MT5 and talks to ChatGPT.

### Open a terminal (Command Prompt or PowerShell):
1. Press **Windows key + R** on your keyboard
2. Type `cmd` and press Enter
3. A black window (terminal) will open

### Navigate to the backend folder:
Type this command and press Enter (adjust the path if your project is in a different location):
```
cd "path\to\your\goldmind-ai\backend"
```

### Install the required packages:
Type this command and press Enter (this downloads the tools the server needs):
```
pip install -r requirements.txt
```
Wait until it says "Successfully installed..." — this may take 1-2 minutes.

### Set up your API key:
Your API key should already be saved in the `.env` file. To check:
```
type .env
```
You should see something like:
```
OPENAI_API_KEY=sk-proj-xxxxx...your-key-here...
OPENAI_MODEL=gpt-4o-2024-08-06
```
If the key is missing, create the file:
```
copy .env.example .env
notepad .env
```
Replace `sk-your-key-here` with your actual API key, save, and close Notepad.

---

## 🚀 Step 2: Start the Server

In the same terminal window, type:
```
python main.py
```

You should see:
```
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     Application startup complete.
```

### ✅ Test that it's working:
Open a **new** terminal window (Windows+R → cmd) and type:
```
curl http://127.0.0.1:8000/health
```
You should see:
```json
{"status":"ok"}
```
If you see this, your server is running! 🎉

> ⚠️ **IMPORTANT:** Keep the server terminal window open! If you close it, the EA will stop getting signals. Minimize it if you want, but don't close it.

---

## 📂 Step 3: Install the EA in MetaTrader 5

You need to copy two files into your MT5 installation folder.

### Find your MT5 data folder:
1. Open MetaTrader 5
2. Click **File** in the top menu bar
3. Click **Open Data Folder**
4. A Windows Explorer window will open — this is your MT5 data folder
5. You should see a folder called `MQL5` — open it

### Copy the JSON parser file:
1. In the `MQL5` folder, open the `Include` subfolder
2. Copy the file from your project:
   - **From:** your project's `mt5\Include\JASONNode.mqh`
   - **To:** the `MQL5\Include\` folder you just opened
   
### Copy the EA file:
1. Go back to the `MQL5` folder, open the `Experts` subfolder
2. Copy the file from your project:
   - **From:** your project's `mt5\Experts\GoldMind_AI.mq5`
   - **To:** the `MQL5\Experts\` folder you just opened

### Compile the EA:
1. In MetaTrader 5, press **F4** on your keyboard — this opens **MetaEditor**
2. In MetaEditor, press **Ctrl+O** (Open) and navigate to `MQL5\Experts\GoldMind_AI.mq5`
3. Press **F7** (or click the **Compile** button) to compile
4. At the bottom, you should see: **`0 errors, 0 warnings`**
5. Close MetaEditor and go back to MetaTrader 5

> 💡 **Already compiled?** If you used the automated setup earlier, the EA might already be compiled (the `.ex5` file already exists). You can skip the compile step.

---

## 🔐 Step 4: Allow WebRequest in MT5 (VERY IMPORTANT!)

This step is **critical**. Without it, the EA cannot communicate with your server and you'll get error 4014.

1. In MetaTrader 5, click **Tools** in the top menu bar
2. Click **Options**
3. Click the **Expert Advisors** tab
4. Check the box: ☑ **Allow WebRequest for listed URL**
5. In the text field below, click **Add** (or double-click in the empty area)
6. Type exactly: `http://127.0.0.1:8000`
7. Press **Enter**
8. Click **OK**

Your settings should look like this:
```
☑ Allow WebRequest for listed URL
   http://127.0.0.1:8000
```

---

## 📊 Step 5: Attach the EA to a Chart

> ⚠️ **IMPORTANT: XAUUSD ONLY!** This EA must be attached to a **XAUUSD** (gold) chart. The AI is specifically trained to analyze gold price action. If you attach it to a different symbol (e.g., EURUSD, GBPJPY), it will send that symbol's data but the AI will still analyze it as if it's gold — **this will produce bad signals!**

### Open a XAUUSD chart:
1. In MetaTrader 5, look at the **Market Watch** panel on the left (press **Ctrl+M** if you don't see it)
2. Find **XAUUSD** in the list (your broker may label it as **GOLD**, **XAUUSDm**, or similar — any gold pair works)
3. Right-click on **XAUUSD** → click **Chart Window**
4. A new chart will open

### Chart timeframe (any is fine):
The chart timeframe **does not matter**. The EA uses its own `Timeframe` input setting (default: M15) to pull candle data, regardless of what timeframe the chart is displaying. You can leave the chart on any timeframe you personally prefer for viewing.

### Attach the EA:
1. Press **Ctrl+N** to open the **Navigator** panel (on the left side)
2. Expand **Expert Advisors** (click the + or triangle next to it)
3. You should see **GoldMind_AI**
4. **Drag it** onto your XAUUSD chart (or double-click it)
5. A dialog box will appear with settings:

#### Common tab:
- ☑ Check **Allow Algo Trading** — this must be checked!

#### Inputs tab:
- You can leave everything as default for now, or adjust:
  - `BackendURL` = `http://127.0.0.1:8000/signal` (leave as is)
  - `RiskPercent` = `1.0` (means 1% of your balance per trade)
  - `MaxSpreadPoints` = `50` (blocks trades when spread is too wide)

6. Click **OK**

### Enable Auto Trading:
Look at the top toolbar of MT5. You should see a button that says **"Algo Trading"** — make sure it's **enabled** (green icon, not red). Click it to toggle.

---

## 👀 Step 6: Watch It Work

### Check the Experts tab:
1. At the bottom of MetaTrader 5, click the **Experts** tab
2. You should see messages like:

```
License valid until: 2026.03.31 23:59
=== GoldMind AI initialized ===
Backend URL: http://127.0.0.1:8000/signal
>>> No pending order found, requesting new signal...
Sending signal request to: http://127.0.0.1:8000/signal
HTTP 200 Response: {"symbol":"XAUUSD",...}
Signal: bias=bullish confidence=0.72 veto=false
Order: type=buy_stop entry=5205.18 SL=5191.08 TP=5220.68
>>> Placing buy_stop entry=5205.18 SL=5191.08 TP=5220.68 lots=0.01
>>> Order placed successfully! Ticket #349283891
```

### Check the Trade tab:
1. Click the **Trade** tab at the bottom of MT5
2. You should see a pending order (buy stop or sell stop) for XAUUSD

### What happens next:
- **If the price hits the entry level** → the pending order becomes a real trade
- **If 4 hours pass and it hasn't triggered** → the EA cancels it and asks for a new signal
- **If the AI says "don't trade"** → the EA logs "Signal vetoed" and waits 4 hours before trying again
- **If the safety filter rejects the trade** (bad R:R, spread too wide, etc.) → the EA waits 4 hours before the next request
- **If the server/API fails** (no internet, API error) → the EA retries in **15 minutes** instead of waiting the full 4 hours

---

## ⚙️ Understanding the EA Settings (Detailed)

When you attach the EA to a chart, a dialog box appears with an **Inputs** tab where you can configure each parameter. Below is a detailed explanation of every parameter — what it does, how it works internally, and tips for tuning it.

---

### 1. `BackendURL` — Server Address

| | |
|---|---|
| **Type** | `string` |
| **Default** | `http://127.0.0.1:8000/signal` |

**What it does:** This is the full URL that the EA sends its market data to via an HTTP POST request. The Python backend server listens at this address and responds with a trading signal.

**How it works internally:**
- Every time the EA needs a new signal, it builds a JSON payload containing candle data, current prices, ATR, and your constraint settings, then sends it to this URL using MQL5's `WebRequest()` function.
- The `/signal` at the end is the specific API endpoint on the backend that processes the request.

**When to change it:**
- **Same computer:** Leave as default (`127.0.0.1` means "this computer").
- **VPS or remote server:** Change to the IP address of the machine running the Python server (e.g., `http://192.168.1.100:8000/signal`).
- **Different port:** If you changed the port in `main.py`, update the `:8000` part to match.

> ⚠️ **Important:** Whatever URL you set here, you **must** also add the base URL (without `/signal`) to MT5's allowed WebRequest list under **Tools → Options → Expert Advisors**. For example, add `http://127.0.0.1:8000`.

---

### 2. `MaxSpreadPoints` — Spread Filter

| | |
|---|---|
| **Type** | `integer` |
| **Default** | `50` |

**What it does:** Sets the maximum allowable spread (in points) before the EA refuses to place a trade. This is a safety filter to prevent trading during volatile or illiquid conditions when spreads widen.

**How it works internally:**
- **In the EA (Safety Filter 1):** Before placing any order, the EA checks the current live spread. If `spread > MaxSpreadPoints`, the trade is rejected with the message `"REJECTED: Spread X > max Y"`.
- **In the backend:** The backend also performs a server-side spread check as an extra layer of protection. If the spread sent by the EA exceeds this value, the backend returns a veto before even calling OpenAI, saving you API costs.
- **In the AI prompt:** This value is passed to the AI in the system prompt as a constraint, so the AI is also told not to propose trades when the spread is too high.

**How to set it:**
- **Lower values (e.g., 30):** More conservative — only trades when spreads are tight. Fewer trades but better entry conditions.
- **Higher values (e.g., 100):** More permissive — trades even during wider spreads. More trades but potentially worse fills.
- Check your broker's typical XAUUSD spread. If it's normally 15–25 points, a `MaxSpreadPoints` of 50 gives comfortable headroom.

---

### 3. `RiskPercent` — Risk Per Trade

| | |
|---|---|
| **Type** | `double` (decimal number) |
| **Default** | `1.0` (= 1%) |

**What it does:** Controls how much of your **account balance** you risk on each trade. The EA uses this to calculate the lot size.

**How it works internally:**
The lot size formula is:

```
risk_amount = account_balance × (RiskPercent / 100)
sl_ticks     = |entry - stop_loss| / tick_size
risk_per_lot = sl_ticks × tick_value
lots         = risk_amount / risk_per_lot
```

For example, with a $1,000 account and `RiskPercent = 1.0`:
- Risk budget = $1,000 × 1% = **$10**
- If the AI sets a stop loss 10 points away (100 ticks), and tick value is $0.01 per tick per 0.01 lot:
- Lots = $10 / (100 × $1.00) = **0.10 lots**

**Special case — minimum lot:**
If the calculated lot size is smaller than your broker's minimum (usually 0.01 lots), the EA will:
1. Use the broker's minimum lot instead
2. Log a warning: `"Using minimum lot"`
3. Display the **actual dollar risk** and **actual risk %** so you know the real exposure

This means your actual risk may exceed `RiskPercent` — but it's the smallest trade possible.

**How to set it:**
- **`0.5` (0.5%):** Very conservative, good for small accounts or cautious traders.
- **`1.0` (1%):** Standard risk management — the most common setting.
- **`2.0` (2%):** Aggressive — higher potential returns but also larger drawdowns.
- **`5.0+` (5%+):** Very aggressive — not recommended unless on a demo account.

---

### 4. `MinRR` — Minimum Reward-to-Risk Ratio

| | |
|---|---|
| **Type** | `double` (decimal number) |
| **Default** | `1.5` |

**What it does:** Sets the minimum acceptable reward-to-risk ratio for a trade. If the AI's suggested trade doesn't meet this threshold, the EA rejects it.

**How it works internally:**
- **Safety Filter 6** calculates the R:R as:
  ```
  R:R = |TP - entry| / |entry - SL|
  ```
- If the result is less than `MinRR`, the trade is rejected with `"REJECTED: R:R X < min Y"`.
- This value is also passed to the AI in the system prompt as a constraint: `"TP must respect min R:R of {MinRR}"`, so the AI tries to design trades that meet this ratio from the start.

**How to set it:**
- **`1.0`:** You're accepting trades where the potential profit equals the potential loss. More signals but lower quality.
- **`1.5`:** Target profit must be 1.5× the stop loss distance. Good balance of quality and quantity.
- **`2.0`:** Only take trades where you stand to gain twice what you risk. Higher quality but fewer trades.
- **`3.0+`:** Very selective — only the best setups pass. Very few trades.

---

### 5. `Timeframe` — Candle Timeframe

| | |
|---|---|
| **Type** | `ENUM_TIMEFRAMES` (dropdown) |
| **Default** | `PERIOD_M15` (15-minute candles) |

**What it does:** Determines which timeframe's candle data (OHLCV) the EA collects and sends to the AI for analysis. This is **independent** of the chart timeframe you're viewing in MT5.

**How it works internally:**
- The EA calls `CopyRates(_Symbol, InpTimeframe, 0, InpCandleCount, rates)` to fetch historical candle data at this specific timeframe.
- The candle data is sent as part of the JSON request to the backend, along with a `"timeframe"` string label (e.g., `"M15"`, `"H1"`).
- The AI uses this data to analyze price action and propose breakout levels.
- The EA also computes ATR(14) from these candles to measure recent volatility.

**Available options:**
| Value | Candle Period |
|-------|--------------|
| `M1` | 1 minute |
| `M5` | 5 minutes |
| `M15` | 15 minutes **(default)** |
| `M30` | 30 minutes |
| `H1` | 1 hour |
| `H4` | 4 hours |
| `D1` | 1 day |
| `W1` | 1 week |
| `MN1` | 1 month |

**How to set it:**
- **M15 (recommended):** Provides a good balance between granularity and noise. With `CandleCount = 200`, this covers about 50 hours of price data.
- **H1 or H4:** Smoother data with less noise, better for swing trading. You may want to reduce `CandleCount` since each candle covers more time.
- **M1 or M5:** Very granular, lots of noise. Generally not recommended for this type of breakout analysis.

---

### 6. `CandleCount` — Number of Candles

| | |
|---|---|
| **Type** | `integer` |
| **Default** | `200` |

**What it does:** Sets how many historical candles (at the configured `Timeframe`) the EA sends to the backend for AI analysis.

**How it works internally:**
- The EA fetches this many candles from MT5's history using `CopyRates()`.
- All candles are included in the JSON payload sent to the backend, ordered from oldest to newest.
- **However**, the backend only sends the **last 50 candles** to OpenAI (to keep token usage reasonable), regardless of how many the EA sends. The full candle set is still used to compute ATR(14) on the server side.
- More candles = more historical context for ATR calculation, but the AI only sees the most recent 50.

**How to set it:**
- **`50`:** Minimum useful amount. The AI sees all of them, but ATR has limited history.
- **`200` (default):** Good balance — provides enough history for accurate ATR calculation while keeping the payload size manageable.
- **`500+`:** More historical context for ATR, but larger payload and slightly slower requests. The AI still only sees the last 50.

**Data coverage examples (with default M15 timeframe):**
| CandleCount | Time Coverage |
|-------------|--------------|
| 50 | ~12.5 hours |
| 200 | ~50 hours (~2 days) |
| 500 | ~125 hours (~5 days) |

---

### 7. `RefreshHours` — Signal Refresh Interval

| | |
|---|---|
| **Type** | `integer` |
| **Default** | `4` (hours) |

**What it does:** Controls two key behaviors:
1. **How long a pending order lives** before it's automatically cancelled and a fresh signal is requested.
2. **The cooldown period** between signal requests when no pending order exists (e.g., after a veto or a rejected trade).

**How it works internally:**
- The EA runs a timer every 60 seconds via `OnTimer()`.
- **Case 1 — Pending order exists and refresh time has passed:** The EA cancels the stale pending order and immediately requests a new signal.
- **Case 2 — No pending order and cooldown has passed:** The EA requests a new signal.
- **Case 3 — Pending order exists and within refresh window:** The EA does nothing and waits.
- The refresh interval is also sent to the backend as `expiry_minutes` (= `RefreshHours × 60`), which the AI uses to set the order's expiration time.

**Retry on failure:** If the last request failed (server down, API error, etc.), the EA uses a shorter cooldown of **15 minutes** instead of the full `RefreshHours`, so it recovers faster from temporary issues.

**How to set it:**
- **`4` (default):** The EA checks for new setups roughly 6 times per day (during market hours). Balances API costs with signal freshness.
- **`1`:** Very frequent — new signal every hour. Higher API costs (~$0.24–$1.20/day) but more responsive to market changes.
- **`8` or `12`:** Infrequent — good for longer-term setups or to minimize API costs.

---

### 8. `MagicNumber` — EA Identifier

| | |
|---|---|
| **Type** | `long` (integer) |
| **Default** | `20250226` |

**What it does:** A unique numeric identifier that tags all orders and positions placed by this EA. It allows the EA to distinguish its own trades from those placed manually or by other EAs.

**How it works internally:**
- On initialization, the EA sets `trade.SetExpertMagicNumber(InpMagicNumber)` so every order it places is tagged with this number.
- When checking for existing positions (`HasOpenPosition()`) or pending orders (`HasPendingOrder()`), the EA filters by both the symbol (`_Symbol`) **and** this magic number. This means:
  - It only manages its own orders — it won't interfere with your manual trades.
  - It correctly detects when it already has a position open, preventing duplicate signals.

**When to change it:**
- **Single EA:** Leave as default. No need to change.
- **Multiple EAs on the same account:** Each EA instance must have a **unique** `MagicNumber` so they don't interfere with each other. For example, use `20250226` for one and `20250227` for another.
- **Same EA on different symbols (not recommended):** If you ever adapt this EA for other symbols, give each a unique magic number.

---

### 9. `Timeout` — WebRequest Timeout

| | |
|---|---|
| **Type** | `integer` (milliseconds) |
| **Default** | `10000` (= 10 seconds) |

**What it does:** Sets the maximum time (in milliseconds) that the EA will wait for a response from the backend server before giving up.

**How it works internally:**
- This value is passed directly to MQL5's `WebRequest()` function as the timeout parameter.
- If the server doesn't respond within this time, `WebRequest()` returns `-1` and the EA logs an error.
- On timeout, the EA sets `g_lastRequestFailed = true`, which triggers the shorter 15-minute retry cooldown instead of the full `RefreshHours` wait.

**How to set it:**
- **`10000` (10s, default):** Usually enough for the backend to call OpenAI and return a response. OpenAI typically responds in 2–8 seconds.
- **`15000–20000` (15–20s):** Use if you experience occasional timeouts, especially with slower models like `gpt-5`.
- **`30000` (30s):** Maximum recommended. If responses consistently take this long, there may be a network or API issue to investigate.
- **`5000` (5s):** Too short for most cases — the OpenAI API call alone may take longer than this.

---

### Quick Reference Table

| Setting | Type | Default | Range / Notes |
|---------|------|---------|---------------|
| `BackendURL` | string | `http://127.0.0.1:8000/signal` | Must match your server address |
| `MaxSpreadPoints` | int | `50` | 0–∞; lower = safer |
| `RiskPercent` | double | `1.0` | 0.1–100; typically 0.5–2.0 |
| `MinRR` | double | `1.5` | 1.0–∞; higher = fewer but better trades |
| `Timeframe` | enum | `M15` | M1, M5, M15, M30, H1, H4, D1, W1, MN1 |
| `CandleCount` | int | `200` | 50–1000; AI only sees last 50 |
| `RefreshHours` | int | `4` | 1–24; controls signal frequency |
| `MagicNumber` | long | `20250226` | Any unique integer |
| `Timeout` | int | `10000` | 5000–30000 ms recommended |

---

## 🛑 How to Stop the EA

### Temporarily pause:
- Click the **"Algo Trading"** button in the MT5 toolbar to disable it (icon turns red)
- The EA stays attached but won't place new trades

### Remove completely:
- Right-click on the chart → **Expert Advisors** → **Remove**
- This removes the EA from the chart

### Stop the server:
- Go to the terminal window where the server is running
- Press **Ctrl+C** to stop it
- Close the terminal window

---

## 🔄 How to Restart Everything (After PC Reboot)

After you restart your computer, you need to start two things:

### 1. Start the server:
1. Open a terminal (Windows+R → cmd)
2. Navigate to the backend folder:
   ```
   cd "path\to\your\goldmind-ai\backend"
   ```
3. Start the server:
   ```
   python main.py
   ```
4. Wait until you see "Application startup complete"
5. **Keep this window open**

### 2. Open MT5:
1. Open MetaTrader 5
2. The EA should still be attached to your XAUUSD chart (it remembers)
3. Make sure **Algo Trading** is enabled (green icon in toolbar)
4. The EA will automatically start working again

> 💡 **Good news:** The EA remembers its last signal time and pending order ticket even after restarts, so it picks up right where it left off.

---

## ❗ Troubleshooting Common Problems

### Problem: "WebRequest failed, code=4014"
**What it means:** MT5 is blocking the connection to your server.
**How to fix:**
1. Go to **Tools → Options → Expert Advisors**
2. Make sure ☑ **Allow WebRequest for listed URL** is checked
3. Make sure `http://127.0.0.1:8000` is in the list
4. Click OK and try again

### Problem: "WebRequest failed" or timeout
**What it means:** Your server isn't running.
**How to fix:**
1. Check if the server terminal window is still open
2. If not, restart the server (see "How to Restart Everything" above)
3. If the terminal shows an error, check if port 8000 is already in use

### Problem: "Failed to parse JSON response"
**What it means:** The server returned something unexpected.
**How to fix:**
1. Check the server terminal for error messages
2. Make sure your OpenAI API key is correct in the `.env` file
3. Make sure you have credits on your OpenAI account

### Problem: "Signal vetoed: model_unavailable"
**What it means:** ChatGPT couldn't be reached (no internet or API issue).
**How to fix:**
1. Check your internet connection
2. Verify your API key at https://platform.openai.com/api-keys
3. Check if you have credits at https://platform.openai.com/settings/organization/billing/overview
4. Check the server terminal for detailed error messages
5. The EA will **automatically retry in 15 minutes** — no manual action needed

### Problem: "REJECTED: Spread 80 > max 50"
**What it means:** The market spread is too wide right now. This is normal during news events or low-liquidity hours.
**How to fix:** Just wait — the EA will try again at the next check. Or increase `MaxSpreadPoints` in the EA settings.

### Problem: "Order FAILED: Invalid stops"
**What it means:** The entry price, stop loss, or take profit is too close to the current price for your broker.
**How to fix:**
1. This can happen when the market moves fast
2. The EA will automatically try again at the next signal refresh
3. If it keeps happening, your broker may have large minimum distance requirements

### Problem: "Using minimum lot" warning
**What it means:** Your account balance is small relative to the SL distance, so the EA is using the broker's minimum lot size (usually 0.01). Your actual risk per trade may be higher than the configured `RiskPercent`.
**How to fix:** This is actually working correctly! The EA tells you exactly how much you're risking in dollars and as a % of balance. If the risk is too high for your comfort:
1. Deposit more funds into your account
2. Or accept the higher risk — it's the smallest possible trade your broker allows

### Problem: Server terminal shows "openai.AuthenticationError"
**What it means:** Your API key is invalid or expired.
**How to fix:**
1. Go to https://platform.openai.com/api-keys
2. Create a new key
3. Open `backend\.env` in Notepad and replace the old key
4. Restart the server (Ctrl+C, then `python main.py`)

### Problem: "Backend returned HTTP 500"
**What it means:** The server received the request but crashed while processing it.
**How to fix:**
1. Check if you have **API credits** at https://platform.openai.com/settings/organization/billing/overview
2. Check the server terminal for error details (look for red text)
3. Make sure the OpenAI model `gpt-4o-2024-08-06` is available on your account
4. Try restarting the server (Ctrl+C, then `python main.py`)

### Problem: "REJECTED: R:R 1.02 < min 1.5"
**What it means:** The AI suggested a trade, but the reward-to-risk ratio wasn't good enough.
**How to fix:** This is the safety filter working correctly! The EA will request a new signal in 4 hours. If this happens frequently, you can lower `MinRR` (e.g., from 1.5 to 1.2), but a higher R:R is generally safer.

---

## ❓ Frequently Asked Questions

**Q: Does this guarantee profits?**
A: No. This is an AI-assisted trading tool, not a money-printing machine. AI can make wrong predictions. Always test on a **demo account** first, and never risk money you can't afford to lose.

**Q: How much does it cost to run?**
A: Each signal request costs about $0.01–$0.05 in OpenAI API usage. With signals every 4 hours (max 6 per day), that's roughly $0.06–$0.30 per day, or about **$2–$9 per month**. The EA only makes a request when there's no open position and no pending order, so actual costs may be even lower.

**Q: Can I run this on a VPS?**
A: Yes! Run the Python server and MT5 on the same VPS. Change `BackendURL` if they're on different machines.

**Q: Can I use this on other symbols besides XAUUSD?**
A: **No — only attach this EA to a XAUUSD (gold) chart.** The AI prompt is specifically designed to analyze gold price action. If you attach it to another symbol (e.g., EURUSD), the EA will send that symbol's data but the AI will still analyze it as gold, producing unreliable signals. To support other symbols, the backend prompt would need to be modified.

**Q: Do I need to keep my computer on 24/7?**
A: Yes, both the server and MT5 need to be running for the EA to work. A VPS is recommended for 24/7 operation.

**Q: Can I change the AI model?**
A: Yes! Edit `OPENAI_MODEL` in `backend\.env`. The file includes commented options you can switch between:

| Model | Speed | Quality | Cost per signal |
|-------|-------|---------|----------------|
| `gpt-4o-2024-08-06` | ⚡ Fast | Great | ~$0.01–$0.05 (default) |
| `gpt-5-mini` | ⚡ Fast | Very good | ~$0.02–$0.08 |
| `gpt-5` | 🐢 Slower | Best | ~$0.05–$0.15 |

To switch: open `backend\.env`, comment out the current model line with `#`, and uncomment the one you want. Then restart the server.

**Q: Is my API key safe?**
A: Yes. The key is stored only on your computer in the `.env` file. It's never sent to MT5 or anywhere else. The `.gitignore` file ensures it won't be uploaded to GitHub.

---

## 📁 Project File Structure

```
goldmind-ai/
├── backend/                        ← The Python server
│   ├── main.py                     ← Server code (you don't need to edit this)
│   ├── requirements.txt            ← List of Python packages needed
│   ├── .env.example                ← Template for API key
│   └── .env                        ← YOUR actual API key (don't share this!)
├── mt5/                            ← MetaTrader 5 files
│   ├── Include/
│   │   └── JASONNode.mqh           ← JSON parser (copy to MQL5\Include\)
│   └── Experts/
│       └── GoldMind_AI.mq5         ← The EA (copy to MQL5\Experts\)
├── .gitignore                      ← Prevents .env from being uploaded
└── README.md                       ← This file you're reading
```

---

## ⚠️ Important Warnings

- **Always test on a demo account first** before using real money
- **Past performance does not guarantee future results** — AI predictions can be wrong
- **Keep your API key secret** — treat it like a password
- **Monitor your trades** — don't just set and forget, especially in the beginning
- **Market conditions matter** — the AI works best in trending/breakout conditions, not during choppy/ranging markets

---

*Built with ❤️ by Syarief Azman using FastAPI, OpenAI Structured Outputs, and MQL5*

*For support, contact: [t.me/syariefazman](https://t.me/syariefazman)*
