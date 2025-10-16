//+------------------------------------------------------------------+
//|                                             ForSpecialEvents.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10" // Fixed constant modification error for trailing stop

//--- Include the Trade and Position Info libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input group      "Trade Settings"
input int        stopLossPips       = 1000;  // Stop Loss in points
input int        takeProfitPips     = 3000;  // Take Profit in points

input group      "Trailing Stop Settings"
// MODIFIED: This input now only sets the INITIAL state of the trailing stop.
input bool       enableTrailingStop = false;  // Initial state for Trailing Stop
input int        trailingStopPips   = 150;  // Trailing stop distance in points (if enabled)
input int        trailingStopStep   = 1;    // Trailing stop update step in points

input group      "Breakeven Settings"
input int        breakevenPoints    = 5;    // Points above/below open price to set BE SL
input string     keyMoveToBE        = "B";  // Key to Move all SLs to the latest position's BE

input group      "Lot Size Settings"
input double     lotSize1           = 0.01; // Lot size for Hotkey Set 1
input double     lotSize2           = 0.05; // Lot size for Hotkey Set 2
input double     lotSize3           = 0.10; // Lot size for Hotkey Set 3
input double     lotSize4           = 1.00; // Lot size for Hotkey Set 4

input group      "Hotkey Settings (Case Insensitive)"
input string     keyBuyLot1         = "N";  // Key to Buy Lot Size 1
input string     keySellLot1        = "M";  // Key to Sell Lot Size 1
input string     keyBuyLot2         = "H";  // Key to Buy Lot Size 2
input string     keySellLot2        = "J";  // Key to Sell Lot Size 2
input string     keyBuyLot3         = "Y";  // Key to Buy Lot Size 3
input string     keySellLot3        = "U";  // Key to Sell Lot Size 3
input string     keyBuyLot4         = "I";  // Key to Buy Lot Size 4
input string     keySellLot4        = "O";  // Key to Sell Lot Size 4
input string     keyToggleTrailing  = "Q";  // Key to Enable/Disable Trailing Stop
input string     keyCloseAll        = "C";  // Key to Close All Positions

//--- Create instances of trade and position info classes
CTrade          trade;
CPositionInfo   posInfo;

//--- Global variables to store the integer key codes
long keyCodeBuyLot1, keyCodeSellLot1;
long keyCodeBuyLot2, keyCodeSellLot2;
long keyCodeBuyLot3, keyCodeSellLot3;
long keyCodeBuyLot4, keyCodeSellLot4;
long keyCodeCloseAll;
long keyCodeMoveToBE;
long keyCodeToggleTrailing;

// ADDED: A mutable global variable to control the trailing stop's active state.
bool g_trailing_stop_active;

