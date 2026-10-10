// Uses the MetaQuotes standard library, which the terminal unpacks on first
// start and the merged include root carries next to the user's Include.
#include <Trade/Trade.mqh>

CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(1);
   return INIT_SUCCEEDED;
}

void OnTick() {}
