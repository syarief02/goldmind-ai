//+------------------------------------------------------------------+
//|                                             GoldMind_AI.mq5      |
//|                        AI-Powered Breakout Signal EA              |
//|                        Calls FastAPI backend for signals          |
//+------------------------------------------------------------------+
#property copyright   "GoldMind AI"
#property link        ""
#property version     "1.00"
#property description "GoldMind AI — AI-powered breakout signals for XAUUSD via FastAPI + OpenAI."
#property strict

//--- Include our JSON parser
#include <JASONNode.mqh>

//--- Include CTrade for order management
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — User configurable                              |
//+------------------------------------------------------------------+
input string   InpBackendURL       = "http://127.0.0.1:8000/signal";  // Backend URL (POST /signal)
input int      InpMaxSpreadPoints  = 50;       // Max spread (points) to allow trading
input double   InpRiskPercent      = 1.0;      // Risk % of account balance per trade
input double   InpMinRR            = 1.5;      // Minimum reward-to-risk ratio
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // Chart timeframe for candles
input int      InpCandleCount      = 200;      // Number of candles to send to backend
input int      InpRefreshHours     = 4;        // Signal refresh interval (hours)
input long     InpMagicNumber      = 20250226; // EA magic number
input int      InpTimeout          = 10000;    // WebRequest timeout ms

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES (in-memory state)                                |
//+------------------------------------------------------------------+
CTrade         trade;                 // Trade helper
datetime       g_lastSignalTime = 0;  // When last signal was requested
ulong          g_pendingTicket  = 0;  // Current pending order ticket
string         GV_PREFIX        = "GoldMind_"; // GlobalVariable prefix

//+------------------------------------------------------------------+
//| LICENSE EXPIRATION — Change the date below to extend the license  |
//| Format: D'YYYY.MM.DD HH:MM:SS'                                   |
//+------------------------------------------------------------------+
datetime       LICENSE_EXPIRY = D'2026.03.31 23:59:59';   // <── EDIT THIS DATE TO EXTEND

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   //=== LICENSE CHECK ===
   datetime now = TimeCurrent();
   if(now >= LICENSE_EXPIRY)
   {
      MessageBox(
         "GoldMind AI license has expired.\n\n"
         "Please contact Syarief Azman on Telegram\n"
         "for authorization and a new license:\n\n"
         "https://t.me/syariefazman",
         "GoldMind AI — License Expired",
         MB_OK | MB_ICONWARNING
      );
      Print("!!! GoldMind AI LICENSE EXPIRED on ", TimeToString(LICENSE_EXPIRY));
      Print("!!! Contact Syarief Azman: https://t.me/syariefazman");
      return(INIT_FAILED);
   }
   Print("License valid until: ", TimeToString(LICENSE_EXPIRY));

   //--- Set timer to fire every 60 seconds
   EventSetTimer(60);

   //--- Set magic number for CTrade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Restore state from GlobalVariables
   string gvTicket = GV_PREFIX + "Ticket";
   string gvTime   = GV_PREFIX + "SignalTime";

   if(GlobalVariableCheck(gvTicket))
      g_pendingTicket = (ulong)GlobalVariableGet(gvTicket);

   if(GlobalVariableCheck(gvTime))
      g_lastSignalTime = (datetime)(long)GlobalVariableGet(gvTime);

   Print("=== GoldMind AI initialized ===");
   Print("Backend URL: ", InpBackendURL);
   Print("Restored ticket: ", g_pendingTicket, "  Last signal: ", TimeToString(g_lastSignalTime));

   //--- Immediately check on first load
   OnTimer();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveState();
   Print("=== GoldMind AI removed ===");
}

//+------------------------------------------------------------------+
//| Save state to GlobalVariables                                     |
//+------------------------------------------------------------------+
void SaveState()
{
   GlobalVariableSet(GV_PREFIX + "Ticket",     (double)g_pendingTicket);
   GlobalVariableSet(GV_PREFIX + "SignalTime",  (double)(long)g_lastSignalTime);
}

//+------------------------------------------------------------------+
//| Timer function — runs every 60 seconds                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Check if we already have an open position (our magic)
   if(HasOpenPosition())
   {
      //--- We have a filled position, nothing to do
      return;
   }

   //--- Check if we have a pending order
   bool hasPending = HasPendingOrder();
   datetime now = TimeCurrent();

   //--- Calculate seconds since last signal
   long elapsed = (long)(now - g_lastSignalTime);
   long refreshSec = InpRefreshHours * 3600;

   //--- Case 1: We have a pending order but it's time to refresh
   if(hasPending && elapsed >= refreshSec)
   {
      Print(">>> 4-hour refresh: cancelling pending order #", g_pendingTicket);
      CancelPendingOrder();
      RequestAndPlace();
      return;
   }

   //--- Case 2: No pending order and no position → request new signal
   if(!hasPending)
   {
      Print(">>> No pending order found, requesting new signal...");
      RequestAndPlace();
      return;
   }

   //--- Case 3: Pending order exists and within refresh window — wait
}

