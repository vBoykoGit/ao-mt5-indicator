//+------------------------------------------------------------------+
//|  AO Cross & Color Markers                                        |
//|  MetaTrader 5 Indicator — MQL5                                   |
//+------------------------------------------------------------------+
#property copyright   ""
#property link        ""
#property version     "1.00"
#property indicator_separate_window
#property indicator_buffers 9
#property indicator_plots   7

// Plot 0 — AO histogram (color index 0=green rising, 1=red falling)
#property indicator_label1  "AO"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrGreen,clrRed
#property indicator_width1  4

// Plot 1 — AC histogram (color index 0=lime rising, 1=maroon falling)
#property indicator_label2  "AC"
#property indicator_type2   DRAW_COLOR_HISTOGRAM
#property indicator_color2  clrLime,clrMaroon
#property indicator_width2  2

// Plot 2 — AO WMA line
#property indicator_label3  "AO WMA"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrBlue
#property indicator_width3  1

// Plot 3 — Average positive AO
#property indicator_label4  "Avg Positive AO"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGreen
#property indicator_width4  1

// Plot 4 — Average negative AO
#property indicator_label5  "Avg Negative AO"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_width5  1

// Plot 5 — Single Bar Down arrow (above bar, AO > 0)
#property indicator_label6  "Single Bar Down"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrRed
#property indicator_width6  1

// Plot 6 — Single Bar Up arrow (below bar, AO < 0)
#property indicator_label7  "Single Bar Up"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrGreen
#property indicator_width7  1

#property indicator_levelcolor clrGray
#property indicator_levels     1
#property indicator_levelvalue 0

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_MARKER_SIZE
{
   SIZE_TINY   = 0,  // Tiny
   SIZE_SMALL  = 1,  // Small
   SIZE_NORMAL = 2,  // Normal
   SIZE_LARGE  = 3,  // Large
   SIZE_HUGE   = 4   // Huge
};

enum ENUM_VLINE_STYLE
{
   VLINE_SOLID  = 0,  // Solid
   VLINE_DASHED = 1,  // Dashed
   VLINE_DOTTED = 2   // Dotted
};

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+

// --- Main ---
input bool             ShowZeroCross   = true;        // Show Zero Cross marker (0)
input bool             ShowColorChange = true;        // Show Color Change marker (C)
input bool             ShowSingleBar   = true;        // Show Single Bar arrows
input color            MarkerColor     = clrOrange;   // Marker Color
input ENUM_MARKER_SIZE MarkerSize      = SIZE_SMALL;  // Marker Size

// --- AO / AC ---
input int AOAvgLen        = 100;   // AO Average Lookback (strength filter for C)
input int AODisplayAvgLen = 1000;  // AO Display Average Lookback
input int AOWmaLen        = 14;    // AO WMA Length

// --- Vertical Lines ---
input bool             ShowVLines     = true;         // Show Vertical Lines (C+21, C+34)
input color            VLineBullColor = clrGreen;     // VLine Bull Color (AO > 0 at C)
input color            VLineBearColor = clrRed;       // VLine Bear Color (AO < 0 at C)
input ENUM_VLINE_STYLE VLineStyle     = VLINE_DASHED; // VLine Style

// --- Alerts ---
input bool EnableAlerts       = true;   // Enable Alerts
input bool AlertOnZeroCross   = false;  // Alert: Zero Cross
input bool AlertOnColorChange = false;  // Alert: Color Change (C)
input bool AlertOnSingleBar   = true;   // Alert: Single Bar
input bool AlertOnSaucer      = true;   // Alert: Saucer
input bool AlertOnWMACross    = true;   // Alert: WMA Cross
input bool AlertOnPeak        = true;   // Alert: Higher/Lower Peak
input bool UsePopupAlert      = true;   // Use Popup Alert
input bool UsePushAlert       = false;  // Use Push Notification
input bool UseEmailAlert      = false;  // Use Email Alert

//+------------------------------------------------------------------+
//| Indicator buffers (9 total: 7 data + 2 color-index)             |
//+------------------------------------------------------------------+
double BufAO[];         // plot 0 data
double BufAOColor[];    // plot 0 color index
double BufAC[];         // plot 1 data
double BufACColor[];    // plot 1 color index
double BufWMA[];        // plot 2
double BufAvgPos[];     // plot 3
double BufAvgNeg[];     // plot 4
double BufArrowDown[];  // plot 5
double BufArrowUp[];    // plot 6