//--- Helper function to safely get keycode from a constant input string
long GetKeyCodeFromString(const string key_string)
  {
   if(StringLen(key_string) == 0) return 0;
   string temp_key = key_string;
   StringToUpper(temp_key);
   return StringGetCharacter(temp_key, 0);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Print("--- ForSpecialEvents EA Initialized ---");

   keyCodeBuyLot1        = GetKeyCodeFromString(keyBuyLot1);
   keyCodeSellLot1       = GetKeyCodeFromString(keySellLot1);
   keyCodeBuyLot2        = GetKeyCodeFromString(keyBuyLot2);
   keyCodeSellLot2       = GetKeyCodeFromString(keySellLot2);
   keyCodeBuyLot3        = GetKeyCodeFromString(keyBuyLot3);
   keyCodeSellLot3       = GetKeyCodeFromString(keySellLot3);
   keyCodeBuyLot4        = GetKeyCodeFromString(keyBuyLot4);
   keyCodeSellLot4       = GetKeyCodeFromString(keySellLot4);
   keyCodeCloseAll       = GetKeyCodeFromString(keyCloseAll);
   keyCodeMoveToBE       = GetKeyCodeFromString(keyMoveToBE);
   keyCodeToggleTrailing = GetKeyCodeFromString(keyToggleTrailing);

   // ADDED: Initialize the mutable variable with the input's value
   g_trailing_stop_active = enableTrailingStop;
   
   Print("--- Hotkey Bindings ---");
   PrintFormat("Buy %.2f Lots  -> Key: '%s'", lotSize1, keyBuyLot1);
   PrintFormat("Sell %.2f Lots -> Key: '%s'", lotSize1, keySellLot1);
   PrintFormat("Buy %.2f Lots  -> Key: '%s'", lotSize2, keyBuyLot2);
   PrintFormat("Sell %.2f Lots -> Key: '%s'", lotSize2, keySellLot2);
   PrintFormat("Buy %.2f Lots  -> Key: '%s'", lotSize3, keyBuyLot3);
   PrintFormat("Sell %.2f Lots -> Key: '%s'", lotSize3, keySellLot3);
   PrintFormat("Buy %.2f Lots  -> Key: '%s'", lotSize4, keyBuyLot4);
   PrintFormat("Sell %.2f Lots -> Key: '%s'", lotSize4, keySellLot4);
   PrintFormat("Close All Positions on %s -> Key: '%s'", _Symbol, keyCloseAll);
   PrintFormat("Move all SLs to latest trade's BE (+%d points) -> Key: '%s'", breakevenPoints, keyMoveToBE);
   PrintFormat("Enable/Disable Trailing Stop -> Key: '%s'", keyToggleTrailing);
   
   // MODIFIED: Display initial status using the new variable
   Comment("Trailing Stop: ", g_trailing_stop_active ? "ON" : "OFF");
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
   Print("--- ForSpecialEvents EA Deinitialized. Reason code: ", reason, " ---");
  }
//+------------------------------------------------------------------+
//| Expert tick function (for Trailing Stop)                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   // MODIFIED: Check the mutable global variable instead of the constant input
   if(!g_trailing_stop_active || trailingStopPips <= 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol)
        {
         double newSL = 0;
         double currentSL = posInfo.StopLoss();
         double openPrice = posInfo.PriceOpen();
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

         if(posInfo.PositionType() == POSITION_TYPE_BUY)
           {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(currentPrice > openPrice)
              {
               newSL = currentPrice - (trailingStopPips * point);
               if(newSL > openPrice && (currentSL < newSL || currentSL == 0))
                 {
                  if(fabs(newSL - currentSL) >= trailingStopStep * point)
                     trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
                 }
              }
           }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
           {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(currentPrice < openPrice)
              {
               newSL = currentPrice + (trailingStopPips * point);
               if(newSL < openPrice && (currentSL > newSL || currentSL == 0))
                 {
                  if(fabs(newSL - currentSL) >= trailingStopStep * point)
                     trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
                 }
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| ChartEvent function (for handling hotkeys)                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_KEYDOWN)
     {
      long key = lparam;

      if(key == keyCodeBuyLot1)      ExecuteTrade(ORDER_TYPE_BUY, lotSize1);
      else if(key == keyCodeSellLot1) ExecuteTrade(ORDER_TYPE_SELL, lotSize1);
      else if(key == keyCodeBuyLot2)  ExecuteTrade(ORDER_TYPE_BUY, lotSize2);
      else if(key == keyCodeSellLot2) ExecuteTrade(ORDER_TYPE_SELL, lotSize2);
      else if(key == keyCodeBuyLot3)  ExecuteTrade(ORDER_TYPE_BUY, lotSize3);
      else if(key == keyCodeSellLot3) ExecuteTrade(ORDER_TYPE_SELL, lotSize3);
      else if(key == keyCodeBuyLot4)  ExecuteTrade(ORDER_TYPE_BUY, lotSize4);
      else if(key == keyCodeSellLot4) ExecuteTrade(ORDER_TYPE_SELL, lotSize4);
      else if(key == keyCodeMoveToBE) MoveAllToLatestBreakeven();
      // MODIFIED: Logic now toggles the mutable global variable
      else if(key == keyCodeToggleTrailing)
        {
         g_trailing_stop_active = !g_trailing_stop_active; // Toggle the boolean state
         if(g_trailing_stop_active)
           {
            Print("Trailing Stop has been ENABLED by hotkey.");
            Comment("Trailing Stop: ON");
           }
         else
           {
            Print("Trailing Stop has been DISABLED by hotkey.");
            Comment("Trailing Stop: OFF");
           }
        }
      else if(key == keyCodeCloseAll)
        {
         Print("Close key detected. Closing all positions for ", _Symbol);
         int closedCount = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol)
              {
               if(trade.PositionClose(posInfo.Ticket())) closedCount++;
              }
           }
         if(closedCount == 0) Print("No open positions found on ", _Symbol, " to close.");
        }
     }
  }