//+------------------------------------------------------------------+
//| Check if we have an open position for this symbol + magic         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if we have a pending order for this symbol + magic          |
//+------------------------------------------------------------------+
bool HasPendingOrder()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         g_pendingTicket = ticket;
         return true;
      }
   }
   g_pendingTicket = 0;
   return false;
}

//+------------------------------------------------------------------+
//| Cancel the current pending order                                  |
//+------------------------------------------------------------------+
void CancelPendingOrder()
{
   if(g_pendingTicket > 0)
   {
      if(trade.OrderDelete(g_pendingTicket))
      {
         Print("Pending order #", g_pendingTicket, " cancelled.");
         g_pendingTicket = 0;
      }
      else
      {
         Print("ERROR cancelling order #", g_pendingTicket, " code=", GetLastError());
      }
   }
   SaveState();
}

//+------------------------------------------------------------------+
//| Build JSON request body with candle data                          |
//+------------------------------------------------------------------+
string BuildRequestJSON()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   //--- Get candle data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpTimeframe, 0, InpCandleCount, rates);
   if(copied <= 0)
   {
      Print("ERROR: CopyRates failed, copied=", copied);
      return "";
   }

   //--- Compute ATR(14) ourselves
   double atr = ComputeATR(rates, copied, 14);

   //--- Build candles JSON array
   string candles = "";
   // Reverse so oldest is first (server expects chronological)
   for(int i = copied - 1; i >= 0; i--)
   {
      if(candles != "") candles += ",";
      candles += "{";
      candles += "\"time\":\"" + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\",";
      candles += "\"open\":" + DoubleToString(rates[i].open, digits) + ",";
      candles += "\"high\":" + DoubleToString(rates[i].high, digits) + ",";
      candles += "\"low\":" + DoubleToString(rates[i].low, digits) + ",";
      candles += "\"close\":" + DoubleToString(rates[i].close, digits) + ",";
      candles += "\"volume\":" + IntegerToString(rates[i].tick_volume);
      candles += "}";
   }

   //--- Build timeframe string
   string tfStr = TimeframeToString(InpTimeframe);

   //--- Build full JSON
   string json = "{";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"timeframe\":\"" + tfStr + "\",";
   json += "\"server_time_utc\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\",";
   json += "\"bid\":" + DoubleToString(bid, digits) + ",";
   json += "\"ask\":" + DoubleToString(ask, digits) + ",";
   json += "\"spread_points\":" + IntegerToString(spread) + ",";
   json += "\"digits\":" + IntegerToString(digits) + ",";
   json += "\"point\":" + DoubleToString(point, digits + 2) + ",";
   json += "\"candles\":[" + candles + "],";
   json += "\"atr\":" + DoubleToString(atr, digits + 2) + ",";
   json += "\"constraints\":{";
   json += "\"max_spread_points\":" + IntegerToString(InpMaxSpreadPoints) + ",";
   json += "\"risk_percent\":" + DoubleToString(InpRiskPercent, 2) + ",";
   json += "\"min_rr\":" + DoubleToString(InpMinRR, 2) + ",";
   json += "\"expiry_minutes\":" + IntegerToString(InpRefreshHours * 60);
   json += "}";
   json += "}";

   return json;
}

//+------------------------------------------------------------------+
//| Compute ATR from rates array                                      |
//+------------------------------------------------------------------+
double ComputeATR(MqlRates &rates[], int count, int period)
{
   if(count < 2) return 0;
   double sum = 0;
   int n = 0;
   // rates[] is in descending order (index 0 = newest)
   for(int i = 0; i < MathMin(period, count - 1); i++)
   {
      double high      = rates[i].high;
      double low       = rates[i].low;
      double prevClose = rates[i + 1].close;
      double tr = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
      sum += tr;
      n++;
   }
   return (n > 0) ? sum / n : 0;
}

//+------------------------------------------------------------------+
//| Convert ENUM_TIMEFRAMES to string for backend                     |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "M15";
   }
}