//+------------------------------------------------------------------+
//| Vertical-line state machine variables                           |
//+------------------------------------------------------------------+
int    g_lastCBar         = -1;
bool   g_cPending         = false;
double g_lastAoAtC        = 0.0;
bool   g_linesLive        = false;
int    g_liveZoneStart    = -1;
int    g_liveZoneEnd      = -1;
bool   g_preZoneProtected = false;
int    g_zoneStarts[];
int    g_zoneEnds[];
string g_vline21Name      = "";
string g_vline34Name      = "";

//+------------------------------------------------------------------+
//| Peak detection state                                            |
//+------------------------------------------------------------------+
double g_prevPeakPos    = EMPTY_VALUE;
double g_currPeakPos    = 0.0;
bool   g_peakAlertedPos = false;
double g_prevPeakNeg    = EMPTY_VALUE;
double g_currPeakNeg    = 0.0;
bool   g_peakAlertedNeg = false;

//+------------------------------------------------------------------+
//| Alert spam protection                                           |
//| idx: 0=ZCUp 1=ZCDown 2=CC 3=SBDown 4=SBUp                      |
//|      5=SaucerBuy 6=SaucerSell 7=WMAUp 8=WMADown                 |
//|      9=HigherPeak 10=LowerPeak                                  |
//+------------------------------------------------------------------+
datetime g_lastAlertTime[11];

//+------------------------------------------------------------------+
//| Cached current close for alert messages                         |
//+------------------------------------------------------------------+
double   g_lastClose   = 0.0;

//+------------------------------------------------------------------+
//| Helpers                                                         |
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "1m";
      case PERIOD_M2:  return "2m";
      case PERIOD_M3:  return "3m";
      case PERIOD_M4:  return "4m";
      case PERIOD_M5:  return "5m";
      case PERIOD_M6:  return "6m";
      case PERIOD_M10: return "10m";
      case PERIOD_M12: return "12m";
      case PERIOD_M15: return "15m";
      case PERIOD_M20: return "20m";
      case PERIOD_M30: return "30m";
      case PERIOD_H1:  return "1H";
      case PERIOD_H2:  return "2H";
      case PERIOD_H3:  return "3H";
      case PERIOD_H4:  return "4H";
      case PERIOD_H6:  return "6H";
      case PERIOD_H8:  return "8H";
      case PERIOD_H12: return "12H";
      case PERIOD_D1:  return "1D";
      case PERIOD_W1:  return "1W";
      case PERIOD_MN1: return "1M";
      default:         return IntegerToString((int)tf) + "m";
   }
}

void DoSendAlert(string msg)
{
   if(UsePopupAlert) Alert(msg);
   if(UsePushAlert)  SendNotification(msg);
   if(UseEmailAlert) SendMail("AO Cross Alert", msg);
}

void TryAlert(int idx, string signalName, bool condition, bool flag)
{
   if(!EnableAlerts || !flag || !condition) return;
   datetime barTime = iTime(Symbol(), Period(), 1);
   if(g_lastAlertTime[idx] == barTime) return;
   g_lastAlertTime[idx] = barTime;
   string msg = "AO Cross | Signal: " + signalName +
                " | Symbol: " + Symbol() +
                " | TF: "     + TFToString(Period()) +
                " | Price: "  + DoubleToString(g_lastClose, _Digits);
   DoSendAlert(msg);
}

void DeleteAOObjects()
{
   long cid   = ChartID();
   int  total = ObjectsTotal(cid, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(cid, i, 0, -1);
      if(StringFind(name, "AO_") == 0)
         ObjectDelete(cid, name);
   }
}

int GetMarkerFontSize()
{
   switch(MarkerSize)
   {
      case SIZE_TINY:   return 7;
      case SIZE_SMALL:  return 9;
      case SIZE_NORMAL: return 12;
      case SIZE_LARGE:  return 16;
      case SIZE_HUGE:   return 22;
   }
   return 9;
}

