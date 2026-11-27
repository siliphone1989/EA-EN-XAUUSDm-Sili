//+------------------------------------------------------------------+
//|                                          Tomahawk_PRO_EA.mq5     |
//|  EA version of the Pine indicator "Tomahawk PRO Sys FINAL"       |
//|  Platform : MetaTrader 5 (hedging or netting - see notes)        |
//|  Symbol   : XAUUSDm (any gold symbol)                            |
//|                                                                  |
//|  Signals  : M15 / H1 / H4 EMA(14/21/50/75/100) stack + RSI zone, |
//|             GSR (Gold/Silver ratio) bias,                        |
//|             MEGA big-volume candle.                              |
//|  Exits    : SL = ATR(H1) x mult, TP1/TP2/TP3 = H4 Fib expansion  |
//|             1.272 / 1.618 / 2.0 (3 split positions),             |
//|             GSR flip exit, optional BE / trailing.               |
//|  NOTE     : a netting account merges the 3 legs into 1 position, |
//|             so use a HEDGING account (Exness "m" accounts are).  |
//+------------------------------------------------------------------+
#property copyright "siliphone"
#property version   "1.00"
#property description "Tomahawk PRO Sys FINAL -> Expert Advisor (auto trading + dashboard)"
#property strict

#include <Trade/Trade.mqh>

//==================================================================
//  INPUTS
//==================================================================
enum ENUM_LOTMODE { LOT_FIXED = 0, LOT_RISK = 1 };

input group "=== General ==="
input long             InpMagic            = 20261120;      // Magic number
input string           InpComment          = "TMH";         // Order comment prefix
input ENUM_TIMEFRAMES  InpSignalTF         = PERIOD_M15;    // Signal TF (M15)
input bool             InpClosedBar        = true;          // Use CLOSED bar signal (false = realtime/forming bar)
input int              InpMaxSpreadPts     = 400;           // Max spread (points; XAUUSDm has 3 digits: 400 pts = $0.40)
input int              InpDeviation        = 30;            // Max slippage (points)
input int              InpCooldownSec      = 60;            // Cooldown after opening a setup (sec)
input bool             InpStartPaused      = false;         // Start in PAUSE mode
input bool             InpTestOrderNow     = false;         // TEST: open ONE order right now (needs SIMPLE MODE), then turn off
input bool             InpTestBuy          = true;          // TEST order side: true = BUY, false = SELL
input bool             InpLevelMode        = false;         // TEST ONLY: enter whenever signal is ON (chases the move!). false = like TradingView labels

input group "=== SIMPLE MODE (easy: 1 order, fixed SL/TP) ==="
input bool             InpSimpleMode       = true;          // true = open ONE order per signal, fixed SL/TP, no extra filters
input double           InpSimpleLot        = 0.01;          // Lot per order
input double           InpSimpleSL         = 8.0;           // SL distance in PRICE units (USD), e.g. 8.0 = $8
input double           InpSimpleTP         = 12.0;          // TP distance in PRICE units (USD), e.g. 12.0 = $12

input group "=== Which signals open orders ==="
input bool             InpTradeM15         = true;          // Trade BUY/SELL (M15)
input bool             InpTradeH1          = false;         // Trade ACTION BUY/SELL (H1)
input bool             InpTradeH4          = false;         // Trade ACTION BUY/SELL (H4)
input bool             InpTradeFollow      = true;          // Trade F-BUY / F-SELL (follow trend, M15)
input bool             InpTradeMega        = true;          // Trade MEGA BUY/SELL (Big Volume, safe-exit mode)
input bool             InpRequireFib       = false;         // Require valid H4 Fib TP (false = fallback RR TP like latest Pine)

input group "=== EMA / RSI ==="
input double           InpEmaSpreadMaxPct  = 3.0;           // Compression % (EMA14-EMA100 / close)
input int              InpRsiLen           = 14;            // RSI length
input double           InpBuyLow           = 23.0;          // RSI BUY zone low
input double           InpBuyHigh          = 30.0;          // RSI BUY zone high
input double           InpSellLow          = 70.0;          // RSI SELL zone low
input double           InpSellHigh         = 85.0;          // RSI SELL zone high
input double           InpFollowBuyLow     = 30.0;          // Follow BUY RSI low
input double           InpFollowBuyHigh    = 50.0;          // Follow BUY RSI high
input double           InpFollowSellLow    = 60.0;          // Follow SELL RSI low
input double           InpFollowSellHigh   = 75.0;          // Follow SELL RSI high

input group "=== GSR (Gold/Silver ratio) ==="
input bool             InpUseGSR           = true;          // Use GSR filter
input string           InpSilverSymbol     = "XAGUSDm";     // Silver symbol (same suffix as gold)
input bool             InpGsrPineMode      = true;          // true = same as TradingView Pine: compare with value N CHART bars ago
input ENUM_TIMEFRAMES  InpGsrChartTF       = PERIOD_H1;     // Chart timeframe you watch in TradingView (Pine mode)
input int              InpGsrLookback      = 10;            // GSR %change lookback (Pine mode: chart bars; else D1 bars)
input double           InpGsrUpPct         = 0.6;           // GSR UP >= %  => SELL bias
input double           InpGsrDnPct         = 0.6;           // GSR DOWN <= % => BUY bias
input bool             InpExitOnGsrFlip    = true;          // Close all when GSR flips against position
input bool             InpBlockEntryOnFlip = true;          // Don't enter if GSR flip would exit immediately

input group "=== SL / TP ==="
input ENUM_TIMEFRAMES  InpAtrTF            = PERIOD_H1;     // ATR timeframe
input int              InpAtrLen           = 14;            // ATR length
input double           InpSlAtrMult        = 2.0;           // SL = ATR x
input int              InpFibPivotLen      = 6;             // H4 pivot length (swing)
input double           InpFibLevelA        = 0.618;         // Fibo retest zone A
input double           InpFibLevelB        = 0.786;         // Fibo retest zone B
input bool             InpShowFibZone      = true;          // Draw H4 retest zone on chart
input double           InpTp1QtyPct        = 33;            // TP1 qty %
input double           InpTp2QtyPct        = 33;            // TP2 qty %
input double           InpTp3QtyPct        = 34;            // TP3 qty %
input double           InpFallbackRR       = 2.0;           // Fib invalid: TP1 = RR x SL (TP2=2x, TP3=3x of that)

input group "=== MEGA (Big Volume) ==="
input int              InpVolMALen         = 20;            // Volume MA length
input double           InpVolSpikeMult     = 2.5;           // Volume spike x
input double           InpVolBodyMinPct    = 55.0;          // Min body % of range
input bool             InpVolReqTrend      = true;          // Require EMA trend alignment (M15)
input double           InpMegaSlBufAtr     = 0.25;          // SL buffer beyond MEGA candle extreme (ATR x)
input double           InpMegaMinSlAtr     = 0.6;           // Min SL distance (ATR x)
input double           InpMegaMaxSlAtr     = 2.0;           // Max SL distance (ATR x) - wider => SKIP trade
input double           InpMegaMaxChaseAtr  = 0.5;           // Skip if price already ran > ATR x from candle close
input double           InpMegaTp1R         = 1.0;           // TP1 = R x SL
input double           InpMegaTp2R         = 2.0;           // TP2 = R x SL
input double           InpMegaTp3R         = 4.0;           // TP3 (runner) = R x SL
input double           InpMegaQty1         = 40;            // TP1 qty %
input double           InpMegaQty2         = 30;            // TP2 qty %
input double           InpMegaQty3         = 30;            // TP3 qty % (runner, trailed)
input double           InpMegaTrailAtr     = 1.0;           // Trail distance after TP1 (ATR x)
input int              InpMegaTimeStopMin  = 45;            // Close all if TP1 not reached within N minutes (0=off)
input double           InpMegaRiskPct      = 1.0;           // Risk % per MEGA setup (LOT_RISK mode)

input group "=== Lot size ==="
input ENUM_LOTMODE     InpLotMode          = LOT_FIXED;     // Lot mode
input double           InpFixedLot         = 0.03;          // Fixed TOTAL lot per setup (split into 3 legs)
input double           InpRiskPct          = 2.0;           // Risk % of equity per setup (LOT_RISK)

input group "=== Risk control / BE / Trailing (latest Pine) ==="
input double           InpBeAtR            = 1.0;           // Move SL to BE (then trail) when profit >= R x initial SL (0 = off, 1.0 = at 1R)
input bool             InpBEOnTP1          = true;          // Move SL to BE after TP1
input int              InpBeOffsetPts      = 20;            // BE offset (points, covers spread)
input bool             InpUseTrailing      = true;          // Use trailing SL
input bool             InpTrailOnTP1       = true;          // Start trailing after TP1
input double           InpTrailAtrMult     = 1.5;           // Trail = ATR x
input double           InpMaxRiskCapPct    = 10.0;          // Skip trade if SL loss > this % of equity (0=off)
input double           InpMaxDailyLossPct  = 5.0;           // Stop opening new trades if today's loss >= this % of balance (0=off)