//+------------------------------------------------------------------+
//| Helper function to execute a trade                               |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE direction, double lotSize)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price = 0, sl = 0, tp = 0;

   if(direction == ORDER_TYPE_BUY)
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = (stopLossPips > 0) ? price - stopLossPips * point : 0;
      tp = (takeProfitPips > 0) ? price + takeProfitPips * point : 0;
      trade.Buy(lotSize, _Symbol, price, sl, tp, "Buy order by hotkey");
     }
   else if(direction == ORDER_TYPE_SELL)
     {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = (stopLossPips > 0) ? price + stopLossPips * point : 0;
      tp = (takeProfitPips > 0) ? price - takeProfitPips * point : 0;
      trade.Sell(lotSize, _Symbol, price, sl, tp, "Sell order by hotkey");
     }
  }
//+------------------------------------------------------------------+
//| Function to move all SLs to the latest position's BE             |
//+------------------------------------------------------------------+
void MoveAllToLatestBreakeven()
  {
   Print("Collective Breakeven key detected.");
   
   // --- Step 1: Find the latest position on the current symbol ---
   ulong latest_ticket = 0;
   datetime latest_open_time = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol)
        {
         if(posInfo.Time() > latest_open_time)
           {
            latest_open_time = posInfo.Time();
            latest_ticket = posInfo.Ticket();
           }
        }
     }

   // --- Step 2: If no position was found, exit ---
   if(latest_ticket == 0)
     {
      Print("No open positions found on ", _Symbol, " to set a collective breakeven.");
      return;
     }

   // --- Step 3: Calculate the target SL based on the latest position ---
   if(!posInfo.SelectByTicket(latest_ticket))
     {
      Print("Error: Could not select the latest position #", latest_ticket);
      return;
     }
     
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double openPrice = posInfo.PriceOpen();
   double target_breakeven_sl = 0;
   
   if(posInfo.PositionType() == POSITION_TYPE_BUY)
     {
      target_breakeven_sl = openPrice + breakevenPoints * point;
      // Safety Check: Is the latest trade profitable enough?
      if(SymbolInfoDouble(_Symbol, SYMBOL_BID) <= target_breakeven_sl)
        {
         Print("The latest BUY position (#", latest_ticket, ") is not yet profitable enough to set a collective breakeven. Action aborted.");
         return;
        }
     }
   else // POSITION_TYPE_SELL
     {
      target_breakeven_sl = openPrice - breakevenPoints * point;
      // Safety Check: Is the latest trade profitable enough?
      if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) >= target_breakeven_sl)
        {
         Print("The latest SELL position (#", latest_ticket, ") is not yet profitable enough to set a collective breakeven. Action aborted.");
         return;
        }
     }
     
   PrintFormat("Target breakeven SL for all positions is %.5f, based on position #%d", target_breakeven_sl, latest_ticket);

   // --- Step 4: Loop through all positions again and modify them ---
   int modified_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol)
        {
         // Skip if SL is already at the target level
         if(posInfo.StopLoss() == target_breakeven_sl)
            continue;
            
         if(trade.PositionModify(posInfo.Ticket(), target_breakeven_sl, posInfo.TakeProfit()))
           {
            Print("SUCCESS: Moved position #", posInfo.Ticket(), " to the collective breakeven.");
            modified_count++;
           }
         else
           {
            Print("ERROR: Failed to move position #", posInfo.Ticket(), " to breakeven. Code: ", trade.ResultRetcode());
           }
        }
     }
     
   if(modified_count > 0)
     {
      Print("Finished. ", modified_count, " positions were moved to the collective breakeven level.");
     }
   else
     {
      Print("No positions required modification.");
     }
  }
//+------------------------------------------------------------------+