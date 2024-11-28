//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA Initialized. Monitoring manual trades...");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function (called on every price tick)                |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckAndDeletePendingOrders(); // Check and delete pending orders if necessary
}

//+------------------------------------------------------------------+
//| Function to handle trade transactions                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, 
                        const MqlTradeRequest &request, 
                        const MqlTradeResult &result)
{
   static int totalManualTrades = 0;
   static datetime lastTradeDay = 0;

   // Reset the count if a new day starts
   datetime currentDay = TimeCurrent() / 86400 * 86400;
   if (currentDay != lastTradeDay)
   {
      totalManualTrades = 0;
      lastTradeDay = currentDay;
      Print("New day detected. Trade count reset to 0.");
   }

   // Check if the transaction is a manual execution
   if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if (trans.deal != 0 && DealIsManual(trans.deal))
      {
         totalManualTrades++;
         Print("New manual trade detected. Total manual trades today: ", totalManualTrades);

         if (totalManualTrades >= 4)
         {
            Print("Trade limit exceeded. Deleting all pending orders and closing market trades.");
            CheckAndDeletePendingOrders();
            CloseAllMarketPositions();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Function to check if the deal is a manual trade                   |
//+------------------------------------------------------------------+
bool DealIsManual(ulong deal)
{
   if (HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN &&
       (HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY ||
        HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_SELL))
   {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Function to check and delete all pending orders                   |
//+------------------------------------------------------------------+
void CheckAndDeletePendingOrders()
{
   // Loop through all current orders
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i); // Get the order ticket
      
      if (OrderSelect(ticket)) // Select the order using ticket
      {
         int orderType = (int)OrderGetInteger(ORDER_TYPE);

         // Check if the order is a pending order type
         if (orderType == ORDER_TYPE_BUY_LIMIT || 
             orderType == ORDER_TYPE_SELL_LIMIT || 
             orderType == ORDER_TYPE_BUY_STOP || 
             orderType == ORDER_TYPE_SELL_STOP)
         {
            Print("Deleting pending order: ", ticket);
            DeletePendingOrder(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Function to delete a specific pending order                      |
//+------------------------------------------------------------------+
void DeletePendingOrder(ulong ticket)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_REMOVE;
   request.order = ticket;

   if (!OrderSend(request, result))
   {
      Print("Failed to delete pending order. Error: ", GetLastError());
   }
   else
   {
      Print("Pending order deleted. Order ID: ", ticket);
   }
}

//+------------------------------------------------------------------+
//| Function to close all market positions                           |
//+------------------------------------------------------------------+
void CloseAllMarketPositions()
{
   int totalPositions = PositionsTotal();

   for (int i = totalPositions - 1; i >= 0; i--)
   {
      if (PositionSelect(PositionGetSymbol(i)))  // Select position by symbol
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         int orderType = (int)PositionGetInteger(POSITION_TYPE);

         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_DEAL;                       // Action to close position
         request.position = ticket;                                // Ticket of the position to close
         request.symbol = symbol;                                  // Symbol of the position
         request.volume = volume;                                  // Volume to close
         request.price = (orderType == POSITION_TYPE_BUY) ?         // Dynamic price based on order type
            SymbolInfoDouble(symbol, SYMBOL_BID) :
            SymbolInfoDouble(symbol, SYMBOL_ASK);
         request.deviation = 10;                                   // Slippage tolerance
         request.type = (orderType == POSITION_TYPE_BUY) ?         // Close opposite type
            ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.comment = "Trade limit exceeded, closing position";

         if (!OrderSend(request, result)) // Send close request
         {
            Print("Failed to close market order. Error: ", GetLastError());
         }
         else
         {
            Print("Market order closed successfully. Ticket: ", ticket);
         }
      }
   }
}