input group "=== Dashboard ==="
input bool             InpShowDash         = true;          // Show dashboard
input int              InpPanelX           = 10;            // Panel X
input int              InpPanelY           = 20;            // Panel Y
input int              InpLogRows          = 20;            // Signal iteration rows (<=20)
input int              InpLogEverySec      = 5;             // Log every N sec
input string           InpFont             = "Consolas";    // Font

//==================================================================
//  CONSTANTS / TYPES
//==================================================================
#define PFX "TMHD_"
#define SRC_M15  0
#define SRC_H1   1
#define SRC_H4   2
#define SRC_MEGA 3
#define SRC_FOLLOW 4
#define R_OPENED 0
#define R_FINAL  1   // rejected - do not retry this signal
#define R_RETRY  2   // blocked temporarily (spread, pause...) - retry next second

struct TFH
  {
   ENUM_TIMEFRAMES tf;
   int             e14, e21, e50, e75, e100, rsi;
  };

struct TrendState
  {
   bool   valid, bull, bear, bullOK, bearOK;
   double rsi, spread, e14, e21, e50, e75, e100;
  };

struct Ctx
  {
   bool   gsrOK, gsrUp, gsrDown;
   double gsr, gsrChg;
  };

struct Sig
  {
   bool buy, sell;
  };

struct FibData
  {
   bool     ok;
   int      dir;          // 1 upswing, -1 downswing
   double   hi, lo, e1272, e1618, e2000, zTop, zBot;
   datetime tFrom;
  };

struct LogRow
  {
   int    n;
   string t;
   double bid;
   int    sprd;
   string sig;
   double conf, bull, bear, rsi, emaSp, atr, vol;
   int    pos;
   string act;
  };

//==================================================================
//  GLOBALS
//==================================================================
CTrade   g_trade;
TFH      g_h[3];                 // M15(signal), H1, H4
int      g_atrH = INVALID_HANDLE;
string   g_silver = "";
bool     g_gsrOn = false;

bool     g_paused = false;
bool     g_minimized = false;
ulong    g_lastProcMs = 0;
datetime g_lastTrig[5][2];       // [src][0=buy,1=sell] bar time already handled
datetime g_lastOpenTime = 0;
string   g_lastAction = "-";
string   g_lastResult = "-";
int      g_setupSrc = -1, g_setupLegs = 0;
bool     g_tp1Done = false;
bool     g_testDone = false;
double   g_riskDist = 0;          // initial SL distance of current setup (1R)
double   g_tp1Price = 0;
bool     g_folBuy = false, g_folSell = false;

// live snapshot for dashboard
TrendState g_ts[3];
Sig        g_now[3];
Sig        g_prev[3];
Ctx        g_ctx;
bool       g_bigBuy = false, g_bigSell = false;
double     g_volRatio = 0.0;
double     g_atr = 0.0;
FibData    g_fib;
datetime   g_fibBar = 0;
ulong      g_fibTry = 0;
double     g_sBull[5], g_sBear[5];
double     g_totBull = 0, g_totBear = 0;
string     g_sigText = "HOLD";
double     g_conf = 0;

// stats
int    g_stClosed = 0, g_stWin = 0, g_stLoss = 0, g_stBE = 0;
double g_stNet = 0, g_stGP = 0, g_stGL = 0, g_stBest = 0, g_stWorst = 0;
ulong  g_lastStatMs = 0;

// log
LogRow   g_log[20];
int      g_logCnt = 0, g_iter = 0;
datetime g_lastLogT = 0;

//==================================================================
//  HELPERS
//==================================================================
double Buf(const int h, const int shift)
  {
   if(h == INVALID_HANDLE)
      return EMPTY_VALUE;
   double a[1];
   if(CopyBuffer(h, 0, shift, 1, a) != 1)
      return EMPTY_VALUE;
   return a[0];
  }

int VolDigits()
  {
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0)
      return 2;
   return (int)MathMax(0, MathCeil(-MathLog10(st) - 1e-9));
  }

string Age(const datetime t)
  {
   int s = (int)(TimeCurrent() - t);
   if(s < 0)
      s = 0;
   return StringFormat("%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60);
  }

int CountPos()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
         c++;
     }
   return c;
  }

bool PosIsLong()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
         return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
     }
   return true;
  }

void CloseAll(const string why)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(g_trade.PositionClose(tk))
         n++;
     }
   if(n > 0)
     {
      g_lastAction = "CLOSE ALL: " + why;
      PrintFormat("Tomahawk: closed %d position(s) - %s", n, why);
     }
  }

//==================================================================
//  INDICATOR DATA
//==================================================================
bool InitTF(TFH &h, const ENUM_TIMEFRAMES tf)
  {
   h.tf   = tf;
   h.e14  = iMA(_Symbol, tf, 14,  0, MODE_EMA, PRICE_CLOSE);
   h.e21  = iMA(_Symbol, tf, 21,  0, MODE_EMA, PRICE_CLOSE);
   h.e50  = iMA(_Symbol, tf, 50,  0, MODE_EMA, PRICE_CLOSE);
   h.e75  = iMA(_Symbol, tf, 75,  0, MODE_EMA, PRICE_CLOSE);
   h.e100 = iMA(_Symbol, tf, 100, 0, MODE_EMA, PRICE_CLOSE);
   h.rsi  = iRSI(_Symbol, tf, InpRsiLen, PRICE_CLOSE);
   return(h.e14 != INVALID_HANDLE && h.e21 != INVALID_HANDLE && h.e50 != INVALID_HANDLE &&
          h.e75 != INVALID_HANDLE && h.e100 != INVALID_HANDLE && h.rsi != INVALID_HANDLE);
  }

void ReleaseTF(TFH &h)
  {
   int a[6];
   a[0] = h.e14; a[1] = h.e21; a[2] = h.e50; a[3] = h.e75; a[4] = h.e100; a[5] = h.rsi;
   for(int i = 0; i < 6; i++)
      if(a[i] != INVALID_HANDLE)
         IndicatorRelease(a[i]);
  }

bool Trend(const TFH &h, const int shift, TrendState &t)
  {
   t.valid = false; t.bull = false; t.bear = false; t.bullOK = false; t.bearOK = false;
   t.rsi = 0; t.spread = 0;
   t.e14 = Buf(h.e14, shift);   t.e21 = Buf(h.e21, shift);   t.e50 = Buf(h.e50, shift);
   t.e75 = Buf(h.e75, shift);   t.e100 = Buf(h.e100, shift); t.rsi = Buf(h.rsi, shift);
   if(t.e14 == EMPTY_VALUE || t.e21 == EMPTY_VALUE || t.e50 == EMPTY_VALUE ||
      t.e75 == EMPTY_VALUE || t.e100 == EMPTY_VALUE || t.rsi == EMPTY_VALUE)
      return false;
   double c = iClose(_Symbol, h.tf, shift);
   if(c <= 0)
      return false;
   t.bull   = (t.e14 > t.e21 && t.e21 > t.e50 && t.e50 > t.e75 && t.e75 > t.e100);
   t.bear   = (t.e14 < t.e21 && t.e21 < t.e50 && t.e50 < t.e75 && t.e75 < t.e100);
   t.spread = MathAbs(t.e14 - t.e100) / c * 100.0;
   t.bullOK = t.bull && t.spread <= InpEmaSpreadMaxPct;
   t.bearOK = t.bear && t.spread <= InpEmaSpreadMaxPct;
   t.valid  = true;
   return true;
  }

//--- GSR context at a given time (slow context, D1 based)
void GetCtx(const datetime tm, Ctx &c)
  {
   c.gsrOK = false; c.gsrUp = false; c.gsrDown = false;
   c.gsr = 0; c.gsrChg = 0;

   // ---- GSR (D1)
   if(g_gsrOn)
     {
      int i0 = iBarShift(_Symbol, PERIOD_D1, tm, false);
      if(i0 >= 0)
        {
         int i1 = i0 + InpGsrLookback;
         if(InpGsrPineMode)   // Pine: gsr[N] = daily-ratio value N bars of the chart TF ago
           {
            datetime tPrev = tm - (datetime)((long)InpGsrLookback * PeriodSeconds(InpGsrChartTF));
            i1 = iBarShift(_Symbol, PERIOD_D1, tPrev, false);
            if(i1 < 0)
               i1 = i0;
           }
         datetime t0 = iTime(_Symbol, PERIOD_D1, i0);
         datetime t1 = iTime(_Symbol, PERIOD_D1, i1);
         int s0 = iBarShift(g_silver, PERIOD_D1, t0, false);
         int s1 = iBarShift(g_silver, PERIOD_D1, t1, false);
         double g0 = iClose(_Symbol, PERIOD_D1, i0), g1 = iClose(_Symbol, PERIOD_D1, i1);
         double v0 = (s0 >= 0) ? iClose(g_silver, PERIOD_D1, s0) : 0;
         double v1 = (s1 >= 0) ? iClose(g_silver, PERIOD_D1, s1) : 0;
         if(g0 > 0 && g1 > 0 && v0 > 0 && v1 > 0 && t1 > 0)
           {
            double r0 = g0 / v0, r1 = g1 / v1;
            c.gsr    = r0;
            c.gsrChg = (r0 - r1) / r1 * 100.0;
            c.gsrUp  = c.gsrChg >=  InpGsrUpPct;
            c.gsrDown = c.gsrChg <= -InpGsrDnPct;
            c.gsrOK  = true;
           }
        }
     }
  }

