// FIXTURE_USER_OVERRIDE exists only in the user's copy of VirtualKeys.mqh.
#include <VirtualKeys.mqh>

int OnInit()
{
   return FIXTURE_USER_OVERRIDE == 1 ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick() {}