void PlaceMarker(string prefix, datetime barTime, double price, string txt)
{
   string name = prefix + (string)barTime;
   long   cid  = ChartID();
   if(ObjectFind(cid, name) >= 0) return;
   ObjectCreate(cid, name, OBJ_TEXT, 0, barTime, price);
   ObjectSetString (cid, name, OBJPROP_TEXT,       txt);
   ObjectSetString (cid, name, OBJPROP_FONT,       "Arial Bold");
   ObjectSetInteger(cid, name, OBJPROP_FONTSIZE,   GetMarkerFontSize());
   ObjectSetInteger(cid, name, OBJPROP_COLOR,      MarkerColor);
   ObjectSetInteger(cid, name, OBJPROP_ANCHOR,     ANCHOR_TOP);
   ObjectSetInteger(cid, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(cid, name, OBJPROP_HIDDEN,     true);
}

ENUM_LINE_STYLE GetVLineStyle()
{
   switch(VLineStyle)
   {
      case VLINE_SOLID:  return STYLE_SOLID;
      case VLINE_DASHED: return STYLE_DASH;
      case VLINE_DOTTED: return STYLE_DOT;
   }
   return STYLE_DASH;
}

string CreateVLine(datetime t, color clr)
{
   string name = "AO_VL_" + (string)t;
   long   cid  = ChartID();
   if(ObjectFind(cid, name) >= 0) ObjectDelete(cid, name);
   ObjectCreate(cid, name, OBJ_VLINE, 0, t, 0.0);
   ObjectSetInteger(cid, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(cid, name, OBJPROP_STYLE,      GetVLineStyle());
   ObjectSetInteger(cid, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(cid, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(cid, name, OBJPROP_HIDDEN,     true);
   return name;
}

void SafeDeleteObj(string &name)
{
   if(name != "")
   {
      ObjectDelete(ChartID(), name);
      name = "";
   }
}

void ResetState()
{
   g_lastCBar         = -1;
   g_cPending         = false;
   g_lastAoAtC        = 0.0;
   g_linesLive        = false;
   g_liveZoneStart    = -1;
   g_liveZoneEnd      = -1;
   g_preZoneProtected = false;
   ArrayResize(g_zoneStarts, 0);
   ArrayResize(g_zoneEnds,   0);
   g_vline21Name      = "";
   g_vline34Name      = "";
   g_prevPeakPos      = EMPTY_VALUE;
   g_currPeakPos      = 0.0;
   g_peakAlertedPos   = false;
   g_prevPeakNeg      = EMPTY_VALUE;
   g_currPeakNeg      = 0.0;
   g_peakAlertedNeg   = false;
   ArrayInitialize(g_lastAlertTime, 0);
}

//+------------------------------------------------------------------+
//| OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Bind buffers
   SetIndexBuffer(0, BufAO,        INDICATOR_DATA);
   SetIndexBuffer(1, BufAOColor,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufAC,        INDICATOR_DATA);
   SetIndexBuffer(3, BufACColor,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, BufWMA,       INDICATOR_DATA);
   SetIndexBuffer(5, BufAvgPos,    INDICATOR_DATA);
   SetIndexBuffer(6, BufAvgNeg,    INDICATOR_DATA);
   SetIndexBuffer(7, BufArrowDown, INDICATOR_DATA);
   SetIndexBuffer(8, BufArrowUp,   INDICATOR_DATA);

   // Arrow codes: 234 = down-pointing, 233 = up-pointing (Wingdings)
   PlotIndexSetInteger(5, PLOT_ARROW, 234);
   PlotIndexSetInteger(6, PLOT_ARROW, 233);

   // Empty value for non-histogram plots
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "AO Cross & Color Markers");
   IndicatorSetInteger(INDICATOR_LEVELS,      1);
   IndicatorSetDouble (INDICATOR_LEVELVALUE,  0, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR,  0, clrGray);

   DeleteAOObjects();
   ResetState();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAOObjects();
}

//+------------------------------------------------------------------+
//| SMA of an array over [i-period+1 .. i]                         |
//+------------------------------------------------------------------+
double SMAArr(const double &arr[], int i, int period)
{
   if(i < period - 1) return EMPTY_VALUE;
   double s = 0.0;
   for(int k = 0; k < period; k++) s += arr[i - k];
   return s / period;
}

//+------------------------------------------------------------------+
//| WMA of an array over [i-period+1 .. i]                         |
//+------------------------------------------------------------------+
double WMAArr(const double &arr[], int i, int period)
{
   if(i < period - 1) return EMPTY_VALUE;
   double num = 0.0, den = 0.0;
   for(int k = 0; k < period; k++)
   {
      int w = period - k;
      num += arr[i - k] * w;
      den += w;
   }
   return (den > 0) ? num / den : EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| OnCalculate                                                     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   int minBars = 34 + AOWmaLen + AOAvgLen + 5;
   if(rates_total < minBars) return 0;

   if(prev_calculated == 0)
   {
      DeleteAOObjects();
      ResetState();
      ArrayInitialize(BufAO,        0.0);
      ArrayInitialize(BufAC,        0.0);
      ArrayInitialize(BufArrowDown, EMPTY_VALUE);
      ArrayInitialize(BufArrowUp,   EMPTY_VALUE);
   }

   // --- Step 1: compute AO array ---
   double ao[];
   ArrayResize(ao, rates_total);

   int aoStart = 33; // need 34 bars
   for(int i = aoStart; i < rates_total; i++)
   {
      double sum5 = 0.0, sum34 = 0.0;
      for(int k = 0; k < 5;  k++) sum5  += (high[i-k] + low[i-k]);
      for(int k = 0; k < 34; k++) sum34 += (high[i-k] + low[i-k]);
      ao[i] = sum5 / 10.0 - sum34 / 68.0;
   }

   // --- Step 2: fill plot buffers (AO, AC, WMA, AvgPos, AvgNeg) ---
   int calcFrom = (prev_calculated <= 1) ? aoStart : prev_calculated - 1;

   for(int i = calcFrom; i < rates_total; i++)
   {
      // AO histogram
      BufAO[i]      = ao[i];
      BufAOColor[i] = (i > 0 && ao[i] >= ao[i-1]) ? 0.0 : 1.0;

      // AC = AO - SMA(AO, 5)
      if(i >= aoStart + 4)
      {
         double sma5 = SMAArr(ao, i, 5);
         double acv  = ao[i] - sma5;
         BufAC[i]      = acv;
         BufACColor[i] = (i > 0 && acv >= BufAC[i-1]) ? 0.0 : 1.0;
      }
      else
      {
         BufAC[i]      = 0.0;
         BufACColor[i] = 0.0;
      }

      // AO WMA
      BufWMA[i] = WMAArr(ao, i, AOWmaLen);

      // AvgPos / AvgNeg over AODisplayAvgLen
      if(i >= aoStart + AODisplayAvgLen - 1)
      {
         double sp = 0.0, cp = 0.0, sn = 0.0, cn = 0.0;
         for(int k = 0; k < AODisplayAvgLen; k++)
         {
            double v = ao[i-k];
            if(v > 0.0) { sp += v; cp++; }
            if(v < 0.0) { sn += v; cn++; }
         }
         BufAvgPos[i] = (cp > 0) ? sp / cp : EMPTY_VALUE;
         BufAvgNeg[i] = (cn > 0) ? sn / cn : EMPTY_VALUE;
      }
      else
      {
         BufAvgPos[i] = EMPTY_VALUE;
         BufAvgNeg[i] = EMPTY_VALUE;
      }
   }

   // --- Step 3: signal processing per bar ---
   // We process each "current bar" index i, looking at bar[1]=i-1, bar[2]=i-2, etc.
   // Start from enough history; for live updates only the last bar matters,
   // but on full recalc we iterate all bars.
   int sigStart = MathMax(calcFrom, aoStart + AOAvgLen + 4);

   for(int i = sigStart; i < rates_total; i++)
   {
      int b1 = i - 1; // bar[1] — last closed bar
      int b2 = i - 2; // bar[2]
      int b3 = i - 3; // bar[3]
      int b4 = i - 4; // bar[4]
      if(b4 < aoStart) continue;

      double ao1 = ao[b1], ao2 = ao[b2], ao3 = ao[b3], ao4 = ao[b4];
      double wma1 = BufWMA[b1], wma2 = BufWMA[b2];

      // 5.1 Zero Cross
      bool zeroCrossUp   = (ao1 > 0.0 && ao2 <= 0.0);
      bool zeroCrossDown = (ao1 < 0.0 && ao2 >= 0.0);
      bool zeroCross     = zeroCrossUp || zeroCrossDown;

      // 5.2 Color Change + strength filter
      int colorNow  = (ao1 > ao2) ? 1 : (ao1 < ao2) ? -1 : 0;
      int colorPrev = (ao2 > ao3) ? 1 : (ao2 < ao3) ? -1 : 0;
      bool colorChangeRaw = (colorNow != colorPrev && colorNow != 0 && colorPrev != 0);

      double sp1 = 0.0, cp1 = 0.0, sn1 = 0.0, cn1 = 0.0;
      for(int k = 0; k < AOAvgLen; k++)
      {
         double v = ao[b1 - k];
         if(v > 0.0) { sp1 += v; cp1++; }
         if(v < 0.0) { sn1 += v; cn1++; }
      }
      double avgPos1 = (cp1 > 0) ? sp1 / cp1 : EMPTY_VALUE;
      double avgNeg1 = (cn1 > 0) ? sn1 / cn1 : EMPTY_VALUE;

      bool strongC = false;
      if(ao1 > 0.0 && avgPos1 != EMPTY_VALUE)
         strongC = MathAbs(ao1) >= MathAbs(avgPos1);
      else if(ao1 < 0.0 && avgNeg1 != EMPTY_VALUE)
         strongC = MathAbs(ao1) >= MathAbs(avgNeg1);

      bool colorChange = colorChangeRaw && strongC;

      // 5.3 Single Bar
      int colorPrevPrev = (ao3 > ao4) ? 1 : (ao3 < ao4) ? -1 : 0;
      bool singleBar = (colorPrevPrev != 0 && colorPrev != 0 && colorNow != 0 &&
                        colorPrev != colorPrevPrev && colorPrev != colorNow &&
                        colorPrevPrev == colorNow);
      bool singleBarDown = singleBar && (ao2 > 0.0);
      bool singleBarUp   = singleBar && (ao2 < 0.0);

      // Arrow offset: 20% of max |AO| over last 50 bars, at bar[2]
      if(ShowSingleBar && (singleBarDown || singleBarUp))
      {
         double maxAbs = 0.0;
         for(int k = 0; k < 50 && (b2-k) >= aoStart; k++)
            maxAbs = MathMax(maxAbs, MathAbs(ao[b2-k]));
         double off = maxAbs * 0.20;
         if(singleBarDown) BufArrowDown[b2] = ao2 + off;
         if(singleBarUp)   BufArrowUp[b2]   = ao2 - off;
      }

      // 5.4 Saucer
      bool saucerBuy  = (ao1 > 0.0 && ao2 > 0.0 && colorPrev == -1 && colorNow == 1);
      bool saucerSell = (ao1 < 0.0 && ao2 < 0.0 && colorPrev == 1  && colorNow == -1);

      // 5.5 WMA Cross
      bool wmaCrossUp   = false;
      bool wmaCrossDown = false;
      if(wma1 != EMPTY_VALUE && wma2 != EMPTY_VALUE)
      {
         wmaCrossUp   = (ao1 > wma1 && ao2 <= wma2);
         wmaCrossDown = (ao1 < wma1 && ao2 >= wma2);
      }

      // 5.6 Peak tracking
      if(ao1 > 0.0) g_currPeakPos = MathMax(g_currPeakPos, ao1);
      if(ao1 < 0.0) g_currPeakNeg = MathMin(g_currPeakNeg, ao1);

      if(zeroCrossDown)
      {
         g_prevPeakPos    = g_currPeakPos;
         g_currPeakPos    = 0.0;
         g_peakAlertedPos = false;
         g_currPeakNeg    = 0.0;
         g_peakAlertedNeg = false;
      }
      if(zeroCrossUp)
      {
         g_prevPeakNeg    = g_currPeakNeg;
         g_currPeakNeg    = 0.0;
         g_peakAlertedNeg = false;
         g_currPeakPos    = 0.0;
         g_peakAlertedPos = false;
      }

      bool newHigherPeak = (ao1 > 0.0 &&
                            g_prevPeakPos != EMPTY_VALUE &&
                            g_currPeakPos > g_prevPeakPos &&
                            !g_peakAlertedPos);
      bool newLowerPeak  = (ao1 < 0.0 &&
                            g_prevPeakNeg != EMPTY_VALUE &&
                            g_currPeakNeg < g_prevPeakNeg &&
                            !g_peakAlertedNeg);

      if(newHigherPeak) g_peakAlertedPos = true;
      if(newLowerPeak)  g_peakAlertedNeg = true;

      // 6. OBJ_TEXT markers on main chart
      if(b1 >= 0 && b1 < rates_total)
      {
         double hl    = high[b1] - low[b1];
         double off1  = (hl > 0) ? hl * 0.5 : _Point * 10;
         double off2  = off1 * 2.0;

         if(ShowZeroCross && zeroCross)
            PlaceMarker("AO_ZC_", time[b1], low[b1] - off1, "0");

         if(ShowColorChange && colorChange)
            PlaceMarker("AO_CC_", time[b1], low[b1] - off2, "C");
      }

      // 7. Vertical lines state machine
      int signalBar = b1;

      bool inZone = false;
      int  zoneCnt = ArraySize(g_zoneStarts);
      for(int z = 0; z < zoneCnt; z++)
      {
         if(signalBar >= g_zoneStarts[z] && signalBar <= g_zoneEnds[z])
         { inZone = true; break; }
      }

      // Phase 1: manage live lines
      if(g_linesLive)
      {
         if(signalBar > g_liveZoneEnd)
         {
            g_linesLive = false;
         }
         else if(zeroCross && signalBar >= g_liveZoneStart && signalBar <= g_liveZoneEnd)
         {
            SafeDeleteObj(g_vline21Name);
            SafeDeleteObj(g_vline34Name);
            int sz = ArraySize(g_zoneStarts);
            if(sz > 0) { ArrayResize(g_zoneStarts, sz-1); ArrayResize(g_zoneEnds, sz-1); }
            g_linesLive = false;
         }
         else if(zeroCross && signalBar < g_liveZoneStart && !g_preZoneProtected)
         {
            SafeDeleteObj(g_vline21Name);
            SafeDeleteObj(g_vline34Name);
            int sz = ArraySize(g_zoneStarts);
            if(sz > 0) { ArrayResize(g_zoneStarts, sz-1); ArrayResize(g_zoneEnds, sz-1); }
            g_linesLive = false;
         }
         else if(colorChange && signalBar < g_liveZoneStart)
         {
            g_preZoneProtected = true;
         }
      }

      // Phase 2: create new lines
      if(!inZone)
      {
         if(colorChange && !zeroCross)
         {
            g_lastCBar  = signalBar;
            g_cPending  = true;
            g_lastAoAtC = ao1;
         }
         else if(zeroCross && g_cPending)
         {
            g_cPending = false;
            if(!g_linesLive)
            {
               int newStart = g_lastCBar + 21;
               int newEnd   = g_lastCBar + 34;
               bool zeroInOwn = (signalBar >= newStart && signalBar <= newEnd);
               bool overlap   = false;
               int  nz        = ArraySize(g_zoneStarts);
               for(int z = 0; z < nz; z++)
               {
                  if(newStart <= g_zoneEnds[z] && newEnd >= g_zoneStarts[z])
                  { overlap = true; break; }
               }
               if(ShowVLines && !overlap && !zeroInOwn)
               {
                  color vclr = (g_lastAoAtC > 0.0) ? VLineBullColor : VLineBearColor;
                  datetime t21 = (newStart < rates_total) ? time[newStart] :
                                  time[rates_total-1] + (long)(newStart - rates_total + 1) * PeriodSeconds();
                  datetime t34 = (newEnd   < rates_total) ? time[newEnd] :
                                  time[rates_total-1] + (long)(newEnd   - rates_total + 1) * PeriodSeconds();
                  g_vline21Name = CreateVLine(t21, vclr);
                  g_vline34Name = CreateVLine(t34, vclr);
                  int sz = ArraySize(g_zoneStarts);
                  ArrayResize(g_zoneStarts, sz + 1);
                  ArrayResize(g_zoneEnds,   sz + 1);
                  g_zoneStarts[sz]   = newStart;
                  g_zoneEnds[sz]     = newEnd;
                  g_liveZoneStart    = newStart;
                  g_liveZoneEnd      = newEnd;
                  g_linesLive        = true;
                  g_preZoneProtected = false;
               }
            }
         }
         else if(colorChange)
         {
            g_cPending = false;
         }
      }

      // 8. Alerts — only on the live (forming) bar
      if(i == rates_total - 1)
      {
         g_lastClose = close[rates_total - 1];
         TryAlert(0,  "Zero Cross UP",    zeroCrossUp,   AlertOnZeroCross);
         TryAlert(1,  "Zero Cross DOWN",  zeroCrossDown, AlertOnZeroCross);
         TryAlert(2,  "Color Change (C)", colorChange,   AlertOnColorChange);
         TryAlert(3,  "Single Bar DOWN",  singleBarDown, AlertOnSingleBar);
         TryAlert(4,  "Single Bar UP",    singleBarUp,   AlertOnSingleBar);
         TryAlert(5,  "Saucer BUY",       saucerBuy,     AlertOnSaucer);
         TryAlert(6,  "Saucer SELL",      saucerSell,    AlertOnSaucer);
         TryAlert(7,  "WMA Cross UP",     wmaCrossUp,    AlertOnWMACross);
         TryAlert(8,  "WMA Cross DOWN",   wmaCrossDown,  AlertOnWMACross);
         TryAlert(9,  "Higher Peak",      newHigherPeak, AlertOnPeak);
         TryAlert(10, "Lower Peak",       newLowerPeak,  AlertOnPeak);
      }
   }

   ChartRedraw(ChartID());
   return rates_total;
}
