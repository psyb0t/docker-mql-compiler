// FIXTURE_USER_OVERRIDE exists only in the user's copy of WinUser32.mqh.
#property strict
#include <WinUser32.mqh>

int OnInit()
{
   return FIXTURE_USER_OVERRIDE == 1 ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick() {}