//--- BUY/SELL state of one timeframe at a shift (same logic as Pine buyNow / sellNow)
bool State(const TFH &h, const int shift, Sig &s, TrendState &t, Ctx &c)
  {
   s.buy = false; s.sell = false;
   if(!Trend(h, shift, t))
      return false;
   datetime tm = iTime(_Symbol, h.tf, shift);
   GetCtx(tm, c);
   bool buyCore  = t.bullOK && t.rsi >= InpBuyLow  && t.rsi <= InpBuyHigh;
   bool sellCore = t.bearOK && t.rsi >= InpSellLow && t.rsi <= InpSellHigh;
   bool gsrBuy   = c.gsrOK && c.gsrDown && t.bullOK;
   bool gsrSell  = c.gsrOK && c.gsrUp   && t.bearOK;
   s.buy  = buyCore  || gsrBuy;
   s.sell = sellCore || gsrSell;
   return true;
  }

//--- Big volume candle on the chart TF
void BigVol(const int shift, const bool bullOK, const bool bearOK, bool &bigBuy, bool &bigSell, double &ratio)
  {
   bigBuy = false; bigSell = false; ratio = 0;
   long v[];
   ArraySetAsSeries(v, true);
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, shift, InpVolMALen, v) < InpVolMALen)
      return;
   double sum = 0;
   for(int i = 0; i < InpVolMALen; i++)
      sum += (double)v[i];
   double ma = sum / InpVolMALen;
   ratio = ma > 0 ? (double)v[0] / ma : 0.0;
   bool spike = (double)v[0] >= ma * InpVolSpikeMult;
   double o = iOpen(_Symbol, PERIOD_CURRENT, shift), c = iClose(_Symbol, PERIOD_CURRENT, shift);
   double hh = iHigh(_Symbol, PERIOD_CURRENT, shift), ll = iLow(_Symbol, PERIOD_CURRENT, shift);
   double rng = hh - ll, body = MathAbs(c - o);
   double bodyPct = rng > 0 ? body / rng * 100.0 : 0.0;
   bool strong = bodyPct >= InpVolBodyMinPct;
   bigBuy  = spike && strong && c > o && (!InpVolReqTrend || bullOK);
   bigSell = spike && strong && c < o && (!InpVolReqTrend || bearOK);
  }

//--- H4 pivots -> Fib retest zone + Fib expansion targets
void CalcFib()
  {
   datetime bt = iTime(_Symbol, PERIOD_H4, 0);
   ulong now = GetTickCount64();
   if(g_fib.ok && bt == g_fibBar)
      return;
   if(!g_fib.ok && now - g_fibTry < 10000)
      return;
   g_fibTry = now;

   int L = InpFibPivotLen;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, PERIOD_H4, 0, 600, r);
   g_fib.ok = false;
   if(n < 2 * L + 5)
      return;

   bool fh = false, fl = false;
   double hi = 0, lo = 0;
   datetime hit = 0, lot = 0;
   for(int k = L + 1; k < n - L && !(fh && fl); k++)
     {
      if(!fh)
        {
         bool p = true;
         for(int j = 1; j <= L; j++)
            if(r[k].high < r[k - j].high || r[k].high < r[k + j].high)
              {
               p = false;
               break;
              }
         if(p)
           {
            fh = true;
            hi = r[k].high;
            hit = r[k].time;
           }
        }
      if(!fl)
        {
         bool p = true;
         for(int j = 1; j <= L; j++)
            if(r[k].low > r[k - j].low || r[k].low > r[k + j].low)
              {
               p = false;
               break;
              }
         if(p)
           {
            fl = true;
            lo = r[k].low;
            lot = r[k].time;
           }
        }
     }
   if(!(fh && fl) || hi == lo)
      return;

   double rng = hi - lo;
   bool lastWasHigh = hit > lot;
   double a = MathMin(InpFibLevelA, InpFibLevelB), b = MathMax(InpFibLevelA, InpFibLevelB);
   g_fib.hi = hi;
   g_fib.lo = lo;
   g_fib.dir = lastWasHigh ? 1 : -1;
   if(lastWasHigh)
     {
      g_fib.zBot  = lo + rng * a;
      g_fib.zTop  = lo + rng * b;
      g_fib.e1272 = hi + rng * 0.272;
      g_fib.e1618 = hi + rng * 0.618;
      g_fib.e2000 = hi + rng * 1.0;
     }
   else
     {
      g_fib.zTop  = hi - rng * a;
      g_fib.zBot  = hi - rng * b;
      g_fib.e1272 = lo - rng * 0.272;
      g_fib.e1618 = lo - rng * 0.618;
      g_fib.e2000 = lo - rng * 1.0;
     }
   g_fib.tFrom = (hit < lot) ? hit : lot;
   g_fib.ok = true;
   g_fibBar = bt;

   // chart zone
   string nm = PFX + "FIBZONE";
   if(InpShowFibZone)
     {
      if(ObjectFind(0, nm) < 0)
         ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_fib.tFrom, g_fib.zTop, TimeCurrent() + 86400 * 30, g_fib.zBot);
      ObjectSetInteger(0, nm, OBJPROP_TIME, 0, g_fib.tFrom);
      ObjectSetDouble(0, nm, OBJPROP_PRICE, 0, g_fib.zTop);
      ObjectSetInteger(0, nm, OBJPROP_TIME, 1, TimeCurrent() + 86400 * 30);
      ObjectSetDouble(0, nm, OBJPROP_PRICE, 1, g_fib.zBot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, nm, OBJPROP_FILL, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
     }
   else
      ObjectDelete(0, nm);
  }

bool FibValid(const bool isLong, const double entry)
  {
   if(!g_fib.ok)
      return false;
   return isLong ? (g_fib.dir == 1 && g_fib.e1272 > entry)
          : (g_fib.dir == -1 && g_fib.e1272 < entry);
  }

//==================================================================
//  EVALUATE ALL SIGNALS (state for dashboard)
//==================================================================
bool LevelOn()
  {
   return InpLevelMode;   // default: enter only on the FIRST bar of a signal (same as Pine BUY/SELL labels)
  }

