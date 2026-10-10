// Sits outside any MQL4/MQL5 folder, so only the standard library is on the
// include path.
#include <Trade/Trade.mqh>

CTrade trade;

void OnStart()
{
   trade.SetExpertMagicNumber(1);
}
