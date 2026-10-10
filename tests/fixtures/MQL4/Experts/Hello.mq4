#property strict
#include <Fixture/Greeting.mqh>

int OnInit()
{
   Print(FixtureGreeting());
   return INIT_SUCCEEDED;
}

void OnTick() {}