void Evaluate(bool &trig[][2])
  {
   int s = InpClosedBar ? 1 : 0;
   Ctx c;
   TrendState tmp;
   Ctx ctmp;
   for(int i = 0; i < 3; i++)
     {
      Sig cur, prv;
      TrendState t;
      Ctx cx;
      bool ok1 = State(g_h[i], s, cur, t, cx);
      bool ok2 = State(g_h[i], s + 1, prv, tmp, ctmp);
      g_ts[i]   = t;
      g_now[i]  = cur;
      g_prev[i] = prv;
      trig[i][0] = ok1 && cur.buy  && (LevelOn() || (ok2 && !prv.buy));
      trig[i][1] = ok1 && cur.sell && (LevelOn() || (ok2 && !prv.sell));
      if(i == 0)
         g_ctx = cx;
     }

   // live context (for GSR flip exit + dashboard)
   GetCtx(TimeCurrent(), c);
   g_ctx = c;

   // MEGA big volume (chart TF); trend alignment taken from signal TF
   double ratio;
   bool b0, s0, b1, s1;
   double r1;
   TrendState tv0, tv1;
   datetime tm0 = iTime(_Symbol, PERIOD_CURRENT, s);
   datetime tm1 = iTime(_Symbol, PERIOD_CURRENT, s + 1);
   int i0 = iBarShift(_Symbol, g_h[0].tf, tm0, false);
   int i1 = iBarShift(_Symbol, g_h[0].tf, tm1, false);
   Trend(g_h[0], MathMax(i0, 0), tv0);
   Trend(g_h[0], MathMax(i1, 0), tv1);
   BigVol(s,     tv0.bullOK, tv0.bearOK, b0, s0, ratio);
   BigVol(s + 1, tv1.bullOK, tv1.bearOK, b1, s1, r1);
   g_bigBuy = b0;
   g_bigSell = s0;
   g_volRatio = ratio;
   trig[3][0] = b0 && (LevelOn() || !b1);
   trig[3][1] = s0 && (LevelOn() || !s1);

   // Follow BUY / SELL (M15)
   TrendState tp15;
   bool pv = Trend(g_h[0], s + 1, tp15);
   bool fb0 = g_ts[0].valid && g_ts[0].bullOK && g_ts[0].rsi >= InpFollowBuyLow  && g_ts[0].rsi <= InpFollowBuyHigh;
   bool fs0 = g_ts[0].valid && g_ts[0].bearOK && g_ts[0].rsi >= InpFollowSellLow && g_ts[0].rsi <= InpFollowSellHigh;
   bool fb1 = pv && tp15.bullOK && tp15.rsi >= InpFollowBuyLow  && tp15.rsi <= InpFollowBuyHigh;
   bool fs1 = pv && tp15.bearOK && tp15.rsi >= InpFollowSellLow && tp15.rsi <= InpFollowSellHigh;
   g_folBuy = fb0;
   g_folSell = fs0;
   trig[4][0] = fb0 && (LevelOn() || !fb1);
   trig[4][1] = fs0 && (LevelOn() || !fs1);

   // ATR
   double a = Buf(g_atrH, 1);
   if(a != EMPTY_VALUE && a > 0)
      g_atr = a;

   CalcFib();

   // ---- dashboard score (informational) ----
   double w[5] = {0.30, 0.30, 0.20, 0.10, 0.10};   // Trend, RSI zone, GSR, Volume, Fib TP
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool fL = FibValid(true, ask), fS = FibValid(false, bid);
   TrendState m = g_ts[0];
   ArrayInitialize(g_sBull, 0);
   ArrayInitialize(g_sBear, 0);
   if(m.valid)
     {
      if(m.bullOK) g_sBull[0] = w[0];
      if(m.bearOK) g_sBear[0] = w[0];
      if(m.rsi >= InpBuyLow && m.rsi <= InpBuyHigh)   g_sBull[1] = w[1];
      if(m.rsi >= InpSellLow && m.rsi <= InpSellHigh) g_sBear[1] = w[1];
     }
   if(g_ctx.gsrOK && g_ctx.gsrDown)    g_sBull[2] = w[2];
   if(g_ctx.gsrOK && g_ctx.gsrUp)      g_sBear[2] = w[2];
   if(g_bigBuy)  g_sBull[3] = w[3];
   if(g_bigSell) g_sBear[3] = w[3];
   if(fL) g_sBull[4] = w[4];
   if(fS) g_sBear[4] = w[4];
   g_totBull = 0;
   g_totBear = 0;
   for(int i = 0; i < 5; i++)
     {
      g_totBull += g_sBull[i];
      g_totBear += g_sBear[i];
     }
   g_conf = MathMax(g_totBull, g_totBear);
   g_sigText = "HOLD";
   if(g_now[0].buy && fL)
      g_sigText = "BUY";
   else
      if(g_now[0].sell && fS)
         g_sigText = "SELL";
      else
         if(g_folBuy)
            g_sigText = "F-BUY";
         else
            if(g_folSell)
               g_sigText = "F-SELL";
  }

//==================================================================
//  ORDER EXECUTION
//==================================================================
double LossPerLot(const double slDist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0)
      return 0;
   return slDist / ts * tv;
  }

double CalcTotalLot(const double slDist, const double riskPct)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot  = InpFixedLot;
   if(InpLotMode == LOT_RISK)
     {
      double lpl = LossPerLot(slDist);
      lot = (lpl > 0) ? AccountInfoDouble(ACCOUNT_EQUITY) * riskPct / 100.0 / lpl : minL;
     }
   if(st > 0)
      lot = MathFloor(lot / st + 1e-9) * st;
   lot = MathMax(minL, MathMin(maxL, lot));
   return NormalizeDouble(lot, VolDigits());
  }

//--- split total lot into 3 legs, merge legs smaller than min lot into the next one
void SplitLots(const double total, double &v[], const double p1, const double p2, const double p3)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double st   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int vd = VolDigits();
   double pc = p1 + p2 + p3;
   if(pc <= 0)
      pc = 100;
   v[0] = MathFloor(total * (p1 / pc) / st + 1e-9) * st;
   v[1] = MathFloor(total * (p2 / pc) / st + 1e-9) * st;
   v[2] = NormalizeDouble(total - v[0] - v[1], vd);
   double carry = 0;
   for(int i = 0; i < 3; i++)
     {
      double x = NormalizeDouble(v[i] + carry, vd);
      if(x < minL - 1e-9)
        {
         carry = x;
         v[i] = 0;
        }
      else
        {
         v[i] = x;
         carry = 0;
        }
     }
   if(carry > 0)
     {
      int last = -1;
      for(int i = 2; i >= 0; i--)
         if(v[i] > 0)
           {
            last = i;
            break;
           }
      if(last < 0)
         v[0] = MathMax(minL, carry);
      else
         v[last] = NormalizeDouble(v[last] + carry, vd);
     }
  }

double MinStopDist()
  {
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double frz   = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double sp    = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   return MathMax(MathMax(stops, frz), sp) + 2 * _Point;
  }

