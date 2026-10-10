// Uses the MetaQuotes standard library, which the terminal unpacks on first
// start and the merged include root carries next to the user's Include.
#property strict
#include <stdlib.mqh>

int OnInit()
{
   Print(ErrorDescription(0));
   return INIT_SUCCEEDED;
}

void OnTick() {}