//+------------------------------------------------------------------+
//| Request signal from backend and place order                       |
//+------------------------------------------------------------------+
void RequestAndPlace()
{
   //--- Build request body
   string requestBody = BuildRequestJSON();
   if(requestBody == "")
   {
      Print("ERROR: Failed to build request JSON");
      return;
   }

   Print("Sending signal request to: ", InpBackendURL);

   //--- Prepare WebRequest
   char   postData[];
   char   result[];
   string resultHeaders;

   StringToCharArray(requestBody, postData, 0, WHOLE_ARRAY, CP_UTF8);
   // Remove the trailing null byte that StringToCharArray adds
   ArrayResize(postData, ArraySize(postData) - 1);

   string headers = "Content-Type: application/json\r\n";

   //--- Send WebRequest
   ResetLastError();
   int httpCode = WebRequest(
      "POST",
      InpBackendURL,
      headers,
      InpTimeout,
      postData,
      result,
      resultHeaders
   );

   if(httpCode == -1)
   {
      int err = GetLastError();
      Print("ERROR: WebRequest failed, code=", err);
      if(err == 4014)
         Print(">>> You must add '", InpBackendURL, "' to Tools -> Options -> Expert Advisors -> Allow WebRequest.");
      return;
   }

   //--- Decode response
   string responseStr = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   Print("HTTP ", httpCode, " Response: ", StringSubstr(responseStr, 0, 500));

   if(httpCode != 200)
   {
      Print("ERROR: Backend returned HTTP ", httpCode);
      return;
   }

   //--- Parse JSON
   JASONNode json;
   if(!json.Deserialize(responseStr))
   {
      Print("ERROR: Failed to parse JSON response");
      return;
   }

   //--- Extract signal fields
   bool   veto       = json.GetBoolByKey("veto");
   string vetoReason = json.GetStringByKey("veto_reason");
   string bias       = json.GetStringByKey("bias");
   double confidence = json.GetDoubleByKey("confidence");

   Print("Signal: bias=", bias, " confidence=", confidence, " veto=", veto);

   //--- Check veto
   if(veto)
   {
      Print(">>> Signal vetoed: ", vetoReason);
      g_lastSignalTime = TimeCurrent();
      SaveState();
      return;
   }

   //--- Get order details
   JASONNode *orderNode = json.FindKey("order");
   if(orderNode == NULL)
   {
      Print("ERROR: No 'order' object in response");
      return;
   }

   string orderType    = orderNode.GetStringByKey("type");
   double entry        = orderNode.GetDoubleByKey("entry");
   double sl           = orderNode.GetDoubleByKey("sl");
   double tp           = orderNode.GetDoubleByKey("tp");
   int    expiryMin    = orderNode.GetIntByKey("expiry_minutes");
   string comment      = orderNode.GetStringByKey("comment");

   Print("Order: type=", orderType, " entry=", entry, " SL=", sl, " TP=", tp, " comment=", comment);

   //--- If order type is "none", nothing to place
   if(orderType == "none")
   {
      Print(">>> No order to place (type=none)");
      g_lastSignalTime = TimeCurrent();
      SaveState();
      return;
   }

   //--- Apply safety filters and place order
   if(PlaceOrder(orderType, entry, sl, tp, expiryMin, comment))
   {
      g_lastSignalTime = TimeCurrent();
      SaveState();
   }
}