//--- SIMPLE MODE: one market order, fixed SL/TP in price units, no extra filters
int OpenSimple(const bool isLong, const string tag)
  {
   string side = isLong ? "BUY" : "SELL";
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double entry = isLong ? ask : bid;
   double minD = MinStopDist();
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double slD = MathMax(InpSimpleSL, minD), tpD = MathMax(InpSimpleTP, minD);
   double sl = NormalizeDouble(isLong ? entry - slD : entry + slD, dg);
   double tp = NormalizeDouble(isLong ? entry + tpD : entry - tpD, dg);

   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vol = InpSimpleLot;
   if(st > 0)
      vol = MathFloor(vol / st + 1e-9) * st;
   vol = NormalizeDouble(MathMax(minL, MathMin(maxL, vol)), VolDigits());

   double mg = 0;
   if(OrderCalcMargin(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, vol, entry, mg) && mg > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      g_lastAction = "skip " + side + " " + tag + ": no margin";
      return R_FINAL;
     }
   string cm = StringFormat("%s-%s", InpComment, tag);
   bool ok = isLong ? g_trade.Buy(vol, _Symbol, 0, sl, tp, cm) : g_trade.Sell(vol, _Symbol, 0, sl, tp, cm);
   if(ok)
     {
      g_lastOpenTime = TimeCurrent();
      g_setupSrc = -1;
      g_setupLegs = 1;
      g_tp1Done = false;
      g_tp1Price = 0;
      g_riskDist = 0;
      g_lastAction = StringFormat("%s %s %.2f lot OK", side, tag, vol);
      Print("Tomahawk SIMPLE: ", g_lastAction, " entry=", DoubleToString(entry, dg), " SL=", DoubleToString(sl, dg), " TP=", DoubleToString(tp, dg));
      return R_OPENED;
     }
   g_lastAction = StringFormat("order failed %s %s (%d)", side, tag, g_trade.ResultRetcode());
   Print("Tomahawk SIMPLE: order failed retcode=", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   return R_RETRY;
  }

int OpenSetup(const bool isLong, const int src)
  {
   string tag = (src == SRC_M15) ? "M15" : (src == SRC_H1) ? "H1" : (src == SRC_H4) ? "H4" : (src == SRC_FOLLOW) ? "FOL" : "MEGA";
   string side = isLong ? "BUY" : "SELL";
   bool mega = (src == SRC_MEGA);

   if(g_paused)
      return R_RETRY;
   if(CountPos() > 0)
     {
      g_lastAction = "skip " + side + " " + tag + ": in trade";
      return R_FINAL;
     }
   if(TimeCurrent() - g_lastOpenTime < InpCooldownSec)
      return R_RETRY;
   if(InpMaxDailyLossPct > 0 && g_stNet <= -AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxDailyLossPct / 100.0)
     {
      g_lastAction = "STOP: daily loss limit";
      return R_FINAL;
     }
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(sp > InpMaxSpreadPts)
     {
      g_lastAction = StringFormat("wait: spread %d>%d", (int)sp, InpMaxSpreadPts);
      return R_RETRY;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_lastAction = "AutoTrading OFF";
      return R_RETRY;
     }
   if(InpSimpleMode)
      return OpenSimple(isLong, tag);
   if(InpBlockEntryOnFlip && InpExitOnGsrFlip && !mega && g_ctx.gsrOK &&
      ((isLong && g_ctx.gsrUp) || (!isLong && g_ctx.gsrDown)))
     {
      g_lastAction = "skip " + side + " " + tag + ": GSR flip";
      return R_FINAL;
     }
   if(g_atr <= 0)
     {
      g_lastAction = "wait: ATR not ready";
      return R_RETRY;
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double entry = isLong ? ask : bid;
   double minD = MinStopDist();
   int    dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slDist = 0;
   double tp[3] = {0, 0, 0};
   double pc1 = InpTp1QtyPct, pc2 = InpTp2QtyPct, pc3 = InpTp3QtyPct;
   double riskPct = InpRiskPct;

   if(mega)
     {
      //--- SAFE MEGA exit plan: SL behind the MEGA candle, 3 targets in R, BE + trail after TP1, time stop
      int sh = InpClosedBar ? 1 : 0;
      double cl = iClose(_Symbol, PERIOD_CURRENT, sh);
      if(MathAbs(entry - cl) > g_atr * InpMegaMaxChaseAtr)
        {
         g_lastAction = "skip " + side + " MEGA: chased";
         return R_FINAL;
        }
      double ex = isLong ? iLow(_Symbol, PERIOD_CURRENT, sh) - g_atr * InpMegaSlBufAtr
                  : iHigh(_Symbol, PERIOD_CURRENT, sh) + g_atr * InpMegaSlBufAtr;
      double d = MathAbs(entry - ex);
      if(d > g_atr * InpMegaMaxSlAtr)
        {
         g_lastAction = "skip " + side + " MEGA: SL too wide";
         return R_FINAL;
        }
      slDist = MathMax(d, g_atr * InpMegaMinSlAtr);
      tp[0] = isLong ? entry + slDist * InpMegaTp1R : entry - slDist * InpMegaTp1R;
      tp[1] = isLong ? entry + slDist * InpMegaTp2R : entry - slDist * InpMegaTp2R;
      tp[2] = isLong ? entry + slDist * InpMegaTp3R : entry - slDist * InpMegaTp3R;
      pc1 = InpMegaQty1;
      pc2 = InpMegaQty2;
      pc3 = InpMegaQty3;
      riskPct = InpMegaRiskPct;
     }
   else
     {
      slDist = g_atr * InpSlAtrMult;
      if(FibValid(isLong, entry))
        {
         tp[0] = g_fib.e1272;
         tp[1] = g_fib.e1618;
         tp[2] = g_fib.e2000;
        }
      else
        {
         if(InpRequireFib)
           {
            g_lastAction = "skip " + side + " " + tag + ": no Fib TP";
            return R_FINAL;
           }
         double rr = MathMax(slDist, minD) * InpFallbackRR;
         for(int i = 0; i < 3; i++)
            tp[i] = isLong ? entry + rr * (i + 1) : entry - rr * (i + 1);
        }
     }
   if(slDist < minD)
      slDist = minD;
   double sl = isLong ? entry - slDist : entry + slDist;

   for(int i = 0; i < 3; i++)   // keep TPs beyond broker stop level
     {
      if(isLong && tp[i] < entry + minD)
         tp[i] = entry + minD;
      if(!isLong && tp[i] > entry - minD)
         tp[i] = entry - minD;
     }

   double total = CalcTotalLot(slDist, riskPct);
   double lpl = LossPerLot(slDist);
   if(InpMaxRiskCapPct > 0 && lpl > 0 && total * lpl > AccountInfoDouble(ACCOUNT_EQUITY) * InpMaxRiskCapPct / 100.0)
     {
      g_lastAction = StringFormat("skip %s %s: risk %.2f too high", side, tag, total * lpl);
      return R_FINAL;
     }
   double vol[3] = {0, 0, 0};
   SplitLots(total, vol, pc1, pc2, pc3);
   int nLegs = 0, firstLeg = -1;
   for(int i = 0; i < 3; i++)
      if(vol[i] > 0)
        {
         nLegs++;
         if(firstLeg < 0)
            firstLeg = i;
        }
   if(nLegs == 1)
      tp[firstLeg] = tp[2];   // single leg: aim at the far target, BE/trail starts when TP1 level is reached

   double need = 0, mg = 0;
   for(int i = 0; i < 3; i++)
      if(vol[i] > 0 && OrderCalcMargin(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, vol[i], entry, mg))
         need += mg;
   if(need > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      g_lastAction = "skip " + side + " " + tag + ": no margin";
      return R_FINAL;
     }

   sl = NormalizeDouble(sl, dg);
   int opened = 0;
   for(int i = 0; i < 3; i++)
     {
      if(vol[i] <= 0)
         continue;
      string cm = StringFormat("%s-%s-TP%d", InpComment, tag, i + 1);
      double tpx = NormalizeDouble(tp[i], dg);
      bool ok = isLong ? g_trade.Buy(vol[i], _Symbol, 0, sl, tpx, cm)
                : g_trade.Sell(vol[i], _Symbol, 0, sl, tpx, cm);
      if(ok)
         opened++;
      else
         PrintFormat("Tomahawk: order failed (%s %s leg %d) retcode=%d %s", side, tag, i + 1,
                     g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
     }
   if(opened > 0)
     {
      g_lastOpenTime = TimeCurrent();
      g_setupSrc = src;
      g_setupLegs = opened;
      g_tp1Done = false;
      g_tp1Price = tp[0];
      g_riskDist = slDist;
      g_lastAction = StringFormat("%s %s x%d legs", side, tag, opened);
      Print("Tomahawk: ", g_lastAction, " | entry=", DoubleToString(entry, dg), " SL=", DoubleToString(sl, dg),
            " TP1=", DoubleToString(tp[0], dg), " TP2=", DoubleToString(tp[1], dg), " TP3=", DoubleToString(tp[2], dg),
            " lots=", DoubleToString(vol[0], 2), "/", DoubleToString(vol[1], 2), "/", DoubleToString(vol[2], 2),
            " risk=", DoubleToString(total * lpl, 2));
      return R_OPENED;
     }
   g_lastAction = "order failed " + side + " " + tag;
   return R_RETRY;
  }

//==================================================================
//  POSITION MANAGEMENT (GSR flip, TP1 -> BE + trailing, MEGA time stop)
//==================================================================
double FirstOpenPrice()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
         return PositionGetDouble(POSITION_PRICE_OPEN);
     }
   return 0;
  }

void ManagePositions()
  {
   int n = CountPos();
   if(n == 0)
     {
      g_tp1Done = false;
      return;
     }
   bool isLong = PosIsLong();

   if(InpExitOnGsrFlip && !InpSimpleMode && g_ctx.gsrOK && ((isLong && g_ctx.gsrUp) || (!isLong && g_ctx.gsrDown)))
     {
      CloseAll("GSR flip");
      return;
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(!g_tp1Done)
     {
      bool reached = (g_tp1Price > 0) && (isLong ? bid >= g_tp1Price : ask <= g_tp1Price);
      if(reached || (g_setupLegs > 1 && n < g_setupLegs))
        {
         g_tp1Done = true;
         g_lastAction = "TP1 hit -> BE + trail";
        }
     }
   // BE + trailing trigger at 1R (R = initial SL distance)
   if(!g_tp1Done && InpBeAtR > 0 && g_riskDist > 0)
     {
      double op0 = FirstOpenPrice();
      double prof0 = isLong ? bid - op0 : op0 - ask;
      if(op0 > 0 && prof0 >= g_riskDist * InpBeAtR)
        {
         g_tp1Done = true;
         g_lastAction = StringFormat("%.1fR reached -> BE + trail", InpBeAtR);
        }
     }
   if(g_setupSrc == SRC_MEGA && !g_tp1Done && InpMegaTimeStopMin > 0 &&
      TimeCurrent() - g_lastOpenTime >= (long)InpMegaTimeStopMin * 60)
     {
      CloseAll("MEGA time stop");
      return;
     }

   bool doTrail = InpUseTrailing && InpTrailOnTP1;
   if(!g_tp1Done || g_atr <= 0 || (!InpBEOnTP1 && !doTrail))
      return;
   double tm = (g_setupSrc == SRC_MEGA) ? InpMegaTrailAtr : InpTrailAtrMult;
   double minD = MinStopDist();
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      bool lg = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tpv = PositionGetDouble(POSITION_TP);
      double px = lg ? bid : ask;
      double nsl = sl;
      if(InpBEOnTP1)
        {
         double be = lg ? op + InpBeOffsetPts * _Point : op - InpBeOffsetPts * _Point;
         if(sl == 0 || (lg && be > nsl) || (!lg && be < nsl))
            nsl = be;
        }
      if(doTrail)
        {
         double t = lg ? px - g_atr * tm : px + g_atr * tm;
         if(nsl == 0 || (lg && t > nsl) || (!lg && t < nsl))
            nsl = t;
        }
      nsl = NormalizeDouble(nsl, dg);
      if(MathAbs(nsl - sl) < _Point)
         continue;
      if(MathAbs(px - nsl) < minD)
         continue;
      if((lg && nsl >= px) || (!lg && nsl <= px))
         continue;
      g_trade.PositionModify(tk, nsl, tpv);
     }
  }

//==================================================================
//  STATS (today)
//==================================================================
void CalcToday()
  {
   ulong now = GetTickCount64();
   if(now - g_lastStatMs < 4000)
      return;
   g_lastStatMs = now;
   g_stClosed = 0; g_stWin = 0; g_stLoss = 0; g_stBE = 0;
   g_stNet = 0; g_stGP = 0; g_stGL = 0; g_stBest = 0; g_stWorst = 0;
   datetime d0 = iTime(_Symbol, PERIOD_D1, 0);
   if(!HistorySelect(d0, TimeCurrent() + 60))
      return;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0)
         continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic || HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol)
         continue;
      long en = HistoryDealGetInteger(tk, DEAL_ENTRY);
      if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_OUT_BY && en != DEAL_ENTRY_INOUT)
         continue;
      double p = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_COMMISSION) + HistoryDealGetDouble(tk, DEAL_SWAP);
      g_stClosed++;
      g_stNet += p;
      if(p > 0.005)
        {
         g_stWin++;
         g_stGP += p;
        }
      else
         if(p < -0.005)
           {
            g_stLoss++;
            g_stGL += -p;
           }
         else
            g_stBE++;
      if(p > g_stBest)
         g_stBest = p;
      if(p < g_stWorst)
         g_stWorst = p;
      g_lastResult = StringFormat("%s%.2f", p >= 0 ? "+$" : "-$", MathAbs(p));
     }
  }

