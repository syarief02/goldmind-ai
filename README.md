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
        │    data every few mins    │                          │
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

---

## ⚙️ Understanding the EA Settings

When you attach the EA, you can change these settings in the **Inputs** tab:

| Setting | Default | What It Does |
|---------|---------|-------------|
| **BackendURL** | `http://127.0.0.1:8000/signal` | Where to find your server. Only change this if your server is on another computer |
| **MaxSpreadPoints** | `50` | If the spread is wider than this, no trade will be placed. Lower = safer but fewer trades |
| **RiskPercent** | `1.0` | How much of your account to risk per trade. 1.0 = 1%. Higher = bigger trades but more risk |
| **MinRR** | `1.5` | Minimum reward-to-risk ratio. 1.5 means the target profit must be 1.5× bigger than the stop loss |
| **Timeframe** | `M15` | Which candle data to analyze. The EA pulls this timeframe's candles regardless of what chart timeframe you're viewing. M15 is recommended for XAUUSD |
| **CandleCount** | `200` | How many candles to send to ChatGPT. More = better analysis but slower |
| **RefreshHours** | `4` | How often to cancel old orders and get new signals |
| **MagicNumber** | `20250226` | A unique ID for this EA's orders. Only change if running multiple EAs |
| **Timeout** | `10000` | How long to wait for server response (milliseconds). 10000 = 10 seconds |

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
**What it means:** ChatGPT couldn't be reached.
**How to fix:**
1. Check your internet connection
2. Verify your API key at https://platform.openai.com/api-keys
3. Check if you have credits at https://platform.openai.com/settings/organization/billing/overview
4. Check the server terminal for detailed error messages

### Problem: "REJECTED: Spread 80 > max 50"
**What it means:** The market spread is too wide right now. This is normal during news events or low-liquidity hours.
**How to fix:** Just wait — the EA will try again at the next check. Or increase `MaxSpreadPoints` in the EA settings.

### Problem: "Order FAILED: Invalid stops"
**What it means:** The entry price, stop loss, or take profit is too close to the current price for your broker.
**How to fix:**
1. This can happen when the market moves fast
2. The EA will automatically try again at the next signal refresh
3. If it keeps happening, your broker may have large minimum distance requirements

### Problem: "Calculated lot size <= 0"
**What it means:** Your account balance is too low for the risk settings, or the stop loss distance is very large.
**How to fix:**
1. Increase `RiskPercent` (e.g., from 1.0 to 2.0)
2. Or deposit more funds into your account

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