//+------------------------------------------------------------------+
//| Apply all safety filters and place the pending order              |
//+------------------------------------------------------------------+
bool PlaceOrder(string orderType, double entry, double sl, double tp, int expiryMin, string comment)
{
   //--- Get current market info
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   //=== SAFETY FILTER 1: Spread check ===
   if(spread > InpMaxSpreadPoints)
   {
      Print(">>> REJECTED: Spread ", spread, " > max ", InpMaxSpreadPoints);
      return false;
   }

   //=== SAFETY FILTER 2: Stop level and freeze level ===
   int stopLevel   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist  = MathMax(stopLevel, freezeLevel) * point;

   //=== SAFETY FILTER 3: Validate entry vs current price ===
   if(orderType == "buy_stop")
   {
      double minEntry = ask + minDist;
      if(entry <= ask)
      {
         Print(">>> REJECTED: buy_stop entry ", entry, " must be above Ask ", ask);
         return false;
      }
      if(entry < minEntry)
      {
         Print(">>> ADJUSTING: buy_stop entry from ", entry, " to ", minEntry, " (stop level)");
         entry = NormalizeDouble(minEntry + point, digits);
      }
   }
   else if(orderType == "sell_stop")
   {
      double maxEntry = bid - minDist;
      if(entry >= bid)
      {
         Print(">>> REJECTED: sell_stop entry ", entry, " must be below Bid ", bid);
         return false;
      }
      if(entry > maxEntry)
      {
         Print(">>> ADJUSTING: sell_stop entry from ", entry, " to ", maxEntry, " (stop level)");
         entry = NormalizeDouble(maxEntry - point, digits);
      }
   }
   else
   {
      Print(">>> REJECTED: Unknown order type '", orderType, "'");
      return false;
   }

   //=== SAFETY FILTER 4: SL/TP minimum distance ===
   double slDist = MathAbs(entry - sl);
   double tpDist = MathAbs(tp - entry);

   if(slDist < minDist)
   {
      Print(">>> REJECTED: SL distance ", slDist, " < min distance ", minDist);
      return false;
   }
   if(tpDist < minDist)
   {
      Print(">>> REJECTED: TP distance ", tpDist, " < min distance ", minDist);
      return false;
   }

   //=== SAFETY FILTER 5: Validate SL direction ===
   if(orderType == "buy_stop" && sl >= entry)
   {
      Print(">>> REJECTED: buy_stop SL ", sl, " must be below entry ", entry);
      return false;
   }
   if(orderType == "sell_stop" && sl <= entry)
   {
      Print(">>> REJECTED: sell_stop SL ", sl, " must be above entry ", entry);
      return false;
   }

   //=== SAFETY FILTER 6: R:R check ===
   double rr = (slDist > 0) ? tpDist / slDist : 0;
   if(rr < InpMinRR)
   {
      Print(">>> REJECTED: R:R ", DoubleToString(rr, 2), " < min ", DoubleToString(InpMinRR, 2));
      return false;
   }

   //=== Calculate lot size based on risk ===
   double lots = CalculateLotSize(entry, sl);
   if(lots <= 0)
   {
      Print(">>> REJECTED: Calculated lot size <= 0");
      return false;
   }

   //=== Normalize prices ===
   entry = NormalizeDouble(entry, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   //=== Calculate expiration time ===
   datetime expiration = 0;
   int expirationMode = (int)SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
   if((expirationMode & SYMBOL_EXPIRATION_SPECIFIED) != 0)
   {
      expiration = TimeCurrent() + expiryMin * 60;
   }
   else
   {
      Print("Broker does not support specified expiration; will cancel manually at refresh.");
   }

   //=== Place the order ===
   Print(">>> Placing ", orderType, " entry=", entry, " SL=", sl, " TP=", tp, " lots=", lots);

   bool success = false;
   if(orderType == "buy_stop")
   {
      ENUM_ORDER_TYPE_TIME typeTime = (expiration > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
      success = trade.BuyStop(lots, entry, _Symbol, sl, tp, typeTime, expiration, comment);
   }
   else if(orderType == "sell_stop")
   {
      ENUM_ORDER_TYPE_TIME typeTime = (expiration > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
      success = trade.SellStop(lots, entry, _Symbol, sl, tp, typeTime, expiration, comment);
   }

   if(success)
   {
      g_pendingTicket = trade.ResultOrder();
      Print(">>> Order placed successfully! Ticket #", g_pendingTicket);
      return true;
   }
   else
   {
      Print(">>> Order FAILED: ", trade.ResultRetcodeDescription());
      Print("    Retcode=", trade.ResultRetcode());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size from risk % and SL distance                    |
//+------------------------------------------------------------------+
// Uses ACCOUNT BALANCE for risk calculation.
// Formula: lots = risk_amount / (sl_distance_in_points * tick_value)
// Where risk_amount = balance * risk_percent / 100
//+------------------------------------------------------------------+
double CalculateLotSize(double entry, double sl)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt   = balance * InpRiskPercent / 100.0;

   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // SL distance in price
   double slDist = MathAbs(entry - sl);
   if(slDist <= 0 || tickSize <= 0 || tickValue <= 0)
   {
      Print("ERROR calculating lots: slDist=", slDist, " tickSize=", tickSize, " tickValue=", tickValue);
      return 0;
   }

   // How many ticks in the SL distance
   double slTicks = slDist / tickSize;

   // Monetary risk per 1 lot for this SL distance
   double riskPerLot = slTicks * tickValue;

   if(riskPerLot <= 0)
   {
      Print("ERROR: riskPerLot=", riskPerLot);
      return 0;
   }

   // Raw lots
   double lots = riskAmt / riskPerLot;

   // Round DOWN to nearest lot step
   lots = MathFloor(lots / lotStep) * lotStep;

   // Clamp to broker limits
   lots = MathMax(lots, lotMin);
   lots = MathMin(lots, lotMax);

   // Normalize
   lots = NormalizeDouble(lots, 2);

   Print("Risk calc: balance=", balance, " risk$=", riskAmt, " slDist=", slDist,
         " slTicks=", slTicks, " riskPerLot=", riskPerLot, " lots=", lots);

   return lots;
}

//+------------------------------------------------------------------+
//| Expert tick function (not used, timer-based)                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // We use OnTimer() instead of OnTick() for periodic checks.
   // OnTick is left empty intentionally.
}
//+------------------------------------------------------------------+