//==================================================================
//  DASHBOARD
//==================================================================
color CBG  = C'10,16,28';
color CCARD = C'16,24,40';
color CBRD = C'34,46,68';
color CTTL = C'70,150,225';
color CLBL = C'150,160,178';
color CVAL = clrWhite;
color CGRN = C'60,205,120';
color CRED = C'240,85,85';
color CORG = C'240,170,60';
color CTRK = C'36,44,60';

void Rect(const string id, const int x, const int y, const int w, const int h, const color bg, const color bd)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, bd);
  }

void Lbl(const string id, const int x, const int y, const string txt, const color c,
         const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER, const int fs = 9, const bool bold = false)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, n, OBJPROP_FONT, bold ? InpFont + " Bold" : InpFont);
   ObjectSetString(0, n, OBJPROP_TEXT, StringLen(txt) == 0 ? " " : txt);   // empty text would show "Label"
  }

void Btn(const string id, const int x, const int y, const int w, const int h, const string txt, const color bg, const color fg)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, n, OBJPROP_FONT, InpFont);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
  }

//--- one "label ........ value" line
void Row(const string id, const int x, const int y, const int w, const string lab, const string val, const color vc = clrWhite)
  {
   Lbl(id + "L", x + 10, y, lab, CLBL);
   Lbl(id + "V", x + w - 10, y, val, vc, ANCHOR_RIGHT_UPPER);
  }

void Card(const string id, const int x, const int y, const int w, const int h, const string title)
  {
   Rect(id, x, y, w, h, CCARD, CBRD);
   Lbl(id + "T", x + 10, y + 6, title, CTTL, ANCHOR_LEFT_UPPER, 10, true);
  }

string F(const double v, const int d)
  {
   return DoubleToString(v, d);
  }

string Money(const double v)
  {
   return (v >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(v), 2);
  }

color PL(const double v)
  {
   return v > 0 ? CGRN : (v < 0 ? CRED : CVAL);
  }

string SideTxt(const Sig &s)
  {
   return s.buy ? "BUY" : (s.sell ? "SELL" : "WAIT");
  }

color SideCol(const Sig &s)
  {
   return s.buy ? CGRN : (s.sell ? CRED : CLBL);
  }

void PushLog()
  {
   datetime now = TimeCurrent();
   if(now - g_lastLogT < InpLogEverySec)
      return;
   g_lastLogT = now;
   g_iter++;
   for(int i = 19; i > 0; i--)
      g_log[i] = g_log[i - 1];
   g_log[0].n = g_iter;
   g_log[0].t = TimeToString(now, TIME_SECONDS);
   g_log[0].bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_log[0].sprd = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   g_log[0].sig = g_sigText;
   g_log[0].conf = g_conf;
   g_log[0].bull = g_totBull;
   g_log[0].bear = g_totBear;
   g_log[0].rsi = g_ts[0].rsi;
   g_log[0].emaSp = g_ts[0].spread;
   g_log[0].atr = g_atr;
   g_log[0].vol = g_volRatio;
   g_log[0].pos = CountPos();
   g_log[0].act = g_lastAction;
   if(g_logCnt < 20)
      g_logCnt++;
  }

