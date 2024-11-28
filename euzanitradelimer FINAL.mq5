//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA Initialized. Monitoring manual trades and pending orders...");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Deinitialized.");
}

//+------------------------------------------------------------------+
//| Trade transaction event function                                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, 
                        const MqlTradeRequest &request, 
                        const MqlTradeResult &result)
{
   static int totalManualTrades = GetManualTradeCount();

   // Handle manual trades and update manual trade count
   if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if (trans.deal != 0 && DealIsManual(trans.deal))
      {
         totalManualTrades++;
         Print("New manual trade detected. Total manual trades today: ", totalManualTrades);

         if (totalManualTrades >= 4)
         {
            Print("Trade limit exceeded. Deleting all pending orders.");
            CheckAndDeletePendingOrders();  // Delete any existing pending orders
            CloseAllMarketPositions();      // Close all market positions
         }
      }
   }

   // Handle pending order placement and immediately delete it if limit is exceeded
   if (trans.type == TRADE_TRANSACTION_ORDER_ADD)
   {
      ulong orderTicket = trans.order;

      if (totalManualTrades >= 4) // If trade limit is exceeded, delete pending order
      {
         Print("Trade limit exceeded. Deleting new pending order: ", orderTicket);
         DeletePendingOrder(orderTicket);
      }
   }
}

//+------------------------------------------------------------------+
//| Function to get the count of manual trades for the day            |
//+------------------------------------------------------------------+
int GetManualTradeCount()
{
   int count = 0;
   int totalDeals = HistoryDealsTotal();

   datetime currentDay = TimeCurrent() / 86400 * 86400; // Start of the current day

   for (int i = totalDeals - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);

      if (HistoryDealSelect(dealTicket))
      {
         if (DealIsManual(dealTicket))
         {
            datetime dealTime = HistoryDealGetInteger(dealTicket, DEAL_TIME);
            if (dealTime >= currentDay)
            {
               count++;
            }
         }
      }
   }
   return count;
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
   int totalOrders = OrdersTotal();

   for (int i = totalOrders - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);

      if (OrderSelect(ticket))
      {
         int orderType = (int)OrderGetInteger(ORDER_TYPE);

         if (IsPendingOrder(orderType))
         {
            Print("Deleting pending order: ", ticket);
            DeletePendingOrder(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Function to check if the order is a pending order                 |
//+------------------------------------------------------------------+
bool IsPendingOrder(int orderType)
{
   return (orderType == ORDER_TYPE_BUY_LIMIT || 
           orderType == ORDER_TYPE_SELL_LIMIT || 
           orderType == ORDER_TYPE_BUY_STOP || 
           orderType == ORDER_TYPE_SELL_STOP);
}

//+------------------------------------------------------------------+
//| Function to delete a specific pending order with retry mechanism  |
//+------------------------------------------------------------------+
void DeletePendingOrder(ulong ticket)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_REMOVE;
   request.order = ticket;

   int maxRetries = 5;        // Maximum number of retries
   int retryDelay = 1000;     // Delay between retries in milliseconds

   for (int attempt = 0; attempt < maxRetries; attempt++)
   {
      if (OrderSend(request, result))
      {
         Print("Pending order deleted successfully. Order ID: ", ticket);
         return; // Exit the loop if successful
      }
      else
      {
         int error = GetLastError();
         Print("Failed to delete pending order. Attempt ", attempt + 1, " Error: ", error);

         // If error is related to trade context, retry after delay
         if (error == 4756) // Trade context busy
         {
            Sleep(retryDelay); // Wait before retrying
         }
         else
         {
            break; // If the error is not trade context-related, exit loop
         }
      }
   }

   Print("Pending order deletion failed after ", maxRetries, " attempts. Order ID: ", ticket);
}

//+------------------------------------------------------------------+
//| Function to close all market positions                            |
//+------------------------------------------------------------------+
void CloseAllMarketPositions()
{
   int totalPositions = PositionsTotal();

   for (int i = totalPositions - 1; i >= 0; i--)
   {
      if (PositionSelect(PositionGetSymbol(i)))
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         int orderType = (int)PositionGetInteger(POSITION_TYPE);

         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = symbol;
         request.volume = volume;
         request.price = (orderType == POSITION_TYPE_BUY) ? 
            SymbolInfoDouble(symbol, SYMBOL_BID) : 
            SymbolInfoDouble(symbol, SYMBOL_ASK);
         request.deviation = 10;
         request.type = (orderType == POSITION_TYPE_BUY) ? 
            ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.comment = "Trade limit exceeded, closing position";

         if (!OrderSend(request, result))
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
