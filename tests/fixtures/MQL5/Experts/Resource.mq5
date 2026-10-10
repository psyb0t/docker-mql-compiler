// A "\\..." resource path starts at the MQL5 folder, so this needs the user's
// Files folder reachable from the include root.
#resource "\\Files\\greeting.txt" as string greeting_text

int OnInit()
{
   Print(greeting_text);
   return INIT_SUCCEEDED;
}

void OnTick() {}