void DrawDash()
  {
   if(!InpShowDash)
      return;
   const int pad = 8, W = 920, LH = 18;
   int X = InpPanelX, Y = InpPanelY;
   int cw = (W - 4 * pad) / 3;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int sprd = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   // ---------------- header ----------------
   Rect("BG", X, Y, W, g_minimized ? 38 : 940, CBG, CBRD);
   Lbl("H_T", X + 14, Y + 9, "TOMAHAWK PRO EA", CORG, ANCHOR_LEFT_UPPER, 12, true);
   Lbl("H_S", X + 230, Y + 12, StringFormat("%s %s | Iter #%d | %s", _Symbol, StringSubstr(EnumToString(Period()), 7), g_iter,
                                           TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)), CLBL);
   Lbl("H_L", X + W - 330, Y + 11, g_paused ? "PAUSED" : "LIVE", g_paused ? CRED : CGRN, ANCHOR_RIGHT_UPPER, 10, true);
   Btn("BTN_PAUSE", X + W - 320, Y + 6, 100, 26, g_paused ? "RESUME" : "PAUSE", C'130,100,30', clrWhite);
   Btn("BTN_CLOSE", X + W - 212, Y + 6, 110, 26, "CLOSE ALL", C'150,40,45', clrWhite);
   Btn("BTN_MIN", X + W - 92, Y + 6, 34, 26, g_minimized ? "+" : "-", C'30,40,60', clrWhite);
   if(g_minimized)
      return;

   // ---------------- row 1 ----------------
   int y1 = Y + 44, ch = 176;
   int x1 = X + pad, x2 = X + 2 * pad + cw, x3 = X + 3 * pad + 2 * cw;

   // ACCOUNT
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double fl = AccountInfoDouble(ACCOUNT_PROFIT), fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   Card("C1", x1, y1, cw, ch, "ACCOUNT  (" + cur + ")");
   Row("A1", x1, y1 + 30, cw, "Balance", F(bal, 2));
   Row("A2", x1, y1 + 30 + LH, cw, "Equity", F(eq, 2));
   Row("A3", x1, y1 + 30 + 2 * LH, cw, "Floating P/L", Money(fl), PL(fl));
   Row("A4", x1, y1 + 30 + 3 * LH, cw, "Free margin", F(fm, 2));
   Row("A5", x1, y1 + 30 + 4 * LH, cw, "Margin level", ml > 0 ? F(ml, 1) + "%" : "-");
   Row("A6", x1, y1 + 30 + 5 * LH, cw, "Today net", Money(g_stNet + fl), PL(g_stNet + fl));
   Row("A7", x1, y1 + 30 + 6 * LH, cw, "Lot total / mode", InpLotMode == LOT_FIXED ? F(InpFixedLot, 2) + " fixed" : F(InpRiskPct, 1) + "% risk");

   // MARKET
   Card("C2", x2, y1, cw, ch, "MARKET");
   Row("M1", x2, y1 + 30, cw, "Symbol / TF", _Symbol + " / " + StringSubstr(EnumToString(Period()), 7));
   Row("M2", x2, y1 + 30 + LH, cw, "Bid", F(bid, dg), CRED);
   Row("M3", x2, y1 + 30 + 2 * LH, cw, "Ask", F(ask, dg), CGRN);
   Row("M4", x2, y1 + 30 + 3 * LH, cw, "Spread (pts)", StringFormat("%d / max %d", sprd, InpMaxSpreadPts), sprd > InpMaxSpreadPts ? CRED : CGRN);
   Row("M5", x2, y1 + 30 + 4 * LH, cw, "ATR (H1)", g_atr > 0 ? F(g_atr, 3) : "-");
   string gb = !g_ctx.gsrOK ? "-" : (g_ctx.gsrUp ? "SELL BIAS" : (g_ctx.gsrDown ? "BUY BIAS" : "NEUTRAL"));
   Row("M7", x2, y1 + 30 + 5 * LH, cw, "GSR %chg / bias", g_ctx.gsrOK ? StringFormat("%s%% %s", F(g_ctx.gsrChg, 2), gb) : (g_gsrOn ? "-" : "off"),
       g_ctx.gsrUp ? CRED : (g_ctx.gsrDown ? CGRN : CVAL));
   string fz = !g_fib.ok ? "-" : (g_fib.dir == 1 ? "UPSWING" : "DOWNSWING");
   Row("M8", x2, y1 + 30 + 6 * LH, cw, "H4 swing / Fib TP", fz + (FibValid(g_fib.dir == 1, g_fib.dir == 1 ? ask : bid) ? " / VALID" : " / --"),
       FibValid(g_fib.dir == 1, g_fib.dir == 1 ? ask : bid) ? CGRN : CLBL);

   // SIGNAL
   Card("C3", x3, y1, cw, ch, "SIGNAL");
   color sc = g_sigText == "BUY" ? CGRN : (g_sigText == "SELL" ? CRED : (StringFind(g_sigText, "F-") == 0 ? C'90,150,255' : C'130,140,155'));
   Lbl("S_BIG", x3 + 10, y1 + 26, g_sigText, sc, ANCHOR_LEFT_UPPER, 20, true);
   Lbl("S_CF", x3 + cw - 10, y1 + 32, "conf " + F(g_conf, 2), CLBL, ANCHOR_RIGHT_UPPER, 10);
   int bx = x3 + 52, bwid = cw - 52 - 56;
   Lbl("S_BL", x3 + 10, y1 + 66, "BULL", CLBL);
   Rect("S_BT", bx, y1 + 69, bwid, 10, CTRK, CTRK);
   Rect("S_BF", bx, y1 + 69, (int)MathMax(1, bwid * g_totBull), 10, CGRN, CGRN);
   Lbl("S_BV", x3 + cw - 10, y1 + 66, F(g_totBull, 2), CGRN, ANCHOR_RIGHT_UPPER);
   Lbl("S_RL", x3 + 10, y1 + 66 + LH, "BEAR", CLBL);
   Rect("S_RT", bx, y1 + 69 + LH, bwid, 10, CTRK, CTRK);
   Rect("S_RF", bx, y1 + 69 + LH, (int)MathMax(1, bwid * g_totBear), 10, CRED, CRED);
   Lbl("S_RV", x3 + cw - 10, y1 + 66 + LH, F(g_totBear, 2), CRED, ANCHOR_RIGHT_UPPER);
   Lbl("S_M15", x3 + 10, y1 + 106, "M15", CLBL);
   Lbl("S_M15v", x3 + 52, y1 + 106, SideTxt(g_now[0]), SideCol(g_now[0]));
   Lbl("S_H1", x3 + 100, y1 + 106, "H1", CLBL);
   Lbl("S_H1v", x3 + 124, y1 + 106, SideTxt(g_now[1]), SideCol(g_now[1]));
   Lbl("S_H4", x3 + 190, y1 + 106, "H4", CLBL);
   Lbl("S_H4v", x3 + 214, y1 + 106, SideTxt(g_now[2]), SideCol(g_now[2]));
   Lbl("S_MG", x3 + 10, y1 + 106 + LH, "MEGA", CLBL);
   Lbl("S_MGv", x3 + 52, y1 + 106 + LH, g_bigBuy ? "BUY" : (g_bigSell ? "SELL" : "-"), g_bigBuy ? CGRN : (g_bigSell ? CRED : CLBL));
   Lbl("S_MD", x3 + 120, y1 + 106 + LH, InpClosedBar ? "mode: closed bar" : "mode: realtime", CLBL);
   Lbl("S_LA", x3 + 10, y1 + 106 + 2 * LH, "last: " + g_lastAction, CVAL);

   // ---------------- row 2 ----------------
   int y2 = y1 + ch + pad;
   TrendState m = g_ts[0];
   Card("C4", x1, y2, cw, ch, "INDICATORS (M15)");
   Row("I1", x1, y2 + 30, cw, "RSI (" + IntegerToString(InpRsiLen) + ")", m.valid ? F(m.rsi, 2) : "-");
   Row("I2", x1, y2 + 30 + LH, cw, "EMA 14 / 21", m.valid ? F(m.e14, 2) + " / " + F(m.e21, 2) : "-");
   Row("I3", x1, y2 + 30 + 2 * LH, cw, "EMA 50 / 75", m.valid ? F(m.e50, 2) + " / " + F(m.e75, 2) : "-");
   Row("I4", x1, y2 + 30 + 3 * LH, cw, "EMA 100", m.valid ? F(m.e100, 2) : "-");
   Row("I5", x1, y2 + 30 + 4 * LH, cw, "Trend", m.bull ? "BULL STACK" : (m.bear ? "BEAR STACK" : "MIXED"), m.bull ? CGRN : (m.bear ? CRED : CLBL));
   Row("I6", x1, y2 + 30 + 5 * LH, cw, "EMA spread / max", m.valid ? F(m.spread, 2) + "% / " + F(InpEmaSpreadMaxPct, 1) + "%" : "-",
       (m.valid && m.spread <= InpEmaSpreadMaxPct) ? CGRN : CRED);
   Row("I7", x1, y2 + 30 + 6 * LH, cw, "Volume ratio", F(g_volRatio, 2) + "x", g_volRatio >= InpVolSpikeMult ? CORG : CLBL);

   Card("C5", x2, y2, cw, ch, "SCORE BREAKDOWN");
   Lbl("B_H1", x2 + cw - 70, y2 + 6, "BULL", CGRN, ANCHOR_RIGHT_UPPER, 9, true);
   Lbl("B_H2", x2 + cw - 10, y2 + 6, "BEAR", CRED, ANCHOR_RIGHT_UPPER, 9, true);
   string nm[5] = {"Trend", "RSI zone", "GSR", "Volume", "Fib TP"};
   double wt[5] = {0.30, 0.30, 0.20, 0.10, 0.10};
   for(int i = 0; i < 5; i++)
     {
      int yy = y2 + 30 + i * LH;
      Lbl("B" + IntegerToString(i) + "n", x2 + 10, yy, nm[i], CLBL);
      Lbl("B" + IntegerToString(i) + "w", x2 + 100, yy, "(" + F(wt[i], 2) + ")", CLBL);
      Lbl("B" + IntegerToString(i) + "b", x2 + cw - 70, yy, F(g_sBull[i], 2), g_sBull[i] > 0 ? CGRN : CLBL, ANCHOR_RIGHT_UPPER);
      Lbl("B" + IntegerToString(i) + "r", x2 + cw - 10, yy, F(g_sBear[i], 2), g_sBear[i] > 0 ? CRED : CLBL, ANCHOR_RIGHT_UPPER);
     }
   Rect("B_LN", x2 + 10, y2 + 30 + 5 * LH + 2, cw - 20, 1, CBRD, CBRD);
   Lbl("B_TN", x2 + 10, y2 + 30 + 5 * LH + 6, "TOTAL", CVAL);
   Lbl("B_Tb", x2 + cw - 70, y2 + 30 + 5 * LH + 6, F(g_totBull, 2), CGRN, ANCHOR_RIGHT_UPPER);
   Lbl("B_Tr", x2 + cw - 10, y2 + 30 + 5 * LH + 6, F(g_totBear, 2), CRED, ANCHOR_RIGHT_UPPER);

   Card("C6", x3, y2, cw, ch, "TODAY STATS");
   double wr = g_stClosed > 0 ? 100.0 * g_stWin / g_stClosed : 0;
   Row("T1", x3, y2 + 30, cw, "Closed deals", IntegerToString(g_stClosed));
   Row("T2", x3, y2 + 30 + LH, cw, "Win / Loss / BE", StringFormat("%d / %d / %d", g_stWin, g_stLoss, g_stBE));
   Row("T3", x3, y2 + 30 + 2 * LH, cw, "Win rate", F(wr, 1) + "%");
   Row("T4", x3, y2 + 30 + 3 * LH, cw, "Net P/L", Money(g_stNet), PL(g_stNet));
   Row("T5", x3, y2 + 30 + 4 * LH, cw, "Profit factor", g_stGL > 0 ? F(g_stGP / g_stGL, 2) : (g_stGP > 0 ? "inf" : "-"));
   Row("T6", x3, y2 + 30 + 5 * LH, cw, "Best / Worst", Money(g_stBest) + " / " + Money(g_stWorst));
   long cdLeft = (long)InpCooldownSec - (TimeCurrent() - g_lastOpenTime);
   Row("T7", x3, y2 + 30 + 6 * LH, cw, "Cooldown", cdLeft > 0 ? IntegerToString((int)cdLeft) + "s" : "ready", cdLeft > 0 ? CORG : CGRN);

   // ---------------- positions ----------------
   int y3 = y2 + ch + pad;
   int ph = 30 + LH + 5 * LH + LH + 6;
   int npos = CountPos();
   Card("C7", X + pad, y3, W - 2 * pad, ph, "OPEN POSITIONS (" + IntegerToString(npos) + ")");
   int px0 = X + pad + 10;
   int cols[10] = {0, 110, 170, 235, 330, 425, 525, 620, 665, 715};
   string hd[10] = {"Ticket", "Type", "Lots", "Open", "SL", "TP", "P/L", "BE", "TL", "Age"};
   for(int c = 0; c < 10; c++)
      Lbl("PH" + IntegerToString(c), px0 + cols[c], y3 + 28, hd[c], CLBL);
   int shown = 0;
   for(int i = 0; i < PositionsTotal() && shown < 5; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      bool lg = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      bool be = sl > 0 && ((lg && sl >= op) || (!lg && sl <= op));
      double px = lg ? bid : ask;
      bool tl = InpUseTrailing && g_tp1Done;
      int yy = y3 + 28 + LH * (1 + shown);
      string r = "R" + IntegerToString(shown) + "_";
      Lbl(r + "0", px0 + cols[0], yy, IntegerToString((long)tk), CVAL);
      Lbl(r + "1", px0 + cols[1], yy, lg ? "BUY" : "SELL", lg ? CGRN : CRED);
      Lbl(r + "2", px0 + cols[2], yy, F(PositionGetDouble(POSITION_VOLUME), 2), CVAL);
      Lbl(r + "3", px0 + cols[3], yy, F(op, dg), CVAL);
      Lbl(r + "4", px0 + cols[4], yy, sl > 0 ? F(sl, dg) : "-", CVAL);
      Lbl(r + "5", px0 + cols[5], yy, tp > 0 ? F(tp, dg) : "-", CVAL);
      Lbl(r + "6", px0 + cols[6], yy, Money(pr), PL(pr));
      Lbl(r + "7", px0 + cols[7], yy, be ? "Y" : "-", be ? CGRN : CLBL);
      Lbl(r + "8", px0 + cols[8], yy, tl ? "Y" : "-", tl ? CGRN : CLBL);
      Lbl(r + "9", px0 + cols[9], yy, Age((datetime)PositionGetInteger(POSITION_TIME)), CVAL);
      shown++;
     }
   for(int k = 0; k < 5; k++)   // clear unused rows
     {
      if(k < shown)
         continue;
      string r = "R" + IntegerToString(k) + "_";
      for(int c = 0; c < 10; c++)
         Lbl(r + IntegerToString(c), px0 + cols[c], y3 + 28 + LH * (1 + k), (k == 0 && c == 0) ? "no open positions" : "", CLBL);
     }
   Lbl("P_PEND", px0, y3 + ph - LH - 4, "Pending: none", CLBL);
   Lbl("P_LR", X + W - pad - 10, y3 + ph - LH - 4, "Last result: " + g_lastResult, CLBL, ANCHOR_RIGHT_UPPER);

   // ---------------- log ----------------
   int y4 = y3 + ph + pad;
   int rows = (int)MathMin(MathMax(InpLogRows, 1), 20);
   int lh = 14;
   Card("C8", X + pad, y4, W - 2 * pad, 52 + rows * lh, "LAST " + IntegerToString(rows) + " SIGNAL ITERATIONS");
   Lbl("L_SUB", X + pad + 230, y4 + 7, "(newest first, every " + IntegerToString(InpLogEverySec) + "s)", CTTL);
   int lc[14] = {0, 36, 112, 186, 236, 306, 360, 414, 468, 522, 580, 640, 695, 740};
   string lhd[14] = {"#", "Time", "Bid", "Sprd", "Signal", "Conf", "Bull", "Bear", "RSI", "EMA%", "ATR", "Vol", "Pos", "Action"};
   for(int c = 0; c < 14; c++)
      Lbl("LH" + IntegerToString(c), px0 + lc[c], y4 + 28, lhd[c], CLBL);
   for(int i = 0; i < rows; i++)
     {
      int yy = y4 + 28 + 18 + i * lh;
      string r = "G" + IntegerToString(i) + "_";
      if(i < g_logCnt)
        {
         LogRow lr = g_log[i];
         color scol = lr.sig == "BUY" ? CGRN : (lr.sig == "SELL" ? CRED : CLBL);
         Lbl(r + "0", px0 + lc[0], yy, IntegerToString(lr.n), CLBL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "1", px0 + lc[1], yy, lr.t, CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "2", px0 + lc[2], yy, F(lr.bid, dg), CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "3", px0 + lc[3], yy, IntegerToString(lr.sprd), lr.sprd > InpMaxSpreadPts ? CRED : CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "4", px0 + lc[4], yy, lr.sig, scol, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "5", px0 + lc[5], yy, F(lr.conf, 2), CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "6", px0 + lc[6], yy, F(lr.bull, 2), CGRN, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "7", px0 + lc[7], yy, F(lr.bear, 2), CRED, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "8", px0 + lc[8], yy, F(lr.rsi, 1), CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "9", px0 + lc[9], yy, F(lr.emaSp, 2), CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "10", px0 + lc[10], yy, F(lr.atr, 2), CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "11", px0 + lc[11], yy, F(lr.vol, 2) + "x", CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "12", px0 + lc[12], yy, IntegerToString(lr.pos), CVAL, ANCHOR_LEFT_UPPER, 8);
         Lbl(r + "13", px0 + lc[13], yy, lr.act, CORG, ANCHOR_LEFT_UPPER, 8);
        }
      else
         for(int c = 0; c < 14; c++)
            Lbl(r + IntegerToString(c), px0 + lc[c], yy, "", CLBL, ANCHOR_LEFT_UPPER, 8);
     }
   Rect("BG", X, Y, W, (y4 + 52 + rows * lh + pad) - Y, CBG, CBRD);
   ChartRedraw(0);
  }

void ClearDash()
  {
   ObjectsDeleteAll(0, PFX);
  }

//==================================================================
//  MAIN LOOP
//==================================================================
void Process()
  {
   ulong now = GetTickCount64();
   if(now - g_lastProcMs < 900)
      return;
   g_lastProcMs = now;

   bool trig[5][2];
   Evaluate(trig);
   ManagePositions();

   // one-shot test order (independent of signals)
   if(InpTestOrderNow && !g_testDone && !g_paused)
     {
      int tr = OpenSetup(InpTestBuy, SRC_M15);
      if(tr != R_RETRY)
         g_testDone = true;
     }

   int srcOn[5];
   srcOn[0] = InpTradeM15 ? 1 : 0;
   srcOn[1] = InpTradeH1 ? 1 : 0;
   srcOn[2] = InpTradeH4 ? 1 : 0;
   srcOn[3] = InpTradeMega ? 1 : 0;
   srcOn[4] = InpTradeFollow ? 1 : 0;
   int s = InpClosedBar ? 1 : 0;
   for(int i = 0; i < 5; i++)
     {
      if(!srcOn[i])
         continue;
      datetime bt = (i < 3 || i == 4) ? iTime(_Symbol, g_h[i == 4 ? 0 : i].tf, s) : iTime(_Symbol, PERIOD_CURRENT, s);
      for(int d = 0; d < 2; d++)
        {
         if(!trig[i][d] || bt == g_lastTrig[i][d])
            continue;
         int r = OpenSetup(d == 0, i);
         if(r != R_RETRY)
            g_lastTrig[i][d] = bt;
        }
     }

   CalcToday();
   PushLog();
   DrawDash();
  }

int OnInit()
  {
   if(!SymbolSelect(_Symbol, true))
      Print("Tomahawk: cannot select ", _Symbol);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   bool ok = InitTF(g_h[0], InpSignalTF);
   ok = InitTF(g_h[1], PERIOD_H1) && ok;
   ok = InitTF(g_h[2], PERIOD_H4) && ok;
   g_atrH = iATR(_Symbol, InpAtrTF, InpAtrLen);
   if(!ok || g_atrH == INVALID_HANDLE)
     {
      Print("Tomahawk: indicator handle creation failed");
      return INIT_FAILED;
     }

   // optional symbols
   g_silver = InpSilverSymbol;
   g_gsrOn = (InpUseGSR && StringLen(g_silver) > 0 && SymbolSelect(g_silver, true));
   if(InpUseGSR && !g_gsrOn)
      Print("Tomahawk: silver symbol '", g_silver, "' not found -> GSR disabled. Set InpSilverSymbol (e.g. XAGUSDm).");

   g_paused = InpStartPaused;
   g_fib.ok = false;
   ArrayInitialize(g_sBull, 0);
   ArrayInitialize(g_sBear, 0);
   for(int i = 0; i < 5; i++)
      for(int d = 0; d < 2; d++)
         g_lastTrig[i][d] = 0;
   g_lastProcMs = 0;
   g_lastOpenTime = 0;
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("Tomahawk WARNING: account is NOT hedging - TP1/TP2/TP3 legs will merge into one position.");

   EventSetTimer(1);
   Print("Tomahawk PRO EA started on ", _Symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < 3; i++)
      ReleaseTF(g_h[i]);
   if(g_atrH != INVALID_HANDLE)
      IndicatorRelease(g_atrH);
   ClearDash();
   ChartRedraw(0);
  }

void OnTick()
  {
   Process();
  }

void OnTimer()
  {
   Process();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam == PFX + "BTN_PAUSE")
     {
      g_paused = !g_paused;
      g_lastAction = g_paused ? "PAUSED by user" : "RESUMED";
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      DrawDash();
     }
   else
      if(sparam == PFX + "BTN_CLOSE")
        {
         CloseAll("manual button");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         DrawDash();
        }
      else
         if(sparam == PFX + "BTN_MIN")
           {
            g_minimized = !g_minimized;
            ClearDash();
            // restore fib zone object next cycle
            g_fib.ok = false;
            g_fibTry = 0;
            DrawDash();
           }
  }
//+------------------------------------------------------------------+
